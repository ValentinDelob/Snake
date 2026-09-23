extends Node3D

## The game itself: state machine, input, fixed-step simulation and the glue
## between the rules (SnakeWorld), the view (BoardView) and the cameras.

enum State { MENU, PLAY, PAUSE, GAMEOVER }

const STATE_NAMES := ["menu", "play", "pause", "gameover"]

const MOVE_KEYS := {
	KEY_UP: SnakeWorld.UP,
	KEY_W: SnakeWorld.UP,
	KEY_Z: SnakeWorld.UP,      # AZERTY
	KEY_DOWN: SnakeWorld.DOWN,
	KEY_S: SnakeWorld.DOWN,
	KEY_LEFT: SnakeWorld.LEFT,
	KEY_A: SnakeWorld.LEFT,
	KEY_Q: SnakeWorld.LEFT,    # AZERTY
	KEY_RIGHT: SnakeWorld.RIGHT,
	KEY_D: SnakeWorld.RIGHT,
}

const TURN_KEYS := {
	KEY_LEFT: -1, KEY_A: -1, KEY_Q: -1,
	KEY_RIGHT: 1, KEY_D: 1,
}

@onready var _camera: CameraRig = $Camera
@onready var _board: BoardView = $Board
@onready var _hud: SnakeHud = $HUD
@onready var _sun: DirectionalLight3D = $Sun

var world: SnakeWorld
var state: State = State.MENU
var agent: GreedyAgent = null

var stats := {
	"frames": 0,
	"steps": 0,
	"games": 0,
	"max_score": 0,
	"last_score": 0,
	"slow_frames": 0,
	"fps": 0.0,
	"reason": "unknown",
	"errors": [],
}

var _driver: SelfTestDriver = null
## --demo lets the bot play while a human keeps control of the cameras.
var _demo := false
var _accumulator := 0.0
var _flash := 0.0
var _elapsed := 0.0
var _seed := 0
var _max_steps := 0
var _last_outcome: SnakeWorld.Outcome = SnakeWorld.Outcome.MOVED
var _last_record := false


# --------------------------------------------------------------------------- #
func _ready() -> void:
	Journal.banner()
	_parse_arguments()

	_sun.rotation_degrees = Vector3(-62.0, -28.0, 0.0)

	world = SnakeWorld.new(GameConfig.GRID_WIDTH, GameConfig.GRID_HEIGHT, _seed)
	_board.build(world)

	_camera.set_mode_by_name(str(PlayerProfile.get_preference("camera")))
	_camera.set_flat(str(PlayerProfile.get_preference("view")) == "flat")
	Journal.info("game", "View %s, camera %s, seed %d" % [
		_camera.view_name(), _camera.mode_name(), _seed,
	])

	if _driver != null or _demo:
		agent = GreedyAgent.new()
	if _driver != null:
		Journal.info("selftest", "Self-test armed (step budget %d)" % _max_steps)
	elif _demo:
		Journal.info("game", "Demo mode: the bot plays, cameras stay under your control")

	_enter_menu()


func _parse_arguments() -> void:
	var args: Array = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())

	for index in range(args.size()):
		var arg: String = str(args[index])
		var value: String = str(args[index + 1]) if index + 1 < args.size() else ""
		match arg:
			"--selftest":
				_driver = SelfTestDriver.new()
			"--demo":
				_demo = true
			"--seed":
				_seed = int(value)
			"--steps":
				_max_steps = int(value)
	if _max_steps <= 0:
		_max_steps = 400
	if _driver != null:
		PlayerProfile.use_path("user://selftest_profile.json")


