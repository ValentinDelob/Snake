class_name BoardView
extends Node3D

## Everything visible on the board: floor, grid, ramparts, snake and food.
##
## The static geometry is built once; only the snake segments and the food
## move every frame, and segment meshes are pooled so no node is created or
## destroyed while playing.

const SEGMENT_SIZE := 0.86
const HEAD_SIZE := 0.94
const FOOD_SIZE := 0.62
const WALL_HEIGHT := 0.8
const WALL_THICKNESS := 0.4

var _segments: Array[MeshInstance3D] = []
var _eyes: Array[MeshInstance3D] = []
var _food: MeshInstance3D
var _head_material: StandardMaterial3D
var _body_materials: Array[StandardMaterial3D] = []
var _segment_mesh: BoxMesh
var _head_mesh: BoxMesh


func build(world: SnakeWorld) -> void:
	for child in get_children():
		child.queue_free()
	_segments.clear()
	_eyes.clear()

	_build_floor(world)
	_build_grid(world)
	_build_walls(world)
	_build_actors()
	Journal.info("board", "Board built for a %dx%d grid" % [world.width, world.height])


## Move the pooled meshes to match the current state of the world.
func refresh(world: SnakeWorld, elapsed: float, flash: float) -> void:
	_ensure_segments(world.length())

	for index in range(_segments.size()):
		var mesh_instance := _segments[index]
		if index >= world.length():
			mesh_instance.visible = false
			continue
		var cell: Vector2i = world.snake[index]
		mesh_instance.visible = true
		mesh_instance.position = Vector3(cell.x + 0.5, 0.45, cell.y + 0.5)
		if index == 0:
			mesh_instance.mesh = _head_mesh
			_head_material.emission_energy_multiplier = 0.15 + flash * 0.85
			mesh_instance.material_override = _head_material
		else:
			mesh_instance.mesh = _segment_mesh
			var shade := float(index) / maxf(1.0, float(world.length() - 1))
			mesh_instance.material_override = _body_material_for(shade)

	_place_eyes(world)

	_food.position = Vector3(
		world.food.x + 0.5,
		0.5 + 0.08 * sin(elapsed * 4.0),
		world.food.y + 0.5
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
	instance.position = Vector3(world.width / 2.0, 0.0, world.height / 2.0)
	add_child(instance)


func _build_grid(world: SnakeWorld) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = GameConfig.GRID_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for x in range(world.width + 1):
		mesh.surface_add_vertex(Vector3(x, 0.01, 0.0))
		mesh.surface_add_vertex(Vector3(x, 0.01, world.height))
	for z in range(world.height + 1):
		mesh.surface_add_vertex(Vector3(0.0, 0.01, z))
		mesh.surface_add_vertex(Vector3(world.width, 0.01, z))
	mesh.surface_end()

	var instance := MeshInstance3D.new()
	instance.name = "Grid"
	instance.mesh = mesh
	add_child(instance)


func _build_walls(world: SnakeWorld) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = GameConfig.WALL_COLOR
	material.roughness = 0.8

	var width := float(world.width)
	var height := float(world.height)
	var half := WALL_THICKNESS / 2.0
	var walls := [
		{"size": Vector3(width + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS),
		 "pos": Vector3(width / 2.0, WALL_HEIGHT / 2.0, -half)},
		{"size": Vector3(width + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS),
		 "pos": Vector3(width / 2.0, WALL_HEIGHT / 2.0, height + half)},
		{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, height),
		 "pos": Vector3(-half, WALL_HEIGHT / 2.0, height / 2.0)},
		{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, height),
		 "pos": Vector3(width + half, WALL_HEIGHT / 2.0, height / 2.0)},
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
	_segment_mesh = BoxMesh.new()
	_segment_mesh.size = Vector3.ONE * SEGMENT_SIZE
	_head_mesh = BoxMesh.new()
	_head_mesh.size = Vector3.ONE * HEAD_SIZE

	_head_material = StandardMaterial3D.new()
	_head_material.albedo_color = GameConfig.SNAKE_HEAD_COLOR
	_head_material.emission_enabled = true
	_head_material.emission = GameConfig.SNAKE_HEAD_COLOR
	_head_material.emission_energy_multiplier = 0.15

	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3.ONE * 0.18
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
	food_mesh.size = Vector3.ONE * FOOD_SIZE
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
		instance.mesh = _segment_mesh
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
	var head: Vector2i = world.head()
	var forward := Vector3(world.direction.x, 0.0, world.direction.y)
	var side := forward.cross(Vector3.UP)
	var center := Vector3(head.x + 0.5, 0.45, head.y + 0.5)
	for index in range(_eyes.size()):
		var sign_value := -1.0 if index == 0 else 1.0
		_eyes[index].position = (
			center + forward * 0.44 + side * (0.22 * sign_value) + Vector3(0.0, 0.16, 0.0)
		)
