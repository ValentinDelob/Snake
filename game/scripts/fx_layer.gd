class_name FxLayer
extends Node3D

## The juice: everything that happens for a moment and then goes away.
##
## Sparks thrown when a gem is swallowed, a burst and a shockwave when a
## snake dies or comes back, confetti out of a crate, sparks behind a
## boosted snake and pollen drifting in the sunlight. None of it touches the
## rules: this layer only ever reads positions and colours.
##
## Emitters are pooled and reused round-robin, so a frantic minute costs no
## more than a quiet one and nothing is ever created mid-round.

const SMALL_POOL := 12
const BIG_POOL := 5
const RING_POOL := 5
const RING_LIFE := 0.7
const HALO_SHADER := "res://shaders/soft_halo.gdshader"

var _small: Array[GPUParticles3D] = []
var _big: Array[GPUParticles3D] = []
var _next_small := 0
var _next_big := 0
var _rings: Array[Dictionary] = []   # { "mesh", "material", "age", "size" }
var _next_ring := 0
var _trails: Dictionary = {}          # snake id -> GPUParticles3D
var _pollen: GPUParticles3D
var _spark_mesh: QuadMesh
var _ring_mesh: PlaneMesh
var _bursts_played := 0


func _ready() -> void:
	_spark_mesh = _make_spark_mesh(0.14)
	for _index in range(SMALL_POOL):
		_small.append(_make_burst(GameConfig.BURST_EAT_SPARKS, 0.55))
	for _index in range(BIG_POOL):
		_big.append(_make_burst(GameConfig.BURST_BIG_SPARKS, 1.1))

	_ring_mesh = PlaneMesh.new()
	_ring_mesh.size = Vector2(2.0, 2.0)
	var shader: Shader = load(HALO_SHADER)
	for _index in range(RING_POOL):
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("hollow", 1.0)
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh
		ring.material_override = material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		add_child(ring)
		_rings.append({"mesh": ring, "material": material, "age": -1.0, "size": 1.0})


## How many bursts have gone off since the board was built. The self-test
## reads it to make sure eating and dying really throw something.
func bursts_played() -> int:
	return _bursts_played


# --------------------------------------------------------------------------- #
# Bursts
# --------------------------------------------------------------------------- #
## A handful of sparks where a gem was swallowed, in the colour of the gem.
func eat_burst(at: Vector2, color: Color) -> void:
	var emitter := _small[_next_small]
	_next_small = (_next_small + 1) % _small.size()
	_fire(emitter, Vector3(at.x, 0.6, at.y), color, 0.0)


## A big one: a snake bursting, a crate opening, a snake coming back.
## Confetti throws every colour at once instead of one.
func big_burst(at: Vector2, color: Color, confetti: bool = false) -> void:
	var emitter := _big[_next_big]
	_next_big = (_next_big + 1) % _big.size()
	_fire(emitter, Vector3(at.x, 0.7, at.y), color, 1.0 if confetti else 0.06)


## A ring of light racing out over the floor.
func shockwave(at: Vector2, color: Color, size: float = 6.0) -> void:
	var ring: Dictionary = _rings[_next_ring]
	_next_ring = (_next_ring + 1) % _rings.size()
	ring["age"] = 0.0
	ring["size"] = size
	var mesh: MeshInstance3D = ring["mesh"]
	mesh.position = Vector3(at.x, 0.06, at.y)
	mesh.visible = true
	ring["material"].set_shader_parameter("color", Color(color.r, color.g, color.b, 1.0))


func _fire(emitter: GPUParticles3D, at: Vector3, color: Color, hue_spread: float) -> void:
	var process := emitter.process_material as ParticleProcessMaterial
	# HDR on purpose: brighter than white is what the bloom picks out, and it
	# is what keeps a spark visible over a sunlit floor.
	process.color = Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 1.0)
	process.hue_variation_min = -hue_spread
	process.hue_variation_max = hue_spread
	emitter.position = at
	emitter.restart()
	emitter.emitting = true
	_bursts_played += 1


func _process(delta: float) -> void:
	for ring: Dictionary in _rings:
		if ring["age"] < 0.0:
			continue
		ring["age"] += delta
		var ratio: float = ring["age"] / RING_LIFE
		var mesh: MeshInstance3D = ring["mesh"]
		if ratio >= 1.0:
			ring["age"] = -1.0
			mesh.visible = false
			continue
		# Fast out, slowing down, fading as it goes.
		var eased := 1.0 - pow(1.0 - ratio, 3.0)
		var radius: float = 0.4 + eased * float(ring["size"])
		mesh.scale = Vector3(radius, 1.0, radius)
		ring["material"].set_shader_parameter("strength", 1.6 * (1.0 - ratio))


