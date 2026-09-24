class_name GameConfig
extends RefCounted

## Tunable constants shared by every script, so gameplay code stays free of
## magic numbers.
##
## The board is a continuous rectangle, not a grid: positions are floats,
## X grows right and Y (of the 2D simulation) maps to Z in the 3D world.

const BOARD_WIDTH := 30.0
const BOARD_HEIGHT := 20.0

## The snake never stops: it cruises forward and only turns.
const SNAKE_SPEED := 5.2          # world units per second
const TURN_RATE := 3.1            # radians per second while a turn is held
const SNAKE_RADIUS := 0.36
const SEGMENT_SPACING := 0.42     # sampling used by collisions
const START_BODY_LENGTH := 2.6    # world units of body behind the head
const GROWTH_PER_FOOD := 1.1
## The body does not jump to its new length: it grows into it.
const GROWTH_SPEED := 2.2         # world units per second
## Body close to the head is ignored by self collision: it always touches.
const SELF_COLLISION_SKIP := 1.5

const FOOD_RADIUS := 0.4

## Speed boost: a lightning bolt lying on the arena, kept in the item slot
## until the player fires it with space.
const BOOST_RADIUS := 0.5
const BOOST_FIRST_SPAWN := Vector2(7.0, 12.0)   # seconds, min and max
const BOOST_RESPAWN := Vector2(16.0, 28.0)      # rarer afterwards
const BOOST_DURATION := 7.0                     # seconds of boosted speed
const BOOST_FACTOR := 2.0                       # top speed multiplier
const BOOST_RAMP_UP := 0.8                      # seconds to reach it
const BOOST_RAMP_DOWN := 1.0                    # seconds to settle back

## Mystery crate: same idea, but what comes out is a gamble.
const MYSTERY_RADIUS := 0.55
const MYSTERY_FIRST_SPAWN := Vector2(9.0, 15.0)
const MYSTERY_RESPAWN := Vector2(18.0, 30.0)
const MYSTERY_BONUS_CHANCE := 0.5
## A crate is a gamble on four faces: a speed boost or three points on the
## good side, a slow down or three points lost on the bad one.
const MYSTERY_SCORE_CHANCE := 0.5    # share of each side that is a score card
const SCORE_CARD_POINTS := 3

## The slow down. It never lies on the arena: it only comes out of a crate,
## and it is forced on the snake straight away.
const SLOW_DURATION := 5.0
const SLOW_FACTOR := 0.5
const SLOW_RAMP_DOWN := 0.5    # seconds to lose the speed
const SLOW_RAMP_UP := 1.0      # seconds to get it back

## Body mesh: a tube swept along the path the head travelled.
const TUBE_RING_SPACING := 0.22   # distance between two rings of the tube
const TUBE_RADIAL_SEGMENTS := 10  # vertices around the body
const HEAD_BULGE := 1.3           # how much thicker the head is
const HEAD_BULGE_LENGTH := 0.9    # over how much body the bulge fades out
const TAIL_TAPER := 0.45          # thickness left just before the tail tip

## The simulation runs at a fixed rate so it behaves the same on any machine.
const SIM_HZ := 120.0
const SIM_STEP := 1.0 / SIM_HZ

## A frame slower than this is logged as a stutter.
const SLOW_FRAME_SECONDS := 0.15

## Rocks scattered over the arena. They are never placed on a spawn point
## nor in the lane a snake sets off along, so nobody starts a round already
## boxed in; everywhere else they are fair game and come in several sizes.
const OBSTACLE_COUNT := Vector2i(5, 8)
const OBSTACLE_RADIUS := Vector2(0.85, 2.6)
const OBSTACLE_GAP := 3.0            # room left between two rocks
const OBSTACLE_WALL_GAP := 2.2       # corridor left between a rock and a wall
const OBSTACLE_GAP_TIGHT := 1.8      # the closest two rocks may sit when room runs out
const OBSTACLE_SPAWN_CLEAR := 5.0    # room left around a spawn point
const OBSTACLE_LANE_LENGTH := 14.0   # how far ahead the spawn lane is kept clear
const OBSTACLE_LANE_MIN := 6.0       # never less than this, however crowded
const OBSTACLE_LANE_CLEAR := 2.2     # half width of that lane
const OBSTACLE_COLOR := Color(0.24, 0.29, 0.38)

const FLOOR_COLOR := Color(0.13, 0.17, 0.23)
const GRID_COLOR := Color(0.18, 0.22, 0.29)
const WALL_COLOR := Color(0.27, 0.34, 0.43)
const SNAKE_HEAD_COLOR := Color(0.47, 1.0, 0.59)
const SNAKE_BODY_COLOR := Color(0.0, 0.78, 0.35)
const SNAKE_TAIL_COLOR := Color(0.0, 0.33, 0.18)
const FOOD_COLOR := Color(1.0, 0.27, 0.27)
const EYE_COLOR := Color(0.04, 0.08, 0.05)

const BOOST_COLOR := Color(1.0, 0.86, 0.28)
const SPARK_COLOR := Color(1.0, 0.98, 0.78)
const MYSTERY_COLOR := Color(0.72, 0.45, 1.0)
const FROST_COLOR := Color(0.48, 0.78, 1.0)
const FROST_PALE_COLOR := Color(0.85, 0.95, 1.0)

## One palette per player: head, body, tail. The first is always yours.
const PLAYER_PALETTES := [
	[Color(0.47, 1.0, 0.59), Color(0.0, 0.78, 0.35), Color(0.0, 0.33, 0.18)],
	[Color(0.55, 0.86, 1.0), Color(0.12, 0.52, 0.95), Color(0.05, 0.2, 0.48)],
	[Color(1.0, 0.78, 0.45), Color(0.95, 0.5, 0.12), Color(0.45, 0.19, 0.03)],
	[Color(1.0, 0.62, 0.95), Color(0.83, 0.2, 0.7), Color(0.38, 0.06, 0.32)],
	[Color(0.85, 0.95, 0.5), Color(0.55, 0.78, 0.1), Color(0.22, 0.33, 0.03)],
]


static func palette_for(index: int) -> Array:
	return PLAYER_PALETTES[index % PLAYER_PALETTES.size()]


const ACCENT_COLOR := Color(1.0, 0.82, 0.31)
const DANGER_COLOR := Color(1.0, 0.35, 0.35)
const TEXT_COLOR := Color(0.93, 0.94, 0.96)
const DIM_COLOR := Color(0.51, 0.56, 0.62)