# --------------------------------------------------------------------------- #
func _process(delta: float) -> void:
	_elapsed += delta
	stats["frames"] += 1

	# A stutter is worth a log line: it is the only trace left once the window
	# is closed.
	if delta > GameConfig.SLOW_FRAME_SECONDS and stats["frames"] > 5:
		stats["slow_frames"] += 1
		Journal.warn("game", "Slow frame: %d ms (state=%s)" % [
			int(delta * 1000.0), STATE_NAMES[state],
		])

	if _driver != null:
		_driver.on_frame(self)

	if state == State.PLAY:
		_flash = maxf(0.0, _flash - delta * 3.0)
		_accumulator += delta
		while _accumulator >= GameConfig.STEP_INTERVAL and world.alive and state == State.PLAY:
			_accumulator -= GameConfig.STEP_INTERVAL
			_advance()

	_camera.update_rig(delta, world)
	_board.refresh(world, _elapsed, _flash)
	_hud.set_stats(
		world.score,
		maxi(PlayerProfile.high_score(), world.score),
		"%s %s" % [_camera.view_name().to_upper(), _camera.mode_name()]
	)


func _advance() -> void:
	if agent != null:
		var wanted: Variant = agent.decide(world)
		if wanted != null:
			world.steer(wanted)

	var outcome := world.step()
	stats["steps"] += 1

	if outcome == SnakeWorld.Outcome.ATE:
		_flash = 1.0
		Journal.debug("game", "Food eaten: score=%d length=%d" % [world.score, world.length()])
	elif SnakeWorld.is_death(outcome):
		_game_over(outcome)
		return

	if stats["steps"] >= _max_steps and _driver != null:
		Journal.info("selftest", "Step budget reached (%d)" % _max_steps)
		request_quit("step-budget")


# --------------------------------------------------------------------------- #
# State machine
# --------------------------------------------------------------------------- #
func state_name() -> String:
	return STATE_NAMES[state]


func _set_state(next_state: State) -> void:
	if state == next_state:
		return
	Journal.info("game", "State: %s -> %s" % [STATE_NAMES[state], STATE_NAMES[next_state]])
	state = next_state


func _enter_menu() -> void:
	_set_state(State.MENU)
	_hud.set_bar_visible(false)
	_camera.set_preview(true)
	_hud.show_overlay(
		"SNAKE 3D",
		GameConfig.SNAKE_HEAD_COLOR,
		"ENTER  play",
		"best score  %d     games played  %d" % [
			PlayerProfile.high_score(), PlayerProfile.games_played(),
		],
		"arrows / WASD / ZQSD  move      P  pause      ESC  quit\n"
		+ "C  camera (follow, overview, chase)      V  flat view"
	)


func _start_game() -> void:
	world.reset()
	_accumulator = 0.0
	_flash = 0.0
	_camera.set_preview(false)
	_camera.reset()
	_hud.hide_overlay()
	_hud.set_bar_visible(true)
	_set_state(State.PLAY)


func _toggle_pause() -> void:
	if state == State.PLAY:
		_set_state(State.PAUSE)
		_hud.show_overlay(
			"PAUSED", GameConfig.TEXT_COLOR, "P or SPACE  resume", "", "ESC  menu"
		)
	elif state == State.PAUSE:
		_hud.hide_overlay()
		_set_state(State.PLAY)


func _game_over(outcome: SnakeWorld.Outcome) -> void:
	_last_outcome = outcome
	var score := world.score
	_last_record = PlayerProfile.record_game(score)
	stats["last_score"] = score
	stats["max_score"] = maxi(int(stats["max_score"]), score)
	stats["games"] = int(stats["games"]) + 1
	Journal.info("game", "Game over (%s) at (%d,%d): score=%d length=%d steps=%d record=%s" % [
		"wall" if outcome == SnakeWorld.Outcome.DEAD_WALL else "self",
		world.death_cell.x, world.death_cell.y,
		score, world.length(), world.steps, _last_record,
	])

	_set_state(State.GAMEOVER)
	_hud.show_overlay(
		"GAME OVER",
		GameConfig.DANGER_COLOR,
		"you hit a wall" if outcome == SnakeWorld.Outcome.DEAD_WALL else "you bit yourself",
		"NEW BEST!" if _last_record else "score %d     best %d" % [score, PlayerProfile.high_score()],
		"R  retry     M  menu     ESC  quit"
	)


