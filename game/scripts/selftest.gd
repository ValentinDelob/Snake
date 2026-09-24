class_name SelfTestDriver
extends RefCounted

## Scripted player driving a real, windowed run so a build can be validated
## without a human at the keyboard.
##
## Two scripts live here. The solo one walks every screen, every camera, both
## turn directions, the boost and both faces of the crate. The network one
## runs when the game was started with --host or --join: it waits for the
## other machine, plays the round out and checks that the last survivor wins
## and that the loser ends up watching.
##
## Injected key events go through the normal input pipeline, so the test
## exercises the same code path as a player.

enum Phase { CAMERAS, TURNS, BOOST, CRATE_BONUS, CRATE_MALUS, SCORE_UP, SCORE_DOWN, PAUSE, FINISH }

const PAUSE_FRAMES := 30
const MIN_ACCEPTABLE_FPS := 25.0
const TURN_HOLD := 0.7
const SPACING_TOLERANCE := 0.25
const MAX_RETRIES := 6
const TURN_ROOM := 6.0
const TURN_ROOM_TIMEOUT := 8.0
## Godot writes its own errors into the same log file, so the test can read
## them back. A looping tween on a freed panel once shipped exactly because
## nothing here was watching for engine errors.
const LOG_PATH := "user://logs/snake.log"

## seconds into the camera phase -> key pressed once
var camera_schedule := {
	0.8: KEY_C, 1.6: KEY_C, 2.4: KEY_C, 3.2: KEY_V, 4.0: KEY_V,
}

var network := false
## Set by --expect-timeout: instead of playing, this run only checks that a
## join to a host that is not there gives up on its own.
var expect_timeout := false
var timeout_waited := -1.0
var timeout_message := ""
var _dialled := false
var _dial_started := 0.0

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
var crate_bonus_in_slot := false
var crate_malus_forced := false
var min_multiplier := 1.0
var multiplier_after_slow := -1.0

# score cards
var score_card_gain := 0
var score_card_loss := 0
var length_after_gain := -1.0
var length_after_loss := -1.0
var score_floor_held := false
var length_after_floor := -1.0
var _gain_crate_requested := false
var _loss_crate_requested := false
var _score_before := -1
var _length_before := -1.0
var _length_checks := 0
var _length_errors := 0
var _score_last := -1
var _length_last := -1.0
var _floor_stage := 0

## graphics modes: name -> faces the body was made of
var quality_faces := {}
## frame pacing: limit -> did the engine take it, and both vsync states
var fps_limits_seen := {}
var vsync_states_seen := {}
## debug readout: the frame rate it showed, and whether it went away again
var debug_fps_shown := 0
var debug_hidden := false
var _debug_step := 0

# rocks
var rocks_seen := 0
var rock_smallest := 99.0
var rock_largest := 0.0
var spawn_lanes_clear := true
var lane_kept := 0.0
var rock_death := false
var _rock_dropped := false
var _rock_dropped_at := -1.0

# network run
var peers_seen := 0
var remote_moved := false
var round_started := false
var match_finished := false
var winner_id := -1
var spectated := false
var died_locally := false

var _phase_started := 0.0
var _done_marks := {}
var _entered_play := false
var _pause_frames := 0
var _retries := 0
var _finished := false
var _turn_phase := 0
var _turn_started := 0.0
var _turn_waiting_since := -1.0
var _heading_before := 0.0
var _saved_agent: GreedyAgent = null
var _bolt_requested := false
var _boost_fired_at := 0.0
var _bonus_crate_requested := false
var _malus_crate_requested := false
var _slow_started_at := -1.0
var _growth_observed := false
var _spacing_checks := 0
var _spacing_errors := 0
var _next_spacing_check := 0.5
var _remote_first_seen := {}
var _release_at := -1.0
var _leave_at := 0.0


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

	if expect_timeout:
		_timeout_frame(game)
		return

	if network or Session.is_online():
		network = true
		_network_frame(game)
		return

	match state_name:
		"menu":
			_on_menu(game)
		"play":
			_on_play(game)
		"pause":
			_on_pause(game)
		"gameover":
			_on_gameover(game)


