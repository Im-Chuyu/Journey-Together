"""Portable local pairing preferences, excluded from Git and separate from game saves."""
import json
from pathlib import Path
import secrets
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


def save(data, directory=None):
    validate(data["pair_code"], data["web_code"])
    validate_hotkey(data.get("voice_hotkey", "F9"))
    validate_voice(data)
    data = {k:v for k,v in data.items() if k != "asr_prompt"}
    directory = Path(directory) if directory else data_dir()
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "settings.json"
    temporary = directory / "settings.json.new"
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def load(directory=None):
    directory = Path(directory) if directory else data_dir()
    path = directory / "settings.json"
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
        validate(data["pair_code"], data["web_code"])
        validate_hotkey(data.get("voice_hotkey", "F9"))
        validate_voice(data)
        return data
    data = {"pair_code": DEFAULT_CODE, "web_code": secrets.token_urlsafe(32), "voice_hotkey": "F9"}
    data["asr_backend"]="whisper"
    save(data, directory)
    return data
