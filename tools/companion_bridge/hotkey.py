"""Global voice shortcut on its own Windows message thread; only one key is inspected."""
import ctypes
from ctypes import wintypes
import os
import queue
import threading

from .settings import validate_hotkey

class KeyboardEvent(ctypes.Structure):
    _fields_ = [("vkCode", wintypes.DWORD), ("scanCode", wintypes.DWORD), ("flags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("extra", ctypes.c_size_t)]

class VoiceHotkey:
    ID = 0xA19

    def __init__(self):
        self.api = ctypes.windll.user32 if os.name == "nt" else None
        self.registered = False
        self.hook = self.callback = self.thread = None
        self.pressed = False
        self.events = queue.SimpleQueue()
        self.stopped = threading.Event()
        self.ready = threading.Event()
        self.bound = False

    def bind(self, key):
        validate_hotkey(key)
        self.close()
        self.vk = 0x6F + int(key[1:])
        self.events = queue.SimpleQueue()
        self.stopped = threading.Event(); self.ready = threading.Event()
        if self.api is None: return True
        self.thread = threading.Thread(target=self._run, args=(key,), daemon=True, name="voice-hotkey")
        self.thread.start()
        if not self.ready.wait(3):
            self.close(); return False
        return self.bound

    def _edge(self, down):
        if down != self.pressed:
            self.pressed = down
            self.events.put(down)

    def _run(self, key):
        try:
            self.api.PeekMessageW.argtypes = [ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT, wintypes.UINT]
            self.api.PeekMessageW.restype = wintypes.BOOL
            if key != "F12":
                self.registered = bool(self.api.RegisterHotKey(None, self.ID, 0x4000, self.vk))
                self.bound = self.registered
            else:
                callback_type = ctypes.WINFUNCTYPE(ctypes.c_ssize_t, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)
                self.api.SetWindowsHookExW.argtypes = [ctypes.c_int, callback_type, wintypes.HINSTANCE, wintypes.DWORD]
                self.api.SetWindowsHookExW.restype = wintypes.HANDLE
                self.api.CallNextHookEx.argtypes = [wintypes.HANDLE, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM]
                self.api.CallNextHookEx.restype = ctypes.c_ssize_t
                self.api.UnhookWindowsHookEx.argtypes = [wintypes.HANDLE]
                def receive(code, message, address):
                    if code >= 0:
                        event = ctypes.cast(address, ctypes.POINTER(KeyboardEvent)).contents
                        if event.vkCode == self.vk and not event.flags & 0x10:
                            if message in (0x100,0x104):
                                if any(self.api.GetAsyncKeyState(k) & 0x8000 for k in (0x10,0x11,0x12,0x5B,0x5C)):
                                    return self.api.CallNextHookEx(self.hook,code,message,address)
                                self._edge(True); return 1
                            if message in (0x101,0x105) and self.pressed:
                                self._edge(False); return 1
                    return self.api.CallNextHookEx(self.hook,code,message,address)
                self.callback = callback_type(receive)
                module = ctypes.windll.kernel32.GetModuleHandleW
                module.argtypes, module.restype = [wintypes.LPCWSTR], wintypes.HMODULE
                self.hook = self.api.SetWindowsHookExW(13,self.callback,module(None),0)
                self.bound = bool(self.hook)
            self.ready.set()
            if not self.bound: return
            message = wintypes.MSG()
            while not self.stopped.is_set():
                while self.api.PeekMessageW(ctypes.byref(message),None,0,0,1):
                    if message.message == 0x312 and message.wParam == self.ID:
                        self._edge(True)
                    else:
                        self.api.TranslateMessage(ctypes.byref(message))
                        self.api.DispatchMessageW(ctypes.byref(message))
                if self.registered and self.pressed and not self.api.GetAsyncKeyState(self.vk) & 0x8000:
                    self._edge(False)
                self.stopped.wait(.01)
        finally:
            if self.registered: self.api.UnregisterHotKey(None,self.ID)
            if self.hook: self.api.UnhookWindowsHookEx(self.hook)
            self.registered=False; self.hook=self.callback=None; self.bound=False
            self.ready.set()

    def poll_events(self):
        events=[]
        while True:
            try: events.append(self.events.get_nowait())
            except queue.Empty: return events

    def poll(self):
        return any(self.poll_events())

    def close(self):
        self.stopped.set()
        if self.thread is not None:
            self.thread.join(3)
            self.thread=None
        self.registered=False; self.hook=self.callback=None
        self.pressed=False; self.bound=False
