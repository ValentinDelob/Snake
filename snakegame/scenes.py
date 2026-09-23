"""The screens of the game: menu, play, pause and game over."""

from __future__ import annotations

import math

import pygame

from . import config, ui
from .engine import Engine, Scene
from .geometry import DOWN, LEFT, RIGHT, UP, turn_left, turn_right
from .logging_setup import get_logger
from .render2d import Board2DRenderer
from .render3d import Board3DRenderer, CameraMode
from .world import SnakeWorld, StepOutcome

log = get_logger("scenes")

_KEY_TO_DIRECTION = {
    pygame.K_UP: UP,
    pygame.K_w: UP,
    pygame.K_z: UP,          # AZERTY
    pygame.K_DOWN: DOWN,
    pygame.K_s: DOWN,
    pygame.K_LEFT: LEFT,
    pygame.K_a: LEFT,
    pygame.K_q: LEFT,        # AZERTY
    pygame.K_RIGHT: RIGHT,
    pygame.K_d: RIGHT,
}

#: in the chase view the board has no fixed orientation, so steering is relative
_KEY_TO_TURN = {
    pygame.K_LEFT: turn_left,
    pygame.K_a: turn_left,
    pygame.K_q: turn_left,
    pygame.K_RIGHT: turn_right,
    pygame.K_d: turn_right,
}

_PAUSE_KEYS = (pygame.K_p, pygame.K_SPACE)
_VIEW_KEY = pygame.K_v
_CAMERA_KEY = pygame.K_c


def make_renderer(view: str, camera: str):
    """Build the renderer described by the stored preferences."""
    if view == "2d":
        return Board2DRenderer()
    try:
        mode = CameraMode(camera)
    except ValueError:
        log.warning("Unknown camera mode %r, falling back to follow", camera)
        mode = CameraMode.FOLLOW
    return Board3DRenderer(mode)


