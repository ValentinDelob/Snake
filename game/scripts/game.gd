extends Node3D

## The game: state machine, input, fixed-step simulation, networking and the
## glue between the rules (SnakeMatch), the view (BoardView) and the cameras.
##
## Multiplayer is server authoritative. The host runs the one and only
## SnakeMatch and sends snapshots; a client sends nothing but its steering
## and mirrors what comes back, so the two machines can never disagree about
## who died first. A client keeps the snakes gliding between snapshots so the
## motion stays smooth at any tick rate.

enum State { MENU, LOBBY, PLAY, PAUSE, GAMEOVER }

const STATE_NAMES := ["menu", "lobby", "play", "pause", "gameover"]

## Keys are ignored for a moment after the window opens.
const STARTUP_INPUT_DELAY := 0.3

## How often the host sends the state of the arena to the clients.
const SNAPSHOT_HZ := 20.0

## Held keys steer continuously: -1 turns left, +1 turns right.
const TURN_KEYS := {
	KEY_LEFT: -1.0,
	KEY_A: -1.0,
	KEY_Q: -1.0,     # AZERTY
	KEY_RIGHT: 1.0,
	KEY_D: 1.0,
}

## While spectating the same keys fly the camera, plus forward and back.
const FLY_KEYS := {
	KEY_LEFT: Vector2(-1.0, 0.0), KEY_A: Vector2(-1.0, 0.0), KEY_Q: Vector2(-1.0, 0.0),
	KEY_RIGHT: Vector2(1.0, 0.0), KEY_D: Vector2(1.0, 0.0),
	KEY_UP: Vector2(0.0, -1.0), KEY_W: Vector2(0.0, -1.0), KEY_Z: Vector2(0.0, -1.0),
	KEY_DOWN: Vector2(0.0, 1.0), KEY_S: Vector2(0.0, 1.0),
}

@onready var _camera: CameraRig = $Camera
@onready var _board: BoardView = $Board
@onready var _hud: SnakeHud = $HUD
@onready var _sun: DirectionalLight3D = $Sun

var game_match: SnakeMatch
var state: State = State.MENU
var agent: GreedyAgent = null
var spectating := false

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
var _demo_crate_bonus := false
var _accumulator := 0.0
var _flash := 0.0
var _elapsed := 0.0
var _play_time := 0.0
var _seed := 0
var _max_steps := 0
var _held_turns := {}
var _held_fly := {}
var _last_record := false
var _was_affected := false
var _snapshot_timer := 0.0
var _winner_id := -1
var _net_autostart := 0.0   # host self-test: start the match on its own
## Test hook: seconds of play after which this instance stops steering, so a
## scripted network run can decide who falls first.
var lose_after := 0.0


