class_name SnakeMatch
extends RefCounted

## A round: the arena, what lies on it, and every snake playing in it.
##
## One snake is a SnakeWorld; the match owns everything they share - the
## food, the crates, the collisions between them and the last-survivor rule.
## Solo is simply a match with a single snake.

signal snake_died(id: int, cause: SnakeWorld.Outcome)
signal food_eaten(id: int)
signal item_collected(id: int, kind: SnakeWorld.Ground, roll: SnakeWorld.Item)
signal finished(winner_id: int)

var width: float
var height: float

var snakes: Dictionary = {}          # id -> SnakeWorld
var food := Vector2.ZERO
var ground: Array = []               # [{ "kind": Ground, "position": Vector2 }]

## Rocks: solid, round, of varying size. They are generated once per round
## and, on a client, copied from the host so both see the same arena.
var obstacles: Array = []            # [{ "position": Vector2, "radius": float, "spin": float, "sides": int }]
var spawns: Dictionary = {}          # id -> [Vector2 position, float heading]
## How far ahead of a spawn point the arena was actually kept clear. A
## crowded arena has to settle for less than the full lane.
var lane_length := GameConfig.OBSTACLE_LANE_LENGTH

## A client mirrors the match instead of judging it: it keeps the snakes
## gliding between snapshots and takes deaths, food and items from the host.
var authoritative := true

var running := false
var over := false
var winner_id := -1
var elapsed := 0.0

var _rng := RandomNumberGenerator.new()
var _next_bolt_at := 0.0
var _next_mystery_at := 0.0
var _forced_roll: SnakeWorld.Item = SnakeWorld.Item.NONE
var _gap := GameConfig.OBSTACLE_GAP


func _init(arena_width: float, arena_height: float, seed_value: int = 0) -> void:
	width = arena_width
	height = arena_height
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


# --------------------------------------------------------------------------- #
## Lay the arena out at a new size. The snakes carry their own bounds for
## collisions, so they have to be told as well.
func resize(new_width: float, new_height: float) -> void:
	if is_equal_approx(width, new_width) and is_equal_approx(height, new_height):
		return
	width = new_width
	height = new_height
	for id: int in snakes:
		snakes[id].width = new_width
		snakes[id].height = new_height


func add_snake(id: int) -> SnakeWorld:
	var snake := SnakeWorld.new(width, height)
	snakes[id] = snake
	return snake


func remove_snake(id: int) -> void:
	snakes.erase(id)


func alive_ids() -> Array:
	var alive: Array = []
	for id: int in snakes:
		if snakes[id].alive:
			alive.append(id)
	return alive


## Place everyone on the arena, spread out and facing the middle.
func start() -> void:
	over = false
	winner_id = -1
	elapsed = 0.0
	ground = []
	_next_bolt_at = _rng.randf_range(
		GameConfig.BOOST_FIRST_SPAWN.x, GameConfig.BOOST_FIRST_SPAWN.y
	)
	_next_mystery_at = _rng.randf_range(
		GameConfig.MYSTERY_FIRST_SPAWN.x, GameConfig.MYSTERY_FIRST_SPAWN.y
	)

	var ids: Array = snakes.keys()
	ids.sort()
	var count := maxi(1, ids.size())
	spawns = {}
	for index in range(ids.size()):
		var spot := _spawn_pose(index, count)
		spawns[ids[index]] = spot
		snakes[ids[index]].reset(spot[0], spot[1])

	_build_obstacles()
	food = free_spot(GameConfig.FOOD_RADIUS + 0.8, 3.0)
	running = true


## Players start spread around a circle, each facing along it rather than
## at the middle: pointing everybody at the same spot only means a pile-up
## in the first seconds.
func _spawn_pose(index: int, count: int) -> Array:
	var centre := Vector2(width * 0.5, height * 0.5)
	if count == 1:
		return [centre, 0.0]
	var radius: float = minf(width, height) * 0.3
	var angle := TAU * index / count
	var position := centre + Vector2(cos(angle), sin(angle)) * radius
	return [position, angle + PI * 0.5]


