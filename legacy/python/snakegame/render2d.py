"""Classic flat renderer, kept as an alternative view to the 3D one."""

from __future__ import annotations

import math

import pygame

from . import config, ui


class Board2DRenderer:
    """Top-down grid view: the original look of the game."""

    name = "2d"

    def update(self, dt: float, world) -> None:
        """No camera to move in a flat view."""

    def reset_camera(self) -> None:
        """Nothing to reset in a flat view."""

    def draw(self, surface: pygame.Surface, world, elapsed: float, flash: float = 0.0) -> None:
        self._draw_board(surface)
        self._draw_food(surface, world, elapsed)
        self._draw_snake(surface, world, flash)

    # ------------------------------------------------------------------ #
    def _draw_board(self, surface: pygame.Surface) -> None:
        pygame.draw.rect(surface, config.BOARD_COLOR, ui.board_rect())
        origin_x, origin_y = config.BOARD_ORIGIN
        for x in range(config.GRID_WIDTH + 1):
            px = origin_x + x * config.CELL_SIZE
            pygame.draw.line(surface, config.GRID_COLOR, (px, origin_y), (px, config.WINDOW_SIZE[1]))
        for y in range(config.GRID_HEIGHT + 1):
            py = origin_y + y * config.CELL_SIZE
            pygame.draw.line(surface, config.GRID_COLOR, (origin_x, py), (config.WINDOW_SIZE[0], py))

    def _draw_food(self, surface: pygame.Surface, world, elapsed: float) -> None:
        pulse = 0.5 + 0.5 * math.sin(elapsed * 6.0)
        radius = int(config.CELL_SIZE * (0.30 + 0.06 * pulse))
        rect = ui.cell_rect(world.food.x, world.food.y)
        pygame.draw.circle(surface, config.FOOD_COLOR, rect.center, radius)
        pygame.draw.circle(surface, (255, 180, 180), rect.center, max(1, radius // 3))

    def _draw_snake(self, surface: pygame.Surface, world, flash: float) -> None:
        length = world.length
        for index, segment in enumerate(world.snake):
            if index == 0:
                color = ui.lerp_color(config.SNAKE_HEAD_COLOR, (255, 255, 255), flash * 0.6)
                rect = ui.cell_rect(segment.x, segment.y, inset=1)
                pygame.draw.rect(surface, color, rect, border_radius=6)
                self._draw_eyes(surface, world, rect)
            else:
                t = index / max(1, length - 1)
                color = ui.lerp_color(config.SNAKE_BODY_COLOR, config.SNAKE_TAIL_COLOR, t)
                pygame.draw.rect(
                    surface, color, ui.cell_rect(segment.x, segment.y, inset=2), border_radius=4
                )

    def _draw_eyes(self, surface: pygame.Surface, world, head_rect: pygame.Rect) -> None:
        direction = world.direction
        offset = config.CELL_SIZE // 5
        side = (-direction.y, direction.x)
        for sign in (-1, 1):
            cx = head_rect.centerx + direction.x * offset + side[0] * offset * sign
            cy = head_rect.centery + direction.y * offset + side[1] * offset * sign
            pygame.draw.circle(surface, config.EYE_COLOR, (int(cx), int(cy)), max(1, offset // 2))
