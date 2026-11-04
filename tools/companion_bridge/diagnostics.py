"""Bounded metadata logs; never log tokens, transcripts, prompts or snapshots."""
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
from .paths import data_dir

LOG = logging.getLogger("companion_bridge")
LOG.addHandler(logging.NullHandler())


def configure(directory=None):
    directory = Path(directory) if directory else data_dir() / "logs"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "bridge.log"
    if not any(isinstance(handler, RotatingFileHandler) for handler in LOG.handlers):
        handler = RotatingFileHandler(path, maxBytes=65536, backupCount=2, encoding="utf-8")
        handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
        LOG.addHandler(handler)
        LOG.setLevel(logging.INFO)
    LOG.info("assistant_started")
    return path