# --------------------------------------------------------------------------- #
func _ready() -> void:
	Journal.banner()
	_parse_arguments()

	_sun.rotation_degrees = Vector3(-62.0, -28.0, 0.0)

	game_match = SnakeMatch.new(GameConfig.BOARD_WIDTH, GameConfig.BOARD_HEIGHT, _seed)
	game_match.snake_died.connect(_on_snake_died)
	game_match.food_eaten.connect(_on_food_eaten)
	game_match.item_collected.connect(_on_item_collected)
	game_match.finished.connect(_on_match_finished)
	_board.build(game_match.width, game_match.height)

	_camera.set_arena(game_match.width, game_match.height)
	_camera.set_mode_by_name(str(PlayerProfile.get_preference("camera")))
	_camera.set_flat(str(PlayerProfile.get_preference("view")) == "flat")
	GameConfig.quality = GameConfig.quality_from_name(
		str(PlayerProfile.get_preference("quality"))
	)
	Journal.info("game", "Graphics mode: %s" % GameConfig.quality_mode()["name"])
	_apply_display_settings()

	_hud.solo_requested.connect(_start_solo)
	_hud.host_requested.connect(_start_hosting)
	_hud.join_requested.connect(_join_session)
	_hud.quality_chosen.connect(_choose_quality)
	_hud.vsync_toggled.connect(_toggle_vsync)
	_hud.fps_limit_cycled.connect(_cycle_fps_limit)
	_hud.debug_toggled.connect(_toggle_debug)
	_hud.quit_requested.connect(func(): request_quit("menu-quit"))

	Session.peer_joined.connect(_on_peer_joined)
	Session.peer_left.connect(_on_peer_left)
	Session.connected_to_host.connect(_on_connected_to_host)
	Session.connection_failed.connect(_on_connection_failed)
	Session.host_disconnected.connect(_on_host_disconnected)

	if _driver != null or _demo:
		agent = GreedyAgent.new()
	if _driver != null:
		Journal.info("selftest", "Self-test armed (step budget %d)" % _max_steps)
	elif _demo:
		Journal.info("game", "Demo mode: the bot plays, cameras stay under your control")

	_enter_menu()
	_apply_network_arguments()


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
			"--host":
				_pending_host = true
			"--join":
				_pending_join = value if value != "" else "127.0.0.1"
			"--lose-after":
				lose_after = float(value)
			"--expect-timeout":
				_pending_expect_timeout = true
			"--start-score":
				_start_score = int(value)
			"--profile":
				_profiler = FrameProfiler.new()
				# Vsync pins every frame to 16.7 ms and hides what each part
				# of the frame costs, so a profiling run is left uncapped and
				# ignores what the player chose.
				_display_locked = true
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				Engine.max_fps = 0
			"--profile-capped":
				# The other half of the question: with vsync where a player
				# has it, how many frames still miss their slot?
				_profiler = FrameProfiler.new()
	if _max_steps <= 0:
		_max_steps = int(GameConfig.SIM_HZ * 60.0)  # one minute of simulation
	if _driver != null:
		_driver.expect_timeout = _pending_expect_timeout
		PlayerProfile.use_path("user://selftest_profile.json")


var _pending_host := false
var _pending_join := ""
var _pending_expect_timeout := false
## Measuring aid: a round that starts with points already on the board is a
## round with a long snake, which is when the game works hardest.
var _start_score := 0
## True while a profiling run is driving the display itself.
var _display_locked := false
## Only built by --profile: measuring costs a little, so it is opt in.
var _profiler: FrameProfiler = null
var _last_menu_message := ""
var _last_death_cause: SnakeWorld.Outcome = SnakeWorld.Outcome.MOVING
var _score_on_bar := -1          # the score the bar is already showing


## --host and --join let a test (or a shortcut) open a session immediately.
func _apply_network_arguments() -> void:
	if _pending_host:
		_start_hosting()
	elif _pending_join != "":
		_join_session(_pending_join)


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

	var clock: int = _profiler.begin_frame() if _profiler != null else 0

	if state == State.PLAY:
		_play_time += delta
		_flash = maxf(0.0, _flash - delta * 3.0)
		# A fixed step keeps the snakes behaving the same on any machine; the
		# accumulator is capped so a long stall cannot teleport them.
		_accumulator = minf(_accumulator + delta, 0.25)
		while _accumulator >= GameConfig.SIM_STEP and state == State.PLAY:
			_accumulator -= GameConfig.SIM_STEP
			_advance()
		if Session.is_host():
			_broadcast_snapshot(delta)
	elif state == State.LOBBY and _net_autostart > 0.0 and Session.is_host():
		_net_autostart -= delta
		if _net_autostart <= 0.0 and Session.players.size() > 1:
			_start_match()

	if _profiler != null:
		clock = _profiler.mark("sim", clock)
	_update_camera(delta)
	if _profiler != null:
		clock = _profiler.mark("camera", clock)
	_board.refresh(game_match, Session.local_id(), _elapsed, _flash)
	if _profiler != null:
		clock = _profiler.mark("board", clock)
	_refresh_hud()
	if _profiler != null:
		clock = _profiler.mark("hud", clock)
		_profiler.end_frame(delta, state == State.PLAY, _play_time)


func _update_camera(delta: float) -> void:
	if spectating:
		var move := Vector2.ZERO
		for keycode: int in _held_fly:
			move += _held_fly[keycode]
		_camera.fly(
			delta, move.normalized(), 0.0,
			Vector2(game_match.width, game_match.height)
		)
		return
	_camera.update_rig(delta, local_snake())


func local_snake():
	return game_match.snakes.get(Session.local_id())


