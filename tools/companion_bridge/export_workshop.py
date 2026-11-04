"""Export working-tree mod files without developer caches or assistant credentials."""
import argparse
import json
from datetime import datetime
from pathlib import Path
import shutil
import subprocess

if __package__:
    from .api_config import DEFAULTS
else:
    from api_config import DEFAULTS


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    destination = (args.output or root / "tests/.local" / (
        "workshop-upload-" + datetime.now().strftime("%Y%m%d-%H%M%S"))).resolve()
    # Never merge an export into an existing directory or upload the live workspace.
    if destination.exists():
        parser.error("Output must be a new directory.")
    files = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
    ).decode("utf-8").split("\0")
    selected = []
    for name in sorted(set(files)):
        path = Path(name)
        if not name or path.parts[0] in {"tests", ".github"} or name in {
            ".gitattributes", ".gitignore", "AGENTS.md", "DEVELOPER.md", "CONTRIBUTING.md", "CONTRIBUTING.en.md",
            "tools/companion_bridge/export_workshop.py",
            "AssistantAPI.json", "AssistantAPI.example.json",
        } or path.name.split(".", 1)[0].casefold() == "readme" or path.name.startswith("AssistantAPI.json.") or any(
            part in {".local", ".git", "__pycache__", ".pytest_cache"} for part in path.parts
        ) or path.suffix in {".pyc", ".pyo", ".log"}:
            continue
        source = root / path
        if source.is_symlink():
            raise ValueError(f"Refusing symlink: {name}")
        if source.is_file():
            selected.append((source, path))
    destination.mkdir(parents=True)
    for source, relative in selected:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    # Generate from code defaults; never copy credentials, even from an edited example.
    for name in ("AssistantAPI.json", "AssistantAPI.example.json"):
        (destination / name).write_text(json.dumps(DEFAULTS, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Exported {len(selected)} files to {destination}")
    print("Review this directory and select it in the Workshop uploader. Nothing was uploaded.")


if __name__ == "__main__":
    main()
