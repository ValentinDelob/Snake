extends SceneTree

func _initialize() -> void:
	var world := SnakeWorld.new(84.0, 56.0)
	world.reset(Vector2(40, 28), 0.0)
	world.carried = SnakeWorld.Item.SPEED
	print("fired: ", world.use_item(), " effect=", world.effect, " left=", world.effect_time_left)
	for step in range(240):
		world.advance(GameConfig.SIM_STEP)
	print("after 2s: multiplier=", world.speed_multiplier, " effect=", world.effect)
	quit()
