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

const FLOOR_COLOR := Color(0.13, 0.17, 0.23)
const GRID_COLOR := Color(0.18, 0.22, 0.29)
const WALL_COLOR := Color(0.27, 0.34, 0.43)
const SNAKE_HEAD_COLOR := Color(0.47, 1.0, 0.59)
const SNAKE_BODY_COLOR := Color(0.0, 0.78, 0.35)
const SNAKE_TAIL_COLOR := Color(0.0, 0.33, 0.18)
const FOOD_COLOR := Color(1.0, 0.27, 0.27)
const EYE_COLOR := Color(0.04, 0.08, 0.05)

const ACCENT_COLOR := Color(1.0, 0.82, 0.31)
const DANGER_COLOR := Color(1.0, 0.35, 0.35)
const TEXT_COLOR := Color(0.93, 0.94, 0.96)
const DIM_COLOR := Color(0.51, 0.56, 0.62)
