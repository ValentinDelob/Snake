class_name SnakeWorld
extends RefCounted

## One snake, with no dependency on nodes or rendering.
##
## It is not on a grid: it has a position, a heading and a constant speed.
## Steering turns the head, and the body follows the exact path the head
## travelled, which is what makes the motion continuous.
##
## Everything shared - the food, the crates, the other snakes - belongs to
## SnakeMatch. A snake owned by a remote player is never simulated here: it
## is fed snapshots and only keeps the trail needed to draw it.

enum Outcome { MOVING, DEAD_WALL, DEAD_SELF, DEAD_OTHER, DEAD_ROCK }

## What an item does once it takes effect.
enum Item { NONE, SPEED, SLOW }

## What can be lying on the arena.
enum Ground { BOLT, MYSTERY }

## Distance the head must travel before the path records another point.
const PATH_SAMPLE := 0.06

var width: float
var height: float

var head_position := Vector2.ZERO
var heading := 0.0              # radians, 0 points towards +X
var body_length := 0.0          # world units of body actually grown
var target_body_length := 0.0   # what eating has earned so far
var turn_input := 0.0           # -1 turn left, +1 turn right, 0 straight

var carried: Item = Item.NONE   # the slot the player fires with space
var effect: Item = Item.NONE    # what is currently running
var effect_time_left := 0.0
var speed_multiplier := 1.0

var score := 0
var steps := 0
var distance_travelled := 0.0
var alive := true
var death_position := Vector2.ZERO

## Head positions, newest first, used to place the body.
var _path: Array[Vector2] = []
## body_points() is asked for several times per step (collision, rendering),
## and rebuilding it walks the whole path, so the result is cached.
var _points_cache: Array[Vector2] = []
var _points_dirty := true


func _init(arena_width: float, arena_height: float) -> void:
	width = arena_width
	height = arena_height
	reset(Vector2(width * 0.5, height * 0.5), 0.0)


func reset(spawn_position: Vector2, spawn_heading: float) -> void:
	head_position = spawn_position
	heading = spawn_heading
	turn_input = 0.0
	body_length = GameConfig.START_BODY_LENGTH
	target_body_length = GameConfig.START_BODY_LENGTH
	carried = Item.NONE
	effect = Item.NONE
	effect_time_left = 0.0
	speed_multiplier = 1.0
	score = 0
	steps = 0
	distance_travelled = 0.0
	alive = true
	death_position = Vector2.ZERO

	# The snake is born already stretched out behind its head, otherwise the
	# body would start piled up on the head and trigger self collision.
	_path = []
	var back := -Vector2(cos(heading), sin(heading))
	var covered := 0.0
	while covered <= body_length + 1.0:
		_path.append(head_position + back * covered)
		covered += PATH_SAMPLE
	_points_dirty = true


# --------------------------------------------------------------------------- #
func direction() -> Vector2:
	return Vector2(cos(heading), sin(heading))


func segment_count() -> int:
	return maxi(1, int(body_length / GameConfig.SEGMENT_SPACING))


## Positions used by collisions, closest to the head first.
func body_points() -> Array[Vector2]:
	if not _points_dirty:
		return _points_cache
	_points_cache = sample_path(GameConfig.SEGMENT_SPACING, segment_count())
	_points_dirty = false
	return _points_cache


