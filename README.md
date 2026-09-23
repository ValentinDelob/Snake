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
  shaders/
    snake_body.gdshader    skin: gradient, belly, scales, rim, boost bolts
    arena_floor.gdshader   floor: anti-aliased grid, vignette, light pool
  scripts/
    game.gd                state machine, input, fixed-step simulation
    snake_world.gd         continuous rules: position, heading, trailing path
    board_view.gd          floor, ramparts, food and the snake mesh
    snake_mesh.gd          the body: procedural tube, gradient and lightning
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
| Left / Right (or A-D, Q-D) | **hold** to turn the head |
| Space | fire the item in the slot |
| Enter | start a game / retry |
| P | pause / resume |
| R | retry after a game over |
| M | back to the menu |
| C | cycle camera: follow, overview, chase |
| V | flat top-down view (the classic look) |
| Esc | quit, or leave the current screen |

## How it plays

The snake never stops and there is no grid: it cruises forward at a constant
speed on a continuous arena, and the only control is the heading - hold left
or right to turn the head, and the body slides along the exact path the head
travelled. Food appears at a random spot of the arena, not on cell centres,
and each bite makes the body longer.

Because steering is relative, every camera is playable; chase is simply the
most immersive.

### Look

The arena is lit rather than flat-coloured: a warm directional sun casting
shadows, a dim ambient fill, ACES tone mapping and a touch of bloom on the
bright things (the bolt, the boost, the title).

Two shaders do the rest:

* `snake_body.gdshader` paints the skin from the mesh UVs - length along the
  body drives the head-to-tail gradient, angle around it draws a paler belly
  and faint diamond scales. A rim light keeps the silhouette readable against
  the dark floor, the head glows a little (more right after a bite), and the
  boost sends bolts of light running down the whole body.
* `arena_floor.gdshader` draws the grid with screen-space derivatives, so it
  stays crisp near the camera and fades in the distance instead of
  shimmering, darkens towards the walls, and lights a pool of ground under
  the snake while it is boosted.

Two small lights ride the props: one on the head, barely there normally and
electric while the boost burns, and one on the bolt, throbbing so it catches
the eye across a dark arena.

### Items

A lightning bolt shows up on the arena from time to time - rarely, and never
more than one at a time. Running over it stores it in the item slot shown in
the HUD (a small ring flashes where it was). Press **space** when you want
it: lightning crackles along the whole body and the speed eases up to twice
the cruising pace for seven seconds, then eases back down. Turning rate does
not change, so a boost is as risky as it is fast.

The body is a single procedural tube rebuilt every frame: a ring of vertices
is swept along the path the head travelled, from a rounded nose to a pointed
tail, so there are no repeated meshes and no visible joints. Thickness bulges
at the head and tapers towards the tail, and the green gradient is carried by
vertex colours. Eating does not snap the body to its new length either: the
snake grows into it over a fraction of a second.

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
every camera -> flat view -> steering test -> boost test -> pause -> resume
-> game over -> retry -> quit. It holds the left key and then the right key
and checks the heading actually turned each way; it drops a bolt, lets the
bot fetch it, fires it with space and follows the speed ramp; and it samples
the body to make sure the segments keep a constant spacing - a gap would mean
the snake jumps instead of sliding. If the snake dies mid-sequence the driver
retries and picks the phase back up.

Exit code `0` means every state was reached, all four views were rendered,
both turns registered, the bolt was collected and fired, the speed reached
x2 and came back to x1, the body stayed continuous and grew progressively,
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