# --------------------------------------------------------------------------- #
# Input
# --------------------------------------------------------------------------- #
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	_on_key(key_event.keycode)


func _on_key(keycode: int) -> void:
	match state:
		State.MENU:
			if keycode == KEY_ENTER or keycode == KEY_KP_ENTER or keycode == KEY_SPACE:
				_start_game()
			elif keycode == KEY_ESCAPE:
				request_quit("menu-quit")
		State.PLAY:
			_play_key(keycode)
		State.PAUSE:
			if keycode == KEY_P or keycode == KEY_SPACE or keycode == KEY_ENTER:
				_toggle_pause()
			elif keycode == KEY_ESCAPE:
				_enter_menu()
		State.GAMEOVER:
			if keycode == KEY_R or keycode == KEY_ENTER or keycode == KEY_SPACE:
				Journal.info("game", "Round restarted")
				_start_game()
			elif keycode == KEY_M:
				_enter_menu()
			elif keycode == KEY_ESCAPE:
				request_quit("gameover-quit")


func _play_key(keycode: int) -> void:
	if keycode == KEY_ESCAPE:
		_enter_menu()
	elif keycode == KEY_P or keycode == KEY_SPACE:
		_toggle_pause()
	elif keycode == KEY_C:
		_cycle_camera()
	elif keycode == KEY_V:
		_toggle_view()
	elif _camera.uses_relative_steering():
		if TURN_KEYS.has(keycode):
			var direction: Vector2i = (
				SnakeWorld.turn_right(world.direction) if TURN_KEYS[keycode] > 0
				else SnakeWorld.turn_left(world.direction)
			)
			world.steer(direction)
			Journal.debug("game", "Relative turn -> (%d,%d)" % [direction.x, direction.y])
	elif MOVE_KEYS.has(keycode):
		var direction: Vector2i = MOVE_KEYS[keycode]
		world.steer(direction)
		Journal.debug("game", "Steer -> (%d,%d)" % [direction.x, direction.y])


func _cycle_camera() -> void:
	if _camera.flat:
		_camera.set_flat(false)
		PlayerProfile.set_preference("view", "3d")
	else:
		_camera.cycle_mode()
		PlayerProfile.set_preference("camera", _camera.mode_name())
	Journal.info("game", "Camera: %s (steering=%s)" % [
		_camera.mode_name(),
		"relative" if _camera.uses_relative_steering() else "absolute",
	])


func _toggle_view() -> void:
	_camera.set_flat(not _camera.flat)
	PlayerProfile.set_preference("view", _camera.view_name())
	Journal.info("game", "View switched to %s" % _camera.view_name())


# --------------------------------------------------------------------------- #
func camera_rig() -> CameraRig:
	return _camera


func report_error(message: String) -> void:
	Journal.error("game", message)
	stats["errors"].append(message)


func request_quit(reason: String) -> void:
	stats["reason"] = reason
	stats["fps"] = float(stats["frames"]) / maxf(0.001, _elapsed)

	var exit_code := 0
	if _driver != null:
		var failures: Array = _driver.verify(self)
		for failure: String in failures:
			Journal.error("selftest", "check failed: %s" % failure)
		exit_code = 0 if failures.is_empty() else 1
		Journal.info("selftest", "SELFTEST %s: states=%s views=%s cameras=%s games=%d best=%d steps=%d frames=%d fps=%.1f" % [
			"PASS" if failures.is_empty() else "FAIL",
			str(_driver.states_seen.keys()),
			str(_driver.views_seen.keys()),
			str(_driver.cameras_seen.keys()),
			stats["games"], stats["max_score"], stats["steps"], stats["frames"], stats["fps"],
		])

	Journal.info("game", "Session finished: reason=%s games=%d best=%d steps=%d frames=%d fps=%.1f slow=%d errors=%s" % [
		reason, stats["games"], stats["max_score"], stats["steps"],
		stats["frames"], stats["fps"], stats["slow_frames"],
		"none" if stats["errors"].is_empty() else str(stats["errors"]),
	])
	get_tree().quit(exit_code)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit("window-closed")
