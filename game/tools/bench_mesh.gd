extends SceneTree

## A bench for the two things whose cost grows with the snake: rebuilding
## the body mesh, and the collision sampling behind it.
##
##     godot --headless --path game --script res://tools/bench_mesh.gd
##
## It prints microseconds per call at several body lengths, which is the
## only way to compare an optimisation honestly: a short snake hides
## everything, and the game is at its worst when a round has gone well.

const LENGTHS := [2.6, 8.0, 16.0, 30.0, 50.0]
const REPEATS := 400


func _initialize() -> void:
	print("length | rebuild us | body_points us | rings")
	for length: float in LENGTHS:
		_bench(length)
	quit()


func _bench(length: float) -> void:
	var world := SnakeWorld.new(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	world.reset(Vector2(15.0, 10.0), 0.0)
	world.target_body_length = length
	world.body_length = length

	# Drive it far enough that the path behind the head is fully grown, and
	# curved, so the sampling has real work to do.
	for step in range(3000):
		world.steer(sin(step * 0.01))
		world.advance(GameConfig.SIM_STEP)

	var mesh := SnakeMesh.new()
	mesh._ready()

	# The mesh only rebuilds when the snake has moved, so the world has to
	# step between rebuilds. Stepping on its own is measured too, and taken
	# off, to leave the cost of the rebuild alone.
	var start := Time.get_ticks_usec()
	for repeat in range(REPEATS):
		world.advance(GameConfig.SIM_STEP)
	var step_us := float(Time.get_ticks_usec() - start) / REPEATS

	start = Time.get_ticks_usec()
	for repeat in range(REPEATS):
		world.advance(GameConfig.SIM_STEP)
		mesh.rebuild(world, 0.4)
	var rebuild_us := float(Time.get_ticks_usec() - start) / REPEATS - step_us

	start = Time.get_ticks_usec()
	for repeat in range(REPEATS):
		world._points_dirty = true
		world.body_points()
	var points_us := float(Time.get_ticks_usec() - start) / REPEATS

	var rings := maxi(3, int(length / GameConfig.TUBE_RING_SPACING))
	print("%6.1f | %10.1f | %14.1f | %5d" % [length, rebuild_us, points_us, rings])
	mesh.free()
