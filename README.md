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
    snake_world.gd         one snake: position, heading, trailing path
    snake_match.gd         the round: arena, food, crates, collisions, winner
    net/session.gd         autoload: hosting, joining, the peer list
    board_view.gd          floor, ramparts, food and the snake mesh
    snake_mesh.gd          the body: procedural tube, gradient and lightning
    camera_rig.gd          follow / overview / chase cameras + flat top view
    hud.gd                 the interface, built in code
    ui/item_slot.gd        the item slot: bolt, ring and countdown
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

### Interface

The interface is built in code from styled panels rather than bare labels:
rounded pills for the score, the camera and the best score, a drawn item
slot - a lightning bolt in a disc, with a ring that empties like a fuse
while the boost burns - and a centred card for the menu, the pause and the
game over screens. Each card leads with the one action worth taking, shown
as a keycap and a verb, with the rest of the keys listed underneath.

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

Small lights ride the props: one on the head - barely there normally,
electric while a boost burns, cold while the snake is frozen - one on the
bolt and one on the crate, throbbing so they catch the eye across a dark
arena.

The game runs on the **Forward+ (Vulkan)** renderer. It used to use the
OpenGL Compatibility renderer, until a run crashed inside the NVIDIA driver
(`nvwgf2umx.dll`, access violation, confirmed in the Windows event log).
Vulkan takes a completely different driver path; `gl_compatibility` is kept
as the fallback method for machines without it.

### Playing together

`H` in the menu opens a session and prints the addresses another machine can
reach you on; `J` joins the last address used. Everyone waits in a lobby
until the host presses `ENTER`, then all the snakes spawn around a circle in
the same arena, each in its own colour, with a scoreboard in the corner.

**The last one standing wins.** Running into another snake is as fatal as
running into a wall or into yourself. A player who dies before the end does
not leave: the camera detaches and they fly freely over the arena with the
arrow keys, inside its bounds, until the round ends. Then everybody sees who
won and the host can start another round.

The host is authoritative: it runs the one and only match and sends the
arena twenty times a second, while a client sends nothing but its steering.
That way the two machines can never disagree about who died first. Between
snapshots a client keeps the snakes gliding on their own, so the motion
stays smooth whatever the tick rate.

### Items

A **lightning bolt** shows up on the arena from time to time - rarely, and
never more than one at a time. Running over it stores it in the item slot
shown in the HUD. Press **space** when you want it: lightning crackles along
the whole body and the speed eases up to twice the cruising pace for seven
seconds, then eases back down. Turning rate does not change, so a boost is
as risky as it is fast.

A **crate** marked with a question mark turns up more rarely still, and it
is a gamble: half the time it holds a speed boost, which goes to the slot
for you to fire when you choose. The other half it holds the **slow down**,
which is never offered and never lies on the arena - it is forced on the
snake the moment the crate opens. Frost creeps over the body, the light
around it turns cold and the speed halves for five seconds before easing
back. The slot keeps whatever it was already holding.

`--demo` also lets you drop items on request, `B` for a bolt and `N` for a
crate, alternating between the bonus and the curse.

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
nothing - the game or the engine - wrote an error in the log. That last
check reads the log file back: engine errors never reached the game code,
and one of them once shipped unnoticed.

Useful flags: `--seed N` (deterministic food), `--steps N` (safety budget),
`--host` / `--join <address>` to open or join a session on startup, and
`--lose-after N` to tell an instance when to stop steering, which is how the
network test decides who falls first.

The network run is the same harness with three instances on one machine: a
host and two clients, the host told to give up first so it dies while the
others are still playing. Each instance checks that it saw the other
players, that their snakes really moved (which only happens if snapshots
arrive), that the round ended with a winner all three agree on, and that
dying put it into the spectator camera. All three must exit `0`.

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
