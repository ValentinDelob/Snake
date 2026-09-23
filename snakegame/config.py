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

HUD_HEIGHT = 44
BOARD_SIZE = (GRID_WIDTH * CELL_SIZE, GRID_HEIGHT * CELL_SIZE)
BOARD_ORIGIN = (0, HUD_HEIGHT)
WINDOW_SIZE = (BOARD_SIZE[0], BOARD_SIZE[1] + HUD_HEIGHT)

# --------------------------------------------------------------------------- #
# Timing
# --------------------------------------------------------------------------- #
UI_FPS = 60          # rendering / input rate
STEP_HZ = 10.0       # how many times per second the snake advances

# --------------------------------------------------------------------------- #
# Palette
# --------------------------------------------------------------------------- #
BG_COLOR = (8, 10, 14)
BOARD_COLOR = (14, 18, 24)
GRID_COLOR = (22, 28, 36)
HUD_COLOR = (18, 22, 30)
SNAKE_HEAD_COLOR = (120, 255, 150)
SNAKE_BODY_COLOR = (0, 200, 90)
SNAKE_TAIL_COLOR = (0, 120, 60)
FOOD_COLOR = (255, 70, 70)
TEXT_COLOR = (236, 240, 244)
TEXT_DIM_COLOR = (130, 142, 158)
ACCENT_COLOR = (255, 208, 80)
OVERLAY_COLOR = (0, 0, 0, 170)

FONT_NAME = "consolas,monospace"
FONT_SIZE_SMALL = 16
FONT_SIZE = 22
FONT_SIZE_BIG = 40

WINDOW_TITLE = "Snake"


# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
def app_dir() -> Path:
    """Directory the application runs from.

    For a PyInstaller build this is the folder holding the ``.exe`` so that
    logs and saves sit next to the binary; when running from sources it is
    the project root.
    """
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


LOG_DIR = app_dir() / "logs"
LOG_FILE = LOG_DIR / "snake.log"
SAVE_FILE = app_dir() / "savegame.json"
