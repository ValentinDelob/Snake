class_name GameConfig
extends RefCounted

## Tunable constants shared by every script, so gameplay code stays free of
## magic numbers. One grid cell is one world unit; X grows right, Z grows
## away from the player, Y is up.

const GRID_WIDTH := 28
const GRID_HEIGHT := 18

## How many times per second the snake advances, independent of frame rate.
const STEP_HZ := 10.0
const STEP_INTERVAL := 1.0 / STEP_HZ

## A frame slower than this is logged as a stutter.
const SLOW_FRAME_SECONDS := 0.15

const FLOOR_COLOR := Color(0.13, 0.17, 0.23)
const GRID_COLOR := Color(0.24, 0.30, 0.38)
const WALL_COLOR := Color(0.27, 0.34, 0.43)
const SNAKE_HEAD_COLOR := Color(0.47, 1.0, 0.59)
const SNAKE_BODY_COLOR := Color(0.0, 0.78, 0.35)
const SNAKE_TAIL_COLOR := Color(0.0, 0.47, 0.24)
const FOOD_COLOR := Color(1.0, 0.27, 0.27)
const EYE_COLOR := Color(0.04, 0.08, 0.05)

const ACCENT_COLOR := Color(1.0, 0.82, 0.31)
const DANGER_COLOR := Color(1.0, 0.35, 0.35)
const TEXT_COLOR := Color(0.93, 0.94, 0.96)
const DIM_COLOR := Color(0.51, 0.56, 0.62)
