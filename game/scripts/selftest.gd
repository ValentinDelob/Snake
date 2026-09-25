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

enum Phase { CAMERAS, TURNS, BOOST, CRATE_BONUS, CRATE_MALUS, SCORE_UP, SCORE_DOWN, GHOST, SPIT, PAUSE, FINISH, WAIT }

const PAUSE_FRAMES := 30
## Matter fed to the snake before the ghost ring phase, so its body is well
## over twice the circle it can turn in.
const GHOST_TEST_MATTER := 45.0
## And before bringing matter up, so a tenth of it is a round number.
const SPIT_TEST_MATTER := 20.0
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
var score_card_gain := 0.0
var score_card_loss := 0.0
var length_after_gain := -1.0
var length_after_loss := -1.0
var score_floor_held := false
var length_after_floor := -1.0
var _gain_crate_requested := false
var _loss_crate_requested := false
var _score_before := -1.0
var _length_before := -1.0
var _length_checks := 0
var _length_errors := 0
var _score_last := -1.0
var _length_last := -1.0
var _floor_stage := 0

## graphics modes: name -> faces the body was made of
var quality_faces := {}
## frame pacing: limit -> did the engine take it, and both vsync states
var fps_limits_seen := {}
var vsync_states_seen := {}
## the ghost ring: found, fired, and walked through a body with
var ghost_collected := false
var ghost_fired := false
var ghost_passed_through := false
var _ghost_requested := false
var _ghost_curling := false
var _ghost_press_sent := false
var _rule_checked := false
var ghost_curled := false

## bringing matter back up, and what a death leaves behind
var spit_refused := false
var spit_taken := 0.0
var spit_dropped := 0.0
var matter_left_behind := 0.0
var corpse_share := -1.0
var _spit_requested := false
var _spit_floor_checked := false
var _spit_floor_score := 0.0
var _spit_before_score := 0.0
var _spit_before_field := 0.0
var _spit_expected := 0.0
var _field_before_death := 0.0
var _score_before_death := 0.0

## dying costs a snake its length, not its round
var respawned := false
var round_ended := false
var _was_alive := true

## the field of motes: how many, how big, and how the sizes are shared out
var motes_seen := 0
var mote_smallest := 99.0
var mote_largest := 0.0
var motes_small := 0
var motes_big := 0

## the arena the round was played on
var arena_seen := Vector2.ZERO

## rivals: how many the menu offered, how many took the field, and whether
## they played like players - moving, eating, firing, slimming down
var rival_counts_offered := {}
var rivals_expected := -1
var rivals_seen := 0
var rivals_moved := {}
var rivals_grew := {}
var rivals_named := false
var rival_boost_rule := false
var rival_spit_rule := false
var rival_spit_share := 0.0
var rival_result_title := ""
var _rival_starts := {}
var _rival_stage := 0
var _rival_id := -1
var _rival_mark := 0
var _rival_score := 0.0
var _rival_since := 0.0
var _menu_step := 0
var _menu_step_at := 0

## the look: a sky over the arena, effects thrown, a shake, and
## the effects setting really switching the pollen off and on
var sky_seen := false
var bursts_seen := 0
var peak_trauma := 0.0
var effects_states := {}
var effects_follow := true

## the crystal shears: deadly crossing without, clean cut with, the matter
## all on the floor, one cut per pass, and fired for real from the slot
var shears_deadly_without := false
var shears_cut := false
var shears_matter := 0.0
var shears_conserved := false
var shears_kept := 0.0
var shears_recut_blocked := false

## the newer items fired for real from the slot: item name -> what the bar said
var live_bar_text := {}
var _live_index := 0
var _live_stage := 0
const LIVE_ITEMS := [SnakeWorld.Item.SHEARS, SnakeWorld.Item.MAGNET]

## the magnet: nothing moves without it, near gems come in, far ones stay
var magnet_still_without := false
var magnet_near_left := -1.0
var magnet_mid_left := -1.0
var magnet_far_moved := -1.0
var magnet_worth_kept := false

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
		arena_seen = Vector2(game.game_match.width, game.game_match.height)
		# A client builds no arena of its own: rocks here mean the host's
		# arena arrived intact.
		rocks_seen = maxi(rocks_seen, game.game_match.obstacles.size())
		_watch_remotes(game)
		if game.spectating:
			spectated = true
		var mine = game.local_snake()
		if mine != null and not mine.alive:
			died_locally = true
		elif died_locally and mine != null and mine.alive:
			respawned = true

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
	if _entered_play or game.stats["frames"] <= 30:
		return
	# Walk down to RIVALS and press it round every count it offers, back to
	# where it started, the way a player would with the keyboard. One key a
	# few frames apart: an injected key is only read on the next frame.
	var frames: int = game.stats["frames"]
	if frames - _menu_step_at < 6:
		return
	_menu_step_at = frames
	var cycle := GameConfig.RIVAL_NAMES.size() + 1
	if _menu_step == 0:
		press(KEY_DOWN)
		release(KEY_DOWN)
	elif _menu_step <= cycle:
		rival_counts_offered[game.rival_count()] = true
		press(KEY_ENTER)
		release(KEY_ENTER)
	elif _menu_step == cycle + 1:
		rival_counts_offered[game.rival_count()] = true
		Journal.info("selftest", "rival counts offered by the menu: %s" % str(rival_counts_offered.keys()))
		press(KEY_UP)
		release(KEY_UP)
	else:
		Journal.info("selftest", "starting a game from the menu")
		_entered_play = true
		press(KEY_ENTER)
		release(KEY_ENTER)
	_menu_step += 1


