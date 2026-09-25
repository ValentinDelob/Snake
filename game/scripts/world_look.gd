class_name WorldLook
extends RefCounted

## The sky, the sun and the air: everything that makes the arena a bright
## afternoon rather than a dark room.
##
## Built in code from the palette in GameConfig, so the whole look is tuned
## in one file instead of being split between it and the scene.


static func dress(world: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = GameConfig.SKY_TOP_COLOR
	sky_material.sky_horizon_color = GameConfig.SKY_HORIZON_COLOR
	sky_material.sky_curve = 0.12
	sky_material.sky_energy_multiplier = 1.1
	sky_material.ground_bottom_color = GameConfig.GROUND_HORIZON_COLOR.darkened(0.25)
	sky_material.ground_horizon_color = GameConfig.GROUND_HORIZON_COLOR
	sky_material.ground_curve = 0.06
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.08

	var sky := Sky.new()
	sky.sky_material = sky_material
	# The sky only lights, it never reflects anything sharp: a low radiance
	# size keeps it cheap.
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Light from the sky fills the shadows with blue instead of black, which
	# is most of what makes a scene read as daylight.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.5
	environment.ambient_light_sky_contribution = 0.6
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.92
	environment.tonemap_white = 3.0

	# Bloom, kept for what is truly brighter than white - the gems, the
	# bolts, a boosted snake - so a bright floor does not glow all over.
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.02
	environment.glow_hdr_threshold = 1.3
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.set_glow_level(1, 0.0)
	environment.set_glow_level(2, 1.0)
	environment.set_glow_level(3, 0.7)
	environment.set_glow_level(4, 0.4)

	# A thin warm haze: the far side of a big arena melts into the horizon
	# instead of stopping at a hard edge, which gives the chase camera depth.
	environment.fog_enabled = true
	environment.fog_light_color = GameConfig.FOG_COLOR
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.0009
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.15

	# A touch more colour than the tone mapper leaves: the palette is meant
	# to be sweet.
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.22
	environment.adjustment_contrast = 1.04

	world.environment = environment

	sun.light_color = GameConfig.SUN_COLOR
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	# Soft, blue-tinted shadows rather than black holes under everything.
	sun.shadow_opacity = 0.72
	sun.light_angular_distance = 1.5
	# Far enough for the biggest arena seen from the overview camera.
	sun.directional_shadow_max_distance = 150.0
