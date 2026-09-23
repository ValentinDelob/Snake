class_name BoardView
extends Node3D

## Everything visible on the board: floor, ramparts, snake and food.
##
## The static geometry is built once. The snake itself is a single procedural
## tube rebuilt every frame by SnakeMesh, so the body is continuous rather
## than a string of separate meshes.

const FLASH_DURATION := 0.45
const WALL_HEIGHT := 0.8
const WALL_THICKNESS := 0.4
const BODY_HEIGHT := 0.4

var _eyes: Array[MeshInstance3D] = []
var _body: SnakeMesh
var _food: MeshInstance3D
var _bolt: MeshInstance3D
var _flash_ring: MeshInstance3D
var _flash_material: StandardMaterial3D
var _flash_time := -1.0


func build(world: SnakeWorld) -> void:
	for child in get_children():
		child.queue_free()
	_eyes.clear()

	_build_floor(world)
	_build_walls(world)
	_build_actors()
	Journal.info("board", "Board built for a %.0fx%.0f arena" % [world.width, world.height])


## Reshape the snake and move the props to match the current world.
func refresh(world: SnakeWorld, elapsed: float, flash: float) -> void:
	_body.rebuild(world, BODY_HEIGHT)
	_body.set_boost(world.boost_intensity(), elapsed)
	_body.set_flash(flash)
	_place_eyes(world)
	_refresh_bolt(world, elapsed)
	_refresh_flash(elapsed)

	_food.position = Vector3(
		world.food.x,
		0.5 + 0.08 * sin(elapsed * 4.0),
		world.food.y
	)
	_food.rotation.y = elapsed * 1.6


## A bolt waiting on the arena: floating, spinning, hard to miss.
func _refresh_bolt(world: SnakeWorld, elapsed: float) -> void:
	_bolt.visible = world.pickup_on_arena
	if not world.pickup_on_arena:
		return
	_bolt.position = Vector3(
		world.pickup.x,
		0.75 + 0.1 * sin(elapsed * 2.6),
		world.pickup.y
	)
	_bolt.rotation.y = elapsed * 1.4


## Small, quick ring when the bolt is collected.
func play_pickup_flash(at: Vector2, elapsed: float) -> void:
	_flash_time = elapsed
	_flash_ring.position = Vector3(at.x, 0.55, at.y)
	_flash_ring.visible = true


## True while the pickup ring is still playing.
func flash_active() -> bool:
	return _flash_time >= 0.0


func _refresh_flash(elapsed: float) -> void:
	if _flash_time < 0.0:
		return
	var age := elapsed - _flash_time
	if age > FLASH_DURATION:
		_flash_ring.visible = false
		_flash_time = -1.0
		return
	var ratio := age / FLASH_DURATION
	var scale_value := 0.5 + ratio * 2.6
	_flash_ring.scale = Vector3(scale_value, 1.0, scale_value)
	_flash_material.albedo_color = Color(
		GameConfig.SPARK_COLOR.r, GameConfig.SPARK_COLOR.g, GameConfig.SPARK_COLOR.b,
		0.75 * (1.0 - ratio)
	)


# --------------------------------------------------------------------------- #
func _build_floor(world: SnakeWorld) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(world.width, world.height)
	var material := StandardMaterial3D.new()
	material.albedo_color = GameConfig.FLOOR_COLOR
	material.roughness = 0.95

	var instance := MeshInstance3D.new()
	instance.name = "Floor"
	instance.mesh = plane
	instance.material_override = material
	instance.position = Vector3(world.width * 0.5, 0.0, world.height * 0.5)
	add_child(instance)

	_build_floor_marks(world)


func _build_floor_marks(world: SnakeWorld) -> void:
	## The arena has no grid any more, but a bare floor gives no sense of
	## speed in the chase view, so a faint ruling is kept as a ground
	## reference.
	var material := StandardMaterial3D.new()
	material.albedo_color = GameConfig.GRID_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var spacing := 2.0
	var x := spacing
	while x < world.width:
		mesh.surface_add_vertex(Vector3(x, 0.01, 0.0))
		mesh.surface_add_vertex(Vector3(x, 0.01, world.height))
		x += spacing
	var z := spacing
	while z < world.height:
		mesh.surface_add_vertex(Vector3(0.0, 0.01, z))
		mesh.surface_add_vertex(Vector3(world.width, 0.01, z))
		z += spacing
	mesh.surface_end()

	var instance := MeshInstance3D.new()
	instance.name = "FloorMarks"
	instance.mesh = mesh
	add_child(instance)