# --------------------------------------------------------------------------- #
# Rocks
# --------------------------------------------------------------------------- #
## Scatter rocks of assorted sizes. Everything a snake needs at the start of
## a round - its spawn point and the lane it sets off along - is kept clear,
## and two rocks never sit closer than a snake is wide, so the arena always
## stays navigable even when it is cluttered.
func _build_obstacles() -> void:
	obstacles = []
	lane_length = GameConfig.OBSTACLE_LANE_LENGTH
	_gap = GameConfig.OBSTACLE_GAP
	var wanted := _rng.randi_range(GameConfig.OBSTACLE_COUNT.x, GameConfig.OBSTACLE_COUNT.y)
	var attempts := 0
	while obstacles.size() < wanted and attempts < 900:
		attempts += 1
		# Every player's lane has to stay clear, so a full arena leaves far
		# less room for rocks than a solo one. Rather than give up on them,
		# the protected lane is shortened a little at a time.
		if attempts % 250 == 0:
			lane_length = maxf(GameConfig.OBSTACLE_LANE_MIN, lane_length - 3.0)
		# Big rocks go down first, while there is room for them; what is
		# left over gets filled with smaller ones. A crowded arena therefore
		# ends up with more boulders and fewer cliffs, never with nothing.
		var squeeze := clampf(1.0 - attempts / 500.0, 0.0, 1.0)
		var radius := _rng.randf_range(
			GameConfig.OBSTACLE_RADIUS.x,
			lerpf(GameConfig.OBSTACLE_RADIUS.x + 0.4, GameConfig.OBSTACLE_RADIUS.y, squeeze)
		)
		# A corridor is always left between a rock and the wall, so the lane
		# running round the edge of the arena is never pinched shut.
		var margin := radius + GameConfig.OBSTACLE_WALL_GAP
		var candidate := Vector2(
			_rng.randf_range(margin, width - margin),
			_rng.randf_range(margin, height - margin)
		)
		if not _obstacle_fits(candidate, radius):
			continue
		_add_obstacle(candidate, radius)

	# The arena promises a handful of rocks; a crowded one must still keep
	# that promise. The last resort is the smallest rock, the shortest lane
	# and a tighter squeeze between neighbours - never a snake's spawn.
	var floor_count := minimum_rocks(snakes.size())
	if obstacles.size() >= floor_count:
		return
	lane_length = GameConfig.OBSTACLE_LANE_MIN
	_gap = GameConfig.OBSTACLE_GAP_TIGHT
	var radius: float = GameConfig.OBSTACLE_RADIUS.x
	var margin := radius + GameConfig.OBSTACLE_WALL_GAP
	for _attempt in range(400):
		if obstacles.size() >= floor_count:
			break
		var candidate := Vector2(
			_rng.randf_range(margin, width - margin),
			_rng.randf_range(margin, height - margin)
		)
		if _obstacle_fits(candidate, radius):
			_add_obstacle(candidate, radius)
	_gap = GameConfig.OBSTACLE_GAP


## The fewest rocks an arena will ever be laid out with. Every player's
## spawn and the lane ahead of it are held clear, so a crowded arena simply
## has less floor left for rocks - the promise bends with the crowd rather
## than being broken.
static func minimum_rocks(players: int) -> int:
	return maxi(3, GameConfig.OBSTACLE_COUNT.x - maxi(0, players - 3))


func _add_obstacle(position: Vector2, radius: float) -> void:
	obstacles.append({
		"position": position,
		"radius": radius,
		"spin": _rng.randf() * TAU,
		"sides": _rng.randi_range(5, 7),
	})


func _obstacle_fits(candidate: Vector2, radius: float) -> bool:
	for other: Dictionary in obstacles:
		if candidate.distance_to(other["position"]) < radius + other["radius"] + _gap:
			return false
	for id: int in spawns:
		var pose: Array = spawns[id]
		if candidate.distance_to(pose[0]) < radius + GameConfig.OBSTACLE_SPAWN_CLEAR:
			return false
		for point: Vector2 in lane_points(pose[0], pose[1]):
			if candidate.distance_to(point) < radius + GameConfig.OBSTACLE_LANE_CLEAR:
				return false
	return true


## The stretch of arena straight ahead of a spawn point. Kept clear so the
## first seconds of a round are never a blind crash.
func lane_points(position: Vector2, heading: float) -> Array:
	var direction := Vector2(cos(heading), sin(heading))
	var points: Array = []
	var travelled := 1.0
	while travelled <= lane_length:
		points.append(position + direction * travelled)
		travelled += 1.5
	return points


## Is that point inside a rock? Clearance widens it by the body radius.
func blocked_by_obstacle(point: Vector2, clearance: float = 0.0) -> bool:
	for rock: Dictionary in obstacles:
		if point.distance_to(rock["position"]) < rock["radius"] + clearance:
			return true
	return false


## Something dropped in a pocket between two rocks can be impossible to
## reach without dying for it, so anything laid on the ground has to have
## open floor on most sides of it. A spot against a wall loses the probes
## that fall outside the arena, which is why five out of eight is enough.
func has_elbow_room(candidate: Vector2) -> bool:
	var open := 0
	for index in range(8):
		var probe := candidate + Vector2.from_angle(TAU * index / 8.0) * 2.8
		if probe.x < 0.4 or probe.y < 0.4 or probe.x > width - 0.4 or probe.y > height - 0.4:
			continue
		if blocked_by_obstacle(probe, GameConfig.SNAKE_RADIUS):
			continue
		open += 1
	return open >= 5


