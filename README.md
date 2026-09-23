# Snake 3D

A pygame Snake game rendered with a home-made software 3D engine, built as a
standalone Windows executable.

## Layout

```
snake.py            entry point (thin wrapper)
snakegame/
  config.py         constants, palette, paths
  logging_setup.py  rotating file log + crash capture
  geometry.py       grid points and directions
  world.py          pure game rules (no pygame)
  render3d.py       software 3D renderer (projection, clipping, shading)
  render2d.py       classic flat renderer
  engine.py         window, main loop, scene stack, run stats
  scenes.py         menu / play / pause / game over screens
  profile_store.py  persistent player profile (best score)
  ui.py             drawing helpers
  agents.py         automated players
  selftest.py       scripted end-to-end driver
  app.py            command line interface
build.py            PyInstaller build script
```

## Controls

| Key | Action |
| --- | --- |
| Arrows, WASD, ZQSD | steer |
| Enter | start a game / retry |
| P or Space | pause / resume |
| R | retry after a game over |
| M | back to the menu |
| C | cycle camera: follow, overview, chase |
| V | switch between the 3D and the flat 2D view |
| Esc | quit (or leave the current screen) |

## The 3D view

The board is drawn by `render3d.py`, a small software rasteriser: no OpenGL,
no GPU driver needed, so the executable starts anywhere. It projects the grid
with a perspective camera, clips geometry against the near plane and the
viewport, sorts faces back to front and shades them with a directional light.

Three cameras, cycled with `C`:

* **follow** - a 3/4 view trailing the head, board orientation fixed
* **overview** - the whole board at once
* **chase** - right behind the head; the board turns with you, so steering
  becomes relative: left and right turn, there is no absolute direction

`V` switches back to the original flat view at any time. Both preferences are
remembered in `savegame.json`.

## Run from sources

```
py -m pip install -r requirements.txt
py snake.py
```

## Build the executable

```
py build.py          # -> dist/snake.exe
```

## Self-test

The executable can drive itself through every screen, which is how each build
is validated:

```
dist\snake.exe --selftest
```

A bot plays a real game while a scripted driver presses the keys: menu ->
play -> every camera -> both renderers -> pause -> resume -> game over ->
retry -> quit. Exit code `0` means every screen was reached, all three
cameras and both views were rendered, the bot scored, two games completed,
the frame rate stayed above 25 fps and no error was logged. The self-test uses its own profile file so the player's best
score is left untouched.

## Files produced at runtime

* `logs/snake.log` - rotating log (512 KiB x 4): environment banner, scene
  transitions, deaths, scores, uncaught exceptions.
* `savegame.json` - best score and number of games played.

Both sit next to the executable (or in the project root when run from
sources).
