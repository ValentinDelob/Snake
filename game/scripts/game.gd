extends Node3D

## The game itself: state machine, input, fixed-step simulation and the glue
## between the rules (SnakeWorld), the view (BoardView) and the cameras.
##
## The snake cruises forward on its own; the player only turns the head, so
## left and right are steering commands, not directions on a board.

enum State { MENU, PLAY, PAUSE, GAMEOVER }

const STATE_NAMES := ["menu", "play", "pause", "gameover"]

## Held keys steer continuously: -1 turns left, +1 turns right.
const TURN_KEYS := {
	KEY_LEFT: -1.0,
	KEY_A: -1.0,
	KEY_Q: -1.0,     # AZERTY
	KEY_RIGHT: 1.0,
	KEY_D: 1.0,
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
var _play_time := 0.0
var _seed := 0
var _max_steps := 0
var _held_turns := {}
var _last_record := false


# --------------------------------------------------------------------------- #
func _ready() -> void:
	Journal.banner()
	_parse_arguments()

	_sun.rotation_degrees = Vector3(-62.0, -28.0, 0.0)

	world = SnakeWorld.new(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT, _seed)
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
		_max_steps = int(GameConfig.SIM_HZ * 60.0)  # one minute of simulation
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
		_play_time += delta
		_flash = maxf(0.0, _flash - delta * 3.0)
		# A fixed step keeps the snake behaving the same on any machine; the
		# accumulator is capped so a long stall cannot teleport it.
		_accumulator = minf(_accumulator + delta, 0.25)
		while _accumulator >= GameConfig.SIM_STEP and world.alive and state == State.PLAY:
			_accumulator -= GameConfig.SIM_STEP
			_advance()

	_camera.update_rig(delta, world)
	_board.refresh(world, _elapsed, _flash)
	_hud.set_stats(
		world.score,
		maxi(PlayerProfile.high_score(), world.score),
		"%s %s" % [_camera.view_name().to_upper(), _camera.mode_name()]
	)


func play_time() -> float:
	return _play_time


func _advance() -> void:
	if agent != null:
		world.steer(agent.decide(world))
	else:
		world.steer(_turn_from_keys())

	var outcome := world.step(GameConfig.SIM_STEP)
	stats["steps"] += 1

	if outcome == SnakeWorld.Outcome.ATE:
		_flash = 1.0
		stats["max_score"] = maxi(int(stats["max_score"]), world.score)
		Journal.debug("game", "Food eaten: score=%d body=%.1f" % [world.score, world.body_length])
	elif SnakeWorld.is_death(outcome):
		_game_over(outcome)
		return

	if stats["steps"] >= _max_steps and _driver != null:
		Journal.info("selftest", "Step budget reached (%d)" % _max_steps)
		request_quit("step-budget")


func _turn_from_keys() -> float:
	var turn := 0.0
	for keycode: int in _held_turns:
		turn += float(_held_turns[keycode])
	return clampf(turn, -1.0, 1.0)


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
	_held_turns.clear()
	_hud.set_bar_visible(false)
	_camera.set_preview(true)
	_hud.show_overlay(
		"SNAKE 3D",
		GameConfig.SNAKE_HEAD_COLOR,
		"ENTER  play",
		"best score  %d     games played  %d" % [
			PlayerProfile.high_score(), PlayerProfile.games_played(),
		],
		"the snake never stops: hold LEFT or RIGHT to turn  (or A / D, Q / D)\n"
		+ "P  pause      C  camera (follow, overview, chase)      V  flat view      ESC  quit"
	)


func _start_game() -> void:
	world.reset()
	_accumulator = 0.0
	_flash = 0.0
	_play_time = 0.0
	_held_turns.clear()
	_camera.set_preview(false)
	_camera.reset()
	_hud.hide_overlay()
	_hud.set_bar_visible(true)
	_set_state(State.PLAY)


func _toggle_pause() -> void:
	if state == State.PLAY:
		_set_state(State.PAUSE)
		_held_turns.clear()
		_hud.show_overlay(
			"PAUSED", GameConfig.TEXT_COLOR, "P or SPACE  resume", "", "ESC  menu"
		)
	elif state == State.PAUSE:
		_hud.hide_overlay()
		_set_state(State.PLAY)


func _game_over(outcome: SnakeWorld.Outcome) -> void:
	var score := world.score
	_last_record = PlayerProfile.record_game(score)
	stats["last_score"] = score
	stats["max_score"] = maxi(int(stats["max_score"]), score)
	stats["games"] = int(stats["games"]) + 1
	Journal.info("game", "Game over (%s) at (%.1f,%.1f): score=%d body=%.1f travelled=%.1f record=%s" % [
		"wall" if outcome == SnakeWorld.Outcome.DEAD_WALL else "self",
		world.death_position.x, world.death_position.y,
		score, world.body_length, world.distance_travelled, _last_record,
	])

	_set_state(State.GAMEOVER)
	_held_turns.clear()
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
	if key_event.echo:
		return

	# Turning is held down, so releases matter as much as presses.
	if TURN_KEYS.has(key_event.keycode):
		if key_event.pressed:
			_held_turns[key_event.keycode] = TURN_KEYS[key_event.keycode]
		else:
			_held_turns.erase(key_event.keycode)
		return

	if key_event.pressed:
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


func _cycle_camera() -> void:
	if _camera.flat:
		_camera.set_flat(false)
		PlayerProfile.set_preference("view", "3d")
	else:
		_camera.cycle_mode()
		PlayerProfile.set_preference("camera", _camera.mode_name())
	Journal.info("game", "Camera: %s" % _camera.mode_name())


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
		Journal.info("selftest", "SELFTEST %s: states=%s views=%s cameras=%s turns=%s games=%d best=%d steps=%d frames=%d fps=%.1f" % [
			"PASS" if failures.is_empty() else "FAIL",
			str(_driver.states_seen.keys()),
			str(_driver.views_seen.keys()),
			str(_driver.cameras_seen.keys()),
			str(_driver.turns_seen.keys()),
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
