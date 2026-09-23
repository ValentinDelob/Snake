"""Automated players.

They exist for the self-test harness: the executable can then play a real
game on its own, exercising the loop, the rules and the renderer without a
human at the keyboard.
"""

from __future__ import annotations

from collections import deque
from typing import Optional

from . import config
from .geometry import DIRECTIONS, Point
from .logging_setup import get_logger

log = get_logger("agent")


class GreedyAgent:
    """Walks towards the food, avoiding immediate death.

    Moves are ranked by the amount of free space reachable afterwards, then
    by distance to the food, which keeps the snake out of dead ends long
    enough for a self-test to be meaningful.
    """

    def decide(self, game) -> Optional[Point]:
        head = game.head
        options = []
        for direction in DIRECTIONS:
            if direction.is_opposite(game.direction):
                continue
            target = head + direction
            if game.is_lethal(target):
                continue
            distance = abs(target.x - game.food.x) + abs(target.y - game.food.y)
            room = self._reachable_area(game, target)
            options.append((-room, distance, direction))

        if not options:
            log.debug("No safe move from (%s,%s)", head.x, head.y)
            return None

        options.sort(key=lambda item: (item[0] // 8, item[1]))
        return options[0][2]

    @staticmethod
    def _reachable_area(game, start: Point, limit: int = 120) -> int:
        """Flood fill the free space reachable from a cell (capped)."""
        blocked = set(game.snake[:-1])
        seen = {start}
        queue = deque([start])
        count = 0
        while queue and count < limit:
            cell = queue.popleft()
            count += 1
            for direction in DIRECTIONS:
                nxt = cell + direction
                if nxt in seen or nxt in blocked:
                    continue
                if not (0 <= nxt.x < config.GRID_WIDTH and 0 <= nxt.y < config.GRID_HEIGHT):
                    continue
                seen.add(nxt)
                queue.append(nxt)
        return count
