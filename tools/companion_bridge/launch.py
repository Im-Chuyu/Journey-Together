"""Windowless desktop entry with visible startup failures."""
from pathlib import Path
import traceback
import io
import os
import sys
from .paths import data_dir


def main():
    previous_stdout, previous_stderr = sys.stdout, sys.stderr
    errors = io.StringIO()
    sys.stderr = errors
    if sys.stdout is None:
        sys.stdout = open(os.devnull, "w", encoding="utf-8")
    try:
        from .desktop import main as desktop_main
        desktop_main()
    except (Exception, SystemExit) as error:
        if isinstance(error, SystemExit) and not error.code:
            return
        folder = data_dir() / "logs"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / "startup-error.log"
        path.write_text(errors.getvalue() + "\n" + traceback.format_exc(), encoding="utf-8")
        import ctypes
        message = errors.getvalue().strip() or str(error)
        ctypes.windll.user32.MessageBoxW(None, f"助手启动失败：{message}\n\n详情：{path}", "一路同行", 0x10)
    finally:
        if previous_stdout is None and sys.stdout is not None:
            sys.stdout.close()
        sys.stdout, sys.stderr = previous_stdout, previous_stderr


if __name__ == "__main__":
    main()
