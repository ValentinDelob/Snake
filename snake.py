"""Snake - entry point.

Run the game
------------
    py snake.py                 play
    py snake.py --selftest      automated run used by the build pipeline

Build a Windows executable
--------------------------
    py build.py

License: MIT
"""

from __future__ import annotations

import sys

try:
    import pygame  # noqa: F401  (imported for the early dependency check)
except ImportError:
    print("Missing dependency: pip install -r requirements.txt")
    sys.exit(1)

from snakegame.app import main

if __name__ == "__main__":
    sys.exit(main())
