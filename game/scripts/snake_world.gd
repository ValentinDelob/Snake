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
var body_length := 0.0      # world units of body trailing the head
var turn_input := 0.0       # -1 turn left, +1 turn right, 0 straight

var food := Vector2.ZERO
var score := 0
var steps := 0
var distance_travelled := 0.0
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
	food = spawn_food()


# --------------------------------------------------------------------------- #
func direction() -> Vector2:
	return Vector2(cos(heading), sin(heading))


func segment_count() -> int:
	return maxi(1, int(body_length / GameConfig.SEGMENT_SPACING))


## Length of the snake, head included, in world units.
func total_length() -> float:
	return body_length + GameConfig.SNAKE_RADIUS * 2.0


## Positions of the drawn body segments, closest to the head first.
func body_points() -> Array[Vector2]:
	if not _points_dirty:
		return _points_cache

	var points: Array[Vector2] = []
	var count := segment_count()
	var wanted := GameConfig.SEGMENT_SPACING
	var travelled := 0.0
	var current := head_position

	for index in range(_path.size()):
		var next_point: Vector2 = _path[index]
		var span := current.distance_to(next_point)
		while span > 0.0 and travelled + span >= wanted and points.size() < count:
			var ratio := (wanted - travelled) / span
			points.append(current.lerp(next_point, ratio))
			wanted += GameConfig.SEGMENT_SPACING
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
		points.append(last + tail_direction * GameConfig.SEGMENT_SPACING)

	_points_cache = points
	_points_dirty = false
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
	var margin := GameConfig.FOOD_RADIUS + 0.8
	for _attempt in range(40):
		var candidate := Vector2(
			_rng.randf_range(margin, width - margin),
			_rng.randf_range(margin, height - margin)
		)
		if candidate.distance_to(head_position) < 3.0:
			continue
		if hits_body(candidate, 0.0):
			continue
		return candidate
	# Crowded board: anywhere is better than nowhere.
	return Vector2(
		_rng.randf_range(margin, width - margin),
		_rng.randf_range(margin, height - margin)
	)


# --------------------------------------------------------------------------- #
## Steering: -1 turns left, +1 turns right, 0 keeps the current heading.
func steer(amount: float) -> void:
	turn_input = clampf(amount, -1.0, 1.0)


## Advance the simulation by one fixed step.
func step(delta: float) -> Outcome:
	steps += 1
	heading = wrapf(heading + turn_input * GameConfig.TURN_RATE * delta, -PI, PI)

	var travel := GameConfig.SNAKE_SPEED * delta
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

	if head_position.distance_to(food) < GameConfig.SNAKE_RADIUS + GameConfig.FOOD_RADIUS:
		score += 1
		body_length += GameConfig.GROWTH_PER_FOOD
		_points_dirty = true
		food = spawn_food()
		return Outcome.ATE

	return Outcome.MOVING


func _trim_path() -> void:
	# Keep a little more than the body needs, no more.
	var budget := body_length + 2.0
	var travelled := 0.0
	for index in range(1, _path.size()):
		travelled += _path[index - 1].distance_to(_path[index])
		if travelled > budget:
			_path.resize(index + 1)
			return


static func is_death(outcome: Outcome) -> bool:
	return outcome == Outcome.DEAD_WALL or outcome == Outcome.DEAD_SELF