func _build_walls(world: SnakeWorld) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = GameConfig.WALL_COLOR
	material.roughness = 0.8

	var half := WALL_THICKNESS / 2.0
	var walls := [
		{"size": Vector3(world.width + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS),
		 "pos": Vector3(world.width / 2.0, WALL_HEIGHT / 2.0, -half)},
		{"size": Vector3(world.width + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS),
		 "pos": Vector3(world.width / 2.0, WALL_HEIGHT / 2.0, world.height + half)},
		{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, world.height),
		 "pos": Vector3(-half, WALL_HEIGHT / 2.0, world.height / 2.0)},
		{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, world.height),
		 "pos": Vector3(world.width + half, WALL_HEIGHT / 2.0, world.height / 2.0)},
	]
	for index in range(walls.size()):
		var box := BoxMesh.new()
		box.size = walls[index]["size"]
		var instance := MeshInstance3D.new()
		instance.name = "Wall%d" % index
		instance.mesh = box
		instance.material_override = material
		instance.position = walls[index]["pos"]
		add_child(instance)


func _build_actors() -> void:
	_body = SnakeMesh.new()
	_body.name = "Body"
	add_child(_body)

	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.085
	eye_mesh.height = 0.17
	eye_mesh.radial_segments = 8
	eye_mesh.rings = 4
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = GameConfig.EYE_COLOR
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index in range(2):
		var eye := MeshInstance3D.new()
		eye.name = "Eye%d" % index
		eye.mesh = eye_mesh
		eye.material_override = eye_material
		add_child(eye)
		_eyes.append(eye)

	var food_mesh := BoxMesh.new()
	food_mesh.size = Vector3.ONE * (GameConfig.FOOD_RADIUS * 1.5)
	var food_material := StandardMaterial3D.new()
	food_material.albedo_color = GameConfig.FOOD_COLOR
	food_material.emission_enabled = true
	food_material.emission = GameConfig.FOOD_COLOR
	food_material.emission_energy_multiplier = 0.55

	_food = MeshInstance3D.new()
	_food.name = "Food"
	_food.mesh = food_mesh
	_food.material_override = food_material
	add_child(_food)

	var bolt_material := StandardMaterial3D.new()
	bolt_material.albedo_color = GameConfig.BOOST_COLOR
	bolt_material.emission_enabled = true
	bolt_material.emission = GameConfig.BOOST_COLOR
	bolt_material.emission_energy_multiplier = 0.8

	_bolt = MeshInstance3D.new()
	_bolt.name = "Bolt"
	_bolt.mesh = _build_bolt_mesh()
	_bolt.material_override = bolt_material
	_bolt.visible = false
	add_child(_bolt)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.42
	ring.rings = 16
	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = GameConfig.SPARK_COLOR
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	_flash_ring = MeshInstance3D.new()
	_flash_ring.name = "PickupFlash"
	_flash_ring.mesh = ring
	_flash_ring.material_override = _flash_material
	_flash_ring.visible = false
	add_child(_flash_ring)


## A lightning bolt: a flat zigzag polygon given a bit of thickness.
func _build_bolt_mesh() -> ArrayMesh:
	var outline := PackedVector2Array([
		Vector2(0.16, 1.0), Vector2(-0.52, 0.06), Vector2(-0.12, 0.06),
		Vector2(-0.3, -1.0), Vector2(0.52, -0.02), Vector2(0.1, -0.02),
	])
	var scale_factor := 0.46
	for index in range(outline.size()):
		outline[index] *= scale_factor

	var triangles := Geometry2D.triangulate_polygon(outline)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var depth := 0.09

	# Front and back faces.
	for face in range(2):
		var z := depth if face == 0 else -depth
		var normal := Vector3(0.0, 0.0, 1.0 if face == 0 else -1.0)
		var index := 0
		while index < triangles.size():
			var corners := [triangles[index], triangles[index + 1], triangles[index + 2]]
			if face == 1:
				corners.reverse()
			for corner: int in corners:
				vertices.append(Vector3(outline[corner].x, outline[corner].y, z))
				normals.append(normal)
			index += 3

	# Sides.
	for index in range(outline.size()):
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index + 1) % outline.size()]
		var edge := (b - a).normalized()
		var normal := Vector3(edge.y, -edge.x, 0.0)
		var quad := [
			Vector3(a.x, a.y, depth), Vector3(b.x, b.y, depth), Vector3(b.x, b.y, -depth),
			Vector3(a.x, a.y, depth), Vector3(b.x, b.y, -depth), Vector3(a.x, a.y, -depth),
		]
		for corner: Vector3 in quad:
			vertices.append(corner)
			normals.append(normal)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _place_eyes(world: SnakeWorld) -> void:
	var forward := Vector3(world.direction().x, 0.0, world.direction().y)
	var side := forward.cross(Vector3.UP)
	var center := Vector3(world.head_position.x, BODY_HEIGHT, world.head_position.y)
	# The eyes must sit on the skin of the tube, not inside it, so they are
	# pushed out along a direction and not along each axis separately.
	var bulge := GameConfig.SNAKE_RADIUS * GameConfig.HEAD_BULGE
	for index in range(_eyes.size()):
		var sign_value := -1.0 if index == 0 else 1.0
		var outwards := (
			forward * 0.45 + side * (0.78 * sign_value) + Vector3.UP * 0.58
		).normalized()
		_eyes[index].position = center + outwards * (bulge * 0.95)
