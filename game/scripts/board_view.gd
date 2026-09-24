class_name BoardView
extends Node3D

## Everything visible on the arena: floor, ramparts, items and the snakes.
##
## The static geometry is built once. Each snake gets its own procedural tube
## and pair of eyes, created the first time it is seen and kept afterwards,
## so a match with several players costs no more per frame than one.

const FLOOR_SHADER := "res://shaders/arena_floor.gdshader"
const FLASH_DURATION := 0.45
const WALL_HEIGHT := 0.8
const WALL_THICKNESS := 0.4
const BODY_HEIGHT := 0.4

var _floor_material: ShaderMaterial
var _head_lamp: OmniLight3D
var _bolt: MeshInstance3D
var _bolt_lamp: OmniLight3D
var _crate: MeshInstance3D
var _crate_lamp: OmniLight3D
var _crate_material: StandardMaterial3D
var _food: MeshInstance3D
var _flash_ring: MeshInstance3D
var _flash_material: StandardMaterial3D
var _flash_time := -1.0
var _flash_color := GameConfig.SPARK_COLOR

## id -> { "mesh": SnakeMesh, "eyes": Array }
var _snakes: Dictionary = {}
var _rocks: Node3D
var _rock_material: StandardMaterial3D
var _eye_mesh: SphereMesh
var _eye_material: StandardMaterial3D


func build(arena_width: float, arena_height: float) -> void:
	for child in get_children():
		child.queue_free()
	_snakes.clear()

	_build_floor(arena_width, arena_height)
	_build_walls(arena_width, arena_height)
	_build_props()
	_rocks = Node3D.new()
	_rocks.name = "Rocks"
	add_child(_rocks)
	Journal.info("board", "Board built for a %.0fx%.0f arena" % [arena_width, arena_height])


## How many triangles a snake's body is made of right now. Used by the
## self-test to check the graphics modes really differ.
func face_count(id: int) -> int:
	if not _snakes.has(id):
		return 0
	var mesh: SnakeMesh = _snakes[id]["mesh"]
	return mesh.face_count()


## Reshape every snake and move the props to match the current match.
func refresh(game_match: SnakeMatch, local_id: int, elapsed: float, flash: float) -> void:
	var order: Array = game_match.snakes.keys()
	order.sort()

	for id: int in order:
		var snake: SnakeWorld = game_match.snakes[id]
		var visual := _visual_for(id, order.find(id), id == local_id)
		var mesh: SnakeMesh = visual["mesh"]
		mesh.visible = snake.alive
		for eye: MeshInstance3D in visual["eyes"]:
			eye.visible = snake.alive
		if not snake.alive:
			continue
		mesh.rebuild(snake, BODY_HEIGHT)
		mesh.set_effects(snake.boost_intensity(), snake.slow_intensity())
		mesh.set_flash(flash if id == local_id else 0.0)
		_place_eyes(visual["eyes"], snake)

	for id: int in _snakes.keys():
		if not game_match.snakes.has(id):
			_drop_visual(id)

	_refresh_lighting(game_match.snakes.get(local_id), game_match)
	_refresh_items(game_match, elapsed)
	_refresh_flash(elapsed)


# --------------------------------------------------------------------------- #
# Snakes
# --------------------------------------------------------------------------- #
func _visual_for(id: int, index: int, is_local: bool) -> Dictionary:
	if _snakes.has(id):
		return _snakes[id]

	var palette: Array = GameConfig.palette_for(0 if is_local else maxi(1, index))
	var mesh := SnakeMesh.new()
	mesh.name = "Snake%d" % id
	add_child(mesh)
	mesh.set_palette(palette[0], palette[1], palette[2])

	var eyes: Array[MeshInstance3D] = []
	for _index in range(2):
		var eye := MeshInstance3D.new()
		eye.mesh = _eye_mesh
		eye.material_override = _eye_material
		add_child(eye)
		eyes.append(eye)

	_snakes[id] = {"mesh": mesh, "eyes": eyes}
	return _snakes[id]


func _drop_visual(id: int) -> void:
	var visual: Dictionary = _snakes[id]
	visual["mesh"].queue_free()
	for eye: MeshInstance3D in visual["eyes"]:
		eye.queue_free()
	_snakes.erase(id)


