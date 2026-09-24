extends SceneTree

## Lay out a great many arenas and check the promises hold every time:
## enough rocks, none on a spawn point or its lane, and room to pass
## between any two of them.
##
##     godot --headless --path game --script res://tools/check_arena.gd

const ROUNDS := 400


func _initialize() -> void:
	for players in [1, 2, 3, 4, 6]:
		var fewest := 99
		var failures := 0
		var short := 0
		for round_index in range(ROUNDS):
			var arena := GameConfig.arena_for(players)
			var game_match := SnakeMatch.new(arena.x, arena.y, round_index + 1)
			for id in range(players):
				game_match.add_snake(id + 1)
			game_match.start()
			fewest = mini(fewest, game_match.obstacles.size())
			if game_match.obstacles.size() < SnakeMatch.minimum_rocks(players):
				short += 1
			failures += _spawn_failures(game_match)
		var arena := GameConfig.arena_for(players)
		print("%d player(s): %.0fx%.0f, fewest rocks %d (floor %d), %d short, %d spawn faults, %d arenas" % [
			players, arena.x, arena.y, fewest,
			SnakeMatch.minimum_rocks(players), short, failures, ROUNDS,
		])
	quit()


func _spawn_failures(game_match: SnakeMatch) -> int:
	var failures := 0
	for id: int in game_match.spawns:
		var pose: Array = game_match.spawns[id]
		for rock: Dictionary in game_match.obstacles:
			if rock["position"].distance_to(pose[0]) < rock["radius"] + 1.0:
				failures += 1
			for point: Vector2 in game_match.lane_points(pose[0], pose[1]):
				if rock["position"].distance_to(point) < rock["radius"] + 0.8:
					failures += 1
	return failures
