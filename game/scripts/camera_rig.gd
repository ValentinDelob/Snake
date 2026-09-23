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
## The menu shows the whole board whatever the player's own preference is.
var _preview := false


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


func update_rig(delta: float, world: SnakeWorld) -> void:
	if flat and not _preview:
		_apply_flat(world)
		return

	projection = PROJECTION_PERSPECTIVE
	fov = MODE_FOV[Mode.OVERVIEW] if _preview else MODE_FOV[mode]

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
		return [board_center + Vector3(0.0, 22.0, 15.0), board_center]

	match mode:
		Mode.OVERVIEW:
			var center := Vector3(width / 2.0, 0.0, height / 2.0)
			return [center + Vector3(0.0, 22.0, 15.0), center]
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


func _apply_flat(world: SnakeWorld) -> void:
	projection = PROJECTION_ORTHOGONAL
	size = world.height + 5.0
	var center := Vector3(world.width * 0.5, 0.0, world.height * 0.5)
	# Straight down: the up vector must not be parallel to the view direction,
	# and -Z keeps the arena oriented like the original 2D board.
	look_at_from_position(center + Vector3(0.0, 24.0, 0.0), center, Vector3(0.0, 0.0, -1.0))
	_settled = false
