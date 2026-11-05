"""Voice preferences, streaming lifecycle and hidden UI. Never uses a real microphone."""
import ctypes
import io
from pathlib import Path
import threading
import unittest
from unittest.mock import patch
from unittest.mock import Mock
from types import SimpleNamespace

from tools.companion_bridge import settings
from tools.companion_bridge.voice import WindowsVoice


class Child:
    def __init__(self, records=()):
        self.stdout = io.BytesIO(b"".join(records))
        self.terminated = False
        self.returncode = None

    def poll(self):
        return self.returncode

    def terminate(self):
        self.terminated = True
        self.returncode = 0

    def wait(self, timeout=None):
        self.returncode = 0
        return 0


class VoiceTests(unittest.TestCase):
    def test_f12_hook_debounces_and_releases_without_registering_the_reserved_key(self):
        from tools.companion_bridge.hotkey import VoiceHotkey, KeyboardEvent
        hotkey = VoiceHotkey()
        api = SimpleNamespace(RegisterHotKey=Mock(return_value=True), UnregisterHotKey=Mock(),
            SetWindowsHookExW=Mock(return_value=1234), UnhookWindowsHookEx=Mock(return_value=True),
            CallNextHookEx=Mock(return_value=77), PeekMessageW=Mock(return_value=0), GetAsyncKeyState=Mock(return_value=0))
        hotkey.api = api
        self.assertTrue(hotkey.bind("F1")); self.assertTrue(hotkey.bind("F11"))
        self.assertTrue(hotkey.bind("F12"))
        self.assertEqual([c.args[-1] for c in api.RegisterHotKey.call_args_list], [0x70, 0x7A])
        event = KeyboardEvent(vkCode=0x7B)
        address = ctypes.addressof(event)
        self.assertEqual(hotkey.callback(0, 0x100, address), 1)
        self.assertTrue(hotkey.poll())
        hotkey.callback(0, 0x100, address)
        self.assertFalse(hotkey.poll())
        hotkey.callback(0, 0x101, address); hotkey.callback(0, 0x100, address)
        self.assertTrue(hotkey.poll())
        event.vkCode = 0x7A
        self.assertEqual(hotkey.callback(0, 0x100, address), 77)
        event.vkCode = 0x7B; hotkey.callback(0, 0x101, address)
        api.GetAsyncKeyState.return_value = 0x8000
        self.assertEqual(hotkey.callback(0, 0x100, address), 77)
        self.assertFalse(hotkey.poll())
        hotkey.close()
        api.UnhookWindowsHookEx.assert_called_once_with(1234)
        self.assertIsNone(hotkey.callback)

    def test_global_hotkey_messages_are_consumed_on_the_registration_thread(self):
        from tools.companion_bridge.hotkey import VoiceHotkey
        import queue, time
        from ctypes import wintypes
        messages=queue.Queue(); down=threading.Event(); registered=[]; unregistered=[]
        def peek(address,*args):
            try: item=messages.get_nowait()
            except queue.Empty: return 0
            msg=ctypes.cast(address,ctypes.POINTER(wintypes.MSG)).contents
            msg.message=0x312;msg.wParam=item;return 1
        api=SimpleNamespace(RegisterHotKey=Mock(side_effect=lambda *args: registered.append(threading.get_ident()) or True),
            UnregisterHotKey=Mock(side_effect=lambda *args: unregistered.append(threading.get_ident())),
            PeekMessageW=Mock(side_effect=peek),GetAsyncKeyState=Mock(side_effect=lambda key: 0x8000 if down.is_set() else 0),
            TranslateMessage=Mock(),DispatchMessageW=Mock())
        key=VoiceHotkey();key.api=api
        try:
            self.assertTrue(key.bind("F9"));self.assertNotEqual(registered[0],threading.get_ident())
            down.set();messages.put(key.ID)
            result=[];deadline=time.monotonic()+1
            while not result and time.monotonic()<deadline: result.extend(key.poll_events());time.sleep(.01)
            self.assertEqual(result,[True])
            down.clear();result=[];deadline=time.monotonic()+1
            while not result and time.monotonic()<deadline: result.extend(key.poll_events());time.sleep(.01)
            self.assertEqual(result,[False])
        finally:key.close()
        self.assertEqual(registered,unregistered)

    def test_push_to_talk_release_is_forwarded_and_old_terms_are_removed(self):
        import json
        voice=WindowsVoice(preferences={"asr_backend":"whisper","asr_prompt":"obsolete"})
        released=threading.Event();released.set()
        child=Mock();child.poll.return_value=None
        child.communicate.return_value=(b'{"status":"recognized","text":"test"}',b'')
        with patch.object(Path,"is_file",return_value=True),patch("tools.companion_bridge.voice.subprocess.Popen",return_value=child) as spawn:
            result=voice.listen_held(released)
        self.assertIn("hold",spawn.call_args.args[0]);self.assertNotIn("--prompt",spawn.call_args.args[0])
        child.stdin.write.assert_called_once_with(b"finish\n")
        self.assertEqual(result["text"],"test");self.assertIsNone(voice.listener)
        directory=Path("tests/.local/body_bridge/removed_terms")
        settings.save({"pair_code":"321151","web_code":"local-test-code-123456789","asr_prompt":"obsolete"},directory)
        self.assertNotIn("asr_prompt",settings.load(directory))

    def test_all_function_keys_persist_and_pairing_edits_preserve_voice_preferences(self):
        from tools.companion_bridge.server import Store
        from tools.companion_bridge.adapter import DemoAdapter
        directory = Path("tests/.local/body_bridge/voice_settings")
        preferences = {"pair_code": "321151", "web_code": "workspace-voice-test-secret"}
        for key in settings.HOTKEYS:
            settings.save({**preferences, "voice_hotkey": key}, directory)
            self.assertEqual(settings.load(directory)["voice_hotkey"], key)
        for key in ("F0", "F13", "f9", "Q", 9, None):
            with self.assertRaises(ValueError):
                settings.validate_hotkey(key)
        saved = []
        store = Store(DemoAdapter())
        try:
            with patch.object(settings, "load", return_value={**preferences, "voice_hotkey": "F12"}), \
                 patch.object(settings, "save", side_effect=lambda data: saved.append(data.copy())):
                store.update_pairing("654321", preferences["web_code"])
            self.assertEqual(saved[-1]["voice_hotkey"], "F12")
        finally:
            store.close()

    def test_voice_profile_validation_and_tts_request_preserve_selected_parameters(self):
        profile = {"asr_backend": "whisper", "tts_voice": "Microsoft Huihui Desktop", "tts_rate": -2, "tts_volume": 65}
        settings.validate_voice(profile)
        for change in ({"tts_rate": 11}, {"tts_volume": -1}, {"asr_backend": "unknown"}, {"tts_rate": True}):
            with self.assertRaises(ValueError): settings.validate_voice({**profile, **change})
        child = Mock()
        child.communicate.return_value = (b'{"status":"completed"}', b'')
        voice = WindowsVoice(preferences=profile)
        with patch("tools.companion_bridge.voice.subprocess.Popen", return_value=child):
            result = voice.run("speak", text="你好")
        import json
        sent = json.loads(child.communicate.call_args.args[0].decode("utf-8"))
        self.assertEqual((sent["voice"], sent["rate"], sent["volume"]), (profile["tts_voice"], -2, 65))
        self.assertEqual(result["status"], "completed")
        self.assertIsNone(voice.speaker)

    def test_offline_recognition_requires_local_files_and_selects_the_isolated_worker(self):
        voice = WindowsVoice(preferences={"asr_backend": "whisper"})
        with patch.object(Path, "is_file", return_value=False), patch("tools.companion_bridge.voice.subprocess.Popen") as spawn:
            self.assertEqual(voice.run("recognize")["status"], "error")
            spawn.assert_not_called()
        with patch.object(Path, "is_file", return_value=True):
            command = voice._recognition_command("continuous")
        self.assertIn("whisper_worker.py", command[2])
        self.assertIn("continuous", command)
        self.assertIn("voice-runtime", command[0])

    def test_continuous_stream_reuses_one_process_for_multiple_utterances(self):
        voice = WindowsVoice()
        child = Child([b'{"text":"first","status":"recognized"}\n', b'{"text":"second","status":"recognized"}\n'])
        records = []
        with patch("tools.companion_bridge.voice.subprocess.Popen", return_value=child) as spawn:
            voice.listen_continuously(records.append, threading.Event())
        self.assertEqual([r["text"] for r in records], ["first", "second"])
        self.assertEqual(spawn.call_count, 1)
        self.assertIn("continuous", spawn.call_args.args[0])
        self.assertIsNone(voice.listener)
        self.assertTrue(child.stdout.closed)

    def test_stop_listener_leaves_speaker_alone_and_closed_module_does_not_restart(self):
        voice = WindowsVoice()
        voice.listener, voice.speaker = Child(), Child()
        speaker = voice.speaker
        voice.stop_listening()
        self.assertTrue(voice.listener.terminated)
        self.assertFalse(speaker.terminated)
        voice.close()
        self.assertTrue(speaker.terminated)
        with patch("tools.companion_bridge.voice.subprocess.Popen") as spawn:
            voice.listen_continuously(lambda _: self.fail("closed module returned speech"), threading.Event())
            self.assertEqual(voice.run("recognize")["status"], "error")
            spawn.assert_not_called()

    def test_tts_audio_is_ignored_by_the_continuous_listener(self):
        voice = WindowsVoice()
        voice.speaker = Child()
        child = Child([b'{"text":"echo","status":"recognized"}\n'])
        with patch("tools.companion_bridge.voice.subprocess.Popen", return_value=child):
            result = []
            voice.listen_continuously(result.append, threading.Event())
        self.assertEqual(result, [])

    def test_hidden_desktop_changes_hotkey_and_toggles_continuous_listening(self):
        import tkinter as tk
        from tkinter import ttk
        from tools.companion_bridge.desktop import desktop
        from tools.companion_bridge.server import Store
        from tools.companion_bridge.adapter import DemoAdapter
        native_tk = tk.Tk
        observations = {"keys": [], "saved": [], "starts": 0}
        preferences = {"pair_code": "321151", "web_code": "workspace-voice-test-secret", "voice_hotkey": "F9"}
        failures = []

        class FakeVoice:
            def __init__(self, *_):
                self.stop_event = None
            def configure(self, preferences): pass
            def stop(self): pass
            def close(self):
                if self.stop_event: self.stop_event.set()
            def stop_listening(self):
                if self.stop_event: self.stop_event.set()
            def listen_held(self, released):
                observations["held_started"]=True
                observations["held_released"]=released.wait(2)
                return {"status":"recognized","text":"test held speech"}
            def listen_continuously(self, callback, event):
                self.stop_event = event
                observations["starts"] += 1
                callback({"text": "温蒂，早上好", "status": "recognized"})
                event.wait(3)

        class FakeHotkey:
            def bind(self, key):
                observations["keys"].append(0x6F + int(key[1:]))
                return True
            def poll(self): return False
            def poll_events(self):
                result=observations.pop("edges",[])
                return result
            def close(self): pass

        def widgets(root):
            for child in root.winfo_children():
                yield child
                yield from widgets(child)

        def button(root, label):
            return next(w for w in widgets(root) if isinstance(w, ttk.Button) and w.cget("text") == label)

        def hidden_tk():
            root = native_tk(); root.withdraw()
            def finish(): root.tk.call(root.protocol("WM_DELETE_WINDOW"))
            def exercise():
                try:
                    button(root, "助手设置").invoke()
                    window = next(w for w in root.winfo_children() if isinstance(w, tk.Toplevel))
                    window.withdraw()
                    self.assertFalse(any("识别术语" in str(w.cget("text")) for w in widgets(window) if isinstance(w,ttk.Label)))
                    choice = next(w for w in widgets(window) if isinstance(w, ttk.Combobox))
                    choice.set("F12"); button(window, "保存").invoke()
                    self.assertEqual(observations["keys"][-1], 0x7B)
                    self.assertEqual(observations["saved"][-1]["voice_hotkey"], "F12")
                    button(root, "语音输入 F12")
                    button(root, "开启持续语音").invoke()
                    root.after(200, stop)
                except Exception as error:
                    failures.append(error); finish()
            def stop():
                try:
                    self.assertEqual(observations["starts"], 1)
                    button(root, "停止持续语音").invoke()
                    root.after(200, verify)
                except Exception as error:
                    failures.append(error); finish()
            def verify():
                try:
                    button(root,"开启持续语音")
                    observations["edges"]=[True]
                    root.after(200,release_held)
                except Exception as error: failures.append(error);finish()
            def release_held():
                observations["edges"]=[False]
                root.after(200,verify_held)
            def verify_held():
                try:
                    self.assertTrue(observations.get("held_started"))
                    self.assertTrue(observations.get("held_released"))
                except Exception as error: failures.append(error)
                finish()
            root.after(20, exercise)
            root.after(2500, finish)
            return root

        store = Store(DemoAdapter())
        with patch.object(tk, "Tk", side_effect=hidden_tk), \
             patch("tools.companion_bridge.desktop.WindowsVoice", FakeVoice), \
             patch("tools.companion_bridge.desktop.VoiceHotkey", FakeHotkey), \
             patch.object(settings, "load", return_value=preferences.copy()), \
             patch.object(settings, "save", side_effect=lambda data: observations["saved"].append(data.copy())):
            desktop(store, None, "zh-CN")
        self.assertTrue(store.stopped)
        if failures: raise failures[0]


    def test_desktop_echoes_pending_text_and_updates_accepted_rejected_and_disconnected_rows(self):
        import tkinter as tk
        from tkinter import ttk
        from tools.companion_bridge.desktop import desktop
        from tools.companion_bridge.server import Store
        native_tk = tk.Tk
        failures = []
        contexts = []
        adapter = Mock()
        adapter.label = "test"
        adapter.decide.side_effect = lambda context: contexts.append(context) or {}
        del adapter.connection_state
        del adapter.secret
        adapter.diagnostics_kind = None
        store = Store(adapter)
        token = store.connect({"code": store.code, "session": "echo", "input_protocol": 2})["token"]

        def widgets(root):
            for child in root.winfo_children():
                yield child
                yield from widgets(child)

        def hidden_tk():
            root = native_tk(); root.withdraw()
            def finish(): root.tk.call(root.protocol("WM_DELETE_WINDOW"))
            def check(fn):
                try: fn()
                except Exception as error: failures.append(error); finish()
            def send(text):
                entry.delete("1.0", "end"); entry.insert("1.0", text)
                button.invoke()
                self.assertIn(text, log.get("1.0", "end"))
                self.assertIn("待游戏确认", log.get("1.0", "end"))
                return next(iter(store.inputs))
            def exchange(event=None, **extra):
                return store.exchange({"token": token, "session": "echo", "events": [event] if event else [], **extra})
            def begin():
                nonlocal entry, log, button
                entry, log = [w for w in widgets(root) if isinstance(w, tk.Text)]
                button = next(w for w in widgets(root) if isinstance(w, ttk.Button) and w.cget("text") == "发送文字")
                input_id = send("第一条本机消息")
                self.assertEqual(contexts, [])
                exchange({"event_id": "accept", "kind": "player_input", "input_id": input_id,
                          "turn_id": "turn", "text": "第一条本机消息", "speaker": {"name": "发言者", "userid": "owner"}})
                root.after(180, lambda: check(accepted))
            def accepted():
                text = log.get("1.0", "end")
                self.assertEqual(text.count("第一条本机消息"), 1)
                self.assertIn("发言者：第一条本机消息", text)
                self.assertNotIn("待游戏确认", text)
                input_id = send("需要拒绝的消息")
                exchange({"event_id": "reject", "kind": "input_rejected", "input_id": input_id, "reason": "rate_limited"})
                root.after(180, lambda: check(rejected))
            def rejected():
                text = log.get("1.0", "end")
                self.assertEqual(text.count("需要拒绝的消息"), 1)
                self.assertIn("未发送：需要拒绝的消息", text)
                self.assertEqual(entry.get("1.0", "end").strip(), "需要拒绝的消息")
                send("断线前的消息")
                exchange(closing="test_disconnect")
                root.after(180, lambda: check(disconnected))
            def disconnected():
                text = log.get("1.0", "end")
                self.assertIn("未确认：断线前的消息", text)
                self.assertNotIn("待游戏确认", text)
                finish()
            entry = log = button = None
            root.after(20, lambda: check(begin))
            root.after(3000, finish)
            return root

        hotkey = Mock()
        hotkey.poll_events.return_value = []
        with patch.object(tk, "Tk", side_effect=hidden_tk), \
             patch("tools.companion_bridge.desktop.WindowsVoice"), \
             patch("tools.companion_bridge.desktop.VoiceHotkey", return_value=hotkey), \
             patch.object(settings, "load", return_value={"voice_hotkey": "F9"}):
            desktop(store, None, "zh-CN")
        if failures: raise failures[0]


if __name__ == "__main__":
    unittest.main()
