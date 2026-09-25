class_name SnakeMatch
extends RefCounted

## A round: the arena, what lies on it, and every snake playing in it.
##
## One snake is a SnakeWorld; the match owns everything they share - the
## food, the crates, the collisions between them and the last-survivor rule.
## Solo is simply a match with a single snake.

signal snake_died(id: int, cause: SnakeWorld.Outcome)
signal food_eaten(id: int)
signal matter_spat(id: int, amount: float)
## A snake running the shears sliced another one.
signal snake_cut(cutter_id: int, victim_id: int, matter: float, at: Vector2)
signal item_collected(id: int, kind: SnakeWorld.Ground, roll: SnakeWorld.Item)
signal finished(winner_id: int)

var width: float
var height: float

var snakes: Dictionary = {}          # id -> SnakeWorld
## Every pellet of matter lying on the floor. Eating one takes it out of
## the field and another is sown somewhere else, so the field never runs
## dry and never fills up.
var food := PackedVector2Array()
## What each mote on the floor is worth, in the same order as `food`.
var food_value := PackedFloat32Array()
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
var duration := GameConfig.ROUND_SECONDS
var _respawn_at: Dictionary = {}       # id -> when it comes back

var _rng := RandomNumberGenerator.new()
var _next_bolt_at := 0.0
var _next_mystery_at := 0.0
var _next_phase_at := 0.0
var _next_shears_at := 0.0
var _next_magnet_at := 0.0
## Who cut whom last, and until when they may not do it again.
var _recut_until: Dictionary = {}     # Vector2i(cutter, victim) -> time
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
	_respawn_at = {}
	ground = []
	_next_bolt_at = _rng.randf_range(
		GameConfig.BOOST_FIRST_SPAWN.x, GameConfig.BOOST_FIRST_SPAWN.y
	)
	_next_mystery_at = _rng.randf_range(
		GameConfig.MYSTERY_FIRST_SPAWN.x, GameConfig.MYSTERY_FIRST_SPAWN.y
	)
	_next_phase_at = _rng.randf_range(
		GameConfig.PHASE_FIRST_SPAWN.x, GameConfig.PHASE_FIRST_SPAWN.y
	)
	_next_shears_at = _rng.randf_range(
		GameConfig.SHEARS_FIRST_SPAWN.x, GameConfig.SHEARS_FIRST_SPAWN.y
	)
	_recut_until = {}
	_next_magnet_at = _rng.randf_range(
		GameConfig.MAGNET_FIRST_SPAWN.x, GameConfig.MAGNET_FIRST_SPAWN.y
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
	_sow_field()
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
## Bring up a tenth of what a snake has swallowed. The matter is not
## destroyed: it lands on the floor behind the snake, where anybody -
## including the snake that brought it up - can eat it again.
func spit(id: int) -> float:
	var snake: SnakeWorld = snakes.get(id)
	if snake == null or not snake.alive:
		return 0.0
	var amount := snake.spit_amount()
	if amount <= 0.0:
		return 0.0
	snake.add_score(-amount)
	# It lands well behind the head and off to the side, so the snake does
	# not simply swallow it again and it is not hidden under the body.
	_scatter_matter(snake.body_points(), amount, 8)
	matter_spat.emit(id, amount)
	return amount


## A snake that dies leaves everything it swallowed on the floor, spread
## along the body it no longer has. Matter is never lost, only dropped.
func decompose(snake: SnakeWorld) -> float:
	var amount := snake.score
	if amount <= 0.0:
		return 0.0
	var spread: PackedVector2Array = snake.body_points()
	if spread.is_empty():
		spread = PackedVector2Array([snake.death_position])
	_scatter_matter(spread, amount, 0)
	return amount


## Lay `amount` pellets along a line of points, skipping the first few so
## nothing lands under the head that produced them.
## Lay motes along a line of points until they are worth `amount` between
## them, skipping the first few so nothing lands under the head that
## produced them. What went in comes back out, mote by mote.
func _scatter_matter(along: PackedVector2Array, amount: float, skip: int) -> void:
	if along.is_empty() or amount <= 0.0:
		return
	# A short snake has fewer points than the skip asks for: start wherever
	# there is something rather than off the end of the body.
	var first := mini(skip, along.size() - 1)
	var usable := maxi(1, along.size() - first)
	var left := amount
	var laid := 0
	while left > 0.0 and laid < 400:
		var value: float = minf(GameConfig.roll_food_value(_rng), left)
		if left - value < GameConfig.FOOD_VALUE.x:
			value = left        # no crumb too small to be worth eating
		left -= value
		var at: Vector2 = along[mini(first + (laid * usable) / 8, along.size() - 1)]
		var jitter := Vector2(_rng.randf_range(-1.3, 1.3), _rng.randf_range(-1.3, 1.3))
		food.append(Vector2(
			clampf(at.x + jitter.x, 0.6, width - 0.6),
			clampf(at.y + jitter.y, 0.6, height - 0.6)
		))
		food_value.append(value)
		laid += 1


## How many pellets this arena should hold.
func field_size() -> int:
	return maxi(GameConfig.FOOD_MIN, int(width * height / GameConfig.FOOD_PER_AREA))


## Fill the field from scratch at the start of a round.
func _sow_field() -> void:
	food.resize(0)
	food_value.resize(0)
	for _index in range(field_size()):
		sow_one()


## Drop one pellet somewhere sensible. Used when one is eaten, so the
## amount of matter on the floor stays where the arena wants it.
func sow_one() -> void:
	var value := GameConfig.roll_food_value(_rng)
	food.append(free_spot(GameConfig.food_radius(value) + 0.8, 3.0))
	food_value.append(value)


## Scatter rocks of assorted sizes. Everything a snake needs at the start of
## a round - its spawn point and the lane it sets off along - is kept clear,
## and two rocks never sit closer than a snake is wide, so the arena always
## stays navigable even when it is cluttered.
func _build_obstacles() -> void:
	obstacles = []
	lane_length = GameConfig.OBSTACLE_LANE_LENGTH
	_gap = GameConfig.OBSTACLE_GAP
	# A field twice as wide needs more than the same handful of rocks.
	var spread := width * height / GameConfig.OBSTACLE_PER_AREA
	var wanted := _rng.randi_range(
		GameConfig.OBSTACLE_COUNT.x, GameConfig.OBSTACLE_COUNT.y
	) + int(spread)
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
		# Marked, so a check on how the arena was laid out does not judge a
		# rock the test dropped in front of the snake on purpose.
		"planted": true,
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
			decompose(snake)
			snake_died.emit(id, outcome)
			continue
		if blocked_by_obstacle(snake.head_position, snake.radius):
			snake.kill(snake.head_position)
			decompose(snake)
			snake_died.emit(id, SnakeWorld.Outcome.DEAD_ROCK)
			continue
		_check_bite(id, snake)

	pull_matter(delta)

	for id: int in snakes:
		var snake: SnakeWorld = snakes[id]
		if snake.alive:
			_check_food(id, snake)
			_check_ground(id, snake)

	_update_spawns()
	_respawn_dead()
	_check_end()


## Running into somebody else is as fatal as running into yourself, unless
## the ghost ring is running: then you go straight through.
func _check_bite(id: int, snake: SnakeWorld) -> void:
	if snake.phasing():
		return
	for other_id: int in snakes:
		if other_id == id:
			continue
		var other: SnakeWorld = snakes[other_id]
		if not other.alive:
			continue
		if other.hits_body(snake.head_position, 0.0):
			if snake.cutting():
				# The shears: the body gives way instead of the head.
				cut(id, other_id)
				continue
			snake.kill(snake.head_position)
			decompose(snake)
			snake_died.emit(id, SnakeWorld.Outcome.DEAD_OTHER)
			return


## Every snake running a magnet draws the gems around its head towards its
## mouth, gently at the edge of the field and fast right at the lips. A gem
## within two fields goes to the nearer one. The matter only moves; eating
## it is still the head's job, one step later.
func pull_matter(delta: float) -> int:
	var magnets: Array[SnakeWorld] = []
	for id: int in snakes:
		var snake: SnakeWorld = snakes[id]
		if snake.alive and snake.magnetic():
			magnets.append(snake)
	if magnets.is_empty():
		return 0
	var reach_squared := GameConfig.MAGNET_REACH * GameConfig.MAGNET_REACH
	var moved := 0
	for index in range(food.size()):
		var gem: Vector2 = food[index]
		var puller: SnakeWorld = null
		var best := reach_squared
		for magnet: SnakeWorld in magnets:
			var distance := gem.distance_squared_to(magnet.head_position)
			if distance < best:
				best = distance
				puller = magnet
		if puller == null:
			continue
		var distance := sqrt(best)
		var closeness := 1.0 - distance / GameConfig.MAGNET_REACH
		var speed := lerpf(GameConfig.MAGNET_PULL, GameConfig.MAGNET_PULL_CLOSE, closeness)
		food[index] = gem.move_toward(puller.head_position, minf(distance, speed * delta))
		moved += 1
	return moved


## Slice `victim` where the head of `cutter` touches it. What was behind the
## cut drops as gems along the part that fell off; the victim keeps its head
## and the rest. Returns the matter that fell, zero when nothing was cut.
func cut(cutter_id: int, victim_id: int) -> float:
	var cutter: SnakeWorld = snakes.get(cutter_id)
	var victim: SnakeWorld = snakes.get(victim_id)
	if cutter == null or victim == null or not victim.alive:
		return 0.0
	var pair := Vector2i(cutter_id, victim_id)
	if elapsed < float(_recut_until.get(pair, -1.0)):
		return 0.0
	# Where along the victim the blade went in: the body point nearest the
	# head that did the cutting.
	var points := victim.body_points()
	var nearest := 0
	var best := INF
	for index in range(points.size()):
		var distance := cutter.head_position.distance_squared_to(points[index])
		if distance < best:
			best = distance
			nearest = index
	var result := victim.sever(GameConfig.SEGMENT_SPACING * (nearest + 1))
	if result.is_empty():
		return 0.0
	_recut_until[pair] = elapsed + GameConfig.SHEARS_RECUT
	var matter: float = result["matter"]
	_scatter_matter(result["points"], matter, 0)
	snake_cut.emit(cutter_id, victim_id, matter, cutter.head_position)
	return matter


func _check_food(id: int, snake: SnakeWorld) -> void:
	for index in range(food.size() - 1, -1, -1):
		var value: float = food_value[index]
		var reach: float = snake.radius + GameConfig.food_radius(value)
		if snake.head_position.distance_squared_to(food[index]) >= reach * reach:
			continue
		food.remove_at(index)
		food_value.remove_at(index)
		snake.add_score(value)
		# The field is kept at its size, but what a snake brought up or left
		# behind counts towards it: sowing on top of that would flood it.
		if food.size() < field_size():
			sow_one()
		food_eaten.emit(id)
		return


func _check_ground(id: int, snake: SnakeWorld) -> void:
	for index in range(ground.size() - 1, -1, -1):
		var item: Dictionary = ground[index]
		var radius: float = _ground_radius(item["kind"])
		if snake.head_position.distance_to(item["position"]) > snake.radius + radius:
			continue
		if item["kind"] != SnakeWorld.Ground.MYSTERY and snake.carried != SnakeWorld.Item.NONE:
			continue    # the slot is busy: leave it where it lies

		ground.remove_at(index)
		var roll := SnakeWorld.Item.SPEED
		if item["kind"] == SnakeWorld.Ground.BOLT:
			snake.carried = SnakeWorld.Item.SPEED
			_next_bolt_at = elapsed + _rng.randf_range(
				GameConfig.BOOST_RESPAWN.x, GameConfig.BOOST_RESPAWN.y
			)
		elif item["kind"] == SnakeWorld.Ground.PHASE:
			roll = SnakeWorld.Item.PHASE
			snake.carried = SnakeWorld.Item.PHASE
			_next_phase_at = elapsed + _rng.randf_range(
				GameConfig.PHASE_RESPAWN.x, GameConfig.PHASE_RESPAWN.y
			)
		elif item["kind"] == SnakeWorld.Ground.MAGNET:
			roll = SnakeWorld.Item.MAGNET
			snake.carried = SnakeWorld.Item.MAGNET
			_next_magnet_at = elapsed + _rng.randf_range(
				GameConfig.MAGNET_RESPAWN.x, GameConfig.MAGNET_RESPAWN.y
			)
		elif item["kind"] == SnakeWorld.Ground.SHEARS:
			roll = SnakeWorld.Item.SHEARS
			snake.carried = SnakeWorld.Item.SHEARS
			_next_shears_at = elapsed + _rng.randf_range(
				GameConfig.SHEARS_RESPAWN.x, GameConfig.SHEARS_RESPAWN.y
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
	if not has_ground(SnakeWorld.Ground.PHASE) and elapsed >= _next_phase_at:
		drop(SnakeWorld.Ground.PHASE)
	if not has_ground(SnakeWorld.Ground.SHEARS) and elapsed >= _next_shears_at:
		drop(SnakeWorld.Ground.SHEARS)
	if not has_ground(SnakeWorld.Ground.MAGNET) and elapsed >= _next_magnet_at:
		drop(SnakeWorld.Ground.MAGNET)


## Seconds left on the clock.
func time_left() -> float:
	return maxf(0.0, duration - elapsed)


## The biggest snake on the field, which is the only thing being played for.
func longest_id() -> int:
	var best := -1
	var best_length := -1.0
	for id: int in snakes:
		var snake: SnakeWorld = snakes[id]
		if snake.target_body_length > best_length:
			best_length = snake.target_body_length
			best = id
	return best


## Nobody is knocked out: a snake that dies is out of the field for a
## couple of seconds and comes back small, wherever there is room.
func _respawn_dead() -> void:
	var index := 0
	var ids: Array = snakes.keys()
	ids.sort()
	for id: int in ids:
		var snake: SnakeWorld = snakes[id]
		if snake.alive:
			continue
		if not _respawn_at.has(id):
			_respawn_at[id] = elapsed + GameConfig.RESPAWN_DELAY
		elif elapsed >= float(_respawn_at[id]):
			_respawn_at.erase(id)
			var spot := free_spot(GameConfig.SNAKE_RADIUS + 1.5, 6.0)
			snake.reset(spot, open_heading(spot))
		index += 1


## Which way to face from a given spot: the direction with the most open
## floor ahead of it. Coming back only to drive into the nearest rock is
## not a second chance, it is the same death twice.
func open_heading(from: Vector2) -> float:
	var best := _rng.randf_range(-PI, PI)
	var best_room := -1.0
	for index in range(12):
		var heading := TAU * index / 12.0
		var direction := Vector2(cos(heading), sin(heading))
		var room := 0.0
		while room < GameConfig.OBSTACLE_LANE_LENGTH:
			var point := from + direction * (room + 1.0)
			if not _inside(point) or blocked_by_obstacle(point, GameConfig.SNAKE_RADIUS + 0.5):
				break
			room += 1.0
		if room > best_room:
			best_room = room
			best = heading
	return best


func _inside(point: Vector2) -> bool:
	var margin := GameConfig.SNAKE_RADIUS + 0.5
	return (
		point.x >= margin and point.x <= width - margin
		and point.y >= margin and point.y <= height - margin
	)


## The round is over when the clock runs out. The longest snake takes it.
func _check_end() -> void:
	if elapsed < duration:
		return
	over = true
	running = false
	winner_id = longest_id()
	finished.emit(winner_id)


# --------------------------------------------------------------------------- #
static func _ground_radius(kind: SnakeWorld.Ground) -> float:
	match kind:
		SnakeWorld.Ground.BOLT:
			return GameConfig.BOOST_RADIUS
		SnakeWorld.Ground.PHASE:
			return GameConfig.PHASE_RADIUS
		SnakeWorld.Ground.MAGNET:
			return GameConfig.MAGNET_RADIUS
		SnakeWorld.Ground.SHEARS:
			return GameConfig.SHEARS_RADIUS
		_:
			return GameConfig.MYSTERY_RADIUS


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
	var margin := _ground_radius(kind) + 1.0
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
	var margin := _ground_radius(kind) + 1.0
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
		if clear:
			for pellet: Vector2 in food:
				if candidate.distance_to(pellet) < 1.6:
					clear = false
					break
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