## What everything on the floor is worth between it all.
func _field_worth(game) -> float:
	var total := 0.0
	for value: float in game.game_match.food_value:
		total += value
	return total


## True while the local snake is on the field.
func snake_alive(game) -> bool:
	var snake = game.local_snake()
	return snake != null and snake.alive


func _on_play(game) -> void:
	var rig: CameraRig = game.camera_rig()
	views_seen[rig.view_name()] = true
	cameras_seen[rig.mode_name()] = true

	var now: float = game.play_time()
	var alive: bool = snake_alive(game)
	if _was_alive and alive:
		# Kept one frame behind, so that when a death lands the state from
		# just before it is still readable.
		var living = game.local_snake()
		_field_before_death = _field_worth(game)
		_score_before_death = living.score if living != null else 0.0
	if _was_alive and not alive:
		var left: float = _field_worth(game) - _field_before_death
		if _score_before_death > 1.0:
			# Measured as a share of what the snake was worth: matter is
			# meant to be conserved, whatever size the corpse was.
			var kept := left / _score_before_death
			matter_left_behind = maxf(matter_left_behind, left)
			corpse_share = kept if corpse_share < 0.0 else minf(corpse_share, kept)
			Journal.info("selftest", "a snake worth %.1f matter left %.1f on the floor" % [
				_score_before_death, left,
			])
		# The snake was lost. The round carries on without it, but whatever
		# this phase was holding has to be let go of. The cause is only
		# readable here now: nothing shows a game over screen any more.
		if game.last_death_cause() == SnakeWorld.Outcome.DEAD_ROCK and not rock_death:
			rock_death = true
			Journal.info("selftest", "the snake died on a rock")
		_phase_started = now
		_on_round_restart(game)
	elif alive and not _was_alive:
		respawned = true
		Journal.info("selftest", "snake came back after dying")
	_was_alive = alive
	if now < 1.0:
		arena_seen = Vector2(game.game_match.width, game.game_match.height)
		_survey_rocks(game)
		_survey_field(game)
	_watch_world(game, now)
	_watch_rivals(game, now)

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
		Phase.GHOST:
			_run_ghost(game, now)
		Phase.SPIT:
			_run_spit(game, now)
		Phase.PAUSE:
			_run_pause()
		Phase.FINISH:
			_run_finish(game, now)
		Phase.WAIT:
			pass        # the bot plays on until the clock runs out


## Look over the motes on the floor: what they are worth, and whether the
## small ones really are the common ones.
func _survey_field(game) -> void:
	var values: PackedFloat32Array = game.game_match.food_value
	if values.size() < 10:
		return
	motes_seen = maxi(motes_seen, values.size())
	for value: float in values:
		mote_smallest = minf(mote_smallest, value)
		mote_largest = maxf(mote_largest, value)
		if value < 1.0:
			motes_small += 1
		elif value > 2.0:
			motes_big += 1


## Look over the rocks this round was given: how many, how varied, and
## whether any of them sits where a snake starts or sets off.
func _survey_rocks(game) -> void:
	var game_match = game.game_match
	var laid: Array = []
	for rock: Dictionary in game_match.obstacles:
		if not rock.get("planted", false):
			laid.append(rock)
	rocks_seen = maxi(rocks_seen, laid.size())
	lane_kept = game_match.lane_length
	for rock: Dictionary in laid:
		rock_smallest = minf(rock_smallest, rock["radius"])
		rock_largest = maxf(rock_largest, rock["radius"])

	for id: int in game_match.spawns:
		var pose: Array = game_match.spawns[id]
		for rock: Dictionary in laid:
			if rock["position"].distance_to(pose[0]) < rock["radius"] + 1.0:
				spawn_lanes_clear = false
				Journal.warn("selftest", "a rock sits on the spawn of player %d" % id)
			for point: Vector2 in game_match.lane_points(pose[0], pose[1]):
				if rock["position"].distance_to(point) < rock["radius"] + 0.8:
					spawn_lanes_clear = false
					Journal.warn("selftest", "a rock blocks the lane of player %d" % id)