# --------------------------------------------------------------------------- #
# The give-up script: join nobody, wait to be dropped back on the menu
# --------------------------------------------------------------------------- #
func _timeout_frame(game) -> void:
	var state_name: String = game.state_name()
	var now := Time.get_ticks_msec() / 1000.0

	if not _dialled:
		if state_name == "lobby":
			_dialled = true
			_dial_started = now
			Journal.info("selftest", "dialling a host that is not there")
		elif now > 10.0:
			timeout_message = "the join never even opened a session"
			_finished = true
			press(KEY_ESCAPE)
		return

	if _finished:
		return

	if state_name == "menu":
		timeout_waited = now - _dial_started
		timeout_message = game.last_menu_message()
		Journal.info("selftest", "back on the menu after %.1f s: %s" % [
			timeout_waited, timeout_message
		])
		_finished = true
		press(KEY_ESCAPE)
	elif now - _dial_started > Session.CONNECT_TIMEOUT + 5.0:
		timeout_waited = now - _dial_started
		Journal.warn("selftest", "still waiting after %.1f s" % timeout_waited)
		_finished = true
		press(KEY_ESCAPE)


func _verify_timeout() -> Array:
	var failures: Array = []
	if not _dialled:
		failures.append("the join never opened a session")
	if timeout_waited < 0.0:
		failures.append("the game never gave up: still waiting for the host")
		return failures
	# A little slack either side: the countdown only ticks on frames.
	if timeout_waited < Session.CONNECT_TIMEOUT - 1.0:
		failures.append("gave up too early: %.1f s" % timeout_waited)
	if timeout_waited > Session.CONNECT_TIMEOUT + 2.0:
		failures.append("gave up too late: %.1f s" % timeout_waited)
	if timeout_message.strip_edges().is_empty():
		failures.append("the menu did not say why the join failed")
	if Session.is_online():
		failures.append("the session was left open after giving up")
	return failures


# --------------------------------------------------------------------------- #
# The network script
# --------------------------------------------------------------------------- #
func _network_frame(game) -> void:
	peers_seen = maxi(peers_seen, Session.players.size())
	var state_name: String = game.state_name()

	if state_name == "play":
		round_started = true
		# A client builds no arena of its own: rocks here mean the host's
		# arena arrived intact.
		rocks_seen = maxi(rocks_seen, game.game_match.obstacles.size())
		_watch_remotes(game)
		if game.spectating:
			spectated = true
		var mine = game.local_snake()
		if mine != null and not mine.alive:
			died_locally = true

		# Whoever is told to let go first loses: that is how the test gets a
		# winner without two machines fighting over it.
		if _release_at < 0.0:
			var fallback: float = 20.0 if Session.is_host() else 45.0
			_release_at = game.play_time() + (
				game.lose_after if game.lose_after > 0.0 else fallback
			)
		elif game.agent != null and game.play_time() >= _release_at:
			Journal.info("selftest", "letting go of the wheel to settle the round")
			game.agent = null

	elif state_name == "gameover":
		if not match_finished:
			match_finished = true
			winner_id = game._winner_id
			Journal.info("selftest", "round over, winner is %d" % winner_id)
			# Leaving the instant the result lands would shut the session
			# down under the other machines, which are still reading it.
			_leave_at = Time.get_ticks_msec() / 1000.0 + 2.0
		elif not _finished and Time.get_ticks_msec() / 1000.0 >= _leave_at:
			_finished = true
			press(KEY_ESCAPE)

	elif state_name == "menu" and round_started and not _finished:
		# Dropped out of the round without a result: nothing left to watch.
		Journal.warn("selftest", "back on the menu with the round unfinished")
		_finished = true
		press(KEY_ESCAPE)


func _watch_remotes(game) -> void:
	for id: int in game.game_match.snakes:
		if id == Session.local_id():
			continue
		var snake: SnakeWorld = game.game_match.snakes[id]
		if not _remote_first_seen.has(id):
			_remote_first_seen[id] = snake.head_position
			Journal.info("selftest", "remote snake %d is on the arena" % id)
		elif not remote_moved and _remote_first_seen[id].distance_to(snake.head_position) > 2.0:
			remote_moved = true
			Journal.info("selftest", "remote snake %d is moving: snapshots are flowing" % id)


