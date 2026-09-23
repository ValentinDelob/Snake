class_name SnakeWorld
extends RefCounted

## The rules, with no dependency on nodes or rendering.
##
## The snake is not on a grid: it has a position, a heading and a constant
## speed. Steering turns the head, and the body follows the exact path the
## head travelled, which is what makes the motion continuous instead of
## jumping from cell to cell.

enum Outcome { MOVING, ATE, DEAD_WALL, DEAD_SELF }

## Distance the head must travel before the path records another point.
const PATH_SAMPLE := 0.06

var width: float
var height: float

var head_position := Vector2.ZERO
var heading := 0.0          # radians, 0 points towards +X
var body_length := 0.0          # world units of body actually grown
var target_body_length := 0.0   # what eating has earned so far
var turn_input := 0.0       # -1 turn left, +1 turn right, 0 straight

var food := Vector2.ZERO

## The speed boost: one bolt at a time on the arena, one slot to carry it.
var pickup := Vector2.ZERO
var pickup_on_arena := false
var carried_item := false
var picked_up_this_step := false
var boost_time_left := 0.0
var speed_multiplier := 1.0

var score := 0
var steps := 0
var distance_travelled := 0.0
var elapsed := 0.0
var _next_pickup_at := 0.0
var alive := true
var death_position := Vector2.ZERO

## Head positions, newest first, used to place the body.
var _path: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()
## body_points() is asked for several times per step (collision, rendering),
## and rebuilding it walks the whole path, so the result is cached.
var _points_cache: Array[Vector2] = []
var _points_dirty := true


func _init(board_width: float, board_height: float, seed_value: int = 0) -> void:
	width = board_width
	height = board_height
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	reset()


func reset() -> void:
	head_position = Vector2(width * 0.5, height * 0.5)
	heading = 0.0
	turn_input = 0.0
	body_length = GameConfig.START_BODY_LENGTH
	target_body_length = GameConfig.START_BODY_LENGTH
	score = 0
	steps = 0
	distance_travelled = 0.0
	alive = true
	death_position = Vector2.ZERO
	pickup_on_arena = false
	carried_item = false
	picked_up_this_step = false
	boost_time_left = 0.0
	speed_multiplier = 1.0
	elapsed = 0.0
	_next_pickup_at = _rng.randf_range(
		GameConfig.BOOST_FIRST_SPAWN.x, GameConfig.BOOST_FIRST_SPAWN.y
	)
	# The snake is born already stretched out behind its head, otherwise the
	# body would start piled up on the head and trigger self collision.
	_path = []
	var back := -Vector2(cos(heading), sin(heading))
	var covered := 0.0
	while covered <= body_length + 1.0:
		_path.append(head_position + back * covered)
		covered += PATH_SAMPLE
	_points_dirty = true
	food = spawn_food()


# --------------------------------------------------------------------------- #
func direction() -> Vector2:
	return Vector2(cos(heading), sin(heading))


func segment_count() -> int:
	return maxi(1, int(body_length / GameConfig.SEGMENT_SPACING))


## Length of the snake, head included, in world units.
func total_length() -> float:
	return body_length + GameConfig.SNAKE_RADIUS * 2.0


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


func spawn_food() -> Vector2:
	return _free_spot(GameConfig.FOOD_RADIUS + 0.8, 3.0)


# --------------------------------------------------------------------------- #
## Steering: -1 turns left, +1 turns right, 0 keeps the current heading.
func steer(amount: float) -> void:
	turn_input = clampf(amount, -1.0, 1.0)


## Advance the simulation by one fixed step.
func step(delta: float) -> Outcome:
	steps += 1
	elapsed += delta
	picked_up_this_step = false
	_update_boost(delta)
	_update_pickup_spawn()
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

	if not is_inside(head_position):
		alive = false
		death_position = head_position
		return Outcome.DEAD_WALL

	if hits_body(head_position):
		alive = false
		death_position = head_position
		return Outcome.DEAD_SELF

	if (
		pickup_on_arena and not carried_item
		and head_position.distance_to(pickup) < GameConfig.SNAKE_RADIUS + GameConfig.BOOST_RADIUS
	):
		pickup_on_arena = false
		carried_item = true
		picked_up_this_step = true
		_next_pickup_at = elapsed + _rng.randf_range(
			GameConfig.BOOST_RESPAWN.x, GameConfig.BOOST_RESPAWN.y
		)

	if head_position.distance_to(food) < GameConfig.SNAKE_RADIUS + GameConfig.FOOD_RADIUS:
		score += 1
		target_body_length += GameConfig.GROWTH_PER_FOOD
		food = spawn_food()
		return Outcome.ATE

	return Outcome.MOVING


## Fire the carried item. Returns false when there is nothing to fire.
func use_item() -> bool:
	if not carried_item:
		return false
	carried_item = false
	boost_time_left = GameConfig.BOOST_DURATION
	return true


func boosting() -> bool:
	return boost_time_left > 0.0 or speed_multiplier > 1.001


## How much of the boost is currently applied, 0 to 1. Drives the visuals.
func boost_intensity() -> float:
	return clampf(
		(speed_multiplier - 1.0) / maxf(0.001, GameConfig.BOOST_FACTOR - 1.0), 0.0, 1.0
	)


func _update_boost(delta: float) -> void:
	if boost_time_left > 0.0:
		boost_time_left = maxf(0.0, boost_time_left - delta)

	# The speed eases in and out instead of snapping, in both directions.
	var target := GameConfig.BOOST_FACTOR if boost_time_left > 0.0 else 1.0
	var ramp := (GameConfig.BOOST_FACTOR - 1.0) / (
		GameConfig.BOOST_RAMP_UP if target > speed_multiplier else GameConfig.BOOST_RAMP_DOWN
	)
	speed_multiplier = move_toward(speed_multiplier, target, ramp * delta)


func _update_pickup_spawn() -> void:
	if pickup_on_arena or carried_item or elapsed < _next_pickup_at:
		return
	pickup = _free_spot(GameConfig.BOOST_RADIUS + 1.0, 5.0)
	pickup_on_arena = true


## Drop a bolt on the arena right now (used by the self-test).
func spawn_pickup_now() -> void:
	if carried_item:
		return
	pickup = _free_spot(GameConfig.BOOST_RADIUS + 1.0, 4.0)
	pickup_on_arena = true


func _free_spot(margin: float, clearance: float) -> Vector2:
	for _attempt in range(40):
		var candidate := Vector2(
			_rng.randf_range(margin, width - margin),
			_rng.randf_range(margin, height - margin)
		)
		if candidate.distance_to(head_position) < clearance:
			continue
		if hits_body(candidate, 0.0):
			continue
		if candidate.distance_to(food) < 2.0:
			continue
		return candidate
	return Vector2(
		_rng.randf_range(margin, width - margin),
		_rng.randf_range(margin, height - margin)
	)


func _trim_path() -> void:
	# Keep a little more than the body needs, no more.
	var budget := maxf(body_length, target_body_length) + 2.0
	var travelled := 0.0
	for index in range(1, _path.size()):
		travelled += _path[index - 1].distance_to(_path[index])
		if travelled > budget:
			_path.resize(index + 1)
			return


static func is_death(outcome: Outcome) -> bool:
	return outcome == Outcome.DEAD_WALL or outcome == Outcome.DEAD_SELF
