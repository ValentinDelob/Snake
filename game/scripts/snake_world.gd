class_name SnakeWorld
extends RefCounted

## The rules, with no dependency on nodes or rendering.
##
## The snake is not on a grid: it has a position, a heading and a constant
## speed. Steering turns the head, and the body follows the exact path the
## head travelled, which is what makes the motion continuous instead of
## jumping from cell to cell.

enum Outcome { MOVING, ATE, DEAD_WALL, DEAD_SELF }

## What an item does once it takes effect.
enum Item { NONE, SPEED, SLOW }

## What can be lying on the arena.
enum Ground { BOLT, MYSTERY }

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

## What lies on the arena: at most one bolt and one crate, each on its own
## timer. A crate hands out a random item, which may be a curse.
var ground: Array = []              # [{ "kind": Ground, "position": Vector2 }]
var carried: Item = Item.NONE       # the slot the player fires with space
var effect: Item = Item.NONE        # what is currently running
var effect_time_left := 0.0
var speed_multiplier := 1.0

## Set for one step when something is collected, for the flash and the logs.
var picked_up_this_step := false
var last_pickup_kind: Ground = Ground.BOLT
var last_pickup_position := Vector2.ZERO
var last_roll: Item = Item.NONE     # what the crate just handed out

var score := 0
var steps := 0
var distance_travelled := 0.0
var elapsed := 0.0
var _next_bolt_at := 0.0
var _next_mystery_at := 0.0
var _forced_roll: Item = Item.NONE  # testing hook, see spawn_mystery_now()
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
	ground = []
	carried = Item.NONE
	effect = Item.NONE
	effect_time_left = 0.0
	speed_multiplier = 1.0
	picked_up_this_step = false
	last_roll = Item.NONE
	_forced_roll = Item.NONE
	elapsed = 0.0
	_next_bolt_at = _rng.randf_range(
		GameConfig.BOOST_FIRST_SPAWN.x, GameConfig.BOOST_FIRST_SPAWN.y
	)
	_next_mystery_at = _rng.randf_range(
		GameConfig.MYSTERY_FIRST_SPAWN.x, GameConfig.MYSTERY_FIRST_SPAWN.y
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
	_update_effect(delta)
	_update_ground_spawns()
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

	_collect_ground_items()

	if head_position.distance_to(food) < GameConfig.SNAKE_RADIUS + GameConfig.FOOD_RADIUS:
		score += 1
		target_body_length += GameConfig.GROWTH_PER_FOOD
		food = spawn_food()
		return Outcome.ATE

	return Outcome.MOVING


## Fire the carried item. Returns false when there is nothing to fire.
func use_item() -> bool:
	if carried == Item.NONE:
		return false
	var fired := carried
	carried = Item.NONE
	_start_effect(fired)
	return true


## A curse is not offered, it is applied: the snake swallows it on the spot.
func _start_effect(kind: Item) -> void:
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


# --------------------------------------------------------------------------- #
# What lies on the arena
# --------------------------------------------------------------------------- #
func has_ground(kind: Ground) -> bool:
	for item: Dictionary in ground:
		if item["kind"] == kind:
			return true
	return false


func ground_position(kind: Ground) -> Vector2:
	for item: Dictionary in ground:
		if item["kind"] == kind:
			return item["position"]
	return Vector2.ZERO


func _update_ground_spawns() -> void:
	if not has_ground(Ground.BOLT) and carried == Item.NONE and elapsed >= _next_bolt_at:
		_drop(Ground.BOLT, GameConfig.BOOST_RADIUS + 1.0)
	if not has_ground(Ground.MYSTERY) and elapsed >= _next_mystery_at:
		_drop(Ground.MYSTERY, GameConfig.MYSTERY_RADIUS + 1.0)


func _drop(kind: Ground, margin: float) -> void:
	ground.append({"kind": kind, "position": _free_spot(margin, 4.5)})


func _collect_ground_items() -> void:
	for index in range(ground.size() - 1, -1, -1):
		var item: Dictionary = ground[index]
		var radius: float = (
			GameConfig.BOOST_RADIUS if item["kind"] == Ground.BOLT
			else GameConfig.MYSTERY_RADIUS
		)
		if head_position.distance_to(item["position"]) > GameConfig.SNAKE_RADIUS + radius:
			continue
		if item["kind"] == Ground.BOLT and carried != Item.NONE:
			continue    # the slot is busy: leave the bolt where it lies

		ground.remove_at(index)
		picked_up_this_step = true
		last_pickup_kind = item["kind"]
		last_pickup_position = item["position"]

		if item["kind"] == Ground.BOLT:
			last_roll = Item.SPEED
			carried = Item.SPEED
			_next_bolt_at = elapsed + _rng.randf_range(
				GameConfig.BOOST_RESPAWN.x, GameConfig.BOOST_RESPAWN.y
			)
		else:
			last_roll = _roll_mystery()
			if last_roll == Item.SLOW:
				# A curse is swallowed on the spot: there is no choosing it.
				_start_effect(Item.SLOW)
			else:
				carried = last_roll
			_next_mystery_at = elapsed + _rng.randf_range(
				GameConfig.MYSTERY_RESPAWN.x, GameConfig.MYSTERY_RESPAWN.y
			)


func _roll_mystery() -> Item:
	if _forced_roll != Item.NONE:
		var forced := _forced_roll
		_forced_roll = Item.NONE
		return forced
	return Item.SPEED if _rng.randf() < GameConfig.MYSTERY_BONUS_CHANCE else Item.SLOW


## Drop a bolt on the arena right now (used by the self-test).
func spawn_pickup_now() -> void:
	if carried != Item.NONE or has_ground(Ground.BOLT):
		return
	_drop(Ground.BOLT, GameConfig.BOOST_RADIUS + 1.0)


## Drop a crate right now, optionally deciding what it hands out, so a test
## can walk both the bonus and the curse on purpose.
func spawn_mystery_now(forced: Item = Item.NONE) -> void:
	_forced_roll = forced
	if has_ground(Ground.MYSTERY):
		return
	_drop(Ground.MYSTERY, GameConfig.MYSTERY_RADIUS + 1.0)


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
		var clear := true
		for item: Dictionary in ground:
			if candidate.distance_to(item["position"]) < 2.5:
				clear = false
				break
		if not clear:
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