# --------------------------------------------------------------------------- #
# The solo script
# --------------------------------------------------------------------------- #
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
	if now < _phase_started:
		_phase_started = 0.0
		_on_round_restart(game)
	if now < 1.0:
		_survey_rocks(game)
	_watch_world(game, now)

	match phase:
		Phase.CAMERAS:
			_run_cameras(game, now)
		Phase.TURNS:
			_run_turns(game, now)
		Phase.BOOST:
			_run_boost(game, now)
		Phase.CRATE_BONUS:
			_run_crate_bonus(game, now)
		Phase.CRATE_MALUS:
			_run_crate_malus(game, now)
		Phase.SCORE_UP:
			_run_score_up(game, now)
		Phase.SCORE_DOWN:
			_run_score_down(game, now)
		Phase.PAUSE:
			_run_pause()
		Phase.FINISH:
			_run_finish(game, now)


## Look over the rocks this round was given: how many, how varied, and
## whether any of them sits where a snake starts or sets off.
func _survey_rocks(game) -> void:
	var game_match = game.game_match
	rocks_seen = maxi(rocks_seen, game_match.obstacles.size())
	lane_kept = game_match.lane_length
	for rock: Dictionary in game_match.obstacles:
		rock_smallest = minf(rock_smallest, rock["radius"])
		rock_largest = maxf(rock_largest, rock["radius"])

	for id: int in game_match.spawns:
		var pose: Array = game_match.spawns[id]
		for rock: Dictionary in game_match.obstacles:
			if rock["position"].distance_to(pose[0]) < rock["radius"] + 1.0:
				spawn_lanes_clear = false
				Journal.warn("selftest", "a rock sits on the spawn of player %d" % id)
			for point: Vector2 in game_match.lane_points(pose[0], pose[1]):
				if rock["position"].distance_to(point) < rock["radius"] + 0.8:
					spawn_lanes_clear = false
					Journal.warn("selftest", "a rock blocks the lane of player %d" % id)


## The last phase: lay a rock right in the snake's path and drive into it,
## so the round ends on a collision the test asked for rather than a wall.
func _run_finish(game, now: float) -> void:
	var snake = game.local_snake()
	if snake == null:
		return
	if not _rock_dropped or now - _rock_dropped_at > 8.0:
		if not _has_room(snake):
			return
		game.game_match.place_obstacle(_ahead_of(snake), 1.4)
		_rock_dropped = true
		_rock_dropped_at = now
		Journal.info("selftest", "a rock laid in the snake's path")
	if game.agent != null:
		Journal.info("selftest", "releasing the bot, straight into the rock")
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
		_bolt_requested = false
		boost_fired = false
	if phase == Phase.CRATE_BONUS and not crate_bonus_in_slot:
		_bonus_crate_requested = false
	if phase == Phase.CRATE_MALUS and multiplier_after_slow < 0.0:
		_malus_crate_requested = false
		_slow_started_at = -1.0
	if phase == Phase.SCORE_UP and score_card_gain == 0:
		_gain_crate_requested = false
	if phase == Phase.SCORE_DOWN and not score_floor_held:
		_loss_crate_requested = false
		_floor_stage = 0
		score_card_loss = 0
	if phase == Phase.FINISH and not rock_death:
		# The rock went with the old arena: the next round needs a new one.
		_rock_dropped = false
		_rock_dropped_at = -1.0


func _enter_phase(next_phase: Phase, now: float) -> void:
	phase = next_phase
	_phase_started = now
	Journal.info("selftest", "phase -> %s" % Phase.keys()[next_phase])


func _run_cameras(game, now: float) -> void:
	var since := now - _phase_started
	_walk_quality_modes(game, since)
	_watch_debug_readout(game, since)
	for mark: float in camera_schedule:
		if since >= mark and not _done_marks.has(mark):
			_done_marks[mark] = true
			Journal.info("selftest", "pressing %s" % OS.get_keycode_string(camera_schedule[mark]))
			press(camera_schedule[mark])
			release(camera_schedule[mark])
			return
	if _done_marks.size() >= camera_schedule.size() and since >= 4.6:
		_check_display_settings(game)
		_enter_phase(Phase.TURNS, now)