func _place_eyes(eyes: Array, snake: SnakeWorld) -> void:
	var forward := Vector3(snake.direction().x, 0.0, snake.direction().y)
	var side := forward.cross(Vector3.UP)
	var center := Vector3(snake.head_position.x, BODY_HEIGHT, snake.head_position.y)
	# The eyes must sit on the skin of the tube, not inside it, so they are
	# pushed out along a direction and not along each axis separately.
	var bulge := GameConfig.SNAKE_RADIUS * GameConfig.HEAD_BULGE
	for index in range(eyes.size()):
		var sign_value := -1.0 if index == 0 else 1.0
		var outwards := (
			forward * 0.45 + side * (0.78 * sign_value) + Vector3.UP * 0.58
		).normalized()
		eyes[index].position = center + outwards * (bulge * 0.95)


# --------------------------------------------------------------------------- #
# Lighting and props
# --------------------------------------------------------------------------- #
## Feed the floor shader and the head lamp. Both follow whatever effect is
## running on the local snake: warm while boosted, cold while slowed.
func _refresh_lighting(local, game_match: SnakeMatch) -> void:
	_floor_material.set_shader_parameter(
		"arena_size", Vector2(game_match.width, game_match.height)
	)
	if local == null or not local.alive:
		_head_lamp.light_energy = 0.0
		_floor_material.set_shader_parameter("head_glow", 0.0)
		return

	var boost: float = local.boost_intensity()
	var slow: float = local.slow_intensity()
	var glow: float = maxf(boost, slow * 0.8)
	var tint := GameConfig.BOOST_COLOR if boost >= slow else GameConfig.FROST_COLOR

	_floor_material.set_shader_parameter("head_position", local.head_position)
	_floor_material.set_shader_parameter("head_glow", glow)
	_floor_material.set_shader_parameter("glow_color", tint)

	var ahead: Vector2 = local.direction() * 0.6
	_head_lamp.position = Vector3(
		local.head_position.x + ahead.x, 1.7, local.head_position.y + ahead.y
	)
	var lamp_color := GameConfig.SNAKE_HEAD_COLOR.lerp(GameConfig.SPARK_COLOR, boost)
	lamp_color = lamp_color.lerp(GameConfig.FROST_COLOR, slow)
	_head_lamp.light_color = lamp_color
	_head_lamp.light_energy = 0.15 + boost * 1.7 + slow * 0.9


func _refresh_items(game_match: SnakeMatch, elapsed: float) -> void:
	_food.position = Vector3(
		game_match.food.x, 0.5 + 0.08 * sin(elapsed * 4.0), game_match.food.y
	)
	_food.rotation.y = elapsed * 1.6

	var has_bolt := game_match.has_ground(SnakeWorld.Ground.BOLT)
	_bolt.visible = has_bolt
	_bolt_lamp.visible = has_bolt
	if has_bolt:
		var spot := game_match.ground_position(SnakeWorld.Ground.BOLT)
		_bolt.position = Vector3(spot.x, 0.75 + 0.1 * sin(elapsed * 2.6), spot.y)
		_bolt.rotation.y = elapsed * 1.4
		_bolt_lamp.position = _bolt.position
		# A slow throb, so the bolt catches the eye across a dark arena.
		_bolt_lamp.light_energy = 0.9 + 0.35 * sin(elapsed * 3.0)

	var has_crate := game_match.has_ground(SnakeWorld.Ground.MYSTERY)
	_crate.visible = has_crate
	_crate_lamp.visible = has_crate
	if has_crate:
		var spot := game_match.ground_position(SnakeWorld.Ground.MYSTERY)
		_crate.position = Vector3(spot.x, 0.85 + 0.12 * sin(elapsed * 2.0), spot.y)
		# Tilted back towards the cameras, which all look down at the arena,
		# and turning slowly so the mark stays readable.
		_crate.rotation = Vector3(-1.0, elapsed * 0.7, 0.0)
		# The colour drifts: you cannot tell what is inside by looking at it.
		var drift := 0.5 + 0.5 * sin(elapsed * 1.6)
		var color := GameConfig.MYSTERY_COLOR.lerp(GameConfig.FROST_COLOR, drift)
		_crate_material.albedo_color = color
		_crate_material.emission = color
		_crate_lamp.position = _crate.position
		_crate_lamp.light_color = color
		_crate_lamp.light_energy = 0.8 + 0.3 * sin(elapsed * 2.4)


