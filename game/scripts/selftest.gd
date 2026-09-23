class_name SelfTestDriver
extends RefCounted

## Scripted player driving a real, windowed run through every screen, every
## camera, both turn directions and the speed boost, so a build can be
## validated without a human at the keyboard.
##
## Injected key events go through the normal input pipeline, which means the
## test exercises the same code path as a player - including holding a turn
## key down and firing the item with space.
##
## The run is a list of phases rather than absolute times: if the snake dies
## halfway through, the driver retries and picks the phase back up.

enum Phase { CAMERAS, TURNS, BOOST, PAUSE, FINISH }

const PAUSE_FRAMES := 30
const MIN_ACCEPTABLE_FPS := 25.0
const TURN_HOLD := 0.7          # seconds a turn key stays down
const SPACING_TOLERANCE := 0.25 # relative error allowed between body segments
const MAX_RETRIES := 6
## Godot writes its own errors into the same log file, so the test can read
## them back. A looping tween on a freed panel once shipped exactly because
## nothing here was watching for engine errors.
const LOG_PATH := "user://logs/snake.log"
const TURN_ROOM := 6.0            # world units of clearance wanted for the test
const TURN_ROOM_TIMEOUT := 8.0    # ... but do not wait forever

## seconds into the camera phase -> key pressed once
var camera_schedule := {
	0.8: KEY_C,   # follow -> overview
	1.6: KEY_C,   # overview -> chase
	2.4: KEY_C,   # chase -> follow (wraps around)
	3.2: KEY_V,   # 3D -> flat top-down view
	4.0: KEY_V,   # back to 3D
}

var states_seen := {}
var views_seen := {}
var cameras_seen := {}
var turns_seen := {}

var phase: Phase = Phase.CAMERAS
var boost_collected := false
var pickup_flash_seen := false
var boost_fired := false
var max_multiplier := 1.0
var multiplier_after_boost := -1.0

var _phase_started := 0.0
var _done_marks := {}
var _entered_play := false
var _pause_frames := 0
var _retries := 0
var _finished := false

# manual steering test
var _turn_phase := 0            # 0 waiting, 1 left held, 2 right held, 3 done
var _turn_started := 0.0
var _turn_waiting_since := -1.0
var _heading_before := 0.0
var _saved_agent: GreedyAgent = null

# boost test
var _bolt_requested := false
var _boost_fired_at := 0.0

## True once the body has been caught mid-growth, which is what proves the
## snake lengthens progressively instead of jumping to its new size.
var _growth_observed := false
var _spacing_checks := 0
var _spacing_errors := 0
var _next_spacing_check := 0.5


static func press(keycode: int) -> void:
	_send(keycode, true)


static func release(keycode: int) -> void:
	_send(keycode, false)