# --------------------------------------------------------------------------- #
# Trails and pollen
# --------------------------------------------------------------------------- #
## Sparks streaming off the head of a boosted snake. Each snake has its own
## emitter, made the first time it boosts.
func trail(id: int, at: Vector3, color: Color, active: bool) -> void:
	var emitter: GPUParticles3D = _trails.get(id)
	var wanted := active and GameConfig.effects_full
	if emitter == null:
		if not wanted:
			return
		emitter = _make_trail()
		_trails[id] = emitter
	emitter.position = at
	if emitter.emitting != wanted:
		var process := emitter.process_material as ParticleProcessMaterial
		process.color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 1.0)
		emitter.emitting = wanted


func drop_trail(id: int) -> void:
	if _trails.has(id):
		_trails[id].queue_free()
		_trails.erase(id)


## Specks of pollen hanging in the light over the whole arena.
func set_arena(arena_width: float, arena_height: float) -> void:
	if _pollen != null:
		_pollen.queue_free()
	_pollen = GPUParticles3D.new()
	_pollen.name = "Pollen"
	_pollen.amount = mini(
		GameConfig.POLLEN_MAX, int(arena_width * arena_height / GameConfig.POLLEN_PER_AREA)
	)
	_pollen.lifetime = 9.0
	_pollen.preprocess = 9.0
	_pollen.randomness = 0.8
	_pollen.visibility_aabb = AABB(
		Vector3(-arena_width * 0.5 - 2.0, -1.0, -arena_height * 0.5 - 2.0),
		Vector3(arena_width + 4.0, 8.0, arena_height + 4.0)
	)
	_pollen.position = Vector3(arena_width * 0.5, 0.0, arena_height * 0.5)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(arena_width * 0.5, 2.2, arena_height * 0.5)
	process.emission_shape_offset = Vector3(0.0, 2.6, 0.0)
	process.direction = Vector3(0.3, 1.0, 0.1)
	process.spread = 60.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	process.gravity = Vector3(0.0, 0.02, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_scale = 6.0
	process.scale_min = 0.25
	process.scale_max = 0.8
	process.color = Color(
		GameConfig.POLLEN_COLOR.r * 1.6, GameConfig.POLLEN_COLOR.g * 1.6,
		GameConfig.POLLEN_COLOR.b * 1.6, 1.0
	)
	process.alpha_curve = _fade_in_out()
	_pollen.process_material = process
	_pollen.draw_pass_1 = _make_spark_mesh(0.09)
	_pollen.visible = GameConfig.effects_full
	add_child(_pollen)


## The effects setting changed: the pollen and trails follow it at once.
func apply_setting() -> void:
	if _pollen != null:
		_pollen.visible = GameConfig.effects_full
	if not GameConfig.effects_full:
		for id: int in _trails:
			_trails[id].emitting = false


# --------------------------------------------------------------------------- #
# Building blocks
# --------------------------------------------------------------------------- #
func _make_burst(amount: int, life: float) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.25
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 80.0
	process.initial_velocity_min = 2.5
	process.initial_velocity_max = 6.5
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.damping_min = 1.5
	process.damping_max = 3.0
	process.scale_min = 0.5
	process.scale_max = 1.4
	process.scale_curve = _shrink()

	var emitter := GPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = life
	emitter.one_shot = true
	emitter.explosiveness = 0.95
	emitter.randomness = 0.5
	emitter.emitting = false
	emitter.local_coords = false
	emitter.process_material = process
	emitter.draw_pass_1 = _spark_mesh
	emitter.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 10, 16))
	add_child(emitter)
	return emitter


func _make_trail() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.3
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 1.0
	process.gravity = Vector3(0.0, 0.6, 0.0)
	process.scale_min = 0.4
	process.scale_max = 1.0
	process.scale_curve = _shrink()

	var emitter := GPUParticles3D.new()
	emitter.amount = 48
	emitter.lifetime = 0.8
	emitter.local_coords = false
	emitter.emitting = false
	emitter.process_material = process
	emitter.draw_pass_1 = _spark_mesh
	emitter.visibility_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 10, 80))
	add_child(emitter)
	return emitter


## A small glowing star, always facing the camera.
func _make_spark_mesh(size: float) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _star_texture()
	# Fog would be added to every pixel of an additive quad, turning a round
	# spark into a pale square at a distance.
	material.disable_fog = true
	material.disable_receive_shadows = true
	mesh.material = material
	return mesh


## A soft round dot with a hot centre, drawn once into a small texture.
static func _star_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.25, Color(1, 1, 1, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture


static func _shrink() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _fade_in_out() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.8, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture
