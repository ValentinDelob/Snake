# Snake 3D

A snake that never stops, on a wide dark field strewn with glowing matter,
built with **Godot 4.7** and exported as a standalone Windows executable.
It started life as a pygame prototype, kept working in `legacy/python`.

The game has drifted a long way from the original Snake: there is no grid,
dying does not end anything, and the score is not a tally of points but the
length of the snake itself. Eat, and you grow wide, slow and hard to turn.
After five minutes, the biggest snake takes the round - against friends over
the network, or alone against up to four rivals the machine drives.

> **The rules, the working method and the decisions already taken live in
> [`docs/`](docs/).** Start there before changing anything.

## Layout

```
build.ps1                  export the game to dist\snake.exe
docs/                      what the game is, how to work on it, and why
game/                      the Godot project (open this folder in Godot)
  project.godot            autoloads, renderer, file logging
  export_presets.cfg       Windows Desktop preset (single embedded .exe)
  scenes/main.tscn         world, sun, camera, board and HUD
  shaders/
    snake_body.gdshader    skin: gradient, belly, scales, rim, boost, ghost
    arena_floor.gdshader   floor: anti-aliased grid, vignette, light pool
  scripts/
    game.gd                state machine, input, fixed-step simulation
    snake_world.gd         one snake: position, heading, girth, trailing path
    snake_match.gd         the round: field, rocks, items, deaths, the clock
    net/session.gd         autoload: hosting, joining, the peer list
    board_view.gd          floor, ramparts, rocks, motes and the snake mesh
    snake_mesh.gd          the body: procedural tube, quality modes
    camera_rig.gd          follow / overview / chase cameras + flat top view
    hud.gd                 the interface, built in code
    ui/item_slot.gd        the item slot: bolt, ring and countdown
    journal.gd             autoload: structured logging
    profile_store.gd       autoload: best length and preferences
    greedy_agent.gd        bot used by the self-test, the demo and the rivals
    rival_brain.gd         a solo rival: steering, items, bringing matter up
    selftest.gd            scripted end-to-end driver
    frame_profiler.gd      where a frame goes, and how bad the worst ones are
    game_config.gd         every tunable number, and the palette
  tools/
    check_arena.gd         lays out two thousand arenas and checks them
    bench_mesh.gd          the cost of the body, by length and quality mode
legacy/python/             the original pygame implementation
```

## Controls

| Key | Action |
| --- | --- |
| Left / Right (or A-D, Q-D) | **hold** to turn the head |
| Space | fire the item in the slot |
| E | bring up a tenth of what you have swallowed |
| Enter | start a game / confirm |
| P | pause / resume |
| R | play another round from the result screen |
| M | back to the menu |
| C | cycle camera: follow, overview, chase, top |
| V | flat top-down view (the classic look) |
| Esc | quit, or leave the current screen |

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

## Validate a build

```
dist\snake.exe --selftest
```

The executable drives itself through every screen, every camera and every
item, dies, comes back, and waits out the clock, then reads its own log back
to make sure neither the game nor the engine wrote an error. Exit code `0`
means the whole sheet came back green. See
[`docs/methode-de-travail.md`](docs/methode-de-travail.md) for the rest of
the flags and the tools.
