shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The lagoon around the arena: shallow turquoise water close to the sand,
// deeper blue further out, with slow swells and glittering sun sparkles.
// The arena reads as an island, and the empty frame around the overview
// camera becomes part of the picture instead of a flat colour.

uniform vec3 shallow_color : source_color = vec3(0.2, 0.85, 0.85);
uniform vec3 deep_color : source_color = vec3(0.05, 0.45, 0.75);
uniform vec3 foam_color : source_color = vec3(0.95, 1.0, 1.0);
uniform vec2 arena_size = vec2(84.0, 56.0);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float swell(vec2 p, float t) {
	return sin(p.x * 0.35 + t * 0.8) * 0.5 + sin(p.y * 0.28 - t * 0.6) * 0.5
		+ sin((p.x + p.y) * 0.18 + t * 0.4) * 0.5;
}

void fragment() {
	vec2 ground = world_position.xz;
	// How far out from the edge of the island, in units.
	vec2 outside = max(abs(ground - arena_size * 0.5) - arena_size * 0.5, vec2(0.0));
	float away = length(outside);

	float depth = smoothstep(0.0, 28.0, away);
	vec3 color = mix(shallow_color, deep_color, depth);

	// A ring of surf hugging the island, breathing in and out.
	float surf = smoothstep(2.2, 0.0, abs(away - 1.2 - 0.6 * sin(TIME * 1.3)));

	// Sun glitter: tiny bright ridges where the swells cross.
	// Two swells at unrelated scales, multiplied: the crossings are rare and
	// scattered instead of a regular grid of blobs.
	float crossing = max(swell(ground * 2.3, TIME * 1.4), 0.0) * max(swell(ground.yx * 3.7 + 11.0, TIME * 1.1), 0.0);
	float glitter = pow(crossing / 2.25, 10.0);

	ALBEDO = mix(color, foam_color, surf * 0.7);
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	EMISSION = foam_color * (glitter * 0.6 + surf * 0.15) + color * 0.12;
}