## Rocks as plain floats, so the host can hand the arena to a client.
func obstacle_data() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for rock: Dictionary in obstacles:
		data.append(rock["position"].x)
		data.append(rock["position"].y)
		data.append(rock["radius"])
		data.append(rock["spin"])
		data.append(float(rock["sides"]))
	return data


func set_obstacles(data: PackedFloat32Array) -> void:
	obstacles = []
	var index := 0
	while index + 4 < data.size():
		obstacles.append({
			"position": Vector2(data[index], data[index + 1]),
			"radius": data[index + 2],
			"spin": data[index + 3],
			"sides": int(data[index + 4]),
		})
		index += 5


## Put a rock at a chosen spot. The self-test lays one in the snake's path
## the way it lays items, so the collision is exercised on purpose.
func place_obstacle(position: Vector2, radius: float) -> void:
	obstacles.append({
		"position": position,
		"radius": radius,
		"spin": _rng.randf() * TAU,
		"sides": 6,
	})


# --------------------------------------------------------------------------- #
func step(delta: float) -> void:
	if not running or over:
		return
	elapsed += delta

	if not authoritative:
		for id: int in snakes:
			var mirrored: SnakeWorld = snakes[id]
			if mirrored.alive:
				mirrored.advance(delta)
		return

	for id: int in snakes:
		var snake: SnakeWorld = snakes[id]
		if not snake.alive:
			continue
		var outcome := snake.step(delta)
		if SnakeWorld.is_death(outcome):
			snake_died.emit(id, outcome)
			continue
		if blocked_by_obstacle(snake.head_position, GameConfig.SNAKE_RADIUS):
			snake.kill(snake.head_position)
			snake_died.emit(id, SnakeWorld.Outcome.DEAD_ROCK)
			continue
		_check_bite(id, snake)

	for id: int in snakes:
		var snake: SnakeWorld = snakes[id]
		if snake.alive:
			_check_food(id, snake)
			_check_ground(id, snake)

	_update_spawns()
	_check_end()


## Running into somebody else is as fatal as running into yourself.
func _check_bite(id: int, snake: SnakeWorld) -> void:
	for other_id: int in snakes:
		if other_id == id:
			continue
		var other: SnakeWorld = snakes[other_id]
		if not other.alive:
			continue
		if other.hits_body(snake.head_position, 0.0):
			snake.kill(snake.head_position)
			snake_died.emit(id, SnakeWorld.Outcome.DEAD_OTHER)
			return


func _check_food(id: int, snake: SnakeWorld) -> void:
	if snake.head_position.distance_to(food) >= GameConfig.SNAKE_RADIUS + GameConfig.FOOD_RADIUS:
		return
	snake.add_score(1)
	food = free_spot(GameConfig.FOOD_RADIUS + 0.8, 3.0)
	food_eaten.emit(id)


func _check_ground(id: int, snake: SnakeWorld) -> void:
	for index in range(ground.size() - 1, -1, -1):
		var item: Dictionary = ground[index]
		var radius: float = (
			GameConfig.BOOST_RADIUS if item["kind"] == SnakeWorld.Ground.BOLT
			else GameConfig.MYSTERY_RADIUS
		)
		if snake.head_position.distance_to(item["position"]) > GameConfig.SNAKE_RADIUS + radius:
			continue
		if item["kind"] == SnakeWorld.Ground.BOLT and snake.carried != SnakeWorld.Item.NONE:
			continue    # the slot is busy: leave the bolt where it lies

		ground.remove_at(index)
		var roll := SnakeWorld.Item.SPEED
		if item["kind"] == SnakeWorld.Ground.BOLT:
			snake.carried = SnakeWorld.Item.SPEED
			_next_bolt_at = elapsed + _rng.randf_range(
				GameConfig.BOOST_RESPAWN.x, GameConfig.BOOST_RESPAWN.y
			)
		else:
			roll = _roll_mystery()
			match roll:
				SnakeWorld.Item.SLOW:
					# A curse is swallowed on the spot: there is no choosing it.
					snake.start_effect(SnakeWorld.Item.SLOW)
				SnakeWorld.Item.SCORE_UP:
					# Points are settled at once, good or bad: there is
					# nothing to aim or hold on to.
					snake.add_score(GameConfig.SCORE_CARD_POINTS)
				SnakeWorld.Item.SCORE_DOWN:
					snake.add_score(-GameConfig.SCORE_CARD_POINTS)
				_:
					snake.carried = roll
			_next_mystery_at = elapsed + _rng.randf_range(
				GameConfig.MYSTERY_RESPAWN.x, GameConfig.MYSTERY_RESPAWN.y
			)
		item_collected.emit(id, item["kind"], roll)
		return


