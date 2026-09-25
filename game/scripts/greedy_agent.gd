class_name GreedyAgent
extends RefCounted

## An automated player, used by the self-test so the executable can play a
## real game on its own.
##
## It steers like a player would: aim at the food, but look a few units ahead
## and turn away when the wall or its own body is in the way.

const LOOK_AHEAD := 3.4
const FEELER_ANGLE := 0.55        # radians between the side feelers
const ALIGNED_ENOUGH := 0.08      # radians: stop correcting below this


var _match: SnakeMatch = null


## Returns the turn to apply: -1 left, 0 straight, +1 right.
func decide_in(game_match: SnakeMatch, world: SnakeWorld) -> float:
	_match = game_match
	return decide(world)


func decide(world: SnakeWorld) -> float:
	var escape := _avoid(world)
	if escape != 0.0:
		return escape

	var to_target := (_target(world) - world.head_position).angle()
	var error := wrapf(to_target - world.heading, -PI, PI)
	if absf(error) < ALIGNED_ENOUGH:
		return 0.0
	return signf(error)


## A bolt or a crate is worth a detour, but not a long one. The bot takes
## the gamble on crates: it cannot know what is inside either.
func _target(world: SnakeWorld) -> Vector2:
	if _match == null:
		return world.head_position + world.direction() * 10.0

	# Blades out: go for the nearest body that is not ours. That is where
	# the matter is now, and the shears only last a few seconds.
	if world.cutting():
		var prey := _nearest_body(world)
		if prey != Vector2.INF:
			return prey

	var best: Vector2 = _nearest_pellet(world)
	var best_distance: float = world.head_position.distance_to(best) * 1.6

	# The shears are nearly as rare as the ring, and far more dangerous in
	# anybody else's slot.
	if world.carried == SnakeWorld.Item.NONE and _match.has_ground(SnakeWorld.Ground.SHEARS):
		var shears: Vector2 = _match.ground_position(SnakeWorld.Ground.SHEARS)
		if world.head_position.distance_to(shears) < best_distance * 3.0:
			return shears

	# The ghost ring is the rarest thing on the field and the only one worth
	# crossing it for, so it outranks everything else.
	if world.carried == SnakeWorld.Item.NONE and _match.has_ground(SnakeWorld.Ground.PHASE):
		return _match.ground_position(SnakeWorld.Ground.PHASE)

	if world.carried == SnakeWorld.Item.NONE and _match.has_ground(SnakeWorld.Ground.BOLT):
		var bolt: Vector2 = _match.ground_position(SnakeWorld.Ground.BOLT)
		var distance: float = world.head_position.distance_to(bolt)
		if distance < best_distance:
			best = bolt
			best_distance = distance

	if _match.has_ground(SnakeWorld.Ground.MYSTERY):
		var crate: Vector2 = _match.ground_position(SnakeWorld.Ground.MYSTERY)
		var distance: float = world.head_position.distance_to(crate)
		if distance < best_distance:
			best = crate

	return best


## The field holds dozens of pellets now, so the bot heads for whichever
## one is closest rather than for the one and only fruit.
func _nearest_pellet(world: SnakeWorld) -> Vector2:
	var best := world.head_position + world.direction() * 10.0
	var best_distance := INF
	for pellet: Vector2 in _match.food:
		var distance := world.head_position.distance_squared_to(pellet)
		if distance < best_distance:
			best_distance = distance
			best = pellet
	return best


## The closest point on another living snake's body, within reach of the
## shears while they last. Vector2.INF when nobody is close enough.
func _nearest_body(world: SnakeWorld) -> Vector2:
	var reach: float = GameConfig.SNAKE_SPEED * world.speed_multiplier * world.effect_time_left
	var best := Vector2.INF
	var best_distance := reach * reach
	for id: int in _match.snakes:
		var other: SnakeWorld = _match.snakes[id]
		if other == world or not other.alive:
			continue
		var points := other.body_points()
		# Every few points is plenty to aim with.
		for index in range(0, points.size(), 3):
			var distance := world.head_position.distance_squared_to(points[index])
			if distance < best_distance:
				best_distance = distance
				best = points[index]
	return best


## Non-zero when something is in the way, pointing to the freer side.
func _avoid(world: SnakeWorld) -> float:
	# Twice the speed needs twice the warning - and so does a body too fat
	# to turn sharply, which needs a wider circle to get out of the way.
	var reach: float = LOOK_AHEAD * world.speed_multiplier / maxf(world.turn_scale, 0.2)
	var ahead := _blocked(world, 0.0, reach)
	var left := _blocked(world, -FEELER_ANGLE, reach * 0.8)
	var right := _blocked(world, FEELER_ANGLE, reach * 0.8)

	if not ahead and not left and not right:
		return 0.0
	if left and not right:
		return 1.0
	if right and not left:
		return -1.0
	if ahead:
		# Both sides are busy: commit to the side with more room.
		return -1.0 if _room(world, -FEELER_ANGLE) >= _room(world, FEELER_ANGLE) else 1.0
	return 0.0


## True when another snake's body lies straight ahead, close enough that
## the ghost ring would be the way through rather than a way round.
func body_ahead(game_match: SnakeMatch, world: SnakeWorld) -> bool:
	var reach: float = LOOK_AHEAD * world.speed_multiplier
	for index in range(1, 5):
		var point: Vector2 = world.head_position + world.direction() * (reach * index / 4.0)
		for id: int in game_match.snakes:
			var other: SnakeWorld = game_match.snakes[id]
			if other != world and other.alive and other.hits_body(point, 0.0):
				return true
	return false


func _blocked(world: SnakeWorld, angle_offset: float, distance: float) -> bool:
	var direction := Vector2(
		cos(world.heading + angle_offset), sin(world.heading + angle_offset)
	)
	var samples := 5
	for index in range(1, samples + 1):
		var point: Vector2 = world.head_position + direction * (distance * index / samples)
		if not world.is_inside(point):
			return true
		if world.hits_body(point):
			return true
		# A rock stops you as dead as a wall does.
		if _match != null and _match.blocked_by_obstacle(point, world.radius):
			return true
		# Another snake is every bit as solid as your own tail - unless the
		# shears are out, and then it is the whole point.
		if _match != null and not world.cutting():
			for id: int in _match.snakes:
				var other: SnakeWorld = _match.snakes[id]
				if other != world and other.alive and other.hits_body(point, 0.0):
					return true
	return false


## How far the snake could travel in that direction before hitting something.
func _room(world: SnakeWorld, angle_offset: float) -> float:
	var direction := Vector2(
		cos(world.heading + angle_offset), sin(world.heading + angle_offset)
	)
	var travelled := 0.0
	var limit: float = 12.0 / maxf(world.turn_scale, 0.2)
	while travelled < limit:
		travelled += 0.6
		var point: Vector2 = world.head_position + direction * travelled
		if not world.is_inside(point) or world.hits_body(point):
			break
		if _match != null and _match.blocked_by_obstacle(point, world.radius):
			break
	return travelled


## Is some other living snake's body within `reach` of the head?
func body_within(game_match: SnakeMatch, world: SnakeWorld, reach: float) -> bool:
	for id: int in game_match.snakes:
		var other: SnakeWorld = game_match.snakes[id]
		if other == world or not other.alive:
			continue
		var points := other.body_points()
		for index in range(0, points.size(), 3):
			if world.head_position.distance_to(points[index]) < reach:
				return true
	return false
