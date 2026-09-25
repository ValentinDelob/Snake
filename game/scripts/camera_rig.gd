class_name CameraRig
extends Camera3D

## The three 3D cameras, plus the flat top-down view inherited from the
## original 2D game.
##
## Steering is always relative now (left and right turn the head), so every
## camera is playable; chase is simply the most immersive one.

enum Mode { FOLLOW, OVERVIEW, CHASE }

const MODE_NAMES := ["follow", "overview", "chase"]
const MODE_FOV := [55.0, 50.0, 62.0]

var mode: Mode = Mode.FOLLOW
var flat := false

var _eye := Vector3.ZERO
var _look := Vector3.ZERO
var _settled := false
var _spectating := false
var _height := 14.0
var _arena := Vector2(30.0, 20.0)
## The menu shows the whole board whatever the player's own preference is.
var _preview := false

## Camera trauma: kicks add to it, it drains on its own, and the shake is its
## square - so a small knock is a nudge and a death is a jolt.
var _trauma := 0.0
var _shake_time := 0.0


## Shake the view. Amounts add up and are capped, so two deaths at once do
## not throw the camera across the arena.
func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func trauma() -> float:
	return _trauma


## Applied after the camera has been placed, as an offset of the lens, so it
## never pushes the rig itself off course.
func _apply_shake(delta: float) -> void:
	_shake_time += delta
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	var power := _trauma * _trauma
	h_offset = sin(_shake_time * 47.0) * 0.55 * power
	v_offset = sin(_shake_time * 39.0 + 1.3) * 0.45 * power


func set_preview(value: bool) -> void:
	if _preview == value:
		return
	_preview = value
	_settled = false


func mode_name() -> String:
	return "top" if flat else MODE_NAMES[mode]


func view_name() -> String:
	return "flat" if flat else "3d"


func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_settled = false


func set_mode_by_name(name: String) -> void:
	var index := MODE_NAMES.find(name)
	if index >= 0:
		mode = index as Mode
	_settled = false


func set_flat(value: bool) -> void:
	flat = value
	_settled = false


func reset() -> void:
	_settled = false


## Free flight for a player who is out of the round: the camera moves
## anywhere inside the arena instead of following a snake.
func fly(delta: float, move: Vector2, lift: float, arena: Vector2) -> void:
	_spectating = true
	_settled = true
	var speed := 12.0
	_look += Vector3(move.x, 0.0, move.y) * speed * delta
	_look.x = clampf(_look.x, 0.0, arena.x)
	_look.z = clampf(_look.z, 0.0, arena.y)
	_height = clampf(_height + lift * speed * 0.6 * delta, 6.0, 30.0)
	_eye = _look + Vector3(0.0, _height, _height * 0.55)
	projection = PROJECTION_PERSPECTIVE
	fov = MODE_FOV[Mode.OVERVIEW]
	look_at_from_position(_eye, _look, Vector3.UP)


func start_spectating(from: Vector2, arena: Vector2) -> void:
	_spectating = true
	_settled = true
	_height = 14.0
	_look = Vector3(
		clampf(from.x, 0.0, arena.x), 0.0, clampf(from.y, 0.0, arena.y)
	)
	_eye = _look + Vector3(0.0, _height, _height * 0.55)


func stop_spectating() -> void:
	_spectating = false
	_settled = false


func spectating() -> bool:
	return _spectating


## The menu and the lobby have no snake to follow: the camera still has to
## sit somewhere sensible, or it ends up at the origin inside the scenery.
func set_arena(arena_width: float, arena_height: float) -> void:
	_arena = Vector2(arena_width, arena_height)


func show_arena(delta: float) -> void:
	projection = PROJECTION_PERSPECTIVE
	fov = MODE_FOV[Mode.OVERVIEW]
	var centre := Vector3(_arena.x * 0.5, 0.0, _arena.y * 0.5)
	var wanted := centre + _overview_offset(_arena.y)
	if not _settled:
		_eye = wanted
		_look = centre
		_settled = true
	else:
		var weight := 1.0 - exp(-delta * 4.0)
		_eye = _eye.lerp(wanted, weight)
		_look = _look.lerp(centre, weight)
	look_at_from_position(_eye, _look, Vector3.UP)


func update_rig(delta: float, world) -> void:
	_update_pose(delta, world)
	_apply_shake(delta)


func _update_pose(delta: float, world) -> void:
	if _spectating:
		return
	if world == null:
		show_arena(delta)
		return
	if flat and not _preview:
		_apply_flat(world)
		return

	projection = PROJECTION_PERSPECTIVE
	# A wider lens while boosting: cheap, and it sells the speed.
	var boost_fov: float = 7.0 * (world.speed_multiplier - 1.0)
	fov = (MODE_FOV[Mode.OVERVIEW] if _preview else MODE_FOV[mode]) + boost_fov

	var pose := _desired_pose(world)
	var wanted_eye: Vector3 = pose[0]
	var wanted_look: Vector3 = pose[1]

	if not _settled:
		_eye = wanted_eye
		_look = wanted_look
		_settled = true
	else:
		var speed := 6.5 if mode == Mode.CHASE else 4.0
		var weight := 1.0 - exp(-delta * speed)
		_eye = _eye.lerp(wanted_eye, weight)
		_look = _look.lerp(wanted_look, weight)

	if _eye.distance_to(_look) > 0.01:
		look_at_from_position(_eye, _look, Vector3.UP)


func _desired_pose(world: SnakeWorld) -> Array:
	var width := world.width
	var height := world.height
	var head := Vector3(world.head_position.x, 0.5, world.head_position.y)

	if _preview:
		var board_center := Vector3(width / 2.0, 0.0, height / 2.0)
		return [board_center + _overview_offset(height), board_center]

	match mode:
		Mode.OVERVIEW:
			var center := Vector3(width / 2.0, 0.0, height / 2.0)
			return [center + _overview_offset(height), center]
		Mode.CHASE:
			var forward := Vector3(world.direction().x, 0.0, world.direction().y)
			return [
				head - forward * 5.0 + Vector3(0.0, 3.0, 0.0),
				head + forward * 4.5 + Vector3(0.0, 0.1, 0.0),
			]
		_:
			# FOLLOW: keep the head roughly centred, without leaving the arena
			var look := Vector3(
				clampf(head.x, 7.0, maxf(7.0, width - 7.0)),
				0.0,
				clampf(head.z, 4.5, maxf(4.5, height - 4.5))
			)
			return [look + Vector3(0.0, 12.0, 8.0), look]


## How far back the overview sits. It has to grow with the arena, or a big
## one would spill out of frame; the numbers are the old fixed ones divided
## by the standard arena, so a standard one looks exactly as it did.
func _overview_offset(arena_height: float) -> Vector3:
	return Vector3(0.0, arena_height * 1.1, arena_height * 0.75)


func _apply_flat(world: SnakeWorld) -> void:
	projection = PROJECTION_ORTHOGONAL
	size = world.height + 5.0
	var center := Vector3(world.width * 0.5, 0.0, world.height * 0.5)
	# Straight down: the up vector must not be parallel to the view direction,
	# and -Z keeps the arena oriented like the original 2D board.
	look_at_from_position(center + Vector3(0.0, 24.0, 0.0), center, Vector3(0.0, 0.0, -1.0))
	_settled = false
