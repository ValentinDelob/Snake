class_name GameConfig
extends RefCounted

## Tunable constants shared by every script, so gameplay code stays free of
## magic numbers.
##
## The board is a continuous rectangle, not a grid: positions are floats,
## X grows right and Y (of the 2D simulation) maps to Z in the 3D world.

## A wide field rather than a room: there is matter scattered all over it
## and several snakes grazing, so everyone needs somewhere to be that is
## not on top of somebody else.
const BOARD_WIDTH := 84.0
const BOARD_HEIGHT := 56.0

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
## Gluttony: what you swallow shows, and it costs. Girth, sluggishness and
## the turning circle all follow the matter eaten, and all of them flatten
## out - a giant is a wide, ponderous beast, never a stationary wall.
const GIRTH_MAX := 2.4              # widest the body gets, times the base
const GIRTH_HALF_MATTER := 45.0     # matter at which half of that is reached
## Bringing it back up: a tenth of what is inside, and only once there is
## something worth bringing up. What comes out lands on the floor behind
## the snake, for anybody at all.
const SPIT_SHARE := 0.1
const SPIT_MINIMUM := 10.0

const SLUGGISH_FLOOR := 0.55        # slowest it goes, as a share of cruising
const TURN_FLOOR := 0.6             # and how tightly it can still turn


## 0 when empty, approaching 1 as the matter piles up.
static func fullness(matter: float) -> float:
	var eaten := maxf(0.0, matter)
	return eaten / (eaten + GIRTH_HALF_MATTER)


static func girth_for(matter: float) -> float:
	return SNAKE_RADIUS * (1.0 + (GIRTH_MAX - 1.0) * fullness(matter))


static func speed_scale_for(matter: float) -> float:
	return 1.0 - (1.0 - SLUGGISH_FLOOR) * fullness(matter)


static func turn_scale_for(matter: float) -> float:
	return 1.0 - (1.0 - TURN_FLOOR) * fullness(matter)


const START_BODY_LENGTH := 2.6    # world units of body behind the head
## Matter is measured in the length it becomes, so a mote worth 0.2 adds
## exactly 0.2 units of snake.
const GROWTH_PER_FOOD := 1.0
## The body does not jump to its new length: it grows into it.
const GROWTH_SPEED := 2.2         # world units per second
## Body close to the head is ignored by self collision: it always touches.
const SELF_COLLISION_SKIP := 1.5

## Motes are worth between a fifth of a unit and three, and the small ones
## are far commoner: the value is rolled on a curve that hugs the bottom of
## the range, so a big mote is a find rather than a fixture.
const FOOD_VALUE := Vector2(0.2, 3.0)
const FOOD_VALUE_BIAS := 4.0
const FOOD_RADIUS := 0.22           # the smallest mote
const FOOD_RADIUS_MAX := 0.62       # and the biggest


## Roll the worth of one mote.
static func roll_food_value(rng: RandomNumberGenerator) -> float:
	return lerpf(FOOD_VALUE.x, FOOD_VALUE.y, pow(rng.randf(), FOOD_VALUE_BIAS))


## How big a mote of that worth looks and how far it can be reached. The
## square root keeps the smallest ones visible rather than specks.
static func food_radius(value: float) -> float:
	var share := clampf((value - FOOD_VALUE.x) / (FOOD_VALUE.y - FOOD_VALUE.x), 0.0, 1.0)
	return lerpf(FOOD_RADIUS, FOOD_RADIUS_MAX, sqrt(share))


## The colour of a mote: a jewel whose hue climbs with its worth - turquoise
## crumbs, pink mid-sized ones, gold for the prizes - so value reads at a
## glance on a bright floor. Alpha carries the worth itself, which the gem
## shader turns into how hard it glows.
static func food_glow(value: float) -> Color:
	var share := clampf((value - FOOD_VALUE.x) / (FOOD_VALUE.y - FOOD_VALUE.x), 0.0, 1.0)
	var hue: Color = MOTE_SMALL_COLOR.lerp(MOTE_MID_COLOR, minf(share * 2.0, 1.0))
	if share > 0.5:
		hue = MOTE_MID_COLOR.lerp(MOTE_BIG_COLOR, (share - 0.5) * 2.0)
	return Color(hue.r, hue.g, hue.b, share)

