"""Game loop and rules."""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Iterable, Optional, Protocol

import pygame

from . import config
from .geometry import DOWN, LEFT, RIGHT, UP, Point
from .logging_setup import get_logger

log = get_logger("game")

_KEY_TO_DIRECTION = {
    pygame.K_UP: UP,
    pygame.K_w: UP,
    pygame.K_DOWN: DOWN,
    pygame.K_s: DOWN,
    pygame.K_LEFT: LEFT,
    pygame.K_a: LEFT,
    pygame.K_RIGHT: RIGHT,
    pygame.K_d: RIGHT,
}


class Agent(Protocol):
    """An automated player, used by the self-test harness."""

    def decide(self, game: "SnakeGame") -> Optional[Point]:
        """Return the direction to steer towards, or None to keep going."""


@dataclass
class RunResult:
    """Outcome of a finished run, reported to the logs and the exit code."""

    score: int = 0
    ticks: int = 0
    reason: str = "unknown"
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


class SnakeGame:
    """The classic board: a growing snake, one food item, deadly walls."""

    def __init__(
        self,
        agent: Optional[Agent] = None,
        max_ticks: Optional[int] = None,
        seed: Optional[int] = None,
    ) -> None:
        self.agent = agent
        self.max_ticks = max_ticks
        self.rng = random.Random(seed)

        pygame.init()
        self.clock = pygame.time.Clock()
        self.screen = pygame.display.set_mode(config.WINDOW_SIZE)
        pygame.display.set_caption(config.WINDOW_TITLE)
        self.font = pygame.font.SysFont(config.FONT_NAME, config.FONT_SIZE)
        log.info(
            "Display ready: %sx%s px, grid %sx%s, player=%s, seed=%s",
            config.WINDOW_SIZE[0],
            config.WINDOW_SIZE[1],
            config.GRID_WIDTH,
            config.GRID_HEIGHT,
            type(agent).__name__ if agent else "human",
            seed,
        )

        mid = Point(config.GRID_WIDTH // 2, config.GRID_HEIGHT // 2)
        self.snake: list[Point] = [mid]
        self.direction: Point = RIGHT
        self.pending_direction: Point = RIGHT
        self.food: Point = self._spawn_food()
        self.score = 0
        self.ticks = 0
        self.running = True
        self.game_over = False
        self.result = RunResult()

    # ------------------------------------------------------------------ #
    # World helpers
    # ------------------------------------------------------------------ #
    @property
    def head(self) -> Point:
        return self.snake[0]

    def is_inside(self, point: Point) -> bool:
        return 0 <= point.x < config.GRID_WIDTH and 0 <= point.y < config.GRID_HEIGHT

    def is_lethal(self, point: Point) -> bool:
        """Would the head die by moving onto this cell?"""
        return not self.is_inside(point) or point in self.snake[:-1]

    def free_cells(self) -> Iterable[Point]:
        occupied = set(self.snake)
        for y in range(config.GRID_HEIGHT):
            for x in range(config.GRID_WIDTH):
                point = Point(x, y)
                if point not in occupied:
                    yield point

    def _spawn_food(self) -> Point:
        candidates = list(self.free_cells())
        if not candidates:
            log.warning("Board is full, no room left for food")
            return self.head
        return self.rng.choice(candidates)

    # ------------------------------------------------------------------ #
    # Input
    # ------------------------------------------------------------------ #
    def steer(self, direction: Point) -> None:
        """Queue a direction change, ignoring 180 degree turns."""
        if not direction.is_opposite(self.direction):
            self.pending_direction = direction

    def _handle_events(self) -> None:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                log.info("Window closed by user")
                self._stop("quit")
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    log.info("ESC pressed")
                    self._stop("escape")
                elif event.key in _KEY_TO_DIRECTION:
                    self.steer(_KEY_TO_DIRECTION[event.key])

    def _apply_agent(self) -> None:
        if self.agent is None:
            return
        try:
            direction = self.agent.decide(self)
        except Exception as exc:  # an agent bug must not kill the run silently
            log.exception("Agent raised")
            self.result.errors.append("agent error: {}".format(exc))
            return
        if direction is not None:
            self.steer(direction)

    # ------------------------------------------------------------------ #
    # Simulation
    # ------------------------------------------------------------------ #
    def _stop(self, reason: str) -> None:
        self.running = False
        self.result.reason = reason

    def _update(self) -> None:
        self.direction = self.pending_direction
        new_head = self.head + self.direction

        if not self.is_inside(new_head):
            log.info("Death: wall at (%s,%s), score %s", new_head.x, new_head.y, self.score)
            self.game_over = True
            self._stop("wall")
            return

        if new_head in self.snake[:-1]:
            log.info("Death: self bite at (%s,%s), score %s", new_head.x, new_head.y, self.score)
            self.game_over = True
            self._stop("self")
            return

        self.snake.insert(0, new_head)
        if new_head == self.food:
            self.score += 1
            self.food = self._spawn_food()
            log.debug("Food eaten, score %s, length %s", self.score, len(self.snake))
        else:
            self.snake.pop()

    # ------------------------------------------------------------------ #
    # Rendering
    # ------------------------------------------------------------------ #
    def _draw_cell(self, pos: Point, color: tuple[int, int, int]) -> None:
        rect = pygame.Rect(
            pos.x * config.CELL_SIZE,
            pos.y * config.CELL_SIZE,
            config.CELL_SIZE,
            config.CELL_SIZE,
        )
        pygame.draw.rect(self.screen, color, rect)

    def _render(self) -> None:
        self.screen.fill(config.BG_COLOR)
        self._draw_cell(self.food, config.FOOD_COLOR)
        for segment in self.snake:
            self._draw_cell(segment, config.SNAKE_COLOR)

        score_surf = self.font.render("Score: {}".format(self.score), True, config.TEXT_COLOR)
        self.screen.blit(score_surf, (5, 5))

        if self.game_over:
            overlay = pygame.Surface(config.WINDOW_SIZE)
            overlay.set_alpha(128)
            overlay.fill((0, 0, 0))
            self.screen.blit(overlay, (0, 0))
            msg = self.font.render("GAME OVER - Press ESC to exit", True, config.TEXT_COLOR)
            self.screen.blit(
                msg,
                msg.get_rect(center=(config.WINDOW_SIZE[0] // 2, config.WINDOW_SIZE[1] // 2)),
            )

        pygame.display.flip()

    # ------------------------------------------------------------------ #
    # Main loop
    # ------------------------------------------------------------------ #
    def run(self) -> RunResult:
        log.info("Run started")
        while self.running:
            self._handle_events()
            if not self.running:
                break
            self._apply_agent()
            self._update()
            self._render()
            self.ticks += 1
            if self.max_ticks is not None and self.ticks >= self.max_ticks:
                log.info("Tick budget reached (%s)", self.max_ticks)
                self._stop("tick-budget")
            self.clock.tick(config.FPS)

        if self.game_over:
            self._render()
            self._wait_for_exit()

        self.result.score = self.score
        self.result.ticks = self.ticks
        log.info(
            "Run finished: reason=%s score=%s ticks=%s length=%s",
            self.result.reason,
            self.result.score,
            self.result.ticks,
            len(self.snake),
        )
        pygame.quit()
        return self.result

    def _wait_for_exit(self) -> None:
        """Hold the game-over screen until the player closes the window."""
        if self.agent is not None:  # automated runs never wait
            return
        waiting = True
        while waiting:
            for event in pygame.event.get():
                if event.type == pygame.QUIT or (
                    event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE
                ):
                    waiting = False
            self.clock.tick(config.FPS)
