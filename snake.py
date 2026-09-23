# snake.py
"""
Simple Snake game written with pygame
-------------------------------------

Author : ChatGPT
License: MIT

How to play
-----------
* Arrow keys (or WASD) move the snake
* Food appears randomly; each bite increases length
* The game ends when the snake collides with itself or the wall
* Press ESC or close the window to quit

Dependencies
------------
Python ≥ 3.10
pygame

To run the game
---------------
    python snake.py

To create a Windows .exe
------------------------
    pip install pyinstaller
    pyinstaller --onefile --windowed snake.py

"""

import random
import sys
from dataclasses import dataclass
from typing import List, Tuple

try:
    import pygame
except ImportError:
    print("Missing dependency: pip install pygame")
    sys.exit(1)

# --------------------------------------------------------------------------- #
# Configuration constants
# --------------------------------------------------------------------------- #
CELL_SIZE = 20            # Size of a single grid cell (px)
GRID_WIDTH = 28          # Number of cells horizontally
GRID_HEIGHT = 18         # Number of cells vertically
WINDOW_SIZE = (GRID_WIDTH * CELL_SIZE, GRID_HEIGHT * CELL_SIZE)
FPS = 10                  # Game speed (frames per second)
BG_COLOR = (0, 0, 0)      # Black
SNAKE_COLOR = (0, 255, 0)# Green
FOOD_COLOR = (255, 0, 0)  # Red
SCORE_COLOR = (255, 255, 255)  # White
FONT_SIZE = 24
DEBUG = False            # Set to True to see debug output

# --------------------------------------------------------------------------- #
# Helper dataclasses
# --------------------------------------------------------------------------- #
@dataclass
class Point:
    x: int
    y: int

# --------------------------------------------------------------------------- #
# Main game logic
# --------------------------------------------------------------------------- #
class SnakeGame:
    def __init__(self) -> None:
        pygame.init()
        self.clock = pygame.time.Clock()
        self.screen = pygame.display.set_mode(WINDOW_SIZE)
        pygame.display.set_caption("Snake")
        self.font = pygame.font.SysFont("monospace", FONT_SIZE)

        # Initialise snake in the center
        mid_x, mid_y = GRID_WIDTH // 2, GRID_HEIGHT // 2
        self.snake: List[Point] = [Point(mid_x, mid_y)]
        self.direction = Point(1, 0)  # Start moving right

        self.food = self._spawn_food()
        self.score = 0
        self.game_over = False

    # --------------------------------------------------------------------- #
    def _spawn_food(self) -> Point:
        """Return a random cell that isn’t occupied by the snake."""
        while True:
            x = random.randint(0, GRID_WIDTH - 1)
            y = random.randint(0, GRID_HEIGHT - 1)
            food_pos = Point(x, y)
            if food_pos not in self.snake:
                return food_pos

    # --------------------------------------------------------------------- #
    def _handle_input(self) -> None:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.game_over = True
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    self.game_over = True
                elif event.key in (pygame.K_UP, pygame.K_w):
                    if self.direction.y == 0:  # prevent 180° turns
                        self.direction = Point(0, -1)
                elif event.key in (pygame.K_DOWN, pygame.K_s):
                    if self.direction.y == 0:
                        self.direction = Point(0, 1)
                elif event.key in (pygame.K_LEFT, pygame.K_a):
                    if self.direction.x == 0:
                        self.direction = Point(-1, 0)
                elif event.key in (pygame.K_RIGHT, pygame.K_d):
                    if self.direction.x == 0:
                        self.direction = Point(1, 0)

    # --------------------------------------------------------------------- #
    def _update(self) -> None:
        if self.game_over:
            return

        new_head = Point(
            self.snake[0].x + self.direction.x,
            self.snake[0].y + self.direction.y,
        )

        # Collision with walls
        if not (0 <= new_head.x < GRID_WIDTH and 0 <= new_head.y < GRID_HEIGHT):
            self.game_over = True
            return

        # Collision with itself
        if new_head in self.snake:
            self.game_over = True
            return

        # Eat food?
        if new_head == self.food:
            self.snake.insert(0, new_head)  # grow
            self.score += 1
            self.food = self._spawn_food()
        else:
            self.snake.insert(0, new_head)  # move
            self.snake.pop()  # remove tail

    # --------------------------------------------------------------------- #
    def _draw_cell(self, pos: Point, color: Tuple[int, int, int]) -> None:
        rect = pygame.Rect(
            pos.x * CELL_SIZE,
            pos.y * CELL_SIZE,
            CELL_SIZE,
            CELL_SIZE,
        )
        pygame.draw.rect(self.screen, color, rect)

    # --------------------------------------------------------------------- #
    def _render(self) -> None:
        self.screen.fill(BG_COLOR)

        # Draw food
        self._draw_cell(self.food, FOOD_COLOR)

        # Draw snake
        for segment in self.snake:
            self._draw_cell(segment, SNAKE_COLOR)

        # Draw score
        score_surf = self.font.render(f"Score: {self.score}", True, SCORE_COLOR)
        self.screen.blit(score_surf, (5, 5))

        # Game over message
        if self.game_over:
            overlay = pygame.Surface(WINDOW_SIZE)
            overlay.set_alpha(128)
            overlay.fill((0, 0, 0))
            self.screen.blit(overlay, (0, 0))

            msg = "GAME OVER – Press ESC to exit"
            surf = self.font.render(msg, True, SCORE_COLOR)
            rect = surf.get_rect(center=(WINDOW_SIZE[0] // 2, WINDOW_SIZE[1] // 2))
            self.screen.blit(surf, rect)

        pygame.display.flip()

    # --------------------------------------------------------------------- #
    def run(self) -> None:
        while not self.game_over:
            self._handle_input()
            self._update()
            self._render()
            self.clock.tick(FPS)

        # Keep the window open until user quits
        while True:
            for e in pygame.event.get():
                if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                    pygame.quit()
                    sys.exit()


# --------------------------------------------------------------------------- #
# Program entry point
# --------------------------------------------------------------------------- #
def main() -> None:
    game = SnakeGame()
    game.run()


if __name__ == "__main__":
    main()