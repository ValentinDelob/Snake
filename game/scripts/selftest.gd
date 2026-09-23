class_name SelfTestDriver
extends RefCounted

## Scripted player driving a real, windowed run through every screen, every
## camera and both turn directions, so a build can be validated without a
## human at the keyboard.
##
## Injected key events go through the normal input pipeline, which means the
## test exercises the same code path as a player - including holding a turn
## key down, which is now the only way to steer.

const PAUSE_FRAMES := 30
const MIN_ACCEPTABLE_FPS := 25.0
const TURN_HOLD := 0.7          # seconds a turn key stays down
const SPACING_TOLERANCE := 0.25 # relative error allowed between body segments

## play time (seconds) -> key pressed once
var schedule := {
	1.0: KEY_C,   # follow -> overview
	2.0: KEY_C,   # overview -> chase
	3.0: KEY_C,   # chase -> follow (wraps around)
	4.0: KEY_V,   # 3D -> flat top-down view
	5.0: KEY_V,   # back to 3D
}

var states_seen := {}
var views_seen := {}
var cameras_seen := {}
var turns_seen := {}

var _done_marks := {}
var _entered_play := false
var _pause_frames := 0
var _paused_done := false
var _retried := false
var _finished := false

# manual steering test
var _turn_phase := 0            # 0 waiting, 1 left held, 2 right held, 3 done
var _turn_started := 0.0
var _heading_before := 0.0
var _saved_agent: GreedyAgent = null

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


func _on_play(game) -> void:
	var rig: CameraRig = game.camera_rig()
	views_seen[rig.view_name()] = true
	cameras_seen[rig.mode_name()] = true

	var now: float = game.play_time()
	_check_body_spacing(game, now)

	for mark: float in schedule:
		if now >= mark and not _done_marks.has(mark):
			_done_marks[mark] = true
			Journal.info("selftest", "pressing %s at %.1fs" % [
				OS.get_keycode_string(schedule[mark]), now,
			])
			press(schedule[mark])
			release(schedule[mark])
			return

	if now >= 6.0 and _turn_phase < 3:
		_drive_turn_test(game, now)
		return

	if _turn_phase == 3 and not _paused_done and now >= 10.0:
		Journal.info("selftest", "pausing at %.1fs" % now)
		press(KEY_P)
		release(KEY_P)
		return

	if _paused_done and game.agent != null and now >= 12.0:
		# No bot and no turn held: a straight line always reaches a wall,
		# whereas a held turn would circle forever.
		Journal.info("selftest", "releasing the bot, straight into a wall")
		game.agent = null


## Hold LEFT, then RIGHT, and check the heading actually turned each way.
func _drive_turn_test(game, now: float) -> void:
	match _turn_phase:
		0:
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


func _on_pause(_game) -> void:
	_pause_frames += 1
	if _pause_frames == PAUSE_FRAMES:
		Journal.info("selftest", "resuming after %d paused frames" % _pause_frames)
		_paused_done = true
		press(KEY_P)
		release(KEY_P)


func _on_gameover(_game) -> void:
	if _finished:
		return
	if not _retried:
		Journal.info("selftest", "retrying from the game over screen")
		_retried = true
		press(KEY_R)
		release(KEY_R)
	else:
		Journal.info("selftest", "quitting from the game over screen")
		_finished = true
		press(KEY_ESCAPE)


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

	if _spacing_checks == 0:
		failures.append("the body spacing was never checked")
	if _spacing_errors > 0:
		failures.append("body segments drifted apart %d times" % _spacing_errors)
	if int(stats["max_score"]) <= 0:
		failures.append("the bot never scored a point")
	if int(stats["games"]) < 2:
		failures.append("expected 2 finished games, got %d" % int(stats["games"]))
	if not _retried:
		failures.append("the retry path was never exercised")
	if float(stats["fps"]) < MIN_ACCEPTABLE_FPS:
		failures.append("frame rate too low: %.1f fps" % float(stats["fps"]))
	if not stats["errors"].is_empty():
		failures.append("errors reported: %s" % str(stats["errors"]))
	return failures
