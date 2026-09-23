"""Small drawing helpers shared by the scenes."""

from __future__ import annotations

from typing import Optional

import pygame

from . import config


def draw_text(
    surface: pygame.Surface,
    font: pygame.font.Font,
    message: str,
    color: tuple[int, int, int],
    center: Optional[tuple[int, int]] = None,
    topleft: Optional[tuple[int, int]] = None,
    midright: Optional[tuple[int, int]] = None,
) -> pygame.Rect:
    surf = font.render(message, True, color)
    if center is not None:
        rect = surf.get_rect(center=center)
    elif midright is not None:
        rect = surf.get_rect(midright=midright)
    else:
        rect = surf.get_rect(topleft=topleft or (0, 0))
    surface.blit(surf, rect)
    return rect


def dim(surface: pygame.Surface, alpha: int = 170) -> None:
    """Darken the whole window, used under overlay scenes."""
    veil = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
    veil.fill((0, 0, 0, alpha))
    surface.blit(veil, (0, 0))


def board_rect() -> pygame.Rect:
    return pygame.Rect(config.BOARD_ORIGIN, config.BOARD_SIZE)


def cell_rect(x: int, y: int, inset: int = 0) -> pygame.Rect:
    """Pixel rectangle of a grid cell, board offset included."""
    return pygame.Rect(
        config.BOARD_ORIGIN[0] + x * config.CELL_SIZE + inset,
        config.BOARD_ORIGIN[1] + y * config.CELL_SIZE + inset,
        config.CELL_SIZE - 2 * inset,
        config.CELL_SIZE - 2 * inset,
    )


def lerp_color(
    start: tuple[int, int, int], end: tuple[int, int, int], t: float
) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return (
        int(start[0] + (end[0] - start[0]) * t),
        int(start[1] + (end[1] - start[1]) * t),
        int(start[2] + (end[2] - start[2]) * t),
    )