## Try every graphics mode on a real body and write down how many faces
## each one costs. A mode that stopped building anything, or that stopped
## differing from its neighbours, shows up here.
func _walk_quality_modes(game, since: float) -> void:
	var wanted := int(since / 1.2)
	if wanted < GameConfig.QUALITY_MODES.size() and wanted != int(GameConfig.quality):
		GameConfig.quality = wanted as GameConfig.Quality
		Journal.info("selftest", "graphics mode -> %s" % GameConfig.quality_mode()["name"])
	var faces: int = game.board_view().face_count(Session.local_id())
	if faces > 0:
		quality_faces[GameConfig.quality_mode()["name"]] = faces


## Switch the debug readout on, check it really counts frames, then switch
## it off again and check it goes away.
func _watch_debug_readout(game, since: float) -> void:
	if since >= 1.0 and _debug_step == 0:
		_debug_step = 1
		if not bool(PlayerProfile.get_preference("debug")):
			game._toggle_debug()
		Journal.info("selftest", "debug readout switched on")
	elif since >= 2.0 and _debug_step == 1:
		var text: String = game.hud().debug_readout()
		if text.begins_with("FPS") and text.to_int() >= 0:
			var counted := int(text.split("  ")[-1])
			if counted > 0:
				debug_fps_shown = counted
				_debug_step = 2
				Journal.info("selftest", "debug readout says %s" % text)
	elif since >= 3.2 and _debug_step == 2:
		_debug_step = 3
		game._toggle_debug()
	elif since >= 3.6 and _debug_step == 3:
		_debug_step = 4
		debug_hidden = game.hud().debug_readout() == ""
		Journal.info("selftest", "debug readout hidden again: %s" % debug_hidden)


## Walk every frame rate ceiling and both vsync states, the way the menu
## does, and check the engine really took what it was given. The walk ends
## where it started, so the rest of the run is unaffected.
func _check_display_settings(game) -> void:
	for _index in range(GameConfig.FPS_LIMITS.size()):
		game._cycle_fps_limit()
		var wanted: int = int(PlayerProfile.get_preference("fps_limit"))
		fps_limits_seen[wanted] = Engine.max_fps == maxi(0, wanted)
	for _index in range(2):
		game._toggle_vsync()
		vsync_states_seen[bool(PlayerProfile.get_preference("vsync"))] = true
	Journal.info("selftest", "display settings walked: limits %s, vsync %s" % [
		str(fps_limits_seen), str(vsync_states_seen.keys()),
	])


## Hold LEFT, then RIGHT, and check the heading actually turned each way.
func _run_turns(game, now: float) -> void:
	match _turn_phase:
		0:
			# Steering by hand means no bot: wait for open space first, so the
			# test is not spent crashing into the nearest wall.
			if not _has_room(game.local_snake()):
				if _turn_waiting_since < 0.0:
					_turn_waiting_since = now
				elif now - _turn_waiting_since < TURN_ROOM_TIMEOUT:
					return
			Journal.info("selftest", "manual steering test: holding LEFT")
			_saved_agent = game.agent
			game.agent = null
			_heading_before = game.local_snake().heading
			_turn_started = now
			_turn_phase = 1
			press(KEY_LEFT)
		1:
			if now - _turn_started >= TURN_HOLD:
				release(KEY_LEFT)
				_record_turn(game, "left", -1.0)
				Journal.info("selftest", "manual steering test: holding RIGHT")
				_heading_before = game.local_snake().heading
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
	var snake = game.local_snake()
	if not _bolt_requested:
		Journal.info("selftest", "dropping a speed bolt in the snake's path")
		game.game_match.drop_at(SnakeWorld.Ground.BOLT, _ahead_of(snake))
		_bolt_requested = true
		return

	if not boost_fired:
		if snake.carried != SnakeWorld.Item.NONE:
			Journal.info("selftest", "bolt in the slot, firing it with SPACE")
			boost_fired = true
			_boost_fired_at = now
			press(KEY_SPACE)
			release(KEY_SPACE)
		elif now - _phase_started > 8.0:
			_bolt_requested = false
			_phase_started = now
		return

	if now - _boost_fired_at >= GameConfig.BOOST_DURATION + GameConfig.BOOST_RAMP_DOWN + 0.5:
		multiplier_after_boost = snake.speed_multiplier
		Journal.info("selftest", "boost finished: peak x%.2f, back to x%.2f" % [
			max_multiplier, multiplier_after_boost,
		])
		_enter_phase(Phase.CRATE_BONUS, now)