func play_time() -> float:
	return _play_time


func _refresh_hud() -> void:
	var snake = local_snake()
	var score: int = snake.score if snake != null else 0
	# Watching the number rather than the pickup covers every case at once:
	# solo, host, and a client whose points are decided on another machine.
	if state == State.PLAY and _score_on_bar >= 0 and score != _score_on_bar:
		_hud.announce_score(score - _score_on_bar)
	_score_on_bar = score
	_hud.set_stats(
		score,
		maxi(PlayerProfile.high_score(), score),
		"%s %s" % [_camera.view_name().to_upper(), _camera.mode_name()]
	)
	_hud.set_debug(bool(PlayerProfile.get_preference("debug")))
	if snake == null:
		_hud.set_item(0, 0, 0.0, 1.0)
	else:
		var total: float = (
			GameConfig.BOOST_DURATION if snake.effect == SnakeWorld.Item.SPEED
			else GameConfig.SLOW_DURATION
		)
		_hud.set_item(snake.carried, snake.effect, snake.effect_time_left, total)
	_hud.set_players(_scoreboard(), Session.local_id(), spectating)


## A short name for a peer: the network id is a huge random number.
func _player_name(id: int) -> String:
	if id == Session.local_id():
		return "you"
	var ids: Array = game_match.snakes.keys()
	ids.sort()
	var index := ids.find(id)
	return "player %d" % (index + 1) if index >= 0 else "player %d" % id


func _scoreboard() -> Array:
	var rows: Array = []
	var ids: Array = game_match.snakes.keys()
	ids.sort()
	for id: int in ids:
		var snake: SnakeWorld = game_match.snakes[id]
		rows.append({"id": id, "score": snake.score, "alive": snake.alive})
	return rows


# --------------------------------------------------------------------------- #
func _advance() -> void:
	var mine = local_snake()
	if mine != null and mine.alive:
		if agent != null:
			mine.steer(agent.decide_in(game_match, mine))
		else:
			mine.steer(_turn_from_keys())
		if Session.role == Session.Role.CLIENT:
			_send_input.rpc_id(1, mine.turn_input)

	game_match.step(GameConfig.SIM_STEP)
	stats["steps"] += 1

	if stats["steps"] >= _max_steps and _driver != null:
		Journal.info("selftest", "Step budget reached (%d)" % _max_steps)
		request_quit("step-budget")


func _turn_from_keys() -> float:
	var turn := 0.0
	for keycode: int in _held_turns:
		turn += float(_held_turns[keycode])
	return clampf(turn, -1.0, 1.0)


# --------------------------------------------------------------------------- #
# Match events (host and solo only: a client takes these from snapshots)
# --------------------------------------------------------------------------- #
## What killed the last snake to die, so a test can check the cause.
func last_death_cause() -> SnakeWorld.Outcome:
	return _last_death_cause


func _on_snake_died(id: int, cause: SnakeWorld.Outcome) -> void:
	_last_death_cause = cause
	var snake: SnakeWorld = game_match.snakes[id]
	Journal.info("game", "%s died (%s) at (%.1f,%.1f) with score %d" % [
		_player_name(id), ["moving", "wall", "self", "another snake", "a rock"][cause],
		snake.death_position.x, snake.death_position.y, snake.score,
	])
	if id == Session.local_id():
		_on_local_death(snake)


func _on_local_death(snake: SnakeWorld) -> void:
	stats["last_score"] = snake.score
	stats["max_score"] = maxi(int(stats["max_score"]), snake.score)
	stats["games"] = int(stats["games"]) + 1
	_last_record = PlayerProfile.record_game(snake.score)
	if Session.is_online() and game_match.snakes.size() > 1:
		_start_spectating(snake.death_position)


func _on_food_eaten(id: int) -> void:
	if id != Session.local_id():
		return
	_flash = 1.0
	var snake: SnakeWorld = game_match.snakes[id]
	stats["max_score"] = maxi(int(stats["max_score"]), snake.score)
	Journal.debug("game", "Food eaten: score=%d" % snake.score)


