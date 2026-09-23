"""Tunable constants and filesystem paths.

Everything that a designer may want to tweak lives here so that gameplay
modules stay free of magic numbers.
"""

from __future__ import annotations

import sys
from pathlib import Path

# --------------------------------------------------------------------------- #
# Board geometry
# --------------------------------------------------------------------------- #
CELL_SIZE = 20
GRID_WIDTH = 28
GRID_HEIGHT = 18
WINDOW_SIZE = (GRID_WIDTH * CELL_SIZE, GRID_HEIGHT * CELL_SIZE)

# --------------------------------------------------------------------------- #
# Timing
# --------------------------------------------------------------------------- #
FPS = 10

# --------------------------------------------------------------------------- #
# Palette
# --------------------------------------------------------------------------- #
BG_COLOR = (0, 0, 0)
SNAKE_COLOR = (0, 255, 0)
FOOD_COLOR = (255, 0, 0)
TEXT_COLOR = (255, 255, 255)

FONT_NAME = "monospace"
FONT_SIZE = 24

WINDOW_TITLE = "Snake"


# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
def app_dir() -> Path:
    """Directory the application runs from.

    For a PyInstaller build this is the folder holding the ``.exe`` so that
    logs sit next to the binary; when running from sources it is the project
    root.
    """
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


LOG_DIR = app_dir() / "logs"
LOG_FILE = LOG_DIR / "snake.log"