# --------------------------------------------------------------------------- #
class MenuScene(Scene):
    name = "menu"

    def handle_event(self, event: pygame.event.Event) -> None:
        if event.type != pygame.KEYDOWN:
            return
        if event.key in (pygame.K_RETURN, pygame.K_KP_ENTER, pygame.K_SPACE):
            self.engine.replace(PlayScene(self.engine))
        elif event.key == pygame.K_ESCAPE:
            self.engine.stop("menu-quit")

    def draw(self, surface: pygame.Surface) -> None:
        surface.fill(config.BG_COLOR)
        width, height = config.WINDOW_SIZE
        fonts = self.engine.fonts
        profile = self.engine.profile

        pulse = 0.5 + 0.5 * math.sin(self.engine.elapsed * 3.0)
        title_color = ui.lerp_color(config.SNAKE_BODY_COLOR, config.SNAKE_HEAD_COLOR, pulse)

        ui.draw_text(surface, fonts["big"], "SNAKE 3D", title_color, center=(width // 2, height // 3 - 8))
        ui.draw_text(
            surface,
            fonts["normal"],
            "ENTER  play",
            config.TEXT_COLOR,
            center=(width // 2, height // 2 + 4),
        )
        ui.draw_text(
            surface,
            fonts["small"],
            "arrows / WASD / ZQSD  move     P  pause     ESC  quit",
            config.TEXT_DIM_COLOR,
            center=(width // 2, height // 2 + 36),
        )
        ui.draw_text(
            surface,
            fonts["small"],
            "C  camera (follow / overview / chase)     V  2D-3D view",
            config.TEXT_DIM_COLOR,
            center=(width // 2, height // 2 + 58),
        )
        ui.draw_text(
            surface,
            fonts["small"],
            "view  {}  {}".format(profile.get("view", "3d").upper(), profile.get("camera", "follow")),
            config.TEXT_DIM_COLOR,
            center=(width // 2, height - 62),
        )
        ui.draw_text(
            surface,
            fonts["small"],
            "best score  {}     games played  {}".format(profile.high_score, profile.games_played),
            config.ACCENT_COLOR,
            center=(width // 2, height - 36),
        )


# --------------------------------------------------------------------------- #
class PlayScene(Scene):
    name = "play"

    def __init__(self, engine: Engine) -> None:
        super().__init__(engine)
        self.world = SnakeWorld(config.GRID_WIDTH, config.GRID_HEIGHT, seed=engine.seed)
        self.step_interval = 1.0 / config.STEP_HZ
        self._accumulator = 0.0
        self._flash = 0.0  # fades out after each bite
        self.renderer = make_renderer(
            engine.profile.get("view", config.DEFAULT_VIEW),
            engine.profile.get("camera", "follow"),
        )
        log.info("Renderer: %s (%s)", self.renderer.name, self._camera_label())

    # ------------------------------------------------------------------ #
    @property
    def view_name(self) -> str:
        return self.renderer.name

    @property
    def camera_name(self) -> str:
        return self._camera_label()

    def _camera_label(self) -> str:
        mode = getattr(self.renderer, "mode", None)
        return mode.value if mode is not None else "flat"

    @property
    def _relative_steering(self) -> bool:
        mode = getattr(self.renderer, "mode", None)
        return mode is not None and mode.uses_relative_steering

    def restart(self) -> None:
        self.world.reset()
        self._accumulator = 0.0
        self._flash = 0.0
        self.renderer.reset_camera()
        log.info("Round restarted")

    # ------------------------------------------------------------------ #
    def handle_event(self, event: pygame.event.Event) -> None:
        if event.type != pygame.KEYDOWN:
            return
        if event.key == pygame.K_ESCAPE:
            self.engine.replace(MenuScene(self.engine))
        elif event.key in _PAUSE_KEYS:
            self.engine.push(PauseScene(self.engine))
        elif event.key == _VIEW_KEY:
            self._toggle_view()
        elif event.key == _CAMERA_KEY:
            self._cycle_camera()
        else:
            self._steer(event.key)

    def _steer(self, key: int) -> None:
        if self._relative_steering:
            turn = _KEY_TO_TURN.get(key)
            if turn is None:
                return
            direction = turn(self.world.direction)
            self.world.steer(direction)
            log.debug("Relative turn -> (%s,%s)", direction.x, direction.y)
            return

        direction = _KEY_TO_DIRECTION.get(key)
        if direction is None:
            return
        self.world.steer(direction)
        log.debug("Steer key %s -> (%s,%s)", pygame.key.name(key), direction.x, direction.y)

    def _toggle_view(self) -> None:
        view = "2d" if self.renderer.name == "3d" else "3d"
        camera = self._camera_label() if self.renderer.name == "3d" else self.engine.profile.get("camera", "follow")
        self.renderer = make_renderer(view, camera)
        self.engine.profile.set_preference("view", view)
        log.info("View switched to %s (%s)", self.renderer.name, self._camera_label())

    def _cycle_camera(self) -> None:
        if self.renderer.name != "3d":
            log.info("Camera modes only apply to the 3D view")
            return
        mode = self.renderer.mode.next()
        self.renderer.set_mode(mode)
        self.engine.profile.set_preference("camera", mode.value)
        log.info("Camera mode: %s (steering=%s)", mode.value, "relative" if mode.uses_relative_steering else "absolute")

    # ------------------------------------------------------------------ #
    def update(self, dt: float) -> None:
        self._flash = max(0.0, self._flash - dt * 3.0)
        self._accumulator += dt
        while self._accumulator >= self.step_interval and self.world.alive:
            self._accumulator -= self.step_interval
            self._advance()
        self.renderer.update(dt, self.world)

    def _advance(self) -> None:
        engine = self.engine
        if engine.agent is not None:
            try:
                direction = engine.agent.decide(self.world)
            except Exception as exc:
                engine.report_error("agent error: {}".format(exc))
                log.exception("Agent raised")
                direction = None
            if direction is not None:
                self.world.steer(direction)

        outcome = self.world.step()
        engine.stats.steps += 1

        if outcome is StepOutcome.ATE:
            self._flash = 1.0
            log.debug("Food eaten: score=%s length=%s", self.world.score, self.world.length)
        elif outcome.is_death:
            self._on_death(outcome)
            return

        if engine.max_steps is not None and engine.stats.steps >= engine.max_steps:
            log.info("Step budget reached (%s)", engine.max_steps)
            engine.stop("step-budget")

    def _on_death(self, outcome: StepOutcome) -> None:
        engine = self.engine
        score = self.world.score
        record = engine.profile.record_game(score)
        engine.stats.last_score = score
        engine.stats.max_score = max(engine.stats.max_score, score)
        engine.stats.games += 1
        cell = self.world.death_cell
        log.info(
            "Game over (%s) at (%s,%s): score=%s length=%s steps=%s record=%s",
            outcome.value,
            cell.x if cell else "?",
            cell.y if cell else "?",
            score,
            self.world.length,
            self.world.steps,
            record,
        )
        engine.push(GameOverScene(engine, self, outcome, record))

    # ------------------------------------------------------------------ #
    def draw(self, surface: pygame.Surface) -> None:
        self.renderer.draw(surface, self.world, self.engine.elapsed, self._flash)
        self._draw_hud(surface)

    def _draw_hud(self, surface: pygame.Surface) -> None:
        fonts = self.engine.fonts
        pygame.draw.rect(surface, config.HUD_COLOR, (0, 0, config.WINDOW_SIZE[0], config.HUD_HEIGHT))
        pygame.draw.line(
            surface,
            config.GRID_COLOR,
            (0, config.HUD_HEIGHT - 1),
            (config.WINDOW_SIZE[0], config.HUD_HEIGHT - 1),
        )
        ui.draw_text(
            surface,
            fonts["normal"],
            "SCORE {}".format(self.world.score),
            config.TEXT_COLOR,
            topleft=(12, 11),
        )
        ui.draw_text(
            surface,
            fonts["small"],
            "{} {}".format(self.renderer.name.upper(), self._camera_label()),
            config.TEXT_DIM_COLOR,
            center=(config.WINDOW_SIZE[0] // 2, config.HUD_HEIGHT // 2),
        )
        ui.draw_text(
            surface,
            fonts["small"],
            "BEST {}".format(max(self.engine.profile.high_score, self.world.score)),
            config.ACCENT_COLOR,
            midright=(config.WINDOW_SIZE[0] - 12, config.HUD_HEIGHT // 2),
        )


# --------------------------------------------------------------------------- #
class PauseScene(Scene):
    name = "pause"
    transparent = True

    def handle_event(self, event: pygame.event.Event) -> None:
        if event.type != pygame.KEYDOWN:
            return
        if event.key in _PAUSE_KEYS or event.key == pygame.K_RETURN:
            self.engine.pop()
        elif event.key == pygame.K_ESCAPE:
            self.engine.replace(MenuScene(self.engine))

    def draw(self, surface: pygame.Surface) -> None:
        ui.dim(surface, 150)
        width, height = config.WINDOW_SIZE
        ui.draw_text(
            surface,
            self.engine.fonts["big"],
            "PAUSED",
            config.TEXT_COLOR,
            center=(width // 2, height // 2 - 10),
        )
        ui.draw_text(
            surface,
            self.engine.fonts["small"],
            "P or SPACE  resume     ESC  menu",
            config.TEXT_DIM_COLOR,
            center=(width // 2, height // 2 + 34),
        )


# --------------------------------------------------------------------------- #
class GameOverScene(Scene):
    name = "gameover"
    transparent = True

    def __init__(self, engine: Engine, play: PlayScene, outcome: StepOutcome, record: bool) -> None:
        super().__init__(engine)
        self.play = play
        self.outcome = outcome
        self.record = record

    def handle_event(self, event: pygame.event.Event) -> None:
        if event.type != pygame.KEYDOWN:
            return
        if event.key in (pygame.K_r, pygame.K_RETURN, pygame.K_SPACE):
            self.engine.pop()
            self.play.restart()
        elif event.key == pygame.K_m:
            self.engine.replace(MenuScene(self.engine))
        elif event.key == pygame.K_ESCAPE:
            self.engine.stop("gameover-quit")

    def draw(self, surface: pygame.Surface) -> None:
        ui.dim(surface, 180)
        width, height = config.WINDOW_SIZE
        fonts = self.engine.fonts
        cause = "you hit a wall" if self.outcome is StepOutcome.DEAD_WALL else "you bit yourself"

        ui.draw_text(
            surface, fonts["big"], "GAME OVER", config.FOOD_COLOR, center=(width // 2, height // 2 - 52)
        )
        ui.draw_text(
            surface, fonts["small"], cause, config.TEXT_DIM_COLOR, center=(width // 2, height // 2 - 18)
        )
        ui.draw_text(
            surface,
            fonts["normal"],
            "score {}".format(self.play.world.score),
            config.TEXT_COLOR,
            center=(width // 2, height // 2 + 14),
        )
        if self.record:
            ui.draw_text(
                surface,
                fonts["normal"],
                "NEW BEST!",
                config.ACCENT_COLOR,
                center=(width // 2, height // 2 + 44),
            )
        else:
            ui.draw_text(
                surface,
                fonts["small"],
                "best {}".format(self.engine.profile.high_score),
                config.ACCENT_COLOR,
                center=(width // 2, height // 2 + 44),
            )
        ui.draw_text(
            surface,
            fonts["small"],
            "R  retry     M  menu     ESC  quit",
            config.TEXT_DIM_COLOR,
            center=(width // 2, height - 34),
        )
