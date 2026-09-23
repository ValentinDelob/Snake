# Snake

A pygame Snake game, built as a standalone Windows executable.

## Layout

```
snake.py            entry point (thin wrapper)
snakegame/
  config.py         constants, palette, paths
  logging_setup.py  rotating file log + crash capture
  geometry.py       grid points and directions
  game.py           game loop and rules
  agents.py         automated players (self-test)
  app.py            command line interface
build.py            PyInstaller build script
```

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

The executable can play a game on its own, which is how each build is
validated:

```
dist\snake.exe --selftest --ticks 300
```

Exit code `0` means the automated run scored at least one point without
errors. The full trace is written to `logs/snake.log`, next to the
executable.

## Logs

Every run appends to `logs/snake.log` (rotating, 512 KiB x 4). It records the
environment banner, display setup, deaths, scores and any uncaught exception.