## Small, quick ring where something was collected.
func play_pickup_flash(at: Vector2, elapsed: float, color: Color = GameConfig.SPARK_COLOR) -> void:
	_flash_time = elapsed
	_flash_color = color
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
		_flash_color.r, _flash_color.g, _flash_color.b, 0.75 * (1.0 - ratio)
	)


# --------------------------------------------------------------------------- #
# Static geometry
# --------------------------------------------------------------------------- #
func _build_floor(arena_width: float, arena_height: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(arena_width, arena_height)
	# The grid is drawn by the shader, but it needs vertices to interpolate
	# the world position across.
	plane.subdivide_width = 8
	plane.subdivide_depth = 8

	_floor_material = ShaderMaterial.new()
	_floor_material.shader = load(FLOOR_SHADER)
	_floor_material.set_shader_parameter("base_color", GameConfig.FLOOR_COLOR)
	_floor_material.set_shader_parameter("line_color", GameConfig.GRID_COLOR)
	_floor_material.set_shader_parameter("glow_color", GameConfig.BOOST_COLOR)
	_floor_material.set_shader_parameter("arena_size", Vector2(arena_width, arena_height))

	var instance := MeshInstance3D.new()
	instance.name = "Floor"
	instance.mesh = plane
	instance.material_override = _floor_material
	instance.position = Vector3(arena_width * 0.5, 0.0, arena_height * 0.5)
	add_child(instance)


## Raise the round's rocks. They only change between rounds, so they are
## built once here rather than touched every frame.
func set_obstacles(obstacles: Array) -> void:
	if _rocks == null:
		return
	for child in _rocks.get_children():
		child.queue_free()

	if _rock_material == null:
		_rock_material = StandardMaterial3D.new()
		_rock_material.albedo_color = GameConfig.OBSTACLE_COLOR
		_rock_material.roughness = 0.9
		_rock_material.metallic = 0.05

	for index in range(obstacles.size()):
		var rock: Dictionary = obstacles[index]
		var radius: float = rock["radius"]
		# A tapered prism with few sides reads as stone from any camera, and
		# the taper keeps the top from hiding what is behind it.
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = radius
		mesh.top_radius = radius * 0.62
		mesh.height = 0.9 + radius * 0.75
		mesh.radial_segments = int(rock["sides"])
		mesh.rings = 1

		var instance := MeshInstance3D.new()
		instance.name = "Rock%d" % index
		instance.mesh = mesh
		instance.material_override = _rock_material
		instance.position = Vector3(
			rock["position"].x, mesh.height * 0.5, rock["position"].y
		)
		instance.rotation.y = rock["spin"]
		_rocks.add_child(instance)
	Journal.debug("board", "Raised %d rock(s)" % obstacles.size())


func _build_walls(arena_width: float, arena_height: float) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = GameConfig.WALL_COLOR.darkened(0.2)
	material.roughness = 0.65

	var half := WALL_THICKNESS / 2.0
	var walls := [
		{"size": Vector3(arena_width + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS),
		 "pos": Vector3(arena_width / 2.0, WALL_HEIGHT / 2.0, -half)},
		{"size": Vector3(arena_width + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS),
		 "pos": Vector3(arena_width / 2.0, WALL_HEIGHT / 2.0, arena_height + half)},
		{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, arena_height),
		 "pos": Vector3(-half, WALL_HEIGHT / 2.0, arena_height / 2.0)},
		{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, arena_height),
		 "pos": Vector3(arena_width + half, WALL_HEIGHT / 2.0, arena_height / 2.0)},
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


