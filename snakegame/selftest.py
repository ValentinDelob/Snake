"""End-to-end self-test driver.

The driver feeds synthetic key presses to a real, windowed run of the game so
that a build can be validated without a human: it walks the whole scene
machine (menu -> play -> pause -> play -> game over -> retry -> quit), lets a
bot score points along the way, and records what it saw.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import pygame

from .logging_setup import get_logger

log = get_logger("selftest")


def _press(key: int) -> None:
    pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=key, mod=0, unicode="", scancode=0))


@dataclass
class SelfTestDriver:
    """Scripted player driving the engine through every scene."""

    pause_at_step: int = 25
    pause_frames: int = 30
    release_agent_at_step: int = 45

    scenes_seen: set[str] = field(default_factory=set)
    _entered_play: bool = False
    _paused_done: bool = False
    _pause_frame: int = 0
    _agent_released: bool = False
    _retried: bool = False
    _finished: bool = False

    # ------------------------------------------------------------------ #
    def on_frame(self, engine) -> None:
        scene = engine.scene
        if scene is None:
            return
        if scene.name not in self.scenes_seen:
            log.info("Self-test reached scene: %s", scene.name)
            self.scenes_seen.add(scene.name)

        handler = getattr(self, "_on_" + scene.name, None)
        if handler is not None:
            handler(engine)

    # ------------------------------------------------------------------ #
    def _on_menu(self, engine) -> None:
        if self._finished:
            _press(pygame.K_ESCAPE)
        elif engine.elapsed > 0.5 and not self._entered_play:
            log.info("Self-test: starting a game from the menu")
            self._entered_play = True
            _press(pygame.K_RETURN)

    def _on_play(self, engine) -> None:
        steps = engine.stats.steps
        if not self._paused_done and steps >= self.pause_at_step:
            log.info("Self-test: pausing at step %s", steps)
            _press(pygame.K_p)
        elif (
            self._paused_done
            and not self._agent_released
            and steps >= self.release_agent_at_step
        ):
            log.info("Self-test: releasing the bot to provoke a game over")
            self._agent_released = True
            engine.agent = None

    def _on_pause(self, engine) -> None:
        self._pause_frame += 1
        if self._pause_frame >= self.pause_frames:
            log.info("Self-test: resuming after %s paused frames", self._pause_frame)
            self._paused_done = True
            _press(pygame.K_p)

    def _on_gameover(self, engine) -> None:
        if not self._retried:
            log.info("Self-test: retrying from the game over screen")
            self._retried = True
            _press(pygame.K_r)
        else:
            log.info("Self-test: quitting from the game over screen")
            self._finished = True
            _press(pygame.K_ESCAPE)

    # ------------------------------------------------------------------ #
    def verify(self, stats) -> list[str]:
        """Return the list of failed expectations (empty means success)."""
        failures: list[str] = []
        expected_scenes = {"menu", "play", "pause", "gameover"}
        missing = expected_scenes - self.scenes_seen
        if missing:
            failures.append("scenes never reached: {}".format(sorted(missing)))
        if stats.max_score <= 0:
            failures.append("the bot never scored a point (session best={})".format(stats.max_score))
        if stats.games < 2:
            failures.append("expected 2 finished games, got {}".format(stats.games))
        if not self._retried:
            failures.append("the retry path was never exercised")
        if stats.errors:
            failures.append("engine reported errors: {}".format(stats.errors))
        if stats.reason not in ("gameover-quit", "quit", "menu-quit", "step-budget"):
            failures.append("unexpected stop reason: {}".format(stats.reason))
        return failures
