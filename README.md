# Snake 3D

A Snake game built with **Godot 4.7**, exported as a standalone Windows
executable. It started life as a pygame prototype, which is kept, working, in
`legacy/python`.

## Layout

```
build.ps1                  export the game to dist\snake.exe
game/                      the Godot project (open this folder in Godot)
  project.godot            autoloads, renderer, file logging
  export_presets.cfg       Windows Desktop preset (single embedded .exe)
  scenes/main.tscn         world, sun, camera, board and HUD
  scripts/
    game.gd                state machine, input, fixed-step simulation
    snake_world.gd         the rules, with no dependency on nodes
    board_view.gd          floor, grid, ramparts, pooled snake meshes, food
    camera_rig.gd          follow / overview / chase cameras + flat top view
    hud.gd                 score bar and centred overlay
    journal.gd             autoload: structured logging
    profile_store.gd       autoload: best score and preferences
    greedy_agent.gd        bot used by the self-test
    selftest.gd            scripted end-to-end driver
    game_config.gd         shared constants and palette
legacy/python/             the original pygame implementation
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
| V | flat top-down view (the classic look) |
| Esc | quit, or leave the current screen |

## Cameras

* **follow** - a 3/4 view trailing the head, board orientation fixed
* **overview** - the whole board at once
* **chase** - right behind the head; the board turns with you, so steering
  becomes relative: left and right turn the snake
* **flat** (`V`) - orthographic top-down, like the original 2D game

The view and the camera are remembered between sessions.

## Build

```
.\build.ps1              # release  -> dist\snake.exe (single file, ~104 MiB)
.\build.ps1 -Debug       # debug build, keeps a console
```

The script finds Godot in `%LOCALAPPDATA%\Programs\Godot`, honours the
`GODOT` environment variable, imports the resources, then exports the
`Windows Desktop` preset. It needs the matching **export templates**
installed (`%APPDATA%\Godot\export_templates\<version>`).

## Run from the editor

```
game\  ->  open in Godot 4.7, then F5
```

## Self-test

The executable can drive itself through every screen and every camera, which
is how each build is validated:

```
dist\snake.exe --selftest
```

A bot plays while a scripted driver injects real key events: menu -> play ->
every camera -> flat view -> pause -> resume -> game over -> retry -> quit.
Exit code `0` means every state was reached, all four views were rendered,
the bot scored, two games completed, the frame rate stayed above 25 fps and
nothing was logged as an error.

Useful flags: `--seed N` (deterministic food), `--steps N` (safety budget).

`--demo` is the quiet cousin: the bot plays a normal game while you keep the
keyboard for the cameras, which is handy to look at the views or to leave the
game running on a screen.

## Logs

Godot's file logging is enabled in `project.godot`, so every run - engine
messages included - is written to:

```
%APPDATA%\Godot\app_userdata\Snake 3D\logs\snake.log
```

The previous four runs are kept beside it. The same folder holds
`savegame.json` with the best score, the games played and the view
preferences.

## The pygame original

`legacy/python` still builds and runs on its own:

```
cd legacy\python
py -m pip install -r requirements.txt
py snake.py            # play
py build.py            # -> legacy\python\dist\snake.exe
```

It contains its own software 3D renderer, written before the move to Godot.
