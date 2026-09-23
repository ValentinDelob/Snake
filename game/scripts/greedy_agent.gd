class_name GreedyAgent
extends RefCounted

## An automated player, used by the self-test so the executable can play a
## real game on its own. Moves are ranked by the free space reachable
## afterwards, then by distance to the food, which keeps the snake out of
## dead ends long enough for a test to be meaningful.

const FLOOD_LIMIT := 120


func decide(world: SnakeWorld) -> Variant:
	var head := world.head()
	var options: Array = []

	for direction: Vector2i in SnakeWorld.DIRECTIONS:
		if direction == -world.direction:
			continue
		var target: Vector2i = head + direction
		if world.is_lethal(target):
			continue
		var distance: int = absi(target.x - world.food.x) + absi(target.y - world.food.y)
		var room := _reachable_area(world, target)
		# Coarse room buckets first: escape dead ends, otherwise chase food.
		options.append({"rank": -(room / 8), "distance": distance, "direction": direction})

	if options.is_empty():
		return null

	options.sort_custom(func(a, b):
		if a["rank"] != b["rank"]:
			return a["rank"] < b["rank"]
		return a["distance"] < b["distance"])
	return options[0]["direction"]


func _reachable_area(world: SnakeWorld, start: Vector2i) -> int:
	var blocked := {}
	for index in range(world.snake.size() - 1):
		blocked[world.snake[index]] = true

	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var count := 0
	while not queue.is_empty() and count < FLOOD_LIMIT:
		var cell: Vector2i = queue.pop_front()
		count += 1
		for direction: Vector2i in SnakeWorld.DIRECTIONS:
			var next_cell: Vector2i = cell + direction
			if seen.has(next_cell) or blocked.has(next_cell):
				continue
			if not world.is_inside(next_cell):
				continue
			seen[next_cell] = true
			queue.append(next_cell)
	return count
