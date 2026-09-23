"""Grid primitives shared by every gameplay module."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Point:
    """An immutable cell coordinate (also used as a direction vector)."""

    x: int
    y: int

    def __add__(self, other: "Point") -> "Point":
        return Point(self.x + other.x, self.y + other.y)

    def is_opposite(self, other: "Point") -> bool:
        return self.x == -other.x and self.y == -other.y


UP = Point(0, -1)
DOWN = Point(0, 1)
LEFT = Point(-1, 0)
RIGHT = Point(1, 0)

DIRECTIONS = (UP, DOWN, LEFT, RIGHT)