func _build_props() -> void:
	_eye_mesh = SphereMesh.new()
	_eye_mesh.radius = 0.085
	_eye_mesh.height = 0.17
	_eye_mesh.radial_segments = 8
	_eye_mesh.rings = 4
	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = GameConfig.EYE_COLOR
	_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# A light riding the head: barely there normally, electric while boosted.
	_head_lamp = OmniLight3D.new()
	_head_lamp.name = "HeadLamp"
	_head_lamp.omni_range = 7.0
	_head_lamp.light_energy = 0.0
	_head_lamp.shadow_enabled = false
	add_child(_head_lamp)

	var food_mesh := BoxMesh.new()
	food_mesh.size = Vector3.ONE * (GameConfig.FOOD_RADIUS * 1.5)
	var food_material := StandardMaterial3D.new()
	food_material.albedo_color = GameConfig.FOOD_COLOR.darkened(0.15)
	food_material.roughness = 0.35
	food_material.emission_enabled = true
	food_material.emission = GameConfig.FOOD_COLOR
	food_material.emission_energy_multiplier = 0.22

	_food = MeshInstance3D.new()
	_food.name = "Food"
	_food.mesh = food_mesh
	_food.material_override = food_material
	add_child(_food)

	_crate_material = StandardMaterial3D.new()
	_crate_material.albedo_color = GameConfig.MYSTERY_COLOR
	_crate_material.emission_enabled = true
	_crate_material.emission = GameConfig.MYSTERY_COLOR
	_crate_material.emission_energy_multiplier = 0.3

	_crate = MeshInstance3D.new()
	_crate.name = "MysteryCrate"
	_crate.mesh = _build_question_mesh()
	_crate.material_override = _crate_material
	_crate.visible = false
	add_child(_crate)

	_crate_lamp = OmniLight3D.new()
	_crate_lamp.name = "CrateLamp"
	_crate_lamp.light_color = GameConfig.MYSTERY_COLOR
	_crate_lamp.light_energy = 1.0
	_crate_lamp.omni_range = 5.0
	_crate_lamp.shadow_enabled = false
	_crate_lamp.visible = false
	add_child(_crate_lamp)

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

	_bolt_lamp = OmniLight3D.new()
	_bolt_lamp.name = "BoltLamp"
	_bolt_lamp.light_color = GameConfig.BOOST_COLOR
	_bolt_lamp.light_energy = 1.1
	_bolt_lamp.omni_range = 5.0
	_bolt_lamp.shadow_enabled = false
	_bolt_lamp.visible = false
	add_child(_bolt_lamp)

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


## A lightning bolt: a flat zigzag given a bit of thickness.
func _build_bolt_mesh() -> ArrayMesh:
	var outline := PackedVector2Array([
		Vector2(0.16, 1.0), Vector2(-0.52, 0.06), Vector2(-0.12, 0.06),
		Vector2(-0.3, -1.0), Vector2(0.52, -0.02), Vector2(0.1, -0.02),
	])
	return _extrude([_scaled(outline, 0.46)], 0.09)


## A question mark, for the crate: the hook, the stem and the dot.
func _build_question_mesh() -> ArrayMesh:
	var hook := PackedVector2Array()
	var outer := 0.52
	var inner := 0.28
	var steps := 14
	# Outer edge of the hook, sweeping over the top from left to right.
	for index in range(steps + 1):
		var angle: float = lerpf(PI * 1.05, -PI * 0.28, float(index) / steps)
		hook.append(Vector2(cos(angle) * outer, sin(angle) * outer))
	# The stem drops from the end of the hook towards the dot.
	hook.append(Vector2(0.12, -0.42))
	hook.append(Vector2(-0.12, -0.42))
	hook.append(Vector2(-0.12, -0.02))
	# Inner edge, coming back the other way.
	for index in range(steps + 1):
		var angle: float = lerpf(-PI * 0.28, PI * 1.05, float(index) / steps)
		hook.append(Vector2(cos(angle) * inner, sin(angle) * inner))

	var dot := PackedVector2Array([
		Vector2(-0.13, -0.58), Vector2(0.13, -0.58),
		Vector2(0.13, -0.84), Vector2(-0.13, -0.84),
	])
	return _extrude([_scaled(hook, 0.95), _scaled(dot, 0.95)], 0.14)


func _scaled(outline: PackedVector2Array, factor: float) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	for point: Vector2 in outline:
		scaled.append(point * factor)
	return scaled


## Turn flat polygons into a solid: two faces and a wall around each outline.
func _extrude(outlines: Array, depth: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()

	for outline: PackedVector2Array in outlines:
		var triangles := Geometry2D.triangulate_polygon(outline)
		if triangles.is_empty():
			Journal.warn("board", "A shape could not be triangulated")
			continue

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
