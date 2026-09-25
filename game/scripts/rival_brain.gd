class_name RivalBrain
extends RefCounted

## One snake the machine plays in a solo round.
##
## The steering is the self-test bot's - head for the nearest matter, look
## ahead, turn away from what would kill you. What a rival adds on top is
## the rest of a player: it fires what it carries, and it brings matter up
## when gluttony has made it too slow to live with.

var id: int
var name: String

var _agent := GreedyAgent.new()
var _rng := RandomNumberGenerator.new()
## Seconds left before a carried bolt is fired; negative while not holding one.
var _boost_wait := -1.0
var _spit_at: float
var _spit_cooldown := 0.0

## What it did this round, for the log and the self-test.
var boosts_fired := 0
var ghosts_fired := 0
var spits := 0


func _init(rival_id: int, rival_name: String, seed_value: int = 0) -> void:
	id = rival_id
	name = rival_name
	if seed_value != 0:
		_rng.seed = seed_value + rival_id
	else:
		_rng.randomize()
	_spit_at = _rng.randf_range(GameConfig.RIVAL_SPIT_AT.x, GameConfig.RIVAL_SPIT_AT.y)


## The matter this rival lets itself carry before bringing some up.
func spit_threshold() -> float:
	return _spit_at


## One simulation step: steer, and maybe act. Called before the match steps.
func think(game_match: SnakeMatch, world: SnakeWorld, delta: float) -> void:
	if not world.alive:
		_boost_wait = -1.0
		return
	world.steer(_agent.decide_in(game_match, world))
	_use_items(game_match, world, delta)
	_digest(game_match, world, delta)


func _use_items(game_match: SnakeMatch, world: SnakeWorld, delta: float) -> void:
	match world.carried:
		SnakeWorld.Item.SPEED:
			# Firing a boost on top of a running effect would waste it.
			if world.effect != SnakeWorld.Item.NONE:
				return
			if _boost_wait < 0.0:
				_boost_wait = _rng.randf_range(
					GameConfig.RIVAL_BOOST_PATIENCE.x, GameConfig.RIVAL_BOOST_PATIENCE.y
				)
			_boost_wait -= delta
			if _boost_wait <= 0.0 and world.use_item():
				_boost_wait = -1.0
				boosts_fired += 1
				Journal.info("rival", "%s fired a speed boost" % name)
		SnakeWorld.Item.PHASE:
			# The ring is kept for the one moment it pays: a body across the
			# road that there is no turning away from in time.
			if _agent.body_ahead(game_match, world) and world.use_item():
				ghosts_fired += 1
				Journal.info("rival", "%s fired the ghost ring through a body" % name)
		_:
			_boost_wait = -1.0


## Too fat to turn is too fat to live: bring a tenth up and get lighter.
func _digest(game_match: SnakeMatch, world: SnakeWorld, delta: float) -> void:
	_spit_cooldown = maxf(0.0, _spit_cooldown - delta)
	if _spit_cooldown > 0.0 or world.score < _spit_at:
		return
	var amount := game_match.spit(id)
	if amount > 0.0:
		spits += 1
		_spit_cooldown = GameConfig.RIVAL_SPIT_COOLDOWN
		Journal.info("rival", "%s brought up %.1f matter at %.1f" % [name, amount, world.score + amount])
