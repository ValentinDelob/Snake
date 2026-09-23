"""Pure game rules, free of any pygame dependency.

Keeping the simulation separate from the presentation means the rules can be
stepped by a bot, a test or a replay without opening a window.
"""

from __future__ import annotations

import random
from enum import Enum
from typing import Iterator, Optional

from .geometry import RIGHT, Point


class StepOutcome(Enum):
    MOVED = "moved"
    ATE = "ate"
    DEAD_WALL = "dead-wall"
    DEAD_SELF = "dead-self"

    @property
    def is_death(self) -> bool:
        return self in (StepOutcome.DEAD_WALL, StepOutcome.DEAD_SELF)


class SnakeWorld:
    """The board state: a snake, one food item and deadly walls."""

    def __init__(self, width: int, height: int, seed: Optional[int] = None) -> None:
        self.width = width
        self.height = height
        self.rng = random.Random(seed)
        self.reset()

    # ------------------------------------------------------------------ #
    def reset(self) -> None:
        mid = Point(self.width // 2, self.height // 2)
        self.snake: list[Point] = [mid]
        self.direction: Point = RIGHT
        self._pending: Point = RIGHT
        self.score = 0
        self.steps = 0
        self.alive = True
        self.death_cell: Optional[Point] = None
        self.food: Point = self.spawn_food()

    # ------------------------------------------------------------------ #
    @property
    def head(self) -> Point:
        return self.snake[0]

    @property
    def length(self) -> int:
        return len(self.snake)

    def is_inside(self, point: Point) -> bool:
        return 0 <= point.x < self.width and 0 <= point.y < self.height

    def is_lethal(self, point: Point) -> bool:
        """Would the head die by moving onto this cell?

        The current tail cell is excluded: it moves away on the same step.
        """
        return not self.is_inside(point) or point in self.snake[:-1]

    def free_cells(self) -> Iterator[Point]:
        occupied = set(self.snake)
        for y in range(self.height):
            for x in range(self.width):
                point = Point(x, y)
                if point not in occupied:
                    yield point

    def spawn_food(self) -> Point:
        candidates = list(self.free_cells())
        return self.rng.choice(candidates) if candidates else self.head

    # ------------------------------------------------------------------ #
    def steer(self, direction: Point) -> None:
        """Queue a direction change, ignoring 180 degree turns."""
        if not direction.is_opposite(self.direction):
            self._pending = direction

    def step(self) -> StepOutcome:
        """Advance the snake by one cell and report what happened."""
        self.direction = self._pending
        new_head = self.head + self.direction
        self.steps += 1

        if not self.is_inside(new_head):
            self.alive = False
            self.death_cell = new_head
            return StepOutcome.DEAD_WALL
        if new_head in self.snake[:-1]:
            self.alive = False
            self.death_cell = new_head
            return StepOutcome.DEAD_SELF

        self.snake.insert(0, new_head)
        if new_head == self.food:
            self.score += 1
            self.food = self.spawn_food()
            return StepOutcome.ATE

        self.snake.pop()
        return StepOutcome.MOVED