## How much matter lies about: one pellet per this many square units, so a
## bigger arena is not a barer one.
const FOOD_PER_AREA := 46.0
const FOOD_MIN := 12

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

## A round is played against the clock, not to the death: dying costs you
## everything you swallowed and a couple of seconds, and the longest snake
## when the clock runs out takes it.
const ROUND_SECONDS := 300.0
const RESPAWN_DELAY := 2.0

## Rivals: snakes the machine drives, so a solo round has somebody to be
## bigger than. Each one is a full player - it takes floor, eats, dies and
## drops its matter like anyone else. There are only as many as there are
## palettes left once yours is taken, so no rival ever wears your colours.
const RIVAL_NAMES := ["VIPER", "MAMBA", "ADDER", "KRAIT"]
const RIVALS_DEFAULT := 3
## How long a rival sits on a speed bolt before firing it, in seconds. A
## little patience makes them readable: you see the bolt go, then the burst.
const RIVAL_BOOST_PATIENCE := Vector2(1.0, 3.5)
## A rival brings matter up once it has swallowed this much, to get its
## speed back. Each one draws its own limit, so they do not all slim down
## at the same moment - and the greedy ones make juicy targets.
const RIVAL_SPIT_AT := Vector2(45.0, 85.0)
## And waits at least this long between two helpings.
const RIVAL_SPIT_COOLDOWN := 4.0

## The simulation runs at a fixed rate so it behaves the same on any machine.
const SIM_HZ := 120.0
const SIM_STEP := 1.0 / SIM_HZ

## A frame slower than this is logged as a stutter.
const SLOW_FRAME_SECONDS := 0.15

## Rocks scattered over the arena. They are never placed on a spawn point
## nor in the lane a snake sets off along, so nobody starts a round already
## boxed in; everywhere else they are fair game and come in several sizes.
## Rocks are counted per square unit as well, for the same reason.
const OBSTACLE_PER_AREA := 210.0
const OBSTACLE_COUNT := Vector2i(5, 8)
const OBSTACLE_RADIUS := Vector2(0.85, 2.6)
const OBSTACLE_GAP := 3.0            # room left between two rocks
const OBSTACLE_WALL_GAP := 2.2       # corridor left between a rock and a wall
const OBSTACLE_GAP_TIGHT := 1.8      # the closest two rocks may sit when room runs out
const OBSTACLE_SPAWN_CLEAR := 5.0    # room left around a spawn point
const OBSTACLE_LANE_LENGTH := 14.0   # how far ahead the spawn lane is kept clear
const OBSTACLE_LANE_MIN := 6.0       # never less than this, however crowded
const OBSTACLE_LANE_CLEAR := 2.2     # half width of that lane
# --------------------------------------------------------------------------- #
# The look: a sunlit lagoon
# --------------------------------------------------------------------------- #
## A bright afternoon rather than a dark room: an azure sky melting into a
## peach horizon, warm sand underfoot with light rippling over it, pastel
## crystals for rocks and coral ramparts with a glowing lip. Everything that
## matters to play - snakes, motes, items - is saturated, so it still reads
## against the light floor from any camera.
const SKY_TOP_COLOR := Color(0.33, 0.6, 0.98)
const SKY_HORIZON_COLOR := Color(1.0, 0.8, 0.68)
const GROUND_HORIZON_COLOR := Color(0.3, 0.72, 0.86)
const FOG_COLOR := Color(1.0, 0.84, 0.74)
const SUN_COLOR := Color(1.0, 0.93, 0.8)

const FLOOR_COLOR := Color(0.9, 0.76, 0.6)
const GRID_COLOR := Color(0.8, 0.62, 0.48)
const CAUSTIC_COLOR := Color(1.0, 0.98, 0.9)
const FLOOR_EDGE_COLOR := Color(0.95, 0.6, 0.55)
const WALL_COLOR := Color(1.0, 0.52, 0.5)
const WALL_GLOW_COLOR := Color(1.0, 0.86, 0.95)
const OBSTACLE_COLOR := Color(0.6, 0.58, 0.93)
const OBSTACLE_TOP_COLOR := Color(0.86, 0.8, 1.0)
const POLLEN_COLOR := Color(1.0, 0.96, 0.8)
const WATER_SHALLOW_COLOR := Color(0.16, 0.82, 0.84)
const WATER_DEEP_COLOR := Color(0.04, 0.4, 0.74)