## A crate rigged to hold a bonus: it must land in the slot, not fire itself.
func _run_crate_bonus(game, now: float) -> void:
	var snake = game.local_snake()
	if not _bonus_crate_requested:
		Journal.info("selftest", "dropping a crate rigged with a bonus in the path")
		game.game_match.drop_at(
			SnakeWorld.Ground.MYSTERY, _ahead_of(snake), SnakeWorld.Item.SPEED
		)
		_bonus_crate_requested = true
		_phase_started = now
		return

	if snake.carried == SnakeWorld.Item.SPEED:
		crate_bonus_in_slot = true
		Journal.info("selftest", "crate bonus went to the slot, as it should")
		_enter_phase(Phase.CRATE_MALUS, now)
	elif now - _phase_started > 8.0:
		# The snake wandered off: lay another one right in front of it.
		_bonus_crate_requested = false


## A crate rigged to hold the curse: it must apply itself, with no choice.
func _run_crate_malus(game, now: float) -> void:
	var snake = game.local_snake()
	if not _malus_crate_requested:
		Journal.info("selftest", "dropping a crate rigged with the slow down in the path")
		game.game_match.drop_at(
			SnakeWorld.Ground.MYSTERY, _ahead_of(snake), SnakeWorld.Item.SLOW
		)
		_malus_crate_requested = true
		_phase_started = now
		return

	if _slow_started_at < 0.0:
		if snake.effect == SnakeWorld.Item.SLOW:
			crate_malus_forced = true
			_slow_started_at = now
			Journal.info("selftest", "crate curse forced itself on the snake")
		elif now - _phase_started > 8.0:
			_malus_crate_requested = false
		return

	if now - _slow_started_at >= GameConfig.SLOW_DURATION + GameConfig.SLOW_RAMP_UP + 0.5:
		multiplier_after_slow = snake.speed_multiplier
		Journal.info("selftest", "slow down finished: floor x%.2f, back to x%.2f" % [
			min_multiplier, multiplier_after_slow,
		])
		_enter_phase(Phase.SCORE_UP, now)


## A crate rigged to hold the winning card: three points, straight away,
## and a body that grows to match them.
func _run_score_up(game, now: float) -> void:
	var snake = game.local_snake()
	if not _gain_crate_requested:
		Journal.info("selftest", "dropping a crate rigged with the winning card")
		_score_before = snake.score
		_length_before = snake.target_body_length
		_score_last = snake.score
		_length_last = snake.target_body_length
		game.game_match.drop_at(
			SnakeWorld.Ground.MYSTERY, _ahead_of(snake), SnakeWorld.Item.SCORE_UP
		)
		_gain_crate_requested = true
		_phase_started = now
		return

	# A fruit swallowed on the same second would flatter the card, so only
	# the jump inside a single frame counts as its doing.
	var jump: int = snake.score - _score_last
	var stretch: float = snake.target_body_length - _length_last
	_score_last = snake.score
	_length_last = snake.target_body_length
	if jump >= GameConfig.SCORE_CARD_POINTS:
		score_card_gain = jump
		length_after_gain = stretch
		Journal.info("selftest", "winning card paid %d points, body up %.2f units" % [
			score_card_gain, length_after_gain,
		])
		_enter_phase(Phase.SCORE_DOWN, now)
	elif now - _phase_started > 8.0:
		_gain_crate_requested = false