func _on_item_collected(id: int, kind: SnakeWorld.Ground, roll: SnakeWorld.Item) -> void:
	var crate := kind == SnakeWorld.Ground.MYSTERY
	var color := GameConfig.SPARK_COLOR
	var told := "collected a speed bolt"
	if crate:
		match roll:
			SnakeWorld.Item.SLOW:
				color = GameConfig.FROST_COLOR
				told = "opened a crate: slow down, forced on the spot"
			SnakeWorld.Item.SCORE_UP:
				color = GameConfig.SNAKE_HEAD_COLOR
				told = "opened a crate: %d points, taken at once" % GameConfig.SCORE_CARD_POINTS
			SnakeWorld.Item.SCORE_DOWN:
				color = GameConfig.DANGER_COLOR
				told = "opened a crate: %d points lost, taken at once" % GameConfig.SCORE_CARD_POINTS
			_:
				color = GameConfig.MYSTERY_COLOR
				told = "opened a crate: speed boost, stored in the slot"
	var snake: SnakeWorld = game_match.snakes[id]
	_board.play_pickup_flash(snake.head_position, _elapsed, color)
	Journal.info("game", "Player %d %s" % [id, told])


func _on_match_finished(winner: int) -> void:
	_winner_id = winner
	if Session.is_host():
		_match_over.rpc(winner)
	_show_result(winner)


func _show_result(winner: int) -> void:
	spectating = false
	_camera.stop_spectating()
	_set_state(State.GAMEOVER)
	_held_turns.clear()
	_held_fly.clear()

	if Session.is_online():
		var mine := winner == Session.local_id()
		var title := "VICTORY" if mine else "DEFEATED"
		var color := GameConfig.SNAKE_HEAD_COLOR if mine else GameConfig.DANGER_COLOR
		var subtitle := (
			"last one standing" if mine
			else ("%s survived" % _player_name(winner) if winner > 0 else "nobody survived")
		)
		var snake = local_snake()
		_hud.show_result(title, color, subtitle, snake.score if snake != null else 0)
	else:
		var snake = local_snake()
		var reason := "you bit yourself"
		if _last_death_cause == SnakeWorld.Outcome.DEAD_ROCK:
			reason = "you hit a rock"
		elif snake != null and not snake.is_inside(snake.death_position):
			reason = "you hit a wall"
		_hud.show_game_over(
			reason,
			snake.score if snake != null else 0,
			PlayerProfile.high_score(),
			_last_record
		)


func _start_spectating(from: Vector2) -> void:
	spectating = true
	_held_turns.clear()
	_camera.start_spectating(from, Vector2(game_match.width, game_match.height))
	Journal.info("game", "You are out: free camera until the round ends")


# --------------------------------------------------------------------------- #
# Networking
# --------------------------------------------------------------------------- #
func _start_hosting() -> void:
	if not Session.host():
		_hud.show_menu(PlayerProfile.high_score(), PlayerProfile.games_played(), Session.last_error)
		return
	_enter_lobby()
	if _driver != null:
		_net_autostart = 6.0   # the network self-test starts on its own


func _join_session(address: String) -> void:
	Journal.info("game", "Joining %s" % address)
	if not Session.join(address):
		_hud.show_menu(PlayerProfile.high_score(), PlayerProfile.games_played(), Session.last_error)
		return
	PlayerProfile.set_preference("address", address)
	_enter_lobby()


func _on_peer_joined(id: int) -> void:
	if state == State.LOBBY:
		_refresh_lobby()
	if Session.is_host() and state == State.PLAY:
		# Latecomers watch the round that is already running.
		_start_round.rpc_id(id, game_match.snakes.keys(), true, game_match.obstacle_data())


func _on_peer_left(id: int) -> void:
	game_match.remove_snake(id)
	if state == State.LOBBY:
		_refresh_lobby()


func _on_connected_to_host() -> void:
	_refresh_lobby()


func _on_connection_failed() -> void:
	Journal.warn("game", "Could not join: %s" % Session.last_error)
	_enter_menu(Session.last_error)


func _on_host_disconnected() -> void:
	game_match.snakes.clear()
	_enter_menu("the host closed the session")


