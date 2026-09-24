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

	var best: Vector2 = _match.food
	var best_distance: float = world.head_position.distance_to(_match.food) * 1.6

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


## Non-zero when something is in the way, pointing to the freer side.
func _avoid(world: SnakeWorld) -> float:
	# Twice the speed needs twice the warning.
	var reach: float = LOOK_AHEAD * world.speed_multiplier
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
		if _match != null and _match.blocked_by_obstacle(point, GameConfig.SNAKE_RADIUS):
			return true
		# Another snake is every bit as solid as your own tail.
		if _match != null:
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
	while travelled < 12.0:
		travelled += 0.6
		var point: Vector2 = world.head_position + direction * travelled
		if not world.is_inside(point) or world.hits_body(point):
			break
		if _match != null and _match.blocked_by_obstacle(point, GameConfig.SNAKE_RADIUS):
			break
	return travelled
