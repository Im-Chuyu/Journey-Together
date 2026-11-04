"""Local credentials, separate from pairing settings and sanitized on export."""
import json
import os
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DEFAULTS = {"provider": "auto", "api_key": "", "model": "deepseek-flash", "thinking": True,
            "reasoning_effort": "low", "max_tokens": 8192, "timeout_seconds": 120,
            "retries": 1, "ambient_enabled": False}


def load(path=None, *, resolve_env=True):
    path = Path(path) if path is not None else ROOT / "AssistantAPI.json"
    if not path.exists():
        # Exclusive creation never overwrites a key entered by another process.
        try:
            with path.open("x", encoding="utf-8") as output:
                json.dump(DEFAULTS, output, ensure_ascii=False, indent=2)
                output.write("\n")
        except FileExistsError:
            pass
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (ValueError, OSError):
        raise ValueError("无法读取 AssistantAPI.json：请检查文件权限及 JSON 格式（双引号、逗号）。") from None
    return validate(data, resolve_env=resolve_env)


def validate(data, *, resolve_env=False):
    if not isinstance(data, dict) or set(data) - DEFAULTS.keys():
        raise ValueError("AssistantAPI.json 含未知配置项，请参照 AssistantAPI.example.json。")
    config = {**DEFAULTS, **data}
    if config["provider"] not in ("auto", "web", "deepseek-api"):
        raise ValueError("API provider 必须为 auto、web 或 deepseek-api。")
    if not isinstance(config["api_key"], str):
        raise ValueError("api_key 必须为字符串。")
    key = config["api_key"] or (os.environ.get("DEEPSEEK_API_KEY", "") if resolve_env else "")
    if not isinstance(key, str) or len(key) > 512 or key and (
        not key.isascii() or any(char.isspace() or ord(char) < 33 for char in key)
    ):
        raise ValueError("API Key 格式错误，请只填写密钥，不附带空格或 Bearer 前缀。")
    config["api_key"] = key
    model = config["model"]
    if not isinstance(model, str) or not 1 <= len(model) <= 100 or not all(
        char.isascii() and (char.isalnum() or char in "-_.") for char in model
    ):
        raise ValueError("API model 必须是有效的模型 ID。")
    for name in ("thinking", "ambient_enabled"):
        if type(config[name]) is not bool:
            raise ValueError("thinking 和 ambient_enabled 必须为 true 或 false。")
    if config["reasoning_effort"] not in ("low", "high", "max"):
        raise ValueError("reasoning_effort 必须为 low、high 或 max。")
    for name, low, high in (("max_tokens", 512, 32768), ("timeout_seconds", 10, 300), ("retries", 0, 2)):
        value = config[name]
        if type(value) is not int or not low <= value <= high:
            raise ValueError(f"{name} 必须为 {low}～{high} 的整数。")
    return config


def save(data, path=None):
    config = validate(data)
    path = Path(path) if path is not None else ROOT / "AssistantAPI.json"
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", prefix="AssistantAPI.json.",
                                         suffix=".new", dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            json.dump(config, output, ensure_ascii=False, indent=2)
            output.write("\n")
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def select_adapter(provider, preferences, config=None):
    if provider == "auto":
        config = config if config is not None else load()
        provider = config["provider"]
        if provider == "auto":
            provider = "deepseek-api" if config["api_key"] else "web"
    if provider == "deepseek-api":
        from .deepseek_api import DeepSeekAPIAdapter
        return DeepSeekAPIAdapter(config if config is not None else load())
    if provider in ("web", "deepseek-web", "doubao-web"):
        from .web_model import WebChatAdapter
        return WebChatAdapter(secret=preferences["web_code"])
    if provider == "demo":
        from .adapter import load_adapter
        return load_adapter()
    raise ValueError("不支持的模型模式。")
