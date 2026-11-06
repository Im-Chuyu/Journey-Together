"""Portable local pairing preferences, excluded from Git and separate from game saves."""
import json
from pathlib import Path
import secrets
import os
import tempfile
from .paths import data_dir

DEFAULT_CODE = "321151"
HOTKEYS = tuple(f"F{number}" for number in range(1, 13))


def validate_hotkey(value):
    if value not in HOTKEYS:
        raise ValueError("语音快捷键必须为F1～F12")


def validate(code, web_code):
    if not isinstance(code, str) or len(code) != 6 or not code.isascii() or not code.isdigit():
        raise ValueError("游戏配对码必须是六位数字")
    if not isinstance(web_code, str) or not 20 <= len(web_code) <= 128 or not web_code.isascii() or any(c.isspace() for c in web_code):
        raise ValueError("网页连接码需为20～128个不含空白的ASCII字符")


def validate_voice(data):
    if data.get("asr_backend", "windows") not in ("windows", "whisper"):
        raise ValueError("不支持的语音识别引擎")
    if not isinstance(data.get("tts_voice", ""), str) or len(data.get("tts_voice", "")) > 200:
        raise ValueError("朗读音色名称不正确")
    for key, low, high in (("tts_rate", -10, 10), ("tts_volume", 0, 100)):
        value = data.get(key, 0 if key == "tts_rate" else 100)
        if type(value) is not int or not low <= value <= high:
            raise ValueError("语速范围-10～10，音量范围0～100")


def validate_chat(data):
    if type(data.get("broadcast_input", False)) is not bool:
        raise ValueError("公屏同步设置必须为布尔值")
    if type(data.get("whisper_input", False)) is not bool:
        raise ValueError("附近私聊设置必须为布尔值")

def pairing_path():
    """Only the web credential is shared across development/Workshop copies."""
    if os.environ.get("MY_FRIEND_ASSISTANT_DATA_DIR"):
        return data_dir() / "web-pairing.json"
    base = Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".local" / "share")
    return base / "JourneyTogether" / "companion_bridge" / "web-pairing.json"


def _write_pairing(web_code):
    path = pairing_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="web-pairing.", suffix=".json.new", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump({"web_code": web_code}, stream)
            stream.write("\n")
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def _shared_web_code(fallback):
    path = pairing_path()
    if path.exists():
        value = json.loads(path.read_text(encoding="utf-8-sig")).get("web_code")
        validate(DEFAULT_CODE, value)
        return value
    path.parent.mkdir(parents=True, exist_ok=True)
    # A simultaneous second launch must use the winner's credential, even if
    # that second process later fails because the HTTP port is already in use.
    try:
        with path.open("x", encoding="utf-8") as stream:
            json.dump({"web_code": fallback}, stream)
            stream.write("\n")
        return fallback
    except FileExistsError:
        value = json.loads(path.read_text(encoding="utf-8-sig")).get("web_code")
        validate(DEFAULT_CODE, value)
        return value


def save(data, directory=None):
    use_shared = directory is None
    validate(data["pair_code"], data["web_code"])
    validate_hotkey(data.get("voice_hotkey", "F9"))
    validate_voice(data)
    validate_chat(data)
    data = {k:v for k,v in data.items() if k != "asr_prompt"}
    directory = Path(directory) if directory else data_dir()
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "settings.json"
    temporary = directory / "settings.json.new"
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)
    if use_shared:
        _write_pairing(data["web_code"])


def load(directory=None):
    use_shared = directory is None
    directory = Path(directory) if directory else data_dir()
    path = directory / "settings.json"
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        validate(data["pair_code"], data["web_code"])
        validate_hotkey(data.get("voice_hotkey", "F9"))
        validate_voice(data)
        validate_chat(data)
        if use_shared:
            data["web_code"] = _shared_web_code(data["web_code"])
        return data
    data = {"pair_code": DEFAULT_CODE, "web_code": secrets.token_urlsafe(32), "voice_hotkey": "F9"}
    data["asr_backend"]="whisper"
    data["broadcast_input"] = False
    data["whisper_input"] = False
    if use_shared:
        data["web_code"] = _shared_web_code(data["web_code"])
    save(data, directory)
    return data