static func _send(keycode: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func on_frame(game) -> void:
	var state_name: String = game.state_name()
	if not states_seen.has(state_name):
		Journal.info("selftest", "reached state: %s" % state_name)
		states_seen[state_name] = true

	match state_name:
		"menu":
			_on_menu(game)
		"play":
			_on_play(game)
		"pause":
			_on_pause(game)
		"gameover":
			_on_gameover(game)


func _on_menu(game) -> void:
	if not _entered_play and game.stats["frames"] > 30:
		Journal.info("selftest", "starting a game from the menu")
		_entered_play = true
		press(KEY_ENTER)
		release(KEY_ENTER)


func _on_play(game) -> void:
	var rig: CameraRig = game.camera_rig()
	views_seen[rig.view_name()] = true
	cameras_seen[rig.mode_name()] = true

	var now: float = game.play_time()
	if now < _phase_started:      # a new round started, play time went back to 0
		_phase_started = 0.0
		_on_round_restart(game)
	_watch_world(game, now)

	match phase:
		Phase.CAMERAS:
			_run_cameras(now)
		Phase.TURNS:
			_run_turns(game, now)
		Phase.BOOST:
			_run_boost(game, now)
		Phase.PAUSE:
			_run_pause()
		Phase.FINISH:
			if game.agent != null:
				# No bot and no turn held: a straight line always reaches a
				# wall, whereas a held turn would circle forever.
				Journal.info("selftest", "releasing the bot, straight into a wall")
				game.agent = null


## A death can land in the middle of a phase: undo whatever that phase was
## holding, or the next round would run without a bot and die at once.
func _on_round_restart(game) -> void:
	Journal.info("selftest", "round restarted during phase %s" % Phase.keys()[phase])
	if _turn_phase > 0 and _turn_phase < 3:
		release(KEY_LEFT)
		release(KEY_RIGHT)
		game.agent = _saved_agent
		_turn_phase = 0
		_turn_waiting_since = -1.0
	if phase == Phase.BOOST and multiplier_after_boost < 0.0:
		# The boost never ran its course (dying at twice the speed is easy):
		# drop another bolt and do it again rather than accept a half ramp.
		_bolt_requested = false
		boost_fired = false


func _enter_phase(next_phase: Phase, now: float) -> void:
	phase = next_phase
	_phase_started = now
	Journal.info("selftest", "phase -> %s" % Phase.keys()[next_phase])


# --------------------------------------------------------------------------- #
func _run_cameras(now: float) -> void:
	var since := now - _phase_started
	for mark: float in camera_schedule:
		if since >= mark and not _done_marks.has(mark):
			_done_marks[mark] = true
			Journal.info("selftest", "pressing %s" % OS.get_keycode_string(camera_schedule[mark]))
			press(camera_schedule[mark])
			release(camera_schedule[mark])
			return
	if _done_marks.size() >= camera_schedule.size() and since >= 4.6:
		_enter_phase(Phase.TURNS, now)


## Hold LEFT, then RIGHT, and check the heading actually turned each way.
func _run_turns(game, now: float) -> void:
	match _turn_phase:
		0:
			# Steering by hand means no bot: wait for open space first, so the
			# test is not spent crashing into the nearest wall.
			if not _has_room(game.world):
				if _turn_waiting_since < 0.0:
					_turn_waiting_since = now
				elif now - _turn_waiting_since < TURN_ROOM_TIMEOUT:
					return
			Journal.info("selftest", "manual steering test: holding LEFT")
			_saved_agent = game.agent
			game.agent = null
			_heading_before = game.world.heading
			_turn_started = now
			_turn_phase = 1
			press(KEY_LEFT)
		1:
			if now - _turn_started >= TURN_HOLD:
				release(KEY_LEFT)
				_record_turn(game, "left", -1.0)
				Journal.info("selftest", "manual steering test: holding RIGHT")
				_heading_before = game.world.heading
				_turn_started = now
				_turn_phase = 2
				press(KEY_RIGHT)
		2:
			if now - _turn_started >= TURN_HOLD:
				release(KEY_RIGHT)
				_record_turn(game, "right", 1.0)
				game.agent = _saved_agent
				_turn_phase = 3
				_enter_phase(Phase.BOOST, now)


## Drop a bolt, let the bot fetch it, fire it and watch the speed ramp.
func _run_boost(game, now: float) -> void:
	var world: SnakeWorld = game.world

	if not _bolt_requested:
		Journal.info("selftest", "dropping a speed bolt on the arena")
		world.spawn_pickup_now()
		_bolt_requested = true
		return

	if not boost_fired:
		if world.carried_item:
			Journal.info("selftest", "bolt in the slot, firing it with SPACE")
			boost_fired = true
			_boost_fired_at = now
			press(KEY_SPACE)
			release(KEY_SPACE)
		elif not world.pickup_on_arena:
			_bolt_requested = false   # the round restarted: drop another one
		return

	if now - _boost_fired_at >= GameConfig.BOOST_DURATION + GameConfig.BOOST_RAMP_DOWN + 0.5:
		multiplier_after_boost = world.speed_multiplier
		Journal.info("selftest", "boost finished: peak x%.2f, back to x%.2f" % [
			max_multiplier, multiplier_after_boost,
		])
		_enter_phase(Phase.PAUSE, now)


func _run_pause() -> void:
	Journal.info("selftest", "pausing")
	press(KEY_P)
	release(KEY_P)


func _watch_world(game, now: float) -> void:
	var world: SnakeWorld = game.world
	if world.carried_item and not boost_collected:
		Journal.info("selftest", "speed bolt collected")
		boost_collected = true
	if boost_collected and not pickup_flash_seen and game.board_view().flash_active():
		Journal.info("selftest", "pickup effect playing")
		pickup_flash_seen = true
	max_multiplier = maxf(max_multiplier, world.speed_multiplier)

	if world.body_length < world.target_body_length - 0.01:
		if not _growth_observed:
			Journal.info("selftest", "growth caught in progress: %.2f of %.2f units" % [
				world.body_length, world.target_body_length,
			])
		_growth_observed = true
	_check_body_spacing(game, now)


## Is the head far enough from every wall to turn freely?
func _has_room(world: SnakeWorld) -> bool:
	var head: Vector2 = world.head_position
	return (
		head.x > TURN_ROOM and head.x < world.width - TURN_ROOM
		and head.y > TURN_ROOM and head.y < world.height - TURN_ROOM
	)


func _record_turn(game, label: String, expected_sign: float) -> void:
	var delta := wrapf(game.world.heading - _heading_before, -PI, PI)
	if signf(delta) == expected_sign and absf(delta) > 0.5:
		turns_seen[label] = true
		Journal.info("selftest", "turn %s confirmed: heading moved %.2f rad" % [label, delta])
	else:
		Journal.warn("selftest", "turn %s did not register: heading moved %.2f rad" % [label, delta])


## The body must trail the head at a constant spacing; a jump would mean the
## snake teleports instead of sliding.
func _check_body_spacing(game, now: float) -> void:
	if now < _next_spacing_check:
		return
	_next_spacing_check = now + 1.0

	var points: Array[Vector2] = game.world.body_points()
	if points.size() < 3:
		return
	_spacing_checks += 1
	for index in range(1, points.size()):
		var gap: float = points[index - 1].distance_to(points[index])
		if absf(gap - GameConfig.SEGMENT_SPACING) > GameConfig.SEGMENT_SPACING * SPACING_TOLERANCE:
			_spacing_errors += 1
			Journal.warn("selftest", "body gap %.3f at segment %d (expected %.3f)" % [
				gap, index, GameConfig.SEGMENT_SPACING,
			])
			return


func _on_pause(game) -> void:
	_pause_frames += 1
	if _pause_frames == PAUSE_FRAMES:
		Journal.info("selftest", "resuming after %d paused frames" % _pause_frames)
		press(KEY_P)
		release(KEY_P)
		_enter_phase(Phase.FINISH, game.play_time())


func _on_gameover(game) -> void:
	if _finished:
		return

	if phase == Phase.FINISH and int(game.stats["games"]) >= 2:
		Journal.info("selftest", "quitting from the game over screen")
		_finished = true
		press(KEY_ESCAPE)
		return

	if _retries >= MAX_RETRIES:
		Journal.warn("selftest", "too many retries, stopping here")
		_finished = true
		press(KEY_ESCAPE)
		return

	_retries += 1
	Journal.info("selftest", "retrying (round %d, phase %s)" % [_retries, Phase.keys()[phase]])
	press(KEY_R)
	release(KEY_R)


## Returns the list of failed expectations (empty means success).
func verify(game) -> Array:
	var failures: Array = []
	var stats: Dictionary = game.stats

	for state_name: String in ["menu", "play", "pause", "gameover"]:
		if not states_seen.has(state_name):
			failures.append("state never reached: %s" % state_name)
	for view_name: String in ["3d", "flat"]:
		if not views_seen.has(view_name):
			failures.append("view never rendered: %s" % view_name)
	for camera_name: String in ["follow", "overview", "chase", "top"]:
		if not cameras_seen.has(camera_name):
			failures.append("camera never used: %s" % camera_name)
	for turn: String in ["left", "right"]:
		if not turns_seen.has(turn):
			failures.append("holding %s never turned the snake" % turn)

	if not boost_collected:
		failures.append("the speed bolt was never collected")
	if boost_collected and not pickup_flash_seen:
		failures.append("collecting the bolt played no effect")
	if not boost_fired:
		failures.append("the speed boost was never fired")
	elif max_multiplier < GameConfig.BOOST_FACTOR - 0.05:
		failures.append("the boost only reached x%.2f" % max_multiplier)
	elif multiplier_after_boost < 0.0:
		failures.append("the boost never ran to completion")
	elif multiplier_after_boost > 1.05:
		failures.append("speed stayed at x%.2f after the boost" % multiplier_after_boost)

	if _spacing_checks == 0:
		failures.append("the body spacing was never checked")
	if _spacing_errors > 0:
		failures.append("body segments drifted apart %d times" % _spacing_errors)
	if int(stats["max_score"]) <= 0:
		failures.append("the bot never scored a point")
	elif not _growth_observed:
		failures.append("the body jumped to its new length instead of growing into it")
	if int(stats["games"]) < 2:
		failures.append("expected 2 finished games, got %d" % int(stats["games"]))
	if float(stats["fps"]) < MIN_ACCEPTABLE_FPS:
		failures.append("frame rate too low: %.1f fps" % float(stats["fps"]))
	if not stats["errors"].is_empty():
		failures.append("errors reported: %s" % str(stats["errors"]))

	var engine_errors := _engine_errors()
	if not engine_errors.is_empty():
		failures.append("engine errors logged: %s" % str(engine_errors.slice(0, 3)))
	return failures


## Distinct engine-level errors written to the log during this run.
func _engine_errors() -> Array:
	var found: Array = []
	if not FileAccess.file_exists(LOG_PATH):
		return found
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return found
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("ERROR:") or line.begins_with("SCRIPT ERROR"):
			if not found.has(line):
				found.append(line)
	file.close()
	return found
