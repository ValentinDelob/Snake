class_name SnakeMesh
extends MeshInstance3D

## The snake body as one continuous tube.
##
## A ring of vertices is swept along the path the head travelled, from a
## rounded nose to a pointed tail. Thickness follows a profile (bulging at
## the head, tapering at the tail) and the surface carries UVs - length along
## the body and angle around it - which is all snake_body.gdshader needs to
## paint the gradient, the belly, the scales and the boost lightning.
##
## How finely it is cut comes from the graphics mode the player chose. The
## rings are also allowed to spread out towards the tail: that end is
## straighter, thinner and further from the eye, so it does not need the
## density the head does. This is the one mesh in the game that is rebuilt
## every frame and that grows while you play, so nothing here allocates.

const SHADER_PATH := "res://shaders/snake_body.gdshader"

var _mesh := ArrayMesh.new()
var _material := ShaderMaterial.new()

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _ring_count := 0
## cos/sin of the ring angles, rebuilt only when the graphics mode changes.
var _ring_cos := PackedFloat32Array()
var _ring_sin := PackedFloat32Array()
var _radial := 0
var _nose_rings := 0
var _quality_built := -1

## Reused between frames.
var _ring_distances := PackedFloat32Array()
var _centres := PackedVector2Array()
var _points := PackedVector3Array()
var _radii := PackedFloat32Array()
var _shades := PackedFloat32Array()
var _girth := GameConfig.SNAKE_RADIUS
var _planned_length := -1.0
var _built_length := -1.0
var _built_steps := -1
var _sent_flash := -1.0
var _sent_boost := -1.0
var _sent_slow := -1.0
var _sent_phase := -1.0


func _ready() -> void:
	mesh = _mesh
	_material.shader = load(SHADER_PATH)
	_material.set_shader_parameter("head_color", GameConfig.SNAKE_HEAD_COLOR)
	_material.set_shader_parameter("body_color", GameConfig.SNAKE_BODY_COLOR)
	_material.set_shader_parameter("tail_color", GameConfig.SNAKE_TAIL_COLOR)
	_material.set_shader_parameter("boost_color", GameConfig.BOOST_COLOR)
	_material.set_shader_parameter("spark_color", GameConfig.SPARK_COLOR)
	_material.set_shader_parameter("frost_color", GameConfig.FROST_COLOR)
	_material.set_shader_parameter("frost_pale_color", GameConfig.FROST_PALE_COLOR)
	_material.set_shader_parameter("phase_color", GameConfig.PHASE_COLOR)
	_material.set_shader_parameter("phase_pale_color", GameConfig.PHASE_PALE_COLOR)
	material_override = _material
	_apply_quality()


## Pick up the graphics mode. Cheap enough to check every rebuild, which
## means a mode chosen in the menu takes effect on the next frame.
func _apply_quality() -> void:
	if _quality_built == int(GameConfig.quality):
		return
	_quality_built = int(GameConfig.quality)
	var mode := GameConfig.quality_mode()
	_radial = int(mode["radial"])
	_nose_rings = int(mode["nose"])
	_ring_cos.resize(_radial)
	_ring_sin.resize(_radial)
	for index in range(_radial):
		var angle := TAU * index / _radial
		_ring_cos[index] = cos(angle)
		_ring_sin[index] = sin(angle)
	# Everything downstream is sized by the ring count, so start again.
	_planned_length = -1.0
	_built_steps = -1
	_ring_count = 0
	_vertices.resize(0)


## Flash the head for a moment after a bite. Every one of these crosses to
## the renderer, so a value that has not moved is not sent again.
func set_flash(flash: float) -> void:
	var value := clampf(flash, 0.0, 1.0)
	if is_equal_approx(value, _sent_flash):
		return
	_sent_flash = value
	_material.set_shader_parameter("flash", value)


## Each player has their own colours; the effects stay the same for all.
func set_palette(head: Color, body: Color, tail: Color) -> void:
	_material.set_shader_parameter("head_color", head)
	_material.set_shader_parameter("body_color", body)
	_material.set_shader_parameter("tail_color", tail)


## How strongly the lightning and the frost show, each 0 to 1.
func set_effects(boost: float, slow: float, phase: float = 0.0) -> void:
	var boost_value := clampf(boost, 0.0, 1.0)
	var slow_value := clampf(slow, 0.0, 1.0)
	var phase_value := clampf(phase, 0.0, 1.0)
	if not is_equal_approx(phase_value, _sent_phase):
		_sent_phase = phase_value
		_material.set_shader_parameter("phase", phase_value)
	if not is_equal_approx(boost_value, _sent_boost):
		_sent_boost = boost_value
		_material.set_shader_parameter("boost", boost_value)
	if not is_equal_approx(slow_value, _sent_slow):
		_sent_slow = slow_value
		_material.set_shader_parameter("slow", slow_value)


## How many triangles the body is made of right now, for the record.
func face_count() -> int:
	return _indices.size() / 3