## Host: build the match and tell everyone to start.
func _start_match() -> void:
	if not Session.is_host():
		return
	game_match.snakes.clear()
	for id: int in Session.players:
		game_match.add_snake(id)
	# The arena is built here, then handed out: every player must be looking
	# at the same rocks or the host's rulings would make no sense on screen.
	_begin_round(game_match.snakes.keys(), false)
	_start_round.rpc(game_match.snakes.keys(), false, game_match.obstacle_data())


@rpc("authority", "call_remote", "reliable")
func _start_round(ids: Array, as_spectator: bool, rocks: PackedFloat32Array) -> void:
	_begin_round(ids, as_spectator, rocks)


func _begin_round(ids: Array, as_spectator: bool, rocks: PackedFloat32Array = PackedFloat32Array()) -> void:
	# Only a network client mirrors somebody else's match. Offline and host
	# both judge their own, which is what solo has always done.
	if Session.role == Session.Role.CLIENT:
		game_match.snakes.clear()
		for id in ids:
			game_match.add_snake(int(id))
		game_match.authoritative = false
	else:
		game_match.authoritative = true
	game_match.start()
	if _start_score > 0:
		for id: int in game_match.snakes:
			game_match.snakes[id].add_score(_start_score)
			game_match.snakes[id].body_length = game_match.snakes[id].target_body_length
	_score_on_bar = -1
	if not rocks.is_empty():
		game_match.set_obstacles(rocks)
	_board.set_obstacles(game_match.obstacles)

	_accumulator = 0.0
	_flash = 0.0
	_play_time = 0.0
	_winner_id = -1
	_held_turns.clear()
	_held_fly.clear()
	_was_affected = false
	spectating = as_spectator
	if as_spectator:
		_camera.start_spectating(
			Vector2(game_match.width, game_match.height) * 0.5,
			Vector2(game_match.width, game_match.height)
		)
	else:
		_camera.stop_spectating()
		_camera.set_preview(false)
		_camera.reset()
	_hud.hide_overlay()
	_hud.set_bar_visible(true)
	_set_state(State.PLAY)
	Journal.info("game", "Round started with %d snake(s)" % game_match.snakes.size())


## Client to host: my steering for this step.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_input(turn: float) -> void:
	if not Session.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var snake = game_match.snakes.get(id)
	if snake != null and snake.alive:
		snake.steer(turn)


## Client to host: fire whatever I am carrying.
@rpc("any_peer", "call_remote", "reliable")
func _request_item() -> void:
	if not Session.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var snake = game_match.snakes.get(id)
	if snake != null and snake.alive and snake.use_item():
		Journal.info("game", "Player %d fired an item" % id)


func _broadcast_snapshot(delta: float) -> void:
	_snapshot_timer -= delta
	if _snapshot_timer > 0.0:
		return
	_snapshot_timer = 1.0 / SNAPSHOT_HZ

	var snakes: Dictionary = {}
	for id: int in game_match.snakes:
		var snake: SnakeWorld = game_match.snakes[id]
		snakes[id] = [
			snake.head_position, snake.heading, snake.body_length,
			snake.speed_multiplier, int(snake.effect), snake.alive, snake.score,
			int(snake.carried), snake.effect_time_left,
		]
	var ground: Array = []
	for item: Dictionary in game_match.ground:
		ground.append([int(item["kind"]), item["position"]])
	_apply_snapshot.rpc(snakes, game_match.food, ground)


@rpc("authority", "call_remote", "unreliable")
func _apply_snapshot(snakes: Dictionary, food: Vector2, ground: Array) -> void:
	game_match.food = food
	game_match.ground = []
	for entry: Array in ground:
		game_match.ground.append({"kind": entry[0], "position": entry[1]})

	for id_key in snakes:
		var id := int(id_key)
		var row: Array = snakes[id_key]
		var snake = game_match.snakes.get(id)
		if snake == null:
			snake = game_match.add_snake(id)
		var was_alive: bool = snake.alive
		snake.apply_snapshot(row[0], row[1], row[2], row[3], row[4], row[5], row[6])
		snake.carried = row[7]
		snake.effect_time_left = row[8]
		if was_alive and not snake.alive and id == Session.local_id():
			_on_local_death(snake)


@rpc("authority", "call_remote", "reliable")
func _match_over(winner: int) -> void:
	_winner_id = winner
	_show_result(winner)


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


