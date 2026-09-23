class_name SelfTestDriver
extends RefCounted

## Scripted player driving a real, windowed run through every screen and
## every camera, so a build can be validated without a human at the keyboard.
##
## Injected key events go through the normal input pipeline, which means the
## test exercises the same code path as a player.

const PAUSE_FRAMES := 30
const MIN_ACCEPTABLE_FPS := 25.0

## step reached -> key to press once
var schedule := {
	10: KEY_C,   # follow -> overview
	16: KEY_C,   # overview -> chase (relative steering)
	22: KEY_C,   # chase -> follow (wraps around)
	28: KEY_V,   # 3D -> flat top-down view
	34: KEY_V,   # back to 3D
	40: KEY_P,   # pause
}

var states_seen := {}
var views_seen := {}
var cameras_seen := {}

var _done_steps := {}
var _entered_play := false
var _pause_frames := 0
var _agent_released := false
var _retried := false
var _finished := false
var _release_at_step := 52


static func press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
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

	var steps: int = game.stats["steps"]
	for step: int in schedule:
		if steps >= step and not _done_steps.has(step):
			_done_steps[step] = true
			Journal.info("selftest", "pressing %s at step %d" % [
				OS.get_keycode_string(schedule[step]), steps,
			])
			press(schedule[step])
			return

	if not _agent_released and steps >= _release_at_step:
		Journal.info("selftest", "releasing the bot to provoke a game over")
		_agent_released = true
		game.agent = null


func _on_pause(_game) -> void:
	_pause_frames += 1
	if _pause_frames == PAUSE_FRAMES:
		Journal.info("selftest", "resuming after %d paused frames" % _pause_frames)
		press(KEY_P)


func _on_gameover(_game) -> void:
	if _finished:
		return
	if not _retried:
		Journal.info("selftest", "retrying from the game over screen")
		_retried = true
		press(KEY_R)
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