## The losing card, twice over: once from a healthy score to see the body
## shrink, then again from nearly nothing to see the score stop at zero and
## the snake go back to the size it started at.
func _run_score_down(game, now: float) -> void:
	var snake = game.local_snake()

	# Second half of the phase: keep feeding it losing cards until the score
	# cannot go any lower, then check where it stopped.
	if _floor_stage == 1 and snake.score == 0:
		score_floor_held = true
		length_after_floor = snake.target_body_length
		Journal.info("selftest", "score bottomed out at 0, body back to %.2f units" % [
			length_after_floor,
		])
		_enter_phase(Phase.PAUSE, now)
		return

	if not _loss_crate_requested:
		Journal.info("selftest", "dropping a crate rigged with the losing card")
		_score_before = snake.score
		_length_before = snake.target_body_length
		_score_last = snake.score
		_length_last = snake.target_body_length
		game.game_match.drop_at(
			SnakeWorld.Ground.MYSTERY, _ahead_of(snake), SnakeWorld.Item.SCORE_DOWN
		)
		_loss_crate_requested = true
		_phase_started = now
		return

	var drop: int = _score_last - snake.score
	var shrink: float = _length_last - snake.target_body_length
	_score_last = snake.score
	_length_last = snake.target_body_length
	if drop < GameConfig.SCORE_CARD_POINTS and snake.score > 0:
		if now - _phase_started > 8.0:
			_loss_crate_requested = false   # it wandered off: lay another
		return

	if _floor_stage == 0 and drop >= GameConfig.SCORE_CARD_POINTS:
		score_card_loss = drop
		length_after_loss = shrink
		Journal.info("selftest", "losing card cost %d points, body down %.2f units" % [
			score_card_loss, length_after_loss,
		])
	_floor_stage = 1
	_loss_crate_requested = false


func _run_pause() -> void:
	Journal.info("selftest", "pausing")
	press(KEY_P)
	release(KEY_P)


func _watch_world(game, now: float) -> void:
	var snake = game.local_snake()
	if snake == null:
		return
	if snake.carried != SnakeWorld.Item.NONE and not boost_collected:
		Journal.info("selftest", "an item reached the slot")
		boost_collected = true
	if boost_collected and not pickup_flash_seen and game.board_view().flash_active():
		Journal.info("selftest", "pickup effect playing")
		pickup_flash_seen = true
	max_multiplier = maxf(max_multiplier, snake.speed_multiplier)
	min_multiplier = minf(min_multiplier, snake.speed_multiplier)

	if snake.body_length < snake.target_body_length - 0.01:
		if not _growth_observed:
			Journal.info("selftest", "growth caught in progress: %.2f of %.2f units" % [
				snake.body_length, snake.target_body_length,
			])
		_growth_observed = true
	_check_body_spacing(snake, now)

	# The promise behind the whole feature: the body a snake carries is
	# never anything other than what its score bought.
	_length_checks += 1
	if absf(snake.target_body_length - SnakeWorld.length_for_score(snake.score)) > 0.001:
		_length_errors += 1


## A spot a few units in front of the snake: whatever is put there will be
## driven over within a second or two.
func _ahead_of(snake) -> Vector2:
	return snake.head_position + snake.direction() * 3.5


## Is the head far enough from every wall to turn freely?
func _has_room(snake) -> bool:
	if snake == null:
		return false
	return (
		snake.head_position.x > TURN_ROOM and snake.head_position.x < snake.width - TURN_ROOM
		and snake.head_position.y > TURN_ROOM and snake.head_position.y < snake.height - TURN_ROOM
	)


func _record_turn(game, label: String, expected_sign: float) -> void:
	var delta := wrapf(game.local_snake().heading - _heading_before, -PI, PI)
	if signf(delta) == expected_sign and absf(delta) > 0.5:
		turns_seen[label] = true
		Journal.info("selftest", "turn %s confirmed: heading moved %.2f rad" % [label, delta])
	else:
		Journal.warn("selftest", "turn %s did not register: heading moved %.2f rad" % [label, delta])