## Hand the window whatever the player asked for. A profiling run keeps
## its own settings, since measuring is the whole point of that run.
func _apply_display_settings() -> void:
	if _display_locked:
		return
	var vsync: bool = bool(PlayerProfile.get_preference("vsync"))
	var limit: int = int(PlayerProfile.get_preference("fps_limit"))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = maxi(0, limit)
	Journal.info("game", "Display: vsync %s, fps limit %s" % [
		"on" if vsync else "off", GameConfig.fps_limit_label(limit),
	])


## The debug readout is a setting like any other: remembered, and on from
## the moment it is switched on.
func _toggle_debug() -> void:
	PlayerProfile.set_preference("debug", not bool(PlayerProfile.get_preference("debug")))
	Journal.info("game", "Debug readout %s" % (
		"on" if PlayerProfile.get_preference("debug") else "off"
	))
	_hud.refresh_menu_page()


func _toggle_vsync() -> void:
	PlayerProfile.set_preference("vsync", not bool(PlayerProfile.get_preference("vsync")))
	_apply_display_settings()
	_hud.refresh_menu_page()


func _cycle_fps_limit() -> void:
	PlayerProfile.set_preference(
		"fps_limit", GameConfig.next_fps_limit(int(PlayerProfile.get_preference("fps_limit")))
	)
	_apply_display_settings()
	_hud.refresh_menu_page()


## The player picked a graphics mode: remember it and let the menu redraw.
func _choose_quality(mode: int) -> void:
	GameConfig.quality = mode as GameConfig.Quality
	PlayerProfile.set_preference("quality", GameConfig.quality_mode()["name"])
	Journal.info("game", "Graphics mode: %s" % GameConfig.quality_mode()["name"])
	_hud.refresh_menu_page()


## What the menu last said, so a test can read the reason a join failed.
func last_menu_message() -> String:
	return _last_menu_message


func _enter_menu(message: String = "") -> void:
	_last_menu_message = message
	Session.leave()
	game_match.snakes.clear()
	game_match.authoritative = true
	_set_state(State.MENU)
	spectating = false
	_camera.stop_spectating()
	_held_turns.clear()
	_held_fly.clear()
	_hud.set_bar_visible(false)
	_camera.set_preview(true)
	_hud.show_menu(PlayerProfile.high_score(), PlayerProfile.games_played(), message)
	_hud.set_address(str(PlayerProfile.get_preference("address")))


func _enter_lobby() -> void:
	_set_state(State.LOBBY)
	_hud.set_bar_visible(false)
	_camera.set_preview(true)
	_refresh_lobby()


func _refresh_lobby() -> void:
	if state != State.LOBBY:
		return
	_hud.show_lobby(
		Session.is_host(),
		Session.players.size(),
		Session.local_addresses() if Session.is_host() else "",
		Session.connect_address() if Session.connecting else ""
	)


## Solo: one snake, the rules unchanged.
func _start_solo() -> void:
	game_match.snakes.clear()
	game_match.authoritative = true
	game_match.add_snake(Session.local_id())
	_begin_round(game_match.snakes.keys(), false)


func _toggle_pause() -> void:
	if Session.is_online():
		return    # pausing would stop the round for everybody else
	if state == State.PLAY:
		_set_state(State.PAUSE)
		_held_turns.clear()
		_hud.show_pause()
	elif state == State.PAUSE:
		_hud.hide_overlay()
		_set_state(State.PLAY)


