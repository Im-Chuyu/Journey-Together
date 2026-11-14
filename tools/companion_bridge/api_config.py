"""Local credentials, separate from pairing settings and sanitized on export."""
import json
import os
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PROVIDERS = ("auto", "deepseek-api", "web", "deepseek-web", "doubao-web", "demo")
DEFAULTS = {"provider": "auto", "api_key": "", "model": "deepseek-flash", "pair_code": "", "thinking": True,
            "reasoning_effort": "low", "max_tokens": 8192, "timeout_seconds": 120,
            "retries": 1, "ambient_enabled": False}


def config_path():
    override = os.environ.get("MY_FRIEND_ASSISTANT_CONFIG")
    return Path(override).expanduser().resolve() if override else ROOT / "AssistantAPI.json"


def load(path=None, *, resolve_env=True, provider="auto"):
    path = Path(path) if path is not None else config_path()
    if not path.exists():
        # Exclusive creation never overwrites a key entered by another process.
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as output:
                json.dump(DEFAULTS, output, ensure_ascii=False, indent=2)
                output.write("\n")
        except FileExistsError:
            pass
        except OSError:
            raise ValueError("无法创建 AssistantAPI.json，请检查目录与写入权限。") from None
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (ValueError, OSError):
        raise ValueError("无法读取 AssistantAPI.json：请检查文件权限及 JSON 格式（双引号、逗号）。") from None
    return validate(data, resolve_env=resolve_env, provider=provider)


def validate(data, *, resolve_env=False, provider="auto"):
    if not isinstance(data, dict) or set(data) - DEFAULTS.keys():
        raise ValueError("AssistantAPI.json 含未知配置项，请参照 AssistantAPI.example.json。")
    config = {**DEFAULTS, **data}
    if config["provider"] not in PROVIDERS:
        raise ValueError("provider 必须为 " + "、".join(PROVIDERS) + "。")
    selected = config["provider"] if provider == "auto" else provider
    if not isinstance(config["api_key"], str):
        raise ValueError("api_key 必须为字符串。")
    key = config["api_key"]
    if resolve_env and not key and selected in ("auto", "deepseek-api"):
        key = os.environ.get("DEEPSEEK_API_KEY", "")
    if not isinstance(key, str) or len(key) > 512 or key and (
        not key.isascii() or any(char.isspace() or ord(char) < 33 for char in key)
    ):
        raise ValueError("API Key 格式错误，请只填写密钥，不附带空格或 Bearer 前缀。")
    config["api_key"] = key
    pair_code = config["pair_code"]
    if not isinstance(pair_code, str) or pair_code and (
        len(pair_code) != 6 or not pair_code.isascii() or not pair_code.isdigit()
    ):
        raise ValueError("pair_code 请留空或填写由六位数字组成的字符串。")
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
    path = Path(path) if path is not None else config_path()
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
        return DeepSeekAPIAdapter(config if config is not None else load(provider=provider))
    if provider in ("web", "deepseek-web", "doubao-web"):
        from .web_model import WebChatAdapter
        return WebChatAdapter(secret=preferences["web_code"])
    if provider == "demo":
        from .adapter import load_adapter
        return load_adapter()
    raise ValueError("不支持的模型模式。")