func _roll_mystery() -> SnakeWorld.Item:
	if _forced_roll != SnakeWorld.Item.NONE:
		var forced := _forced_roll
		_forced_roll = SnakeWorld.Item.NONE
		return forced
	var card := _rng.randf() < GameConfig.MYSTERY_SCORE_CHANCE
	if _rng.randf() < GameConfig.MYSTERY_BONUS_CHANCE:
		return SnakeWorld.Item.SCORE_UP if card else SnakeWorld.Item.SPEED
	return SnakeWorld.Item.SCORE_DOWN if card else SnakeWorld.Item.SLOW


func _update_spawns() -> void:
	if not has_ground(SnakeWorld.Ground.BOLT) and elapsed >= _next_bolt_at:
		drop(SnakeWorld.Ground.BOLT)
	if not has_ground(SnakeWorld.Ground.MYSTERY) and elapsed >= _next_mystery_at:
		drop(SnakeWorld.Ground.MYSTERY)


## The round is over when at most one snake is left standing.
func _check_end() -> void:
	var alive := alive_ids()
	if snakes.size() > 1:
		if alive.size() <= 1:
			over = true
			running = false
			winner_id = alive[0] if alive.size() == 1 else -1
			finished.emit(winner_id)
	elif alive.is_empty():
		over = true
		running = false
		winner_id = -1
		finished.emit(-1)


# --------------------------------------------------------------------------- #
func has_ground(kind: SnakeWorld.Ground) -> bool:
	for item: Dictionary in ground:
		if item["kind"] == kind:
			return true
	return false


func ground_position(kind: SnakeWorld.Ground) -> Vector2:
	for item: Dictionary in ground:
		if item["kind"] == kind:
			return item["position"]
	return Vector2.ZERO


func drop(kind: SnakeWorld.Ground, forced: SnakeWorld.Item = SnakeWorld.Item.NONE) -> void:
	if kind == SnakeWorld.Ground.MYSTERY:
		_forced_roll = forced
	if has_ground(kind):
		return
	var margin: float = (
		GameConfig.BOOST_RADIUS if kind == SnakeWorld.Ground.BOLT
		else GameConfig.MYSTERY_RADIUS
	) + 1.0
	ground.append({"kind": kind, "position": free_spot(margin, 4.5)})


## Put an item at a chosen spot rather than a random one. The self-test uses
## it to lay something right in the snake's path, so a phase never waits on
## the bot deciding a detour is worth it.
func drop_at(kind: SnakeWorld.Ground, position: Vector2, forced: SnakeWorld.Item = SnakeWorld.Item.NONE) -> void:
	if kind == SnakeWorld.Ground.MYSTERY:
		_forced_roll = forced
	for index in range(ground.size() - 1, -1, -1):
		if ground[index]["kind"] == kind:
			ground.remove_at(index)
	var margin: float = (
		GameConfig.BOOST_RADIUS if kind == SnakeWorld.Ground.BOLT
		else GameConfig.MYSTERY_RADIUS
	) + 1.0
	ground.append({"kind": kind, "position": Vector2(
		clampf(position.x, margin, width - margin),
		clampf(position.y, margin, height - margin)
	)})


## A spot clear of the walls, the snakes, the food and the other items.
func free_spot(margin: float, clearance: float) -> Vector2:
	for _attempt in range(40):
		var candidate := Vector2(
			_rng.randf_range(margin, width - margin),
			_rng.randf_range(margin, height - margin)
		)
		var clear := not blocked_by_obstacle(candidate, margin + 1.0)
		for id: int in snakes:
			if not clear:
				break
			var snake: SnakeWorld = snakes[id]
			if snake.head_position.distance_to(candidate) < clearance:
				clear = false
				break
			if snake.hits_body(candidate, 0.0):
				clear = false
				break
		if clear and candidate.distance_to(food) < 2.0:
			clear = false
		if clear:
			for item: Dictionary in ground:
				if candidate.distance_to(item["position"]) < 2.5:
					clear = false
					break
		if clear and not has_elbow_room(candidate):
			clear = false
		if clear:
			return candidate
	# Out of attempts: settle for anywhere that is at least not inside a rock,
	# since an item buried in one could never be picked up.
	for _last_try in range(60):
		var fallback := Vector2(
			_rng.randf_range(margin, width - margin),
			_rng.randf_range(margin, height - margin)
		)
		if not blocked_by_obstacle(fallback, margin + 0.5) and has_elbow_room(fallback):
			return fallback
	return Vector2(width * 0.5, height * 0.5)