## Motes are jewels: turquoise crumbs, pink mid-sized ones, gold prizes.
const MOTE_SMALL_COLOR := Color(0.0, 0.72, 0.95)
const MOTE_MID_COLOR := Color(0.95, 0.12, 0.58)
const MOTE_BIG_COLOR := Color(1.0, 0.6, 0.0)

const SNAKE_HEAD_COLOR := Color(0.6, 1.0, 0.55)
const SNAKE_BODY_COLOR := Color(0.06, 0.82, 0.42)
const SNAKE_TAIL_COLOR := Color(0.0, 0.5, 0.45)
const FOOD_COLOR := Color(1.0, 0.33, 0.72)
const EYE_COLOR := Color(0.06, 0.07, 0.16)

const BOOST_COLOR := Color(1.0, 0.8, 0.2)
const SPARK_COLOR := Color(1.0, 0.98, 0.78)
const MYSTERY_COLOR := Color(0.7, 0.4, 1.0)
const PHASE_COLOR := Color(1.0, 0.9, 0.3)
const PHASE_PALE_COLOR := Color(1.0, 0.99, 0.82)
const FROST_COLOR := Color(0.4, 0.74, 1.0)
const FROST_PALE_COLOR := Color(0.85, 0.95, 1.0)

## One palette per player: head, body, tail. The first is always yours.
## Each one runs through two hues from head to tail, so a body reads as a
## ribbon of colour rather than a hose of one.
const PLAYER_PALETTES := [
	[Color(0.6, 1.0, 0.55), Color(0.06, 0.82, 0.42), Color(0.0, 0.5, 0.45)],
	[Color(0.62, 0.88, 1.0), Color(0.15, 0.5, 1.0), Color(0.32, 0.2, 0.85)],
	[Color(1.0, 0.86, 0.42), Color(1.0, 0.42, 0.18), Color(0.85, 0.12, 0.3)],
	[Color(1.0, 0.72, 0.96), Color(0.9, 0.25, 0.75), Color(0.5, 0.16, 0.8)],
	[Color(0.62, 1.0, 0.96), Color(0.0, 0.74, 0.8), Color(0.0, 0.38, 0.62)],
]


static func palette_for(index: int) -> Array:
	return PLAYER_PALETTES[index % PLAYER_PALETTES.size()]


## The interface sits on frosted white glass, so its ink is dark and its
## accents deep enough to read on it.
const ACCENT_COLOR := Color(1.0, 0.5, 0.1)
const DANGER_COLOR := Color(0.93, 0.2, 0.33)
const GOOD_COLOR := Color(0.05, 0.64, 0.38)
const TEXT_COLOR := Color(0.12, 0.15, 0.3)
const DIM_COLOR := Color(0.4, 0.45, 0.6)

# --------------------------------------------------------------------------- #
# Effects
# --------------------------------------------------------------------------- #
## FULL draws everything below; LIGHT keeps what tells you something (the
## bursts, the shockwave, the shake) and drops what is only there to be
## pretty (the pollen in the air and the sparks behind a boosted snake).
static var effects_full := true

const POLLEN_PER_AREA := 14.0        # one floating speck per this many units²
const POLLEN_MAX := 520
const BURST_EAT_SPARKS := 14         # sparks thrown by a swallowed gem
const BURST_BIG_SPARKS := 72         # by a death, a crate or a comeback
const SHAKE_DEATH := 0.8             # camera trauma when you die
const SHAKE_NEAR_DEATH := 0.35       # when somebody dies close to you
const SHAKE_CRATE := 0.25
const SHAKE_NEAR := 14.0             # how close "close" is, in units
## Swallowing gems in quick succession makes a streak: purely for show, it
## never changes what they are worth.
const STREAK_WINDOW := 1.1           # seconds allowed between two gems
const STREAK_SHOWN_FROM := 3