## Walk the path travelled by the head and return evenly spaced points.
func sample_path(spacing: float, count: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var wanted := spacing
	var travelled := 0.0
	var current := head_position

	for index in range(_path.size()):
		var next_point: Vector2 = _path[index]
		var span := current.distance_to(next_point)
		while span > 0.0 and travelled + span >= wanted and points.size() < count:
			var ratio := (wanted - travelled) / span
			points.append(current.lerp(next_point, ratio))
			wanted += spacing
		travelled += span
		current = next_point
		if points.size() >= count:
			break

	# While the snake is still growing the path can be shorter than the body:
	# extend the tail backwards instead of stacking segments on one spot.
	var tail_direction := -direction()
	if points.size() >= 2:
		tail_direction = (points[points.size() - 1] - points[points.size() - 2]).normalized()
	while points.size() < count:
		var last: Vector2 = points[points.size() - 1] if not points.is_empty() else head_position
		points.append(last + tail_direction * spacing)

	return points


func is_inside(point: Vector2) -> bool:
	var margin := GameConfig.SNAKE_RADIUS
	return (
		point.x >= margin and point.x <= width - margin
		and point.y >= margin and point.y <= height - margin
	)


## Does this point hit the body, ignoring the part right behind the head?
func hits_body(point: Vector2, ignore_from_head: float = GameConfig.SELF_COLLISION_SKIP) -> bool:
	var skip := int(ignore_from_head / GameConfig.SEGMENT_SPACING)
	var points := body_points()
	var radius := GameConfig.SNAKE_RADIUS * 1.6
	for index in range(skip, points.size()):
		if point.distance_to(points[index]) < radius:
			return true
	return false


# --------------------------------------------------------------------------- #
## Steering: -1 turns left, +1 turns right, 0 keeps the current heading.
func steer(amount: float) -> void:
	turn_input = clampf(amount, -1.0, 1.0)


## Move by one fixed step without judging the result. A client uses this to
## keep remote snakes gliding between snapshots; the host follows it with
## the collision checks in step().
func advance(delta: float) -> void:
	steps += 1
	_update_effect(delta)
	if body_length < target_body_length:
		body_length = minf(
			target_body_length, body_length + GameConfig.GROWTH_SPEED * delta
		)
		_points_dirty = true
	heading = wrapf(heading + turn_input * GameConfig.TURN_RATE * delta, -PI, PI)

	var travel := GameConfig.SNAKE_SPEED * speed_multiplier * delta
	head_position += direction() * travel
	distance_travelled += travel

	_points_dirty = true
	if _path.is_empty() or head_position.distance_to(_path[0]) >= PATH_SAMPLE:
		_path.push_front(head_position)
		_trim_path()


## Advance this snake and report what happened to it. Food, items and the
## other snakes are the match's business.
func step(delta: float) -> Outcome:
	advance(delta)
	if not is_inside(head_position):
		kill(head_position)
		return Outcome.DEAD_WALL
	if hits_body(head_position):
		kill(head_position)
		return Outcome.DEAD_SELF
	return Outcome.MOVING


func kill(at: Vector2) -> void:
	alive = false
	death_position = at


func grow(amount: float) -> void:
	target_body_length += amount


# --------------------------------------------------------------------------- #
# Items
# --------------------------------------------------------------------------- #
## Fire the carried item. Returns false when there is nothing to fire.
func use_item() -> bool:
	if carried == Item.NONE:
		return false
	var fired := carried
	carried = Item.NONE
	start_effect(fired)
	return true


## A curse is not offered, it is applied: the snake swallows it on the spot.
func start_effect(kind: Item) -> void:
	effect = kind
	effect_time_left = (
		GameConfig.BOOST_DURATION if kind == Item.SPEED else GameConfig.SLOW_DURATION
	)


func boosting() -> bool:
	return effect == Item.SPEED or speed_multiplier > 1.001


func slowed() -> bool:
	return effect == Item.SLOW or speed_multiplier < 0.999


## How much of the boost shows, 0 to 1. Drives the visuals.
func boost_intensity() -> float:
	return clampf(
		(speed_multiplier - 1.0) / maxf(0.001, GameConfig.BOOST_FACTOR - 1.0), 0.0, 1.0
	)


## Same for the slow down, so the frost fades in and out with it.
func slow_intensity() -> float:
	return clampf(
		(1.0 - speed_multiplier) / maxf(0.001, 1.0 - GameConfig.SLOW_FACTOR), 0.0, 1.0
	)


func _update_effect(delta: float) -> void:
	if effect_time_left > 0.0:
		effect_time_left = maxf(0.0, effect_time_left - delta)
		if effect_time_left == 0.0:
			effect = Item.NONE

	var target := 1.0
	var ramp := 1.0
	match effect:
		Item.SPEED:
			target = GameConfig.BOOST_FACTOR
			ramp = (GameConfig.BOOST_FACTOR - 1.0) / GameConfig.BOOST_RAMP_UP
		Item.SLOW:
			target = GameConfig.SLOW_FACTOR
			ramp = (1.0 - GameConfig.SLOW_FACTOR) / GameConfig.SLOW_RAMP_DOWN
		_:
			# Coming back to cruising speed, from either side.
			if speed_multiplier > 1.0:
				ramp = (GameConfig.BOOST_FACTOR - 1.0) / GameConfig.BOOST_RAMP_DOWN
			else:
				ramp = (1.0 - GameConfig.SLOW_FACTOR) / GameConfig.SLOW_RAMP_UP

	# The speed always eases, never snaps.
	speed_multiplier = move_toward(speed_multiplier, target, ramp * delta)


func _trim_path() -> void:
	# Keep a little more than the body needs, no more.
	var budget := maxf(body_length, target_body_length) + 2.0
	var travelled := 0.0
	for index in range(1, _path.size()):
		travelled += _path[index - 1].distance_to(_path[index])
		if travelled > budget:
			_path.resize(index + 1)
			return


# --------------------------------------------------------------------------- #
# Remote snakes
# --------------------------------------------------------------------------- #
## Feed a snapshot from the server. The trail is rebuilt from the stream of
## head positions, so a remote body draws exactly as a local one would.
func apply_snapshot(
	position: Vector2, new_heading: float, length: float,
	multiplier: float, new_effect: Item, is_alive: bool, new_score: int
) -> void:
	head_position = position
	heading = new_heading
	body_length = length
	target_body_length = length
	speed_multiplier = multiplier
	effect = new_effect
	score = new_score
	if alive and not is_alive:
		death_position = position
	alive = is_alive

	_points_dirty = true
	if _path.is_empty() or head_position.distance_to(_path[0]) >= PATH_SAMPLE:
		_path.push_front(head_position)
		_trim_path()


static func is_death(outcome: Outcome) -> bool:
	return outcome != Outcome.MOVING