# --------------------------------------------------------------------------- #
# Input
# --------------------------------------------------------------------------- #
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.echo:
		return
	# A keystroke left over from whatever launched the game would otherwise
	# skip the menu before the player has seen it.
	if _elapsed < STARTUP_INPUT_DELAY:
		return

	if state == State.PLAY and spectating and FLY_KEYS.has(key_event.keycode):
		if key_event.pressed:
			_held_fly[key_event.keycode] = FLY_KEYS[key_event.keycode]
		else:
			_held_fly.erase(key_event.keycode)
		return

	# Turning is held down, so releases matter as much as presses. The menu
	# needs the same keys to walk its list, so it gets them first.
	if state == State.MENU:
		if key_event.pressed:
			_on_key(key_event.keycode)
		return

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
			# Clicks go straight to the buttons; the keyboard is walked here
			# so it behaves the same whatever has focus.
			if keycode == KEY_UP or keycode == KEY_W or keycode == KEY_Z:
				_hud.move_menu_focus(-1)
			elif keycode == KEY_DOWN or keycode == KEY_S:
				_hud.move_menu_focus(1)
			elif keycode == KEY_ENTER or keycode == KEY_KP_ENTER or keycode == KEY_SPACE:
				if not _hud.activate_menu_item():
					_start_solo()
			elif keycode == KEY_ESCAPE:
				if not _hud.menu_back():
					request_quit("menu-quit")
		State.LOBBY:
			if keycode == KEY_ENTER and Session.is_host():
				_start_match()
			elif keycode == KEY_ESCAPE:
				_enter_menu()
		State.PLAY:
			_play_key(keycode)
		State.PAUSE:
			if keycode == KEY_P or keycode == KEY_ENTER:
				_toggle_pause()
			elif keycode == KEY_ESCAPE:
				_enter_menu()
		State.GAMEOVER:
			if keycode == KEY_R or keycode == KEY_ENTER or keycode == KEY_SPACE:
				if Session.is_host():
					_start_match()
				elif Session.is_online():
					_enter_lobby()
				else:
					Journal.info("game", "Round restarted")
					_start_solo()
			elif keycode == KEY_M:
				_enter_menu()
			elif keycode == KEY_ESCAPE:
				request_quit("gameover-quit")


func _play_key(keycode: int) -> void:
	if keycode == KEY_ESCAPE:
		_enter_menu()
	elif keycode == KEY_SPACE:
		_use_item()
	elif keycode == KEY_P:
		_toggle_pause()
	elif keycode == KEY_C:
		_cycle_camera()
	elif keycode == KEY_V:
		_toggle_view()
	elif _demo:
		_demo_key(keycode)


## Demo mode doubles as a showroom: drop items where you want them.
func _demo_key(keycode: int) -> void:
	if keycode == KEY_B:
		game_match.drop(SnakeWorld.Ground.BOLT)
		Journal.info("game", "Demo: a bolt dropped on request")
	elif keycode == KEY_N:
		_demo_crate_bonus = not _demo_crate_bonus
		game_match.drop(
			SnakeWorld.Ground.MYSTERY,
			SnakeWorld.Item.SPEED if _demo_crate_bonus else SnakeWorld.Item.SLOW
		)
		Journal.info("game", "Demo: a crate dropped, rigged with %s" % [
			"a bonus" if _demo_crate_bonus else "the curse",
		])


func _use_item() -> void:
	var snake = local_snake()
	if snake == null or not snake.alive:
		return
	if Session.role == Session.Role.CLIENT:
		_request_item.rpc_id(1)
		return
	if not snake.use_item():
		Journal.debug("game", "Space pressed with an empty item slot")
		return
	Journal.info("game", "Speed boost fired for %.0fs" % GameConfig.BOOST_DURATION)


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


func board_view() -> BoardView:
	return _board


func hud() -> SnakeHud:
	return _hud


func report_error(message: String) -> void:
	Journal.error("game", message)
	stats["errors"].append(message)


func request_quit(reason: String) -> void:
	stats["reason"] = reason
	stats["fps"] = float(stats["frames"]) / maxf(0.001, _elapsed)
	if _profiler != null:
		_profiler.report()

	var exit_code := 0
	if _driver != null:
		var failures: Array = _driver.verify(self)
		for failure: String in failures:
			Journal.error("selftest", "check failed: %s" % failure)
		exit_code = 0 if failures.is_empty() else 1
		Journal.info("selftest", "SELFTEST %s: %s" % [
			"PASS" if failures.is_empty() else "FAIL", _driver.summary(self),
		])

	Journal.info("game", "Session finished: reason=%s games=%d best=%d steps=%d frames=%d fps=%.1f slow=%d errors=%s" % [
		reason, stats["games"], stats["max_score"], stats["steps"],
		stats["frames"], stats["fps"], stats["slow_frames"],
		"none" if stats["errors"].is_empty() else str(stats["errors"]),
	])
	Session.leave()
	get_tree().quit(exit_code)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit("window-closed")
