class_name BoardView
extends Node3D

## Everything visible on the board: floor, ramparts, snake and food.
##
## The static geometry is built once; the snake segments follow continuous
## positions every frame and their meshes are pooled, so nothing is created
## or destroyed while playing.

const HEAD_SIZE := 0.78
const WALL_HEIGHT := 0.8
const WALL_THICKNESS := 0.4
const BODY_HEIGHT := 0.4

var _segments: Array[MeshInstance3D] = []
var _eyes: Array[MeshInstance3D] = []
var _head: MeshInstance3D
var _food: MeshInstance3D
var _head_material: StandardMaterial3D
var _body_materials: Array[StandardMaterial3D] = []
var _body_mesh: SphereMesh


func build(world: SnakeWorld) -> void:
	for child in get_children():
		child.queue_free()
	_segments.clear()
	_eyes.clear()
	_body_materials.clear()

	_build_floor(world)
	_build_walls(world)
	_build_actors()
	Journal.info("board", "Board built for a %.0fx%.0f arena" % [world.width, world.height])


## Move the pooled meshes to match the current state of the world.
func refresh(world: SnakeWorld, elapsed: float, flash: float) -> void:
	var points := world.body_points()
	_ensure_segments(points.size())

	for index in range(_segments.size()):
		var mesh_instance := _segments[index]
		if index >= points.size():
			mesh_instance.visible = false
			continue
		var point: Vector2 = points[index]
		mesh_instance.visible = true
		mesh_instance.position = Vector3(point.x, BODY_HEIGHT, point.y)
		mesh_instance.material_override = _body_material_for(
			float(index) / maxf(1.0, float(points.size() - 1))
		)

	var head := world.head_position
	_head.position = Vector3(head.x, BODY_HEIGHT, head.y)
	_head.rotation.y = -world.heading
	_head_material.emission_energy_multiplier = 0.15 + flash * 0.85
	_place_eyes(world)

	_food.position = Vector3(
		world.food.x,
		0.5 + 0.08 * sin(elapsed * 4.0),
		world.food.y
	)
	_food.rotation.y = elapsed * 1.6


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
	_body_mesh = SphereMesh.new()
	_body_mesh.radius = GameConfig.SNAKE_RADIUS
	_body_mesh.height = GameConfig.SNAKE_RADIUS * 2.0
	_body_mesh.radial_segments = 12
	_body_mesh.rings = 6

	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(HEAD_SIZE, HEAD_SIZE * 0.82, HEAD_SIZE * 0.96)
	_head_material = StandardMaterial3D.new()
	_head_material.albedo_color = GameConfig.SNAKE_HEAD_COLOR
	_head_material.emission_enabled = true
	_head_material.emission = GameConfig.SNAKE_HEAD_COLOR
	_head_material.emission_energy_multiplier = 0.15

	_head = MeshInstance3D.new()
	_head.name = "Head"
	_head.mesh = head_mesh
	_head.material_override = _head_material
	add_child(_head)

	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.09
	eye_mesh.height = 0.18
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


func _ensure_segments(count: int) -> void:
	while _segments.size() < count:
		var instance := MeshInstance3D.new()
		instance.name = "Segment%d" % _segments.size()
		instance.mesh = _body_mesh
		add_child(instance)
		_segments.append(instance)


func _body_material_for(shade: float) -> StandardMaterial3D:
	var bucket := clampi(int(shade * 8.0), 0, 8)
	while _body_materials.size() <= bucket:
		var material := StandardMaterial3D.new()
		material.albedo_color = GameConfig.SNAKE_BODY_COLOR.lerp(
			GameConfig.SNAKE_TAIL_COLOR, float(_body_materials.size()) / 8.0
		)
		material.roughness = 0.7
		_body_materials.append(material)
	return _body_materials[bucket]


func _place_eyes(world: SnakeWorld) -> void:
	var forward := Vector3(world.direction().x, 0.0, world.direction().y)
	var side := forward.cross(Vector3.UP)
	var center := Vector3(world.head_position.x, BODY_HEIGHT, world.head_position.y)
	for index in range(_eyes.size()):
		var sign_value := -1.0 if index == 0 else 1.0
		_eyes[index].position = (
			center + forward * 0.36 + side * (0.22 * sign_value) + Vector3(0.0, 0.18, 0.0)
		)
