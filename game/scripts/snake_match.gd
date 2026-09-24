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


func _init(arena_width: float, arena_height: float, seed_value: int = 0) -> void:
	width = arena_width
	height = arena_height
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


# --------------------------------------------------------------------------- #
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
	for index in range(ids.size()):
		var spot := _spawn_pose(index, count)
		snakes[ids[index]].reset(spot[0], spot[1])

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
	snake.score += 1
	snake.grow(GameConfig.GROWTH_PER_FOOD)
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
			if roll == SnakeWorld.Item.SLOW:
				# A curse is swallowed on the spot: there is no choosing it.
				snake.start_effect(SnakeWorld.Item.SLOW)
			else:
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
	return (
		SnakeWorld.Item.SPEED if _rng.randf() < GameConfig.MYSTERY_BONUS_CHANCE
		else SnakeWorld.Item.SLOW
	)


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
		var clear := true
		for id: int in snakes:
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
		if clear:
			return candidate
	return Vector2(
		_rng.randf_range(margin, width - margin),
		_rng.randf_range(margin, height - margin)
	)
