class_name SnakeMesh
extends MeshInstance3D

## The snake body as one continuous tube.
##
## A ring of vertices is swept along the path the head travelled, from a
## rounded nose to a pointed tail. Thickness follows a profile (bulging at
## the head, tapering at the tail) and the surface carries UVs - length along
## the body and angle around it - which is all snake_body.gdshader needs to
## paint the gradient, the belly, the scales and the boost lightning.

const NOSE_RINGS := 4

const SHADER_PATH := "res://shaders/snake_body.gdshader"

var _mesh := ArrayMesh.new()
var _material := ShaderMaterial.new()

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _ring_count := 0
## cos/sin of the ring angles, computed once.
var _ring_cos := PackedFloat32Array()
var _ring_sin := PackedFloat32Array()


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
	material_override = _material

	var radial := GameConfig.TUBE_RADIAL_SEGMENTS
	_ring_cos.resize(radial)
	_ring_sin.resize(radial)
	for index in range(radial):
		var angle := TAU * index / radial
		_ring_cos[index] = cos(angle)
		_ring_sin[index] = sin(angle)


## Flash the head for a moment after a bite.
func set_flash(flash: float) -> void:
	_material.set_shader_parameter("flash", clampf(flash, 0.0, 1.0))


## Each player has their own colours; the effects stay the same for all.
func set_palette(head: Color, body: Color, tail: Color) -> void:
	_material.set_shader_parameter("head_color", head)
	_material.set_shader_parameter("body_color", body)
	_material.set_shader_parameter("tail_color", tail)


## How strongly the lightning and the frost show, each 0 to 1.
func set_effects(boost: float, slow: float) -> void:
	_material.set_shader_parameter("boost", clampf(boost, 0.0, 1.0))
	_material.set_shader_parameter("slow", clampf(slow, 0.0, 1.0))


func rebuild(world: SnakeWorld, height: float) -> void:
	var length: float = maxf(world.body_length, GameConfig.TUBE_RING_SPACING * 2.0)
	var body_rings := maxi(3, int(length / GameConfig.TUBE_RING_SPACING))
	var centres := world.sample_path(GameConfig.TUBE_RING_SPACING, body_rings)

	# Ring centres: the rounded nose first, then the body down to the tail.
	var points: Array[Vector3] = []
	var radii := PackedFloat32Array()
	var shades := PackedFloat32Array()

	var head := Vector3(world.head_position.x, height, world.head_position.y)
	var forward := Vector3(world.direction().x, 0.0, world.direction().y)
	var head_radius := GameConfig.SNAKE_RADIUS * GameConfig.HEAD_BULGE

	for index in range(NOSE_RINGS + 1):
		var ratio := float(index) / NOSE_RINGS      # 0 at the tip, 1 at the head
		var ahead := head_radius * (1.0 - ratio)
		points.append(head + forward * ahead)
		radii.append(head_radius * sqrt(maxf(0.0, 1.0 - (1.0 - ratio) * (1.0 - ratio))))
		shades.append(0.0)

	for index in range(centres.size()):
		var travelled := GameConfig.TUBE_RING_SPACING * (index + 1)
		var along: float = clampf(travelled / length, 0.0, 1.0)
		points.append(Vector3(centres[index].x, height, centres[index].y))
		radii.append(_radius_at(travelled, along))
		shades.append(along)

	# A last ring of zero radius closes the tail into a point.
	if points.size() >= 2:
		var last: Vector3 = points[points.size() - 1]
		var before: Vector3 = points[points.size() - 2]
		points.append(last + (last - before).normalized() * GameConfig.TUBE_RING_SPACING * 0.6)
		radii.append(0.0)
		shades.append(1.0)

	_build_surface(points, radii, shades)


# --------------------------------------------------------------------------- #
func _radius_at(travelled: float, along: float) -> float:
	var radius := GameConfig.SNAKE_RADIUS

	# The head bulge fades out over the first body units.
	if travelled < GameConfig.HEAD_BULGE_LENGTH:
		var fade := 1.0 - travelled / GameConfig.HEAD_BULGE_LENGTH
		radius *= lerpf(1.0, GameConfig.HEAD_BULGE, fade * fade)

	# Then it thins down towards the tail, ending in a point.
	radius *= lerpf(1.0, GameConfig.TAIL_TAPER, along * along)
	if along > 0.88:
		radius *= 1.0 - (along - 0.88) / 0.12
	return maxf(radius, 0.0)


func _build_surface(
	points: Array[Vector3], radii: PackedFloat32Array, shades: PackedFloat32Array
) -> void:
	var rings := points.size()
	if rings < 2:
		return
	var radial := GameConfig.TUBE_RADIAL_SEGMENTS
	var vertex_count := rings * radial

	if _vertices.size() != vertex_count:
		_vertices.resize(vertex_count)
		_normals.resize(vertex_count)
		_uvs.resize(vertex_count)
	if _ring_count != rings:
		_ring_count = rings
		_rebuild_indices(rings, radial)

	for ring in range(rings):
		var centre: Vector3 = points[ring]
		var tangent := _tangent(points, ring)
		var side := tangent.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(tangent).normalized()
		var radius: float = radii[ring]
		var along: float = shades[ring]

		for index in range(radial):
			var offset: Vector3 = side * _ring_cos[index] + up * _ring_sin[index]
			var vertex_index := ring * radial + index
			_vertices[vertex_index] = centre + offset * radius
			_normals[vertex_index] = offset
			_uvs[vertex_index] = Vector2(along, float(index) / float(radial))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices

	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _tangent(points: Array[Vector3], ring: int) -> Vector3:
	var previous: Vector3 = points[maxi(ring - 1, 0)]
	var following: Vector3 = points[mini(ring + 1, points.size() - 1)]
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
