shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert;

// The arena floor.
//
// The grid is drawn by the shader instead of line geometry, so it stays
// crisp at any distance; the edges fall off into the dark, and the snake
// casts a coloured pool of light while it is boosted.

uniform vec3 base_color : source_color = vec3(0.13, 0.17, 0.23);
uniform vec3 line_color : source_color = vec3(0.22, 0.28, 0.36);
uniform vec3 glow_color : source_color = vec3(1.0, 0.86, 0.28);
uniform vec2 arena_size = vec2(30.0, 20.0);
uniform float cell = 2.0;
uniform float line_strength : hint_range(0.0, 1.0) = 0.45;
uniform float vignette : hint_range(0.0, 1.0) = 0.3;

uniform vec2 head_position = vec2(15.0, 10.0);
uniform float head_glow : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 ground = world_position.xz;

	// Anti-aliased grid: width follows the screen derivative, so far away
	// lines fade instead of shimmering.
	vec2 grid = abs(fract(ground / cell - 0.5) - 0.5) / fwidth(ground / cell);
	float line = 1.0 - min(min(grid.x, grid.y), 1.0);

	// Darker towards the walls, brighter in the middle of the arena.
	vec2 centred = (ground / arena_size - 0.5) * 2.0;
	float edge = clamp(1.0 - vignette * dot(centred, centred) * 0.5, 0.0, 1.0);

	vec3 color = mix(base_color, line_color, line * line_strength) * edge;

	// The boosted snake lights the ground under itself.
	float distance_to_head = distance(ground, head_position);
	float pool = smoothstep(4.0, 0.0, distance_to_head) * head_glow;

	ALBEDO = color;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	EMISSION = glow_color * pool * 0.45 + line_color * line * 0.06;
}