## The body must trail the head at a constant spacing; a jump would mean the
## snake teleports instead of sliding.
func _check_body_spacing(snake, now: float) -> void:
	if now < _next_spacing_check:
		return
	_next_spacing_check = now + 1.0

	var points: PackedVector2Array = snake.body_points()
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
	if not rock_death and game.last_death_cause() == SnakeWorld.Outcome.DEAD_ROCK:
		rock_death = true
		Journal.info("selftest", "the snake died on a rock")
	if phase == Phase.FINISH and rock_death and int(game.stats["games"]) >= 2:
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


# --------------------------------------------------------------------------- #
func summary(game) -> String:
	var stats: Dictionary = game.stats
	if expect_timeout:
		return "join-timeout waited=%.1fs limit=%.1fs message=%s frames=%d fps=%.1f" % [
			timeout_waited, Session.CONNECT_TIMEOUT, timeout_message,
			stats["frames"], stats["fps"],
		]
	if network:
		return "network(%s) peers=%d remote_moved=%s winner=%d spectated=%s rocks=%d games=%d frames=%d fps=%.1f" % [
			"host" if Session.is_host() else "client",
			peers_seen, remote_moved, winner_id, spectated, rocks_seen,
			stats["games"], stats["frames"], stats["fps"],
		]
	return "states=%s views=%s cameras=%s turns=%s boost(peak x%.2f, after x%.2f) slow(floor x%.2f, after x%.2f) crate(bonus=%s, curse=%s) faces%s pacing(limits=%d, vsync=%d) debug(fps=%d, hides=%s) cards(+%d/%+.1fu, -%d/%+.1fu, floor=%s at %.1fu) rocks(%d, r%.1f-%.1f, lane=%.0f, lanes_clear=%s, fatal=%s) games=%d best=%d steps=%d frames=%d fps=%.1f" % [
		str(states_seen.keys()), str(views_seen.keys()), str(cameras_seen.keys()),
		str(turns_seen.keys()), max_multiplier, multiplier_after_boost,
		min_multiplier, multiplier_after_slow, crate_bonus_in_slot, crate_malus_forced,
		str(quality_faces), fps_limits_seen.size(), vsync_states_seen.size(),
		debug_fps_shown, debug_hidden,
		score_card_gain, length_after_gain, score_card_loss, -length_after_loss,
		score_floor_held, length_after_floor,
		rocks_seen, rock_smallest, rock_largest, lane_kept, spawn_lanes_clear, rock_death,
		stats["games"], stats["max_score"], stats["steps"], stats["frames"], stats["fps"],
	]


## Returns the list of failed expectations (empty means success).
func verify(game) -> Array:
	var failures: Array = []
	var stats: Dictionary = game.stats

	if expect_timeout:
		failures.append_array(_verify_timeout())
	elif network:
		failures.append_array(_verify_network())
	else:
		failures.append_array(_verify_solo(stats))

	if float(stats["fps"]) < MIN_ACCEPTABLE_FPS:
		failures.append("frame rate too low: %.1f fps" % float(stats["fps"]))
	if not stats["errors"].is_empty():
		failures.append("errors reported: %s" % str(stats["errors"]))
	# Two instances of the game share one log file, so in a network run the
	# lines of the other machine would be read as ours. The harness checks
	# each process separately instead.
	if not network and not expect_timeout:
		var engine_errors := _engine_errors()
		if not engine_errors.is_empty():
			failures.append("engine errors logged: %s" % str(engine_errors.slice(0, 3)))
	return failures


func _verify_network() -> Array:
	var failures: Array = []
	if peers_seen < 2:
		failures.append("never saw a second player (peers=%d)" % peers_seen)
	if not round_started:
		failures.append("the round never started")
	if not remote_moved:
		failures.append("the other snake never moved: no snapshots arrived")
	if not match_finished:
		failures.append("the round never ended")
	elif winner_id <= 0:
		failures.append("the round ended without a winner")
	if died_locally and not spectated:
		failures.append("dying did not put this player into the spectator camera")
	var floor_count := SnakeMatch.minimum_rocks(peers_seen)
	if rocks_seen < floor_count:
		failures.append("the arena arrived with %d rock(s), fewer than %d" % [
			rocks_seen, floor_count,
		])
	return failures


