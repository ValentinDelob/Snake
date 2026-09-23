"""Window, main loop and scene stack.

The engine owns everything that is global to a session (display, clock,
fonts, player profile) and delegates behaviour to the scene on top of the
stack. Scenes can be stacked so that pause and game-over overlays keep the
board visible underneath.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

import pygame

from . import config
from .logging_setup import get_logger
from .profile_store import Profile

log = get_logger("engine")


@dataclass
class RunStats:
    """What a session did, reported to the logs and to the exit code."""

    best_score: int = 0
    last_score: int = 0
    max_score: int = 0  # best score of this session only
    games: int = 0
    steps: int = 0
    frames: int = 0
    reason: str = "unknown"
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


class Scene:
    """Base class for everything the engine can display."""

    #: when True the scene below stays visible (overlay scenes)
    transparent = False
    name = "scene"

    def __init__(self, engine: "Engine") -> None:
        self.engine = engine

    def on_enter(self) -> None:
        pass

    def on_exit(self) -> None:
        pass

    def handle_event(self, event: pygame.event.Event) -> None:
        pass

    def update(self, dt: float) -> None:
        pass

    def draw(self, surface: pygame.Surface) -> None:
        pass


class Engine:
    def __init__(
        self,
        seed: Optional[int] = None,
        agent=None,
        driver=None,
        max_steps: Optional[int] = None,
        profile_path=None,
    ) -> None:
        self.seed = seed
        self.agent = agent
        self.driver = driver
        self.max_steps = max_steps

        pygame.init()
        self.clock = pygame.time.Clock()
        self.screen = pygame.display.set_mode(config.WINDOW_SIZE)
        pygame.display.set_caption(config.WINDOW_TITLE)
        self.fonts = {
            "small": pygame.font.SysFont(config.FONT_NAME, config.FONT_SIZE_SMALL),
            "normal": pygame.font.SysFont(config.FONT_NAME, config.FONT_SIZE),
            "big": pygame.font.SysFont(config.FONT_NAME, config.FONT_SIZE_BIG, bold=True),
        }
        self.profile = Profile.load(profile_path)
        self.stats = RunStats(best_score=self.profile.high_score)
        self.scenes: list[Scene] = []
        self.running = True
        self.elapsed = 0.0

        log.info(
            "Engine ready: window=%sx%s grid=%sx%s player=%s seed=%s",
            config.WINDOW_SIZE[0],
            config.WINDOW_SIZE[1],
            config.GRID_WIDTH,
            config.GRID_HEIGHT,
            type(agent).__name__ if agent else "human",
            seed,
        )

    # ------------------------------------------------------------------ #
    # Scene stack
    # ------------------------------------------------------------------ #
    @property
    def scene(self) -> Optional[Scene]:
        return self.scenes[-1] if self.scenes else None

    def push(self, scene: Scene) -> None:
        log.info("Scene push: %s", scene.name)
        self.scenes.append(scene)
        scene.on_enter()

    def pop(self) -> None:
        if not self.scenes:
            return
        scene = self.scenes.pop()
        log.info("Scene pop: %s", scene.name)
        scene.on_exit()
        if not self.scenes:
            self.stop("empty-stack")

    def replace(self, scene: Scene) -> None:
        while self.scenes:
            self.pop_silent()
        self.push(scene)

    def pop_silent(self) -> None:
        scene = self.scenes.pop()
        scene.on_exit()

    def stop(self, reason: str) -> None:
        log.info("Stopping: %s", reason)
        self.stats.reason = reason
        self.running = False

    def report_error(self, message: str) -> None:
        log.error("%s", message)
        self.stats.errors.append(message)

    # ------------------------------------------------------------------ #
    # Main loop
    # ------------------------------------------------------------------ #
    def run(self) -> RunStats:
        log.info("Loop started")
        while self.running and self.scenes:
            dt = self.clock.tick(config.UI_FPS) / 1000.0
            self.elapsed += dt
            self.stats.frames += 1

            if self.driver is not None:
                try:
                    self.driver.on_frame(self)
                except Exception as exc:  # a broken driver must not hide the game
                    self.report_error("driver error: {}".format(exc))
                    log.exception("Driver raised")

            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.stop("quit")
                    break
                if self.scene is not None:
                    self.scene.handle_event(event)

            if not self.running:
                break
            if self.scene is not None:
                self.scene.update(dt)
            self._draw()

        self.stats.best_score = self.profile.high_score
        log.info(
            "Loop finished: reason=%s games=%s last=%s best=%s steps=%s frames=%s errors=%s",
            self.stats.reason,
            self.stats.games,
            self.stats.last_score,
            self.stats.best_score,
            self.stats.steps,
            self.stats.frames,
            self.stats.errors or "none",
        )
        pygame.quit()
        return self.stats

    def _draw(self) -> None:
        if not self.scenes:
            return
        first = len(self.scenes) - 1
        while first > 0 and self.scenes[first].transparent:
            first -= 1
        self.screen.fill(config.BG_COLOR)
        for scene in self.scenes[first:]:
            scene.draw(self.screen)
        pygame.display.flip()
