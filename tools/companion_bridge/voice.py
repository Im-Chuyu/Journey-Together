"""Windows local speech. Microphone access starts only from an explicit user action."""
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from .paths import data_dir, model_dir


class WindowsVoice:
    def __init__(self, language="zh-CN", preferences=None):
        self.language = language
        self.lock = threading.Lock()
        self.speaker = None
        self.listener = None
        self.suppress_until = 0
        self.closed = False
        self.children = set()
        self.preferences = dict(preferences or {})

    def configure(self, preferences):
        with self.lock:
            self.preferences = dict(preferences)

    def _recognition_command(self, mode):
        if self.preferences.get("asr_backend", "windows") != "whisper":
            return None
        folder = Path(__file__).parent
        python = data_dir() / "voice-runtime/Scripts/python.exe"
        model = model_dir()
        if not python.is_file() or not (model / "model.bin").is_file():
            raise ValueError("请先在助手设置中安装/准备离线识别。")
        command = [str(python), "-B", str(folder / "whisper_worker.py"), "--mode", mode,
                   "--model", str(model), "--language", self.language.split("-")[0]]
        return command

    def _listener_control(self, command):
        if self.preferences.get("asr_backend") == "whisper" and self.listener is not None and self.listener.stdin:
            try:
                self.listener.stdin.write((command + "\n").encode()); self.listener.stdin.flush()
            except (OSError, ValueError):
                pass

    def listen_held(self, released):
        command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                   str(Path(__file__).with_name("speech.ps1")), "-Mode", "hold", "-Language", self.language, "-Seconds", "20"]
        child = None
        try:
            command = self._recognition_command("hold") or command
            with self.lock:
                if self.closed: return {"status": "error", "error": "语音模块已关闭"}
                child = subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                                         creationflags=subprocess.CREATE_NO_WINDOW)
                self.listener=child; self.children.add(child)
            deadline=time.monotonic()+20
            while not released.wait(.05):
                if self.closed or child.poll() is not None or time.monotonic()>=deadline: break
            try: child.stdin.write(b"finish\n"); child.stdin.flush()
            except (OSError,ValueError): pass
            output,_=child.communicate(timeout=90)
            lines=output.decode("utf-8-sig","replace").strip().splitlines()
            return json.loads(lines[-1]) if lines else {"status":"no_speech","text":""}
        except (OSError,ValueError,subprocess.TimeoutExpired) as error:
            if child is not None and child.poll() is None: child.kill();child.communicate()
            return {"status":"error","error":str(error)}
        finally:
            with self.lock:
                if self.listener is child: self.listener=None
                self.children.discard(child)

    def listen_continuously(self, callback, stopped):
        """Reuse one recognizer. Only the opt-in UI button starts microphone access."""
        if os.name != "nt":
            callback({"status": "error", "error": "持续语音需要Windows语音识别组件"})
            return
        command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                   str(Path(__file__).with_name("speech.ps1")), "-Mode", "continuous", "-Language", self.language]
        child = None
        try:
            command = self._recognition_command("continuous") or command
            with self.lock:
                if stopped.is_set() or self.closed:
                    return
                child = subprocess.Popen(command, stdin=subprocess.PIPE if self.preferences.get("asr_backend") == "whisper" else subprocess.DEVNULL, stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
                self.listener = child
                self.children.add(child)
            for line in child.stdout:
                if stopped.is_set():
                    break
                result = json.loads(line.decode("utf-8-sig"))
                with self.lock:
                    audible = self.speaker is not None or time.monotonic() < self.suppress_until
                if not audible or result.get("status") == "error":
                    callback(result)
            if not stopped.is_set() and child.wait() != 0:
                callback({"status": "error", "error": "持续语音进程已退出，请检查麦克风和语音语言包"})
        except (OSError, ValueError) as error:
            if not stopped.is_set():
                callback({"status": "error", "error": str(error)})
        finally:
            if child is not None:
                if child.poll() is None:
                    child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill(); child.wait()
                child.stdout.close()
                if getattr(child, "stdin", None): child.stdin.close()
            with self.lock:
                if self.listener is child:
                    self.listener = None
                self.children.discard(child)

    def run(self, mode, text=None, wave_path=None, options=None):
        if os.name != "nt":
            return {"status": "error", "error": "本模块需要 Windows 的 System.Speech 组件"}
        command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                   str(Path(__file__).with_name("speech.ps1")), "-Mode", mode, "-Language", self.language]
        if wave_path is not None:
            command.extend(["-WavePath", str(wave_path)])
        if mode == "recognize":
            try:
                command = self._recognition_command("recognize") or command
            except ValueError as error:
                return {"status": "error", "error": str(error)}
        with self.lock:
            if self.closed:
                return {"status": "error", "error": "语音模块已关闭"}
            try:
                child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                         creationflags=subprocess.CREATE_NO_WINDOW)
            except OSError as error:
                return {"status": "error", "error": str(error)}
            self.children.add(child)
            if mode == "speak":
                self.speaker = child
                self._listener_control("pause")
            elif mode in {"recognize", "selftest"}:
                self.listener = child
        try:
            profile = options if options is not None else self.preferences
            request = {"text": text, "voice": profile.get("tts_voice", ""),
                       "rate": profile.get("tts_rate", 0), "volume": profile.get("tts_volume", 100)}
            payload = json.dumps(request, ensure_ascii=False).encode("utf-8") if text is not None else b""
            output, _ = child.communicate(payload, timeout=100 if mode == "speak" else 90 if mode == "recognize" and self.preferences.get("asr_backend") == "whisper" else 25)
            lines = output.decode("utf-8-sig", "replace").strip().splitlines()
            return json.loads(lines[-1]) if lines else {"status": "error", "error": "语音进程未返回结果"}
        except (subprocess.TimeoutExpired, ValueError):
            child.kill(); child.communicate()
            return {"status": "error", "error": "语音处理失败或超时"}
        finally:
            with self.lock:
                if self.speaker == child:
                    self.speaker = None
                    self.suppress_until = time.monotonic() + 1
                    self._listener_control("resume")
                if self.listener == child:
                    self.listener = None
                self.children.discard(child)

    def stop(self):
        with self.lock:
            child = self.speaker
            if child is not None and child.poll() is None:
                child.terminate()

    def stop_listening(self):
        with self.lock:
            child = self.listener
            if child is not None and child.poll() is None:
                child.terminate()

    def close(self):
        with self.lock:
            self.closed = True
            for child in set(self.children) | {self.speaker, self.listener}:
                if child is not None and child.poll() is None:
                    child.terminate()