## The last of the scripted phases: lay a rock right in the snake's path
## and drive into it, then watch it come back, because dying is no longer
## the end of anything.
func _run_finish(game, now: float) -> void:
	var snake = game.local_snake()
	if snake == null or not snake.alive:
		return
	if rock_death:
		# The bot may have found a rock on its own earlier in the run, in
		# which case the bot was never let go of and there is nothing to
		# wait for: the death this phase is after has already been seen.
		if respawned and game.agent == null:
			game.agent = _saved_agent
		if respawned and game.agent != null:
			_enter_phase(Phase.WAIT, now)
		return
	if not _rock_dropped or now - _rock_dropped_at > 8.0:
		if not _has_room(snake):
			return
		_saved_agent = game.agent
		game.game_match.place_obstacle(_ahead_of(snake), 1.4)
		_rock_dropped = true
		_rock_dropped_at = now
		Journal.info("selftest", "a rock laid in the snake's path")
	if game.agent != null:
		Journal.info("selftest", "releasing the bot, straight into the rock")
		game.agent = null
		return
	if rock_death and respawned:
		Journal.info("selftest", "back on the field: waiting for the clock")
		game.agent = _saved_agent
		_enter_phase(Phase.WAIT, now)


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
	# A death ends whatever effect was running, so a phase interrupted by
	# one has to start over rather than write down what it half measured.
	if phase == Phase.BOOST and max_multiplier < GameConfig.BOOST_FACTOR - 0.05:
		_bolt_requested = false
		boost_fired = false
		multiplier_after_boost = -1.0
	if phase == Phase.CRATE_BONUS and not crate_bonus_in_slot:
		_bonus_crate_requested = false
	if phase == Phase.CRATE_MALUS and min_multiplier > GameConfig.SLOW_FACTOR + 0.05:
		_malus_crate_requested = false
		_slow_started_at = -1.0
		multiplier_after_slow = -1.0
	if phase == Phase.SCORE_UP and score_card_gain <= 0.0:
		_gain_crate_requested = false
	if phase == Phase.SCORE_DOWN and not score_floor_held:
		_loss_crate_requested = false
		_floor_stage = 0
		score_card_loss = 0.0
	if phase == Phase.GHOST and not ghost_fired:
		_ghost_requested = false
		ghost_collected = false
		_ghost_press_sent = false
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
	_check_shears_rule()
	_check_magnet_rule()
	# The effects setting, walked both ways and back to where it was.
	var fx: FxLayer = game.board_view().fx()
	for _index in range(2):
		game._toggle_effects()
		var full := bool(PlayerProfile.get_preference("effects"))
		effects_states[full] = true
		if fx._pollen == null or fx._pollen.visible != full or GameConfig.effects_full != full:
			effects_follow = false
	var environment: Environment = game.get_node("WorldEnvironment").environment
	sky_seen = environment != null and environment.background_mode == Environment.BG_SKY
	Journal.info("selftest", "effects walked %s, pollen followed: %s, sky: %s" % [
		str(effects_states.keys()), effects_follow, sky_seen,
	])


