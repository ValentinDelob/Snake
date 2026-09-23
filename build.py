"""Build the Windows executable with PyInstaller.

    py build.py              windowed one-file build -> dist/snake.exe
    py build.py --console    same, but keeps a console for stdout/stderr
    py build.py --clean      wipe PyInstaller caches first

The previous executable is deleted before the build so that the freshly
produced binary can never be confused with an older one.
"""

from __future__ import annotations

import argparse
import datetime as dt
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"
WORK = ROOT / "build"
APP_NAME = "snake"
ENTRY = ROOT / "snake.py"


def main() -> int:
    parser = argparse.ArgumentParser(description="Build snake.exe")
    parser.add_argument("--console", action="store_true", help="keep the console window")
    parser.add_argument("--clean", action="store_true", help="clear PyInstaller caches")
    args = parser.parse_args()

    exe = DIST / f"{APP_NAME}.exe"
    if exe.exists():
        exe.unlink()
        print(f"[build] removed previous {exe.name}")
    if args.clean and WORK.exists():
        shutil.rmtree(WORK, ignore_errors=True)
        print("[build] cleared build cache")

    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--onefile",
        "--name",
        APP_NAME,
        "--distpath",
        str(DIST),
        "--workpath",
        str(WORK),
        "--specpath",
        str(WORK),
        "--console" if args.console else "--windowed",
        str(ENTRY),
    ]
    print("[build]", " ".join(cmd))
    completed = subprocess.run(cmd, cwd=ROOT)
    if completed.returncode != 0:
        print(f"[build] FAILED with code {completed.returncode}")
        return completed.returncode

    if not exe.exists():
        print("[build] FAILED: executable not produced")
        return 1

    stamp = dt.datetime.fromtimestamp(exe.stat().st_mtime).isoformat(timespec="seconds")
    print(f"[build] OK -> {exe}")
    print(f"[build] size={exe.stat().st_size / 1_048_576:.1f} MiB built={stamp}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
