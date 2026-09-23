"""The screens of the game: menu, play, pause and game over."""

from __future__ import annotations

import math

import pygame

from . import config, ui
from .engine import Engine, Scene
from .geometry import DOWN, LEFT, RIGHT, UP
from .logging_setup import get_logger
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

_PAUSE_KEYS = (pygame.K_p, pygame.K_SPACE)


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

        pulse = 0.5 + 0.5 * math.sin(self.engine.elapsed * 3.0)
        title_color = ui.lerp_color(config.SNAKE_BODY_COLOR, config.SNAKE_HEAD_COLOR, pulse)

        ui.draw_text(surface, fonts["big"], "SNAKE", title_color, center=(width // 2, height // 3))
        ui.draw_text(
            surface,
            fonts["normal"],
            "ENTER  play",
            config.TEXT_COLOR,
            center=(width // 2, height // 2 + 10),
        )
        ui.draw_text(
            surface,
            fonts["small"],
            "arrows / WASD / ZQSD  move     P  pause     ESC  quit",
            config.TEXT_DIM_COLOR,
            center=(width // 2, height // 2 + 44),
        )
        ui.draw_text(
            surface,
            fonts["small"],
            "best score  {}     games played  {}".format(
                self.engine.profile.high_score, self.engine.profile.games_played
            ),
            config.ACCENT_COLOR,
            center=(width // 2, height - 40),
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

    # ------------------------------------------------------------------ #
    def restart(self) -> None:
        self.world.reset()
        self._accumulator = 0.0
        self._flash = 0.0
        log.info("Round restarted")

    # ------------------------------------------------------------------ #
    def handle_event(self, event: pygame.event.Event) -> None:
        if event.type != pygame.KEYDOWN:
            return
        if event.key == pygame.K_ESCAPE:
            self.engine.replace(MenuScene(self.engine))
        elif event.key in _PAUSE_KEYS:
            self.engine.push(PauseScene(self.engine))
        elif event.key in _KEY_TO_DIRECTION:
            direction = _KEY_TO_DIRECTION[event.key]
            self.world.steer(direction)
            log.debug("Steer key %s -> (%s,%s)", pygame.key.name(event.key), direction.x, direction.y)

    def update(self, dt: float) -> None:
        self._flash = max(0.0, self._flash - dt * 3.0)
        self._accumulator += dt
        while self._accumulator >= self.step_interval and self.world.alive:
            self._accumulator -= self.step_interval
            self._advance()

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
        self._draw_hud(surface)
        self._draw_board(surface)
        self._draw_food(surface)
        self._draw_snake(surface)

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
            "BEST {}".format(max(self.engine.profile.high_score, self.world.score)),
            config.ACCENT_COLOR,
            midright=(config.WINDOW_SIZE[0] - 12, config.HUD_HEIGHT // 2),
        )

    def _draw_board(self, surface: pygame.Surface) -> None:
        pygame.draw.rect(surface, config.BOARD_COLOR, ui.board_rect())
        origin_x, origin_y = config.BOARD_ORIGIN
        for x in range(config.GRID_WIDTH + 1):
            px = origin_x + x * config.CELL_SIZE
            pygame.draw.line(surface, config.GRID_COLOR, (px, origin_y), (px, config.WINDOW_SIZE[1]))
        for y in range(config.GRID_HEIGHT + 1):
            py = origin_y + y * config.CELL_SIZE
            pygame.draw.line(surface, config.GRID_COLOR, (origin_x, py), (config.WINDOW_SIZE[0], py))

    def _draw_food(self, surface: pygame.Surface) -> None:
        pulse = 0.5 + 0.5 * math.sin(self.engine.elapsed * 6.0)
        radius = int(config.CELL_SIZE * (0.30 + 0.06 * pulse))
        rect = ui.cell_rect(self.world.food.x, self.world.food.y)
        pygame.draw.circle(surface, config.FOOD_COLOR, rect.center, radius)
        pygame.draw.circle(surface, (255, 180, 180), rect.center, max(1, radius // 3))

    def _draw_snake(self, surface: pygame.Surface) -> None:
        length = self.world.length
        for index, segment in enumerate(self.world.snake):
            if index == 0:
                color = ui.lerp_color(config.SNAKE_HEAD_COLOR, (255, 255, 255), self._flash * 0.6)
                rect = ui.cell_rect(segment.x, segment.y, inset=1)
                pygame.draw.rect(surface, color, rect, border_radius=6)
                self._draw_eyes(surface, rect)
            else:
                t = index / max(1, length - 1)
                color = ui.lerp_color(config.SNAKE_BODY_COLOR, config.SNAKE_TAIL_COLOR, t)
                pygame.draw.rect(
                    surface, color, ui.cell_rect(segment.x, segment.y, inset=2), border_radius=4
                )

    def _draw_eyes(self, surface: pygame.Surface, head_rect: pygame.Rect) -> None:
        direction = self.world.direction
        offset = config.CELL_SIZE // 5
        side = (-direction.y, direction.x)  # perpendicular
        for sign in (-1, 1):
            cx = head_rect.centerx + direction.x * offset + side[0] * offset * sign
            cy = head_rect.centery + direction.y * offset + side[1] * offset * sign
            pygame.draw.circle(surface, (10, 20, 14), (int(cx), int(cy)), max(1, offset // 2))


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
            surface, self.engine.fonts["big"], "PAUSED", config.TEXT_COLOR, center=(width // 2, height // 2 - 10)
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

        ui.draw_text(surface, fonts["big"], "GAME OVER", config.FOOD_COLOR, center=(width // 2, height // 2 - 52))
        ui.draw_text(surface, fonts["small"], cause, config.TEXT_DIM_COLOR, center=(width // 2, height // 2 - 18))
        ui.draw_text(
            surface,
            fonts["normal"],
            "score {}".format(self.play.world.score),
            config.TEXT_COLOR,
            center=(width // 2, height // 2 + 14),
        )
        if self.record:
            ui.draw_text(
                surface, fonts["normal"], "NEW BEST!", config.ACCENT_COLOR, center=(width // 2, height // 2 + 44)
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
