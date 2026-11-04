"""Mod-local assistant data; exclude .local when publishing to Workshop."""
import os
from pathlib import Path


def data_dir():
    override = os.environ.get("MY_FRIEND_ASSISTANT_DATA_DIR")
    if override:
        return Path(override).expanduser().resolve()
    return Path(__file__).parent / ".local"


def model_dir():
    return data_dir() / "models/faster-whisper-small"