## Hold LEFT, then RIGHT, and check the heading actually turned each way.
func _run_turns(game, now: float) -> void:
	# Steering a snake that is off the field proves nothing, and the reading
	# taken at the end of the hold would be meaningless.
	if not snake_alive(game):
		if _turn_phase > 0 and _turn_phase < 3:
			release(KEY_LEFT)
			release(KEY_RIGHT)
			game.agent = _saved_agent
			_turn_phase = 0
			_turn_waiting_since = -1.0
		return
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
	if snake == null or not snake.alive:
		return        # a boost cut short by a death proves nothing
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
	if snake == null or not snake.alive:
		return
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
	if snake == null or not snake.alive:
		return
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
	if snake == null or not snake.alive:
		return
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
	var jump: float = snake.score - _score_last
	var stretch: float = snake.target_body_length - _length_last
	_score_last = snake.score
	_length_last = snake.target_body_length
	if jump >= float(GameConfig.SCORE_CARD_POINTS) - 0.01:
		score_card_gain = jump
		length_after_gain = stretch
		Journal.info("selftest", "winning card paid %.1f points, body up %.2f units" % [
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
	if snake == null or not snake.alive:
		return

	# Second half of the phase: keep feeding it losing cards until the score
	# cannot go any lower, then check where it stopped.
	if _floor_stage == 1 and snake.score <= 0.0:
		score_floor_held = true
		length_after_floor = snake.target_body_length
		Journal.info("selftest", "score bottomed out at 0, body back to %.2f units" % [
			length_after_floor,
		])
		_enter_phase(Phase.GHOST, now)
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

	var drop: float = _score_last - snake.score
	var shrink: float = _length_last - snake.target_body_length
	_score_last = snake.score
	_length_last = snake.target_body_length
	if drop < float(GameConfig.SCORE_CARD_POINTS) - 0.01 and snake.score > 0.0:
		if now - _phase_started > 8.0:
			_loss_crate_requested = false   # it wandered off: lay another
		return

	if _floor_stage == 0 and drop >= float(GameConfig.SCORE_CARD_POINTS) - 0.01:
		score_card_loss = drop
		length_after_loss = shrink
		Journal.info("selftest", "losing card cost %.1f points, body down %.2f units" % [
			score_card_loss, length_after_loss,
		])
	_floor_stage = 1
	_loss_crate_requested = false


## The ghost ring, driven the way a player would: pick it up, fire it, see
## the second start. Whether it really carries a head through a body is
## settled separately, against the rules themselves, because driving a
## snake into its own tail inside a one second window is a coin toss and a
## test should not be one.
func _run_ghost(game, now: float) -> void:
	var snake = game.local_snake()
	if snake == null or not snake.alive:
		return

	if not _rule_checked:
		_rule_checked = true
		_check_phase_rule()

	# The ring will not go into a slot that is already full, so whatever is
	# in there is spent first.
	if snake.carried != SnakeWorld.Item.NONE and snake.carried != SnakeWorld.Item.PHASE:
		Journal.info("selftest", "emptying the slot before the ghost ring")
		press(KEY_SPACE)
		release(KEY_SPACE)
		return

	if not _ghost_requested:
		Journal.info("selftest", "dropping the ghost ring in the path")
		game.game_match.drop_at(SnakeWorld.Ground.PHASE, _ahead_of(snake))
		_ghost_requested = true
		_phase_started = now
		return

	if not ghost_collected:
		if snake.carried == SnakeWorld.Item.PHASE:
			ghost_collected = true
			Journal.info("selftest", "ghost ring is in the slot")
			_phase_started = now
		elif now - _phase_started > 8.0:
			_ghost_requested = false      # it wandered off: lay another
		return

	# An injected key is only read on the next frame, so firing and checking
	# that it fired have to be two separate steps.
	if not _ghost_press_sent:
		Journal.info("selftest", "firing the ghost ring")
		press(KEY_SPACE)
		release(KEY_SPACE)
		_ghost_press_sent = true
		_phase_started = now
		return

	if not ghost_fired:
		if snake.effect == SnakeWorld.Item.PHASE:
			ghost_fired = true
			Journal.info("selftest", "the ghost second is running")
			_enter_phase(Phase.SPIT, now)
		elif now - _phase_started > 1.5:
			_ghost_press_sent = false     # the press was lost: try again
			_ghost_requested = false
			ghost_collected = false


## The rule behind the ring, checked where it lives. A snake is curled into
## its own body, and then stepped once with the ring running and once
## without: the same position has to be a death in one case and nothing at
## all in the other.
func _check_phase_rule() -> void:
	var world := SnakeWorld.new(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT)
	world.reset(Vector2(GameConfig.BOARD_WIDTH * 0.5, GameConfig.BOARD_HEIGHT * 0.5), 0.0)
	world.add_score(60)
	world.body_length = world.target_body_length
	world.steer(-1.0)

	var curled := false
	for _step in range(4000):
		world.advance(GameConfig.SIM_STEP)
		if world.hits_body(world.head_position):
			curled = true
			break
	if not curled:
		Journal.warn("selftest", "could not curl a snake into its own body")
		return
	ghost_curled = true

	# Without the ring, this is a death.
	var deadly := world.step(GameConfig.SIM_STEP)
	if deadly != SnakeWorld.Outcome.DEAD_SELF:
		Journal.warn("selftest", "a head inside its own body did not kill: %d" % deadly)
		return

	# With it, the same crossing is nothing at all.
	world.alive = true
	world.start_effect(SnakeWorld.Item.PHASE)
	var survived := world.step(GameConfig.SIM_STEP)
	ghost_passed_through = (
		survived == SnakeWorld.Outcome.MOVING
		and world.alive
		and world.hits_body(world.head_position)
	)
	Journal.info("selftest", "phase rule: deadly without the ring, %s with it" % [
		"harmless" if ghost_passed_through else "still deadly",
	])


## The shears, judged on the rules rather than by driving: lay a long snake
## straight across an empty arena, put another head right on its body, and
## see what that crossing does with and without the blades.
func _check_shears_rule() -> void:
	var arena := SnakeMatch.new(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT, 7)
	var victim := arena.add_snake(2)
	victim.reset(Vector2(12.0, 28.0), 0.0)
	victim.add_score(20.0)
	# Let it grow into its length along a straight line.
	for _step in range(1400):
		victim.advance(GameConfig.SIM_STEP)
	var points := victim.body_points()
	if victim.body_length < victim.target_body_length - 0.01 or points.size() < 20:
		Journal.warn("selftest", "could not lay a long snake out for the shears")
		return
	var cut_point: Vector2 = points[points.size() / 2]
	var cutter := arena.add_snake(1)
	cutter.reset(cut_point, PI * 0.5)

	# Without the blades, that head is dead.
	arena._check_bite(1, cutter)
	shears_deadly_without = not cutter.alive

	cutter.reset(cut_point, PI * 0.5)
	cutter.start_effect(SnakeWorld.Item.SHEARS)
	var score_before := victim.score
	var worth_before := _worth_of(arena)
	arena._check_bite(1, cutter)
	shears_matter = score_before - victim.score
	var fell := _worth_of(arena) - worth_before
	shears_cut = cutter.alive and victim.alive and shears_matter > 1.0
	shears_conserved = absf(fell - shears_matter) < 0.01
	shears_kept = victim.body_length
	# The same crossing straight away is the same cut, not a second one.
	shears_recut_blocked = arena.cut(1, 2) == 0.0
	Journal.info("selftest", "shears rule: %s without, cut %.1f of %.1f with (%.1f fell, body now %.1f), recut blocked %s" % [
		"deadly" if shears_deadly_without else "harmless", shears_matter, score_before,
		fell, shears_kept, shears_recut_blocked,
	])


## The magnet, judged on the rules: gems laid at known distances from a
## still head, then the field switched on for a second and a half.
func _check_magnet_rule() -> void:
	var arena := SnakeMatch.new(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT, 11)
	var snake := arena.add_snake(1)
	var head := Vector2(40.0, 28.0)
	snake.reset(head, 0.0)
	var near := head + Vector2(0.0, 3.0)
	var mid := head + Vector2(0.0, -6.0)
	var far := head + Vector2(0.0, GameConfig.MAGNET_REACH + 3.0)
	arena.food = PackedVector2Array([near, mid, far])
	arena.food_value = PackedFloat32Array([0.5, 1.0, 2.0])

	# Nothing moves without a magnet running.
	arena.pull_matter(GameConfig.SIM_STEP)
	magnet_still_without = arena.food[0] == near and arena.food[1] == mid

	snake.start_effect(SnakeWorld.Item.MAGNET)
	for _step in range(int(1.5 * GameConfig.SIM_HZ)):
		arena.pull_matter(GameConfig.SIM_STEP)
	magnet_near_left = arena.food[0].distance_to(head)
	magnet_mid_left = arena.food[1].distance_to(head)
	magnet_far_moved = arena.food[2].distance_to(far)
	magnet_worth_kept = absf(_worth_of(arena) - 3.5) < 0.001
	Journal.info("selftest", "magnet rule: still without %s; near 3.0 -> %.2f, mid 6.0 -> %.2f, far moved %.2f, worth kept %s" % [
		magnet_still_without, magnet_near_left, magnet_mid_left, magnet_far_moved, magnet_worth_kept,
	])


static func _worth_of(arena: SnakeMatch) -> float:
	var total := 0.0
	for value: float in arena.food_value:
		total += value
	return total


## Hand our own snake the shears once the scripted phases are over and fire
## them with the space bar: the slot, the effect and the bar have to agree.
## Hand our own snake each of the newer items once the scripted phases are
## over and fire it with the space bar: the slot, the effect and the bar
## have to agree. One item after the other, each waiting for the last.
func _check_items_live(game) -> void:
	if _live_index >= LIVE_ITEMS.size():
		return
	var snake = game.local_snake()
	if snake == null or not snake.alive:
		return
	var item: SnakeWorld.Item = LIVE_ITEMS[_live_index]
	match _live_stage:
		0:
			if snake.effect == SnakeWorld.Item.NONE and snake.carried == SnakeWorld.Item.NONE:
				snake.carried = item
				_live_stage = 1
		1:
			press(KEY_SPACE)
			release(KEY_SPACE)
			_live_stage = 2
		2:
			if snake.effect == item:
				_live_stage = 3
			elif snake.carried != item:
				_live_stage = 0
		3:
			# The key fired the item at the start of the last frame, before the
			# bar was drawn: it is read one frame later.
			var text: String = game.hud()._boost_label.text
			live_bar_text[SnakeWorld.Item.keys()[item]] = text
			Journal.info("selftest", "%s fired from the slot: bar says '%s'" % [SnakeWorld.Item.keys()[item], text])
			_live_stage = 4
		4:
			# Let it run out before handing over the next one.
			if snake.effect == SnakeWorld.Item.NONE:
				_live_index += 1
				_live_stage = 0


## Bringing matter back up: a snake with nothing much inside it must not
## be able to, and one that is full must lose exactly a tenth of it onto
## the floor, where it can be eaten again.
func _run_spit(game, now: float) -> void:
	var snake = game.local_snake()
	if snake == null or not snake.alive:
		return

	# An empty snake first: there is nothing to bring up, and asking must
	# change nothing. Asked of the rules directly, because a snake left to
	# itself for half a second on a field this rich is no longer empty.
	if not _spit_floor_checked:
		snake.add_score(-snake.score)
		snake.body_length = snake.target_body_length
		_spit_floor_score = snake.score
		spit_refused = (
			snake.spit_amount() == 0
			and game.game_match.spit(Session.local_id()) == 0
			and snake.score == _spit_floor_score
		)
		_spit_floor_checked = true
		Journal.info("selftest", "an empty snake brought up nothing: %s" % spit_refused)
		return

	if not _spit_requested:
		if snake.score < SPIT_TEST_MATTER:
			snake.add_score(SPIT_TEST_MATTER - snake.score)
			snake.body_length = snake.target_body_length
		_spit_before_score = snake.score
		_spit_before_field = _field_worth(game)
		_spit_expected = snake.spit_amount()
		Journal.info("selftest", "bringing up a tenth of %.1f matter" % _spit_before_score)
		press(KEY_E)
		release(KEY_E)
		_spit_requested = true
		_phase_started = now
		return

	if snake.score < _spit_before_score - 0.01:
		spit_taken = _spit_before_score - snake.score
		spit_dropped = _field_worth(game) - _spit_before_field
		Journal.info("selftest", "brought up %.1f of %.1f expected, %.1f landed" % [
			spit_taken, _spit_expected, spit_dropped,
		])
		_enter_phase(Phase.PAUSE, now)
	elif now - _phase_started > 2.0:
		_spit_requested = false       # the press was lost: try again


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
	_watch_look(game)

	# The promise behind the whole feature: the body a snake carries is
	# never anything other than what its score bought.
	_length_checks += 1
	if absf(snake.target_body_length - SnakeWorld.length_for_score(snake.score)) > 0.001:
		_length_errors += 1


## Rivals are watched all round long: they have to leave their spawn, eat,
## and be listed on the bar under their own names.
func _watch_rivals(game, now: float) -> void:
	var rivals: Dictionary = game.rivals
	if rivals_expected < 0:
		rivals_expected = game.rival_count()
		rivals_seen = rivals.size()
		Journal.info("selftest", "%d rival(s) on the field, %d expected" % [rivals_seen, rivals_expected])
	for id: int in rivals:
		var snake = game.game_match.snakes.get(id)
		if snake == null or not snake.alive:
			continue
		if not _rival_starts.has(id):
			_rival_starts[id] = snake.head_position
		if not rivals_moved.has(id) and snake.head_position.distance_to(_rival_starts[id]) > 5.0:
			rivals_moved[id] = true
		if not rivals_grew.has(id) and snake.score > 0.0:
			rivals_grew[id] = true
			Journal.info("selftest", "%s ate something" % rivals[id].name)
	if not rivals_named and not rivals.is_empty():
		rivals_named = _bar_lists_rivals(game)
	# The rules rivals play by are checked once the scripted phases are
	# over, so nothing done to a rival here can disturb them.
	if phase == Phase.WAIT and not rivals.is_empty():
		_check_rival_rules(game, now)
	# Our own shears go last, once the rivals have been judged.
	if phase == Phase.WAIT and (rivals.is_empty() or _rival_stage == 3):
		_check_items_live(game)


func _bar_lists_rivals(game) -> bool:
	var box: Control = game.hud()._players_box
	if not box.visible:
		return false
	var text := ""
	for label in box.get_children():
		text += (label as Label).text + "\n"
	for id: int in game.rivals:
		if not text.contains(game.rivals[id].name):
			return false
	Journal.info("selftest", "the bar lists the rivals: %s" % text.replace("\n", " | "))
	return true


## Hand a rival a bolt and check it fires it; then stuff it past its limit
## and check it brings a tenth up. Driving a bot into either situation would
## be left to chance, so the situation is set up and the rival judged on it.
func _check_rival_rules(game, now: float) -> void:
	var rival = game.game_match.snakes.get(_rival_id)
	var brain = game.rivals.get(_rival_id)
	if _rival_stage in [1, 2] and (rival == null or not rival.alive):
		Journal.info("selftest", "the rival under test died: trying another")
		_rival_stage = 0
		_rival_score = 0.0
	match _rival_stage:
		0:
			for id: int in game.rivals:
				var candidate = game.game_match.snakes.get(id)
				if candidate != null and candidate.alive and candidate.effect == SnakeWorld.Item.NONE:
					_rival_id = id
					break
			rival = game.game_match.snakes.get(_rival_id)
			if rival == null or not rival.alive:
				return
			brain = game.rivals[_rival_id]
			if not rival_boost_rule:
				rival.carried = SnakeWorld.Item.SPEED
				_rival_mark = brain.boosts_fired
				_rival_since = now
				_rival_stage = 1
				Journal.info("selftest", "%s handed a speed bolt" % brain.name)
			elif not rival_spit_rule:
				_rival_stage = 2
		1:
			if brain.boosts_fired > _rival_mark and rival.effect == SnakeWorld.Item.SPEED:
				rival_boost_rule = true
				Journal.info("selftest", "%s fired it after %.1fs" % [brain.name, now - _rival_since])
				_rival_stage = 0
			elif now - _rival_since > GameConfig.RIVAL_BOOST_PATIENCE.y + GameConfig.BOOST_DURATION + 2.0:
				Journal.warn("selftest", "%s sat on its bolt" % brain.name)
				_rival_stage = 0
		2:
			# Fed one frame, judged on a later one: the brain acts on the
			# next simulation step, not on this frame.
			if _rival_score <= 0.0:
				rival.add_score(brain.spit_threshold() + 5.0 - rival.score)
				_rival_score = rival.score
				_rival_mark = brain.spits
				_rival_since = now
				Journal.info("selftest", "%s fed up to %.1f (limit %.1f)" % [
					brain.name, rival.score, brain.spit_threshold(),
				])
			elif brain.spits > _rival_mark:
				rival_spit_share = 1.0 - rival.score / _rival_score
				rival_spit_rule = true
				_rival_stage = 3
				Journal.info("selftest", "%s brought up %.0f%% of its matter" % [
					brain.name, rival_spit_share * 100.0,
				])
			elif now - _rival_since > GameConfig.RIVAL_SPIT_COOLDOWN + 1.0:
				Journal.warn("selftest", "%s never slimmed down" % brain.name)
				_rival_score = 0.0
				_rival_stage = 0


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


## The round is over when the clock says so, whoever is alive.
func _on_gameover(game) -> void:
	if _finished:
		return
	round_ended = true
	rival_result_title = game.hud()._title.text
	Journal.info("selftest", "clock ran out, longest snake was %.1f units" % _longest_length(game))
	Journal.info("selftest", "result screen: %s / %s" % [
		rival_result_title, game.hud()._subtitle.text,
	])
	_finished = true
	press(KEY_ESCAPE)


func _longest_length(game) -> float:
	var best := 0.0
	for id: int in game.game_match.snakes:
		best = maxf(best, game.game_match.snakes[id].target_body_length)
	return best


# --------------------------------------------------------------------------- #
func summary(game) -> String:
	var stats: Dictionary = game.stats
	if expect_timeout:
		return "join-timeout waited=%.1fs limit=%.1fs message=%s frames=%d fps=%.1f" % [
			timeout_waited, Session.CONNECT_TIMEOUT, timeout_message,
			stats["frames"], stats["fps"],
		]
	if network:
		return "network(%s) peers=%d arena=%.0fx%.0f remote_moved=%s winner=%d spectated=%s rocks=%d games=%d frames=%d fps=%.1f" % [
			"host" if Session.is_host() else "client",
			peers_seen, arena_seen.x, arena_seen.y, remote_moved, winner_id, spectated, rocks_seen,
			stats["games"], stats["frames"], stats["fps"],
		]
	return "states=%s views=%s cameras=%s turns=%s boost(peak x%.2f, after x%.2f) slow(floor x%.2f, after x%.2f) crate(bonus=%s, curse=%s) faces%s pacing(limits=%d, vsync=%d) debug(fps=%d, hides=%s) ghost(slot=%s, fired=%s, through=%s) round(respawned=%s, ended=%s) motes(%d, %.1f-%.1f, %d small vs %d big) spit(refused=%s, %.1f up, %.1f down, corpse=%.1f at %.0f%%) cards(+%.1f/%+.1fu, -%.1f/%+.1fu, floor=%s at %.1fu) rocks(%d, r%.1f-%.1f, lane=%.0f, lanes_clear=%s, fatal=%s) rivals(%d/%d, offered=%d, moved=%d, ate=%d, named=%s, boost=%s, spit=%.0f%%, result=%s) shears(deadly=%s, cut=%.1f, conserved=%s, kept=%.1f, recut_blocked=%s) magnet(still=%s, near=%.2f, mid=%.2f, far=%.2f, kept=%s) live=%s look(sky=%s, effects=%d/%s, bursts=%d, shake=%.2f) arena=%.0fx%.0f games=%d best=%d steps=%d frames=%d fps=%.1f" % [
		str(states_seen.keys()), str(views_seen.keys()), str(cameras_seen.keys()),
		str(turns_seen.keys()), max_multiplier, multiplier_after_boost,
		min_multiplier, multiplier_after_slow, crate_bonus_in_slot, crate_malus_forced,
		str(quality_faces), fps_limits_seen.size(), vsync_states_seen.size(),
		debug_fps_shown, debug_hidden,
		ghost_collected, ghost_fired, ghost_passed_through, respawned, round_ended,
		motes_seen, mote_smallest, mote_largest, motes_small, motes_big,
		spit_refused, spit_taken, spit_dropped, matter_left_behind,
		maxf(corpse_share, 0.0) * 100.0,
		score_card_gain, length_after_gain, score_card_loss, -length_after_loss,
		score_floor_held, length_after_floor,
		rocks_seen, rock_smallest, rock_largest, lane_kept, spawn_lanes_clear, rock_death,
		rivals_seen, rivals_expected, rival_counts_offered.size(), rivals_moved.size(),
		rivals_grew.size(), rivals_named, rival_boost_rule, rival_spit_share * 100.0,
		rival_result_title, shears_deadly_without, shears_matter, shears_conserved, shears_kept,
		shears_recut_blocked, magnet_still_without, magnet_near_left, magnet_mid_left,
		magnet_far_moved, magnet_worth_kept, str(live_bar_text.keys()),
		sky_seen, effects_states.size(), effects_follow, bursts_seen,
		peak_trauma, arena_seen.x, arena_seen.y,
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
	if died_locally and not respawned:
		failures.append("a snake that died never came back")
	var floor_count := SnakeMatch.minimum_rocks(peers_seen)
	var wanted_arena := GameConfig.arena_for(peers_seen)
	if arena_seen.distance_to(wanted_arena) > 0.1:
		failures.append("arena was %.0fx%.0f, expected %.0fx%.0f for %d players" % [
			arena_seen.x, arena_seen.y, wanted_arena.x, wanted_arena.y, peers_seen,
		])
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
	if not ghost_collected:
		failures.append("the ghost ring never reached the slot")
	elif not ghost_fired:
		failures.append("firing the ghost ring did not start the effect")
	if not ghost_curled:
		failures.append("the rule check never got a head inside a body")
	elif not ghost_passed_through:
		failures.append("a head inside its own body still died with the ring running")

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

	failures.append_array(_verify_rivals())
	failures.append_array(_verify_look())
	failures.append_array(_verify_shears())
	failures.append_array(_verify_magnet())
	failures.append_array(_verify_live_items())
	var field := 1 + maxi(0, rivals_expected)
	if arena_seen.distance_to(GameConfig.arena_for(field)) > 0.1:
		failures.append("solo arena was %.0fx%.0f, expected %.0fx%.0f for %d snakes" % [
			arena_seen.x, arena_seen.y,
			GameConfig.arena_for(field).x, GameConfig.arena_for(field).y, field,
		])
	if rocks_seen < SnakeMatch.minimum_rocks(field):
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
	if not respawned:
		failures.append("a snake that died never came back")
	if motes_seen < 10:
		failures.append("the field held only %d motes" % motes_seen)
	else:
		if mote_smallest < GameConfig.FOOD_VALUE.x - 0.01:
			failures.append("a mote was worth %.2f, under the floor" % mote_smallest)
		if mote_largest > GameConfig.FOOD_VALUE.y + 0.01:
			failures.append("a mote was worth %.2f, over the ceiling" % mote_largest)
		if mote_largest < 1.5:
			failures.append("no mote worth more than %.2f ever appeared" % mote_largest)
		if motes_small < motes_big * 2:
			failures.append("small motes were not the common ones: %d small, %d big" % [
				motes_small, motes_big,
			])
	if not spit_refused:
		failures.append("an almost empty snake was still able to bring matter up")
	if absf(spit_taken - _spit_expected) > 0.05 or spit_taken <= 0.0:
		failures.append("brought up %.1f matter, expected %.1f" % [spit_taken, _spit_expected])
	elif spit_dropped < spit_taken - 0.05:
		failures.append("%.1f matter came up but only %.1f landed on the floor" % [
			spit_taken, spit_dropped,
		])
	if matter_left_behind <= 0.0:
		failures.append("a snake that died left nothing behind")
	elif corpse_share < 0.9:
		failures.append("a corpse left only %.0f%% of its matter behind" % [corpse_share * 100.0])
	if not round_ended:
		failures.append("the round never ended on the clock")

	var card: float = float(GameConfig.SCORE_CARD_POINTS)
	var per_point: float = GameConfig.GROWTH_PER_FOOD
	# A mote swallowed in the same frame would flatter the card either way,
	# so the reading is allowed a mote's worth of slack.
	var slack: float = GameConfig.FOOD_VALUE.y + 0.05
	if absf(score_card_gain - card) > slack or score_card_gain <= 0.0:
		failures.append("the winning card paid %.1f points instead of %.1f" % [
			score_card_gain, card,
		])
	elif absf(length_after_gain - score_card_gain * per_point) > 0.05:
		failures.append("the body grew %.2f units for %.1f points" % [
			length_after_gain, score_card_gain,
		])
	if absf(score_card_loss - card) > slack or score_card_loss <= 0.0:
		failures.append("the losing card cost %.1f points instead of %.1f" % [
			score_card_loss, card,
		])
	elif absf(length_after_loss - score_card_loss * per_point) > 0.05:
		failures.append("the body shrank %.2f units for %.1f points" % [
			length_after_loss, score_card_loss,
		])
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
	return failures


## Effects have no rules to check, only that they happen: bursts go off,
## a death shakes the camera.
func _watch_look(game) -> void:
	bursts_seen = game.board_view().fx().bursts_played()
	peak_trauma = maxf(peak_trauma, game.camera_rig().trauma())


func _verify_shears() -> Array:
	var failures: Array = []
	if not shears_deadly_without:
		failures.append("a head on another body survived without the shears")
	if not shears_cut:
		failures.append("the shears did not cut the body they went through (%.1f)" % shears_matter)
	elif not shears_conserved:
		failures.append("a cut spilled matter that did not all land on the floor")
	if shears_cut and shears_kept >= GameConfig.START_BODY_LENGTH + 20.0 - 0.5:
		failures.append("the cut snake kept its whole body (%.1f)" % shears_kept)
	if not shears_recut_blocked:
		failures.append("one pass of the shears cut the same body twice")
	return failures


func _verify_magnet() -> Array:
	var failures: Array = []
	if not magnet_still_without:
		failures.append("gems moved towards a head with no magnet running")
	if magnet_near_left < 0.0 or magnet_near_left > 0.05:
		failures.append("a gem 3 units away was still %.2f away after 1.5 s of magnet" % magnet_near_left)
	if magnet_mid_left < 0.0 or magnet_mid_left > 1.0:
		failures.append("a gem 6 units away was still %.2f away after 1.5 s of magnet" % magnet_mid_left)
	if magnet_far_moved != 0.0:
		failures.append("a gem out of reach moved %.2f units" % magnet_far_moved)
	if not magnet_worth_kept:
		failures.append("pulling gems changed what the field was worth")
	return failures


## Every newer item has to fire from the slot and say its name on the bar.
func _verify_live_items() -> Array:
	var failures: Array = []
	for item: SnakeWorld.Item in LIVE_ITEMS:
		var name: String = SnakeWorld.Item.keys()[item]
		if not live_bar_text.has(name):
			failures.append("%s in the slot never fired from the space bar" % name)
		elif not str(live_bar_text[name]).begins_with(name):
			failures.append("the bar said '%s' while %s was running" % [live_bar_text[name], name])
	return failures


func _verify_look() -> Array:
	var failures: Array = []
	if not sky_seen:
		failures.append("the arena was not under a sky")
	if effects_states.size() < 2:
		failures.append("the effects setting was never seen both ways")
	elif not effects_follow:
		failures.append("the pollen did not follow the effects setting")
	if bursts_seen < 10:
		failures.append("only %d effect burst(s) went off in a whole round" % bursts_seen)
	if peak_trauma < GameConfig.SHAKE_DEATH * 0.8:
		failures.append("dying only shook the camera to %.2f" % peak_trauma)
	return failures


func _verify_rivals() -> Array:
	var failures: Array = []
	for count in range(GameConfig.RIVAL_NAMES.size() + 1):
		if not rival_counts_offered.has(count):
			failures.append("the menu never offered %d rival(s)" % count)
	if rivals_expected <= 0:
		failures.append("the round was played without rivals (expected %d)" % rivals_expected)
		return failures
	if rivals_seen != rivals_expected:
		failures.append("%d rival(s) took the field, %d were asked for" % [rivals_seen, rivals_expected])
	if rivals_moved.size() < rivals_seen:
		failures.append("only %d of %d rivals ever left their spawn" % [rivals_moved.size(), rivals_seen])
	if rivals_grew.is_empty():
		failures.append("no rival ever ate anything")
	if not rivals_named:
		failures.append("the bar never listed the rivals by name")
	if not rival_boost_rule:
		failures.append("a rival handed a speed bolt never fired it")
	if not rival_spit_rule:
		failures.append("a rival over its limit never brought matter up")
	elif absf(rival_spit_share - GameConfig.SPIT_SHARE) > 0.04:
		failures.append("a rival brought up %.0f%% of its matter, not %.0f%%" % [
			rival_spit_share * 100.0, GameConfig.SPIT_SHARE * 100.0,
		])
	if not rival_result_title in ["BIGGEST", "OUTGROWN"]:
		failures.append("the round against rivals ended on '%s', not a ranking" % rival_result_title)
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
