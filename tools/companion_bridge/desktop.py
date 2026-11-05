"""Desktop input and speech UI; this program never injects keyboard input into DST."""
import argparse
import json
import os
import queue
import subprocess
from .paths import data_dir
import threading
import webbrowser
from pathlib import Path

from .adapter import load_adapter
from .capabilities import TOOLS
from .server import BridgeError, Store, make_server
from .voice import WindowsVoice
from .hotkey import VoiceHotkey


def desktop(store, server, language):
    import tkinter as tk
    from tkinter import ttk
    root = tk.Tk()
    root.title("一路同行 · 本机动作与语音助手")
    root.geometry("780x720")
    from .settings import load, HOTKEYS
    voice_hotkey = tk.StringVar(value=load().get("voice_hotkey", "F9"))
    hotkey = VoiceHotkey()
    voice = WindowsVoice(language, load())
    voice_installing = [False]
    voice_installer = [None]
    speaking = queue.Queue(maxsize=12)
    closed = threading.Event()
    poll_timer = [None]
    speech_epoch = [0]
    ttk.Label(root, text="模式：" + getattr(store.adapter, "label", type(store.adapter).__name__)).pack(anchor="w", padx=12, pady=6)
    pairing_line = tk.StringVar(value=f'游戏配对码：{store.code}；可在模组配置启用AI大模型模式，也可复制手动命令。')
    ttk.Label(root, textvariable=pairing_line).pack(anchor="w", padx=12)
    ttk.Label(root, text='开启模型模式后自动连接；助手直接对话，游戏公屏须带伙伴名字。人人可聊天，跟随时只接受领队安排工作。').pack(anchor="w", padx=12)
    setup = ttk.Frame(root); setup.pack(fill="x", padx=12, pady=5)
    def copy(value):
        root.clipboard_clear(); root.clipboard_append(value); root.update()
    ttk.Button(setup, text="复制游戏配对命令", command=lambda: copy(f'c_myfriend_ai("start", "{store.code}")')).pack(side="left")
    if hasattr(store.adapter, "secret"):
        open_web = ttk.Menubutton(setup, text="打开模型网页")
        web_menu = tk.Menu(open_web, tearoff=False)
        web_menu.add_command(label="DeepSeek", command=lambda: webbrowser.open("https://chat.deepseek.com/"))
        web_menu.add_command(label="豆包", command=lambda: webbrowser.open("https://www.doubao.com/chat/"))
        open_web.config(menu=web_menu); open_web.pack(side="left", padx=5)
        ttk.Button(setup, text="复制网页连接码", command=lambda: copy(store.adapter.secret)).pack(side="left")
        extension_folder = Path(__file__).with_name("browser_extension")
        if extension_folder.is_dir():
            ttk.Button(setup, text="扩展所在文件夹", command=lambda: os.startfile(str(extension_folder))).pack(side="left", padx=5)
        ttk.Label(root, text="首次加载扩展，登录DeepSeek或豆包，在所选聊天页连接；支持自动新建对话。").pack(anchor="w", padx=12)
    if getattr(store.adapter, "diagnostics_kind", None) == "api":
        from .api_config import ROOT
        ttk.Button(setup, text="API配置文件", command=lambda: os.startfile(str(ROOT / "AssistantAPI.json"))).pack(side="left", padx=5)
        ttk.Label(root, text="API模式直接连接DeepSeek；修改AssistantAPI.json后重启助手。用量按DeepSeek账单计费。").pack(anchor="w", padx=12)
    ttk.Button(setup, text="诊断日志", command=lambda: os.startfile(str(data_dir() / "logs"))).pack(side="left", padx=5)
    def model_settings():
        from .api_settings import show
        show(root)
    ttk.Button(setup, text="大模型设置", command=model_settings).pack(side="left", padx=5)
    def pairing_settings():
        window = tk.Toplevel(root); window.title("助手设置")
        ttk.Button(window, text="大模型设置", command=model_settings).pack(anchor="w", padx=12, pady=6)
        ttk.Label(window, text="六位游戏配对码（默认321151，需与模组配置一致）：").pack(anchor="w", padx=12, pady=6)
        game_code = ttk.Entry(window, width=46); game_code.insert(0, store.code); game_code.pack(padx=12)
        ttk.Label(window, text="网页连接码（20～128个ASCII字符，重启后保持不变）：").pack(anchor="w", padx=12, pady=6)
        web_code = ttk.Entry(window, width=46, show="*")
        from .settings import load
        web_code.insert(0, getattr(store.adapter, "secret", "") or load()["web_code"]); web_code.pack(padx=12)
        ttk.Label(window, text="全局语音快捷键（F1～F12）：").pack(anchor="w", padx=12, pady=6)
        key_choice = ttk.Combobox(window, values=HOTKEYS, state="readonly", width=12)
        key_choice.set(voice_hotkey.get()); key_choice.pack(anchor="w", padx=12)
        preferences = load()
        ttk.Label(window, text="识别引擎（离线Whisper需先准备模型）：").pack(anchor="w", padx=12, pady=4)
        asr_choice = ttk.Combobox(window, values=("Whisper 离线识别", "Windows 系统识别"), state="readonly", width=42)
        asr_choice.set("Whisper 离线识别" if preferences.get("asr_backend") == "whisper" else "Windows 系统识别")
        asr_choice.pack(padx=12)
        def install_voice():
            if voice_installing[0]: return
            if listening[0]: hint.config(text="请先停止语音识别再准备运行库。"); return
            voice_installing[0] = True
            hint.config(text="正在安装离线运行库及下载small模型，首次需要联网，请等待。")
            def prepare():
                folder = Path(__file__).parent
                logs = data_dir() / "logs"; logs.mkdir(parents=True, exist_ok=True)
                try:
                    with (logs / "voice-setup.log").open("w", encoding="utf-8") as output:
                        command = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(folder / "setup_voice.ps1")]
                        child = subprocess.Popen(command,
                            stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
                        voice_installer[0] = child
                        if closed.is_set():
                            subprocess.run(["taskkill.exe", "/PID", str(child.pid), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW, timeout=5)
                        code = child.wait()
                    store.notify("voice_setup", success=code == 0)
                except OSError as error:
                    store.notify("voice_setup", success=False, error=str(error))
                finally: voice_installing[0] = False; voice_installer[0] = None
            threading.Thread(target=prepare, daemon=True).start()
        ttk.Button(window, text="安装/准备离线识别", command=install_voice).pack(anchor="w", padx=12, pady=3)
        ttk.Label(window, text="朗读音色：").pack(anchor="w", padx=12, pady=4)
        voice_choice = ttk.Combobox(window, values=("自动匹配语言",), state="readonly", width=48)
        voice_choice.set(preferences.get("tts_voice") or "自动匹配语言"); voice_choice.pack(padx=12)
        rate = tk.StringVar(value=str(preferences.get("tts_rate", 0)))
        volume = tk.StringVar(value=str(preferences.get("tts_volume", 100)))
        for label, variable, low, high in (("语速（-10～10）：", rate, -10, 10), ("音量（0～100）：", volume, 0, 100)):
            row = ttk.Frame(window); row.pack(fill="x", padx=12, pady=2)
            ttk.Label(row, text=label).pack(side="left")
            ttk.Spinbox(row, from_=low, to=high, textvariable=variable, width=8).pack(side="left")
        def voice_preferences():
            from .settings import validate_voice
            data = {"asr_backend": "whisper" if asr_choice.get().startswith("Whisper") else "windows",
                    "tts_voice": "" if voice_choice.get() == "自动匹配语言" else voice_choice.get(),
                    "tts_rate": int(rate.get()), "tts_volume": int(volume.get())}
            validate_voice(data)
            return data
        def preview():
            try: profile = voice_preferences()
            except ValueError as error: hint.config(text=str(error)); return
            speech_epoch[0] += 1; voice.stop()
            threading.Thread(target=lambda: store.notify("voice_preview", result=voice.run("speak", text="你好，我会陪你一起探索饥荒世界。", options=profile)), daemon=True).start()
        ttk.Button(window, text="试听音色", command=preview).pack(anchor="w", padx=12, pady=4)
        def read_voices():
            result = voice.run("check")
            def update():
                if window.winfo_exists():
                    names = [v["name"] for v in result.get("voices", [])]
                    voice_choice.config(values=["自动匹配语言", *names])
            if not closed.is_set():
                try: root.after(0, update)
                except RuntimeError: pass
        if hasattr(voice, "run"): threading.Thread(target=read_voices, daemon=True).start()
        hint = ttk.Label(window, text="网页码改变后需在扩展重新粘贴一次；游戏码供下次配对使用。", wraplength=420)
        hint.pack(padx=12, pady=8)
        def apply():
            previous = voice_hotkey.get()
            try:
                if listening[0]: raise ValueError("请先停止语音识别，再修改设置。")
                profile = voice_preferences()
                if not bind_hotkey(key_choice.get()):
                    raise ValueError(key_choice.get() + " 已被占用，请选择其他键。")
                store.update_pairing(game_code.get().strip(), web_code.get().strip(), key_choice.get(), voice_preferences=profile)
                voice.configure({**load(), **profile})
                voice_hotkey.set(key_choice.get())
                voice_button.config(text="语音输入 " + voice_hotkey.get())
                pairing_line.set(f'游戏配对码：{store.code}；可在模组配置启用AI大模型模式，也可复制手动命令。')
                window.destroy()
            except (ValueError, OSError) as error:
                bind_hotkey(previous)
                hint.config(text=str(error))
        ttk.Button(window, text="保存", command=apply).pack(pady=8)
    ttk.Button(setup, text="助手设置", command=pairing_settings).pack(side="left")
    connection = ttk.Label(root, text="等待游戏配对；服务仅监听 127.0.0.1:18766")
    connection.pack(anchor="w", padx=12, pady=6)
    entry = tk.Text(root, height=3, font=("Microsoft YaHei UI", 11))
    entry.pack(fill="x", padx=12)
    options = ttk.Frame(root); options.pack(fill="x", padx=12, pady=6)
    auto_send, speak = tk.BooleanVar(value=True), tk.BooleanVar(value=False)
    ttk.Checkbutton(options, text="识别后自动发送", variable=auto_send).pack(side="left")
    ttk.Checkbutton(options, text="本机念出伙伴回复", variable=speak).pack(side="left")
    message = ttk.Label(root, text=voice_hotkey.get() + " 按住录音、松开识别；持续语音需手动开启，无需说伙伴名字。", wraplength=740, justify="left")
    message.pack(anchor="w", padx=12)
    buttons = ttk.Frame(root); buttons.pack(fill="x", padx=12, pady=6)
    log = tk.Text(root, height=20, wrap="word", font=("Microsoft YaHei UI", 10))
    log.pack(fill="both", expand=True, padx=12, pady=6)
    manual = ttk.Frame(root); manual.pack(fill="x", padx=12, pady=6)
    names = [tool["name"] for tool in TOOLS]
    selected = ttk.Combobox(manual, values=names, width=20, state="readonly")
    selected.set("observe"); selected.pack(side="left")
    arguments = ttk.Entry(manual); arguments.insert(0, '{"scope":"structures","radius":32}')
    arguments.pack(side="left", fill="x", expand=True, padx=6)
    listening = [False]
    continuous = [False]
    listener_stop = threading.Event()
    held_release = threading.Event()
    held_recording = [False]

    local_inputs = {}

    def append(text, tag=None):
        log.insert("end", text + "\n", (tag,) if tag else ()); log.see("end")
        if int(log.index("end-1c").split(".")[0]) > 300:
            log.delete("1.0", "50.0")

    def resolve_input(event, text):
        input_id = event.get("input_id")
        if input_id not in local_inputs:
            return False
        del local_inputs[input_id]
        tag = "local_input_" + input_id
        ranges = log.tag_ranges(tag)
        if ranges:
            start = str(ranges[0])
            log.delete(ranges[0], ranges[-1])
            log.insert(start, text + "\n")
        log.tag_delete(tag)
        return True

    def submit():
        text = entry.get("1.0", "end").strip()
        try:
            if not store.connected:
                raise BridgeError("游戏未连接：确认模组开启AI大模型模式、六位码一致，并等待自动连接；也可复制手动配对命令。")
            if hasattr(store.adapter, "connection_state"):
                if store.adapter.connection_state() == "disconnected":
                    raise BridgeError("网页尚未连通：刷新当前模型聊天页，在扩展中重新连接，确认弹窗显示网页和助手均已连通。")
            input_id = store.submit(text)
            if input_id:
                local_inputs[input_id] = text
                append("你（待游戏确认）：" + text, "local_input_" + input_id)
            speech_epoch[0] += 1; voice.stop()
            entry.delete("1.0", "end")
        except BridgeError as error:
            message.config(text=str(error))
            append("未发送：" + str(error))

    def listen():
        if listening[0]:
            return
        speech_epoch[0] += 1; voice.stop()
        listening[0] = True; message.config(text="正在识别麦克风输入，请说话…")
        def recognize():
            result = voice.run("recognize")
            if not closed.is_set():
                store.notify("recognition", result=result)
        threading.Thread(target=recognize, daemon=True).start()

    def start_held():
        if listening[0]: return
        speech_epoch[0] += 1; voice.stop()
        held_release.clear(); held_recording[0] = True; listening[0] = True
        message.config(text="按住录音中，松开快捷键后识别。")
        def recognize_held():
            result = voice.listen_held(held_release)
            if not closed.is_set(): store.notify("recognition", result=result)
        threading.Thread(target=recognize_held, daemon=True).start()

    def toggle_continuous():
        if continuous[0]:
            continuous[0] = False; listener_stop.set(); voice.stop_listening()
            continuous_button.config(text="正在停止语音…")
            return
        if listening[0]:
            message.config(text="请等待当前语音识别结束。")
            return
        speech_epoch[0] += 1; voice.stop()
        listening[0], continuous[0] = True, True
        listener_stop.clear()
        continuous_button.config(text="停止持续语音")
        message.config(text="持续语音已开启，直接说话即可；再次点击按钮关闭麦克风。")
        def recognize_continuously():
            try:
                voice.listen_continuously(lambda result: store.notify("recognition", result=result, continuous=True), listener_stop)
            finally:
                store.notify("listener_stopped")
        threading.Thread(target=recognize_continuously, daemon=True).start()

    def call():
        try:
            store.direct_call(selected.get(), json.loads(arguments.get()))
        except (BridgeError, ValueError) as error:
            message.config(text=str(error))

    def stop():
        try:
            store.stop_action()
        except BridgeError as error:
            message.config(text=str(error))

    ttk.Button(buttons, text="发送文字", command=submit).pack(side="left")
    voice_button = ttk.Button(buttons, text="语音输入 " + voice_hotkey.get(), command=listen)
    voice_button.pack(side="left", padx=6)
    continuous_button = ttk.Button(buttons, text="开启持续语音", command=toggle_continuous)
    continuous_button.pack(side="left", padx=6)
    ttk.Button(buttons, text="停止当前动作", command=stop).pack(side="left")
    ttk.Button(manual, text="调用动作", command=call).pack(side="left")
    ttk.Label(root, text="动作参数使用JSON；目标/item等使用观察结果里的handle。此窗口日志不会自动保存到磁盘。").pack(anchor="w", padx=12, pady=6)

    def speech_worker():
        while not closed.is_set():
            try:
                epoch, action_id, text = speaking.get(timeout=.3)
            except queue.Empty:
                continue
            if epoch != speech_epoch[0]:
                continue
            store.speech(action_id, "playing")
            result = voice.run("speak", text=text)
            store.speech(action_id, "completed" if result.get("status") == "completed" else "failed")
    threading.Thread(target=speech_worker, daemon=True).start()

    def bind_hotkey(key):
        return hotkey.bind(key)
    if not bind_hotkey(voice_hotkey.get()):
        message.config(text=voice_hotkey.get() + " 注册失败或被占用，请在设置更换或使用语音输入按钮。")

    def poll():
        poll_timer[0] = None
        if closed.is_set(): return
        for down in hotkey.poll_events():
            if down: start_held()
            elif held_recording[0]:
                held_recording[0] = False; held_release.set()
                message.config(text="录音结束，正在识别…")
        for _ in range(30):
            try:
                event = store.messages.get_nowait()
            except queue.Empty:
                break
            kind = event["kind"]
            if kind == "recognition":
                if not event.get("continuous"): listening[0] = False; held_recording[0] = False
                elif not continuous[0]: continue
                result = event["result"]
                text = result.get("text", "")
                if text:
                    entry.delete("1.0", "end"); entry.insert("1.0", text)
                    message.config(text="已识别：" + text)
                    if auto_send.get(): submit()
                else: message.config(text=result.get("error", "未识别到语音，请检查麦克风后重试。"))
            elif kind == "listener_stopped":
                listening[0], continuous[0] = False, False
                continuous_button.config(text="开启持续语音")
            elif kind == "voice_setup":
                message.config(text="离线识别已准备好，请在助手设置选择Whisper并保存。" if event.get("success") else "离线识别准备失败，请查看诊断日志中的voice-setup.log后重试。")
            elif kind == "voice_preview":
                message.config(text="试听完成。" if event["result"].get("status") == "completed" else event["result"].get("error", "试听失败"))
            elif kind == "input_rejected":
                reason = {"companion_name_required": "请在消息中包含伙伴名字。", "rate_limited": "消息太快，请稍后再说。"}.get(event.get("reason"), "游戏未接收消息，请检查连接。")
                message.config(text=reason)
                if not resolve_input(event, "未发送：" + event.get("text", "") + "（" + reason + "）"):
                    append("未发送：" + reason)
                if event.get("text") and not entry.get("1.0", "end").strip(): entry.insert("1.0", event["text"])
            elif kind == "assistant":
                append("伙伴：" + event["text"])
                if speak.get():
                    try:
                        speaking.put_nowait((speech_epoch[0], event.get("action_id"), event["text"]))
                    except queue.Full:
                        store.speech(event.get("action_id"), "failed")
                else: store.speech(event.get("action_id"), "disabled")
            elif kind == "disconnected":
                speech_epoch[0] += 1; voice.stop()
                for input_id, text in list(local_inputs.items()):
                    resolve_input({"input_id": input_id}, "未确认：" + text)
                append("控制已结束：" + str(event.get("reason")))
            elif kind == "task_replaced":
                speech_epoch[0] += 1; voice.stop()
                append("游戏新指令已接替旧模型任务，连接保持。")
            elif kind == "user":
                text = (event.get("speaker") or "玩家") + "：" + event["text"]
                if not resolve_input(event, text): append(text)
            else: append(json.dumps(event, ensure_ascii=False)[:8000])
        status = "游戏已连接" if store.connected else "等待游戏配对"
        if getattr(store.adapter, "diagnostics_kind", None) == "api":
            usage = store.adapter.diagnostics()
            status += f' · API请求{usage["requests"]}次 · 输入{usage["prompt_tokens"]}/输出{usage["completion_tokens"]} tokens'
        if hasattr(store.adapter, "connection_state"):
            status += {"connected": " · 模型网页已连接", "background": " · 网页后台等待（仍可发送）",
                       "disconnected": " · 网页暂未连通，请检查浏览器"}[store.adapter.connection_state()]
        connection.config(text=status)
        if not closed.is_set(): poll_timer[0] = root.after(100, poll)

    def close():
        if poll_timer[0] is not None:
            root.after_cancel(poll_timer[0]); poll_timer[0] = None
        closed.set(); listener_stop.set(); held_release.set(); voice.close(); store.close()
        installer = voice_installer[0]
        if installer is not None and installer.poll() is None:
            try:
                subprocess.run(["taskkill.exe", "/PID", str(installer.pid), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW, timeout=5)
            except (OSError, subprocess.TimeoutExpired): installer.terminate()
        hotkey.close()
        root.destroy()
    root.protocol("WM_DELETE_WINDOW", close)
    poll_timer[0] = root.after(100, poll)
    root.mainloop()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--adapter", help="Explicit local provider adapter .py file")
    parser.add_argument("--provider", choices=("auto", "demo", "web", "deepseek-api", "deepseek-web", "doubao-web"), default="auto")
    parser.add_argument("--pair-code", help="Optional six-digit code; otherwise randomly generated")
    parser.add_argument("--speech-language", default="zh-CN")
    parser.add_argument("--voice-check", action="store_true")
    args = parser.parse_args()
    if args.voice_check:
        print(json.dumps(WindowsVoice(args.speech_language).run("check"), ensure_ascii=False)); return
    from .diagnostics import configure
    configure()
    from .settings import load, save
    preferences = load()
    if args.pair_code is not None and (len(args.pair_code) != 6 or not args.pair_code.isascii() or not args.pair_code.isdigit()):
        parser.error("pair-code must be six digits")
    if args.adapter:
        adapter = load_adapter(args.adapter)
    else:
        from .api_config import select_adapter
        try:
            adapter = select_adapter(args.provider, preferences)
        except ValueError as error:
            parser.error(str(error))
    if args.pair_code:
        preferences["pair_code"] = args.pair_code; save(preferences)
    store = Store(adapter, preferences["pair_code"])
    try:
        server = make_server(store)
    except OSError:
        store.close()
        parser.exit(1, "本机端口 18766 已被占用；请检查是否已打开伙伴助手。\n")
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"Loopback assistant: http://127.0.0.1:18766; mode={getattr(store.adapter, 'label', type(store.adapter).__name__)}", flush=True)
    print(f'Game console: c_myfriend_ai("start", "{store.code}")', flush=True)
    try:
        if args.headless:
            print("Local automation client token: " + store.client_token, flush=True)
            threading.Event().wait()
        else:
            desktop(store, server, args.speech_language)
    except KeyboardInterrupt:
        pass
    finally:
        store.close(); server.shutdown(); server.server_close()


if __name__ == "__main__":
    main()