## Nothing about the tube changes unless the snake does, so a frame that
## finds it where it left it hands the renderer nothing at all.
func rebuild(world: SnakeWorld, height: float) -> void:
	_apply_quality()
	if (
		world.steps == _built_steps
		and is_equal_approx(world.body_length, _built_length)
		and is_equal_approx(world.radius, _girth)
	):
		return
	_built_steps = world.steps
	_built_length = world.body_length

	var mode := GameConfig.quality_mode()
	_girth = world.radius
	var length: float = maxf(world.body_length, float(mode["ring"]) * 2.0)
	_plan_rings(length, mode)
	world.sample_path_at(_ring_distances, _centres)

	var body_rings := _ring_distances.size()
	var total := _nose_rings + 1 + body_rings + 1
	if _points.size() != total:
		_points.resize(total)
		_radii.resize(total)
		_shades.resize(total)

	var head := Vector3(world.head_position.x, height, world.head_position.y)
	var forward := Vector3(world.direction().x, 0.0, world.direction().y)
	var head_radius := _girth * GameConfig.HEAD_BULGE

	# Ring centres: the rounded nose first, then the body down to the tail.
	for index in range(_nose_rings + 1):
		var ratio := float(index) / _nose_rings      # 0 at the tip, 1 at the head
		var ahead := head_radius * (1.0 - ratio)
		_points[index] = head + forward * ahead
		_radii[index] = head_radius * sqrt(maxf(0.0, 1.0 - (1.0 - ratio) * (1.0 - ratio)))
		_shades[index] = 0.0

	for index in range(body_rings):
		var travelled: float = _ring_distances[index]
		var along: float = clampf(travelled / length, 0.0, 1.0)
		var slot := _nose_rings + 1 + index
		_points[slot] = Vector3(_centres[index].x, height, _centres[index].y)
		_radii[slot] = _radius_at(travelled, along)
		_shades[slot] = along

	# A last ring of zero radius closes the tail into a point.
	var last_slot := total - 1
	var last: Vector3 = _points[last_slot - 1]
	var before: Vector3 = _points[maxi(last_slot - 2, 0)]
	var away := last - before
	if away.length_squared() < 0.000001:
		away = -forward
	_points[last_slot] = last + away.normalized() * float(mode["ring"]) * 0.6
	_radii[last_slot] = 0.0
	_shades[last_slot] = 1.0

	_build_surface(total)


## Where to put the rings: tight behind the head, opening out towards the
## tail. Only recomputed when the body changes length.
func _plan_rings(length: float, mode: Dictionary) -> void:
	if is_equal_approx(length, _planned_length):
		return
	_planned_length = length
	_ring_distances.clear()
	var near: float = mode["ring"]
	var far: float = mode["ring_tail"]
	var detail: float = mode["detail"]
	var travelled := 0.0
	while travelled < length:
		travelled += lerpf(near, far, clampf(travelled / detail, 0.0, 1.0))
		_ring_distances.append(minf(travelled, length))
	while _ring_distances.size() < 3:
		_ring_distances.append(length)


# --------------------------------------------------------------------------- #
func _radius_at(travelled: float, along: float) -> float:
	var radius := _girth

	# The head bulge fades out over the first body units, and a fatter
	# snake has a proportionally longer one.
	var bulge_length: float = GameConfig.HEAD_BULGE_LENGTH * _girth / GameConfig.SNAKE_RADIUS
	if travelled < bulge_length:
		var fade := 1.0 - travelled / bulge_length
		radius *= lerpf(1.0, GameConfig.HEAD_BULGE, fade * fade)

	# Then it thins down towards the tail, ending in a point.
	radius *= lerpf(1.0, GameConfig.TAIL_TAPER, along * along)
	if along > 0.88:
		radius *= 1.0 - (along - 0.88) / 0.12
	return maxf(radius, 0.0)


func _build_surface(rings: int) -> void:
	if rings < 2:
		return
	var vertex_count := rings * _radial

	if _vertices.size() != vertex_count:
		_vertices.resize(vertex_count)
		_normals.resize(vertex_count)
		_uvs.resize(vertex_count)
	if _ring_count != rings:
		_ring_count = rings
		_rebuild_indices(rings, _radial)

	for ring in range(rings):
		var centre: Vector3 = _points[ring]
		var tangent := _tangent(rings, ring)
		var side := tangent.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(tangent).normalized()
		var radius: float = _radii[ring]
		var along: float = _shades[ring]

		for index in range(_radial):
			var offset: Vector3 = side * _ring_cos[index] + up * _ring_sin[index]
			var vertex_index := ring * _radial + index
			_vertices[vertex_index] = centre + offset * radius
			_normals[vertex_index] = offset
			_uvs[vertex_index] = Vector2(along, float(index) / float(_radial))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices

	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _tangent(rings: int, ring: int) -> Vector3:
	var previous: Vector3 = _points[maxi(ring - 1, 0)]
	var following: Vector3 = _points[mini(ring + 1, rings - 1)]
	var tangent := previous - following      # points from tail towards head
	if tangent.length_squared() < 0.000001:
		return Vector3.FORWARD
	return tangent.normalized()


## The triangle list only depends on the ring count, so it is cached.
func _rebuild_indices(rings: int, radial: int) -> void:
	_indices = PackedInt32Array()
	_indices.resize((rings - 1) * radial * 6)
	var cursor := 0
	for ring in range(rings - 1):
		var base := ring * radial
		var next_base := (ring + 1) * radial
		for index in range(radial):
			var next_index := (index + 1) % radial
			_indices[cursor] = base + index
			_indices[cursor + 1] = next_base + index
			_indices[cursor + 2] = base + next_index
			_indices[cursor + 3] = base + next_index
			_indices[cursor + 4] = next_base + index
			_indices[cursor + 5] = next_base + next_index
			cursor += 6
