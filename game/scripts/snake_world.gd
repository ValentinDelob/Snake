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
enum Item { NONE, SPEED, SLOW, SCORE_UP, SCORE_DOWN, PHASE, SHEARS }

## What can be lying on the arena.
enum Ground { BOLT, MYSTERY, PHASE, SHEARS }

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

## Matter swallowed, in the length it bought. The score and the length are
## the same thing seen twice.
var score := 0.0
## How wide the body is, and how much the girth costs in speed and in
## turning. All three follow the matter eaten, so they are kept together.
var radius := GameConfig.SNAKE_RADIUS
var speed_scale := 1.0
var turn_scale := 1.0
var steps := 0
var distance_travelled := 0.0
var alive := true
var death_position := Vector2.ZERO

## Head positions, newest first, used to place the body.
var _path: Array[Vector2] = []
## body_points() is asked for several times per step (collision, rendering),
## and rebuilding it walks the whole path, so the result is cached.
var _points_cache := PackedVector2Array()
var _even_distances := PackedFloat32Array()
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
	score = 0.0
	_follow_girth()
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


## Positions used by collisions, closest to the head first. The buffer is
## kept between calls: this is asked for on every simulation step, and a
## fresh array each time was pure allocator traffic.
func body_points() -> PackedVector2Array:
	if not _points_dirty:
		return _points_cache
	var count := segment_count()
	if _even_distances.size() != count:
		_even_distances.resize(count)
		for index in range(count):
			_even_distances[index] = GameConfig.SEGMENT_SPACING * (index + 1)
	sample_path_at(_even_distances, _points_cache)
	_points_dirty = false
	return _points_cache


## Pick points along the path at the given distances behind the head. The
## distances must increase, which lets one walk of the path serve them all -
## and lets the body mesh ask for rings that are not evenly spaced. Results
## are written into `out`, which is resized in place.
func sample_path_at(distances: PackedFloat32Array, out: PackedVector2Array) -> void:
	var count := distances.size()
	if out.size() != count:
		out.resize(count)
	if count == 0:
		return

	var filled := 0
	var travelled := 0.0
	var current := head_position
	var wanted: float = distances[0]

	for index in range(_path.size()):
		var next_point: Vector2 = _path[index]
		var span := current.distance_to(next_point)
		while span > 0.0 and travelled + span >= wanted and filled < count:
			out[filled] = current.lerp(next_point, (wanted - travelled) / span)
			filled += 1
			if filled < count:
				wanted = distances[filled]
		travelled += span
		current = next_point
		if filled >= count:
			break

	# While the snake is still growing the path can be shorter than the body:
	# extend the tail backwards instead of stacking rings on one spot.
	if filled >= count:
		return
	var tail_direction := -direction()
	if filled >= 2:
		tail_direction = (out[filled - 1] - out[filled - 2]).normalized()
	var anchor: Vector2 = out[filled - 1] if filled > 0 else head_position
	var anchor_at: float = distances[filled - 1] if filled > 0 else 0.0
	while filled < count:
		out[filled] = anchor + tail_direction * (distances[filled] - anchor_at)
		filled += 1


func is_inside(point: Vector2) -> bool:
	var margin := radius
	return (
		point.x >= margin and point.x <= width - margin
		and point.y >= margin and point.y <= height - margin
	)


## Does this point hit the body, ignoring the part right behind the head?
func hits_body(point: Vector2, ignore_from_head: float = GameConfig.SELF_COLLISION_SKIP) -> bool:
	var skip := int(ignore_from_head / GameConfig.SEGMENT_SPACING)
	var points := body_points()
	# Squared throughout: this runs over every body point on every step, and
	# a square root per point is a square root wasted.
	var reach := radius * 1.6
	var radius_squared := reach * reach
	for index in range(skip, points.size()):
		if point.distance_squared_to(points[index]) < radius_squared:
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
	elif body_length > target_body_length:
		# Points lost pull the tail back in at the same pace it grew out.
		body_length = maxf(
			target_body_length, body_length - GameConfig.GROWTH_SPEED * delta
		)
		_points_dirty = true
	heading = wrapf(
		heading + turn_input * GameConfig.TURN_RATE * turn_scale * delta, -PI, PI
	)

	var travel := GameConfig.SNAKE_SPEED * speed_multiplier * speed_scale * delta
	head_position += direction() * travel
	distance_travelled += travel
	# The samples are measured from the head, so moving invalidates them.
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
	if not phasing() and hits_body(head_position):
		kill(head_position)
		return Outcome.DEAD_SELF
	return Outcome.MOVING


