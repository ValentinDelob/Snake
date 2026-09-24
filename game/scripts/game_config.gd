class_name GameConfig
extends RefCounted

## Tunable constants shared by every script, so gameplay code stays free of
## magic numbers.
##
## The board is a continuous rectangle, not a grid: positions are floats,
## X grows right and Y (of the 2D simulation) maps to Z in the 3D world.

const BOARD_WIDTH := 30.0
const BOARD_HEIGHT := 20.0

## The arena grows with the crowd. Two players get half as much floor again
## as one, three get twice, and so on - room enough that a second snake is
## an opponent to hunt rather than a wall you back into at once. Both sides
## grow by the same factor, so the arena keeps its shape and everything
## framed against it - the cameras, the spawn circle - still fits.
const BOARD_GROWTH_PER_PLAYER := 0.5


static func arena_for(players: int) -> Vector2:
	var floor_scale := sqrt(1.0 + BOARD_GROWTH_PER_PLAYER * float(maxi(1, players) - 1))
	return Vector2(BOARD_WIDTH * floor_scale, BOARD_HEIGHT * floor_scale)

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
## The ghost ring: the rarest thing on the arena. It buys one second of
## walking through bodies - yours and everybody else's - which is long
## enough to cut a corner nobody else can cut, and short enough that it
## has to be spent on purpose.
const PHASE_RADIUS := 0.55
const PHASE_FIRST_SPAWN := Vector2(35.0, 60.0)   # seconds, min and max
const PHASE_RESPAWN := Vector2(55.0, 95.0)       # rarer still afterwards
const PHASE_DURATION := 1.0

const SLOW_DURATION := 5.0
const SLOW_FACTOR := 0.5
const SLOW_RAMP_DOWN := 0.5    # seconds to lose the speed
const SLOW_RAMP_UP := 1.0      # seconds to get it back

## Body mesh: a tube swept along the path the head travelled.
##
## The tube is the only thing in the game whose cost grows while you play,
## so how finely it is cut is a setting rather than a constant. Each mode
## says how many vertices go around the body, how far apart the rings sit
## behind the head, how far apart they are allowed to drift towards the
## tail (which is straighter and thinner, so it needs fewer), over what
## length that drift happens, and how many rings round off the nose.
enum Quality { SIMPLE, SMOOTH, FINE }

const QUALITY_MODES := [
	{
		"name": "simple", "label": "SIMPLE", "note": "fewest faces, fastest",
		"radial": 5, "ring": 0.55, "ring_tail": 1.1, "detail": 4.0, "nose": 2,
	},
	{
		"name": "smooth", "label": "SMOOTH", "note": "the default balance",
		"radial": 7, "ring": 0.34, "ring_tail": 0.7, "detail": 6.0, "nose": 3,
	},
	{
		"name": "fine", "label": "FINE", "note": "roundest body, most faces",
		"radial": 10, "ring": 0.22, "ring_tail": 0.34, "detail": 8.0, "nose": 4,
	},
]

## Which mode is in force. Set once from the saved profile and whenever the
## player picks another one in the menu.
static var quality: Quality = Quality.SMOOTH

## Frame rate ceilings offered in the menu. Zero means no ceiling at all:
## the game runs as fast as the machine allows, which is what somebody with
## a fast screen and vsync off is after.
const FPS_LIMITS := [0, 30, 60, 120, 144, 240]


static func fps_limit_label(limit: int) -> String:
	return "UNLIMITED" if limit <= 0 else str(limit)


## The next ceiling in the list, wrapping round.
static func next_fps_limit(limit: int) -> int:
	var index := FPS_LIMITS.find(limit)
	return FPS_LIMITS[wrapi(index + 1, 0, FPS_LIMITS.size())]


static func quality_mode() -> Dictionary:
	return QUALITY_MODES[clampi(int(quality), 0, QUALITY_MODES.size() - 1)]


## Look a mode up by the name kept in the save file.
static func quality_from_name(name: String) -> Quality:
	for index in range(QUALITY_MODES.size()):
		if QUALITY_MODES[index]["name"] == name:
			return index as Quality
	return Quality.SMOOTH


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
const PHASE_COLOR := Color(1.0, 0.93, 0.36)
const PHASE_PALE_COLOR := Color(1.0, 0.99, 0.82)
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