func _verify_solo(stats: Dictionary) -> Array:
	var failures: Array = []
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

	if boost_collected and not pickup_flash_seen:
		failures.append("collecting an item played no effect")
	if not boost_fired:
		failures.append("the speed boost was never fired")
	elif max_multiplier < GameConfig.BOOST_FACTOR - 0.05:
		failures.append("the boost only reached x%.2f" % max_multiplier)
	elif multiplier_after_boost < 0.0:
		failures.append("the boost never ran to completion")
	elif multiplier_after_boost > 1.05:
		failures.append("speed stayed at x%.2f after the boost" % multiplier_after_boost)

	if not crate_bonus_in_slot:
		failures.append("a crate bonus never reached the item slot")
	if not crate_malus_forced:
		failures.append("a crate curse was never forced on the snake")
	elif min_multiplier > GameConfig.SLOW_FACTOR + 0.05:
		failures.append("the slow down only reached x%.2f" % min_multiplier)
	elif multiplier_after_slow < 0.0:
		failures.append("the slow down never ran to completion")
	elif absf(multiplier_after_slow - 1.0) > 0.05:
		failures.append("speed stayed at x%.2f after the slow down" % multiplier_after_slow)

	for limit: int in GameConfig.FPS_LIMITS:
		if not fps_limits_seen.has(limit):
			failures.append("frame rate ceiling never tried: %s" % str(limit))
		elif not fps_limits_seen[limit]:
			failures.append("the engine did not take the ceiling %s" % str(limit))
	if vsync_states_seen.size() < 2:
		failures.append("vsync was never seen both ways")
	if debug_fps_shown <= 0:
		failures.append("the debug readout never counted a frame rate")
	if not debug_hidden:
		failures.append("the debug readout did not go away when switched off")

	for mode: Dictionary in GameConfig.QUALITY_MODES:
		if not quality_faces.has(mode["name"]):
			failures.append("graphics mode never drew anything: %s" % mode["name"])
	if quality_faces.size() == GameConfig.QUALITY_MODES.size():
		var simple: int = quality_faces["simple"]
		var smooth: int = quality_faces["smooth"]
		var fine: int = quality_faces["fine"]
		if not (simple < smooth and smooth < fine):
			failures.append("graphics modes did not order themselves: %s" % str(quality_faces))

	if rocks_seen < SnakeMatch.minimum_rocks(1):
		failures.append("only %d rock(s) on the arena" % rocks_seen)
	elif rock_largest - rock_smallest < 0.5:
		failures.append("every rock was the same size (r%.1f-%.1f)" % [
			rock_smallest, rock_largest
		])
	if not spawn_lanes_clear:
		failures.append("a rock was blocking a spawn point or its lane")
	if lane_kept < GameConfig.OBSTACLE_LANE_MIN:
		failures.append("the clear lane shrank to %.1f units" % lane_kept)
	if not rock_death:
		failures.append("driving into a rock did not kill the snake")

	var card: int = GameConfig.SCORE_CARD_POINTS
	var per_point: float = GameConfig.GROWTH_PER_FOOD
	if score_card_gain != card:
		failures.append("the winning card paid %d points instead of %d" % [score_card_gain, card])
	elif absf(length_after_gain - card * per_point) > 0.05:
		failures.append("the body grew %.2f units for %d points" % [length_after_gain, card])
	if score_card_loss != card:
		failures.append("the losing card cost %d points instead of %d" % [score_card_loss, card])
	elif absf(length_after_loss - card * per_point) > 0.05:
		failures.append("the body shrank %.2f units for %d points" % [length_after_loss, card])
	if not score_floor_held:
		failures.append("the score never reached its floor of zero")
	elif absf(length_after_floor - GameConfig.START_BODY_LENGTH) > 0.05:
		failures.append("at zero the body was %.2f units, not its starting %.2f" % [
			length_after_floor, GameConfig.START_BODY_LENGTH
		])


	if _length_checks == 0:
		failures.append("the length was never compared against the score")
	if _length_errors > 0:
		failures.append("the body did not match the score on %d frame(s)" % _length_errors)
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