func kill(at: Vector2) -> void:
	alive = false
	death_position = at


func grow(amount: float) -> void:
	target_body_length += amount


## Move the score and let the body follow it. Length is nothing but the
## score made visible: lose points and the snake shortens again, and a
## score driven down to nothing leaves it as small as it started.
func add_score(points: float) -> float:
	var before := score
	score = maxf(0.0, score + points)
	target_body_length = length_for_score(score)
	_follow_girth()
	return score - before


## Girth, speed and turning are nothing but the matter eaten, read three
## different ways.
func _follow_girth() -> void:
	radius = GameConfig.girth_for(score)
	speed_scale = GameConfig.speed_scale_for(score)
	turn_scale = GameConfig.turn_scale_for(score)


static func length_for_score(value: float) -> float:
	return GameConfig.START_BODY_LENGTH + maxf(0.0, value) * GameConfig.GROWTH_PER_FOOD


# --------------------------------------------------------------------------- #
# Items
# --------------------------------------------------------------------------- #
## How much would come up if the snake were to spit now: a tenth of what
## it has swallowed, and nothing at all below the threshold.
func spit_amount() -> float:
	if score < GameConfig.SPIT_MINIMUM:
		return 0.0
	return score * GameConfig.SPIT_SHARE


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
	# Score cards are settled the instant the crate opens: there is no
	# effect to run down, so they never reach this.
	match kind:
		Item.SPEED:
			effect_time_left = GameConfig.BOOST_DURATION
		Item.SLOW:
			effect_time_left = GameConfig.SLOW_DURATION
		Item.PHASE:
			effect_time_left = GameConfig.PHASE_DURATION
		Item.SHEARS:
			effect_time_left = GameConfig.SHEARS_DURATION
		_:
			return
	effect = kind


## While this runs the snake walks through bodies, its own and everybody
## else's. Walls and rocks are as solid as ever.
func phasing() -> bool:
	return effect == Item.PHASE and effect_time_left > 0.0


## How much of the ghost shows: full at the start, fading out with it.
func phase_intensity() -> float:
	if not phasing():
		return 0.0
	return clampf(effect_time_left / GameConfig.PHASE_DURATION, 0.0, 1.0)


## While this runs the head slices through other snakes instead of dying
## on them.
func cutting() -> bool:
	return effect == Item.SHEARS and effect_time_left > 0.0


## How much of the blade shows: bright when fired, fading with the effect.
func cut_intensity() -> float:
	if not cutting():
		return 0.0
	return clampf(0.35 + 0.65 * effect_time_left / GameConfig.SHEARS_DURATION, 0.0, 1.0)


## Cut the body `at_distance` behind the head: everything further back is
## gone at once, and the score drops to what the part that is left is worth.
## A cut closer to the head than a newborn snake is long still leaves it
## that long. Returns the points the lost part covered and the matter it
## held, so the match can drop it on the floor; an empty dictionary means
## there was nothing behind the cut.
func sever(at_distance: float) -> Dictionary:
	var keep := maxf(GameConfig.START_BODY_LENGTH, at_distance)
	if keep >= body_length - 0.2 or score <= 0.0:
		return {}
	var points := body_points()
	var from := mini(int(keep / GameConfig.SEGMENT_SPACING), points.size() - 1)
	var lost_part := points.slice(from)
	var kept_score := maxf(0.0, (keep - GameConfig.START_BODY_LENGTH) / GameConfig.GROWTH_PER_FOOD)
	var matter := score - kept_score
	if matter <= 0.0:
		return {}
	add_score(-matter)
	# A cut is a cut: the tail does not shrink back in, it is simply gone.
	body_length = target_body_length
	_trim_path()
	_points_dirty = true
	return {"points": lost_part, "matter": matter}


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
	multiplier: float, new_effect: Item, is_alive: bool, new_score: float
) -> void:
	head_position = position
	heading = new_heading
	body_length = length
	target_body_length = length
	speed_multiplier = multiplier
	effect = new_effect
	score = new_score
	_follow_girth()
	if alive and not is_alive:
		death_position = position
	alive = is_alive

	_points_dirty = true
	if _path.is_empty() or head_position.distance_to(_path[0]) >= PATH_SAMPLE:
		_path.push_front(head_position)
		_trim_path()


static func is_death(outcome: Outcome) -> bool:
	return outcome != Outcome.MOVING
