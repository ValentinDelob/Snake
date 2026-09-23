# Snake

A pygame Snake game, built as a standalone Windows executable.

## Layout

```
snake.py            entry point (thin wrapper)
snakegame/
  config.py         constants, palette, paths
  logging_setup.py  rotating file log + crash capture
  geometry.py       grid points and directions
  world.py          pure game rules (no pygame)
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
| Esc | quit (or leave the current screen) |

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
play -> pause -> resume -> game over -> retry -> quit. Exit code `0` means
every screen was reached, the bot scored, two games completed and no error
was logged. The self-test uses its own profile file so the player's best
score is left untouched.

## Files produced at runtime

* `logs/snake.log` - rotating log (512 KiB x 4): environment banner, scene
  transitions, deaths, scores, uncaught exceptions.
* `savegame.json` - best score and number of games played.

Both sit next to the executable (or in the project root when run from
sources).
