"""End-to-end self-test driver.

The driver feeds synthetic key presses to a real, windowed run of the game so
that a build can be validated without a human: it walks the whole scene
machine (menu -> play -> pause -> play -> game over -> retry -> quit), cycles
through every camera and both renderers, lets a bot score points along the
way, and records what it saw.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import pygame

from .logging_setup import get_logger

log = get_logger("selftest")

MIN_ACCEPTABLE_FPS = 25.0


def _press(key: int) -> None:
    pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=key, mod=0, unicode="", scancode=0))


@dataclass
class SelfTestDriver:
    """Scripted player driving the engine through every scene and view."""

    #: step -> key to press once the play scene reaches it
    schedule: dict[int, int] = field(
        default_factory=lambda: {
            10: pygame.K_c,  # follow -> overview
            16: pygame.K_c,  # overview -> chase (relative steering)
            22: pygame.K_c,  # chase -> follow (wraps around)
            28: pygame.K_v,  # 3D -> 2D
            34: pygame.K_v,  # 2D -> 3D
            40: pygame.K_p,  # pause
        }
    )
    pause_frames: int = 30
    release_agent_at_step: int = 52

    scenes_seen: set[str] = field(default_factory=set)
    views_seen: set[str] = field(default_factory=set)
    cameras_seen: set[str] = field(default_factory=set)
    _done_steps: set[int] = field(default_factory=set)
    _entered_play: bool = False
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
        scene = engine.scene
        self.views_seen.add(scene.view_name)
        self.cameras_seen.add(scene.camera_name)

        steps = engine.stats.steps
        for step, key in self.schedule.items():
            if steps >= step and step not in self._done_steps:
                self._done_steps.add(step)
                log.info("Self-test: pressing %s at step %s", pygame.key.name(key), steps)
                _press(key)
                return

        if not self._agent_released and steps >= self.release_agent_at_step:
            log.info("Self-test: releasing the bot to provoke a game over")
            self._agent_released = True
            engine.agent = None

    def _on_pause(self, engine) -> None:
        self._pause_frame += 1
        if self._pause_frame >= self.pause_frames:
            log.info("Self-test: resuming after %s paused frames", self._pause_frame)
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
        missing_scenes = {"menu", "play", "pause", "gameover"} - self.scenes_seen
        if missing_scenes:
            failures.append("scenes never reached: {}".format(sorted(missing_scenes)))
        missing_views = {"2d", "3d"} - self.views_seen
        if missing_views:
            failures.append("views never rendered: {}".format(sorted(missing_views)))
        missing_cameras = {"follow", "overview", "chase"} - self.cameras_seen
        if missing_cameras:
            failures.append("camera modes never used: {}".format(sorted(missing_cameras)))
        if stats.max_score <= 0:
            failures.append("the bot never scored a point (session best={})".format(stats.max_score))
        if stats.games < 2:
            failures.append("expected 2 finished games, got {}".format(stats.games))
        if not self._retried:
            failures.append("the retry path was never exercised")
        if stats.fps < MIN_ACCEPTABLE_FPS:
            failures.append("frame rate too low: {:.1f} fps".format(stats.fps))
        if stats.errors:
            failures.append("engine reported errors: {}".format(stats.errors))
        if stats.reason not in ("gameover-quit", "quit", "menu-quit", "step-budget"):
            failures.append("unexpected stop reason: {}".format(stats.reason))
        return failures
