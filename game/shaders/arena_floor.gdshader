shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

// The arena floor: warm sand in a sunlit lagoon.
//
// Soft tiles are drawn by the shader instead of line geometry, so they stay
// crisp at any distance. Over them runs rippling light, the kind shallow
// water throws on a sunny bottom - it moves all the time, so the floor is
// alive even when nothing is on it. The edges blush towards the ramparts,
// and a boosted snake lights a pool of colour under itself.

uniform vec3 base_color : source_color = vec3(0.97, 0.86, 0.69);
uniform vec3 line_color : source_color = vec3(0.91, 0.73, 0.57);
uniform vec3 caustic_color : source_color = vec3(1.0, 0.98, 0.9);
uniform vec3 edge_color : source_color = vec3(0.99, 0.7, 0.62);
uniform vec3 glow_color : source_color = vec3(1.0, 0.86, 0.28);
uniform vec2 arena_size = vec2(30.0, 20.0);
uniform float cell = 3.0;
uniform float line_strength : hint_range(0.0, 1.0) = 0.55;
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.22;

uniform vec2 head_position = vec2(15.0, 10.0);
uniform float head_glow : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Two layers of drifting sine ripples, folded so the bright lines are thin
// and the dark between them wide - cheap, and it reads as caustics.
float caustics(vec2 p, float t) {
	vec2 a = p * 0.33 + vec2(t * 0.11, t * 0.07);
	vec2 b = p * 0.47 - vec2(t * 0.06, -t * 0.09);
	float wave = sin(a.x + sin(a.y * 1.3 + t * 0.4) * 1.6)
		+ sin(a.y * 1.1 + sin(a.x * 0.9 - t * 0.3) * 1.4)
		+ sin((b.x + b.y) * 1.2 + sin(b.x * 1.7 + t * 0.5));
	float ridge = 1.0 - abs(wave) / 3.0;
	return pow(clamp(ridge, 0.0, 1.0), 7.0);
}

void fragment() {
	vec2 ground = world_position.xz;

	// Rounded tiles: the distance to the cell edge is shaped into a soft
	// groove rather than a hairline, anti-aliased on the screen derivative.
	vec2 local = abs(fract(ground / cell) - 0.5) * 2.0;
	float edge_distance = 1.0 - max(local.x, local.y);
	float width = fwidth(ground.x / cell) * 2.5 + 0.06;
	float groove = 1.0 - smoothstep(0.0, width, edge_distance);
	// A faint dome on every tile, so the grid reads as paving, not paper.
	float dome = 1.0 - dot(local, local) * 0.08;

	vec2 centred = (ground / arena_size - 0.5) * 2.0;
	float edge = clamp(max(abs(centred.x), abs(centred.y)), 0.0, 1.0);
	float blush = smoothstep(0.78, 1.0, edge);

	vec3 color = base_color * dome;
	color = mix(color, line_color, groove * line_strength);
	color = mix(color, edge_color, blush * 0.4);

	float light = caustics(ground, TIME) * caustic_strength * (1.0 - blush * 0.5);

	float distance_to_head = distance(ground, head_position);
	float pool = smoothstep(5.0, 0.0, distance_to_head) * head_glow;

	ALBEDO = color + caustic_color * light * 0.3;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	EMISSION = caustic_color * light * 0.2 + glow_color * pool * 0.6;
}
