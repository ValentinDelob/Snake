shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A mote of matter, cut as a little gem.
//
// The colour comes from the instance: its hue says what the mote is worth
// and its alpha carries the worth itself, which sets how hard the gem
// glows. Every facet catches a glint in turn as the gems spin, so the field
// twinkles without a single extra light.

uniform float glow_small = 0.22;
uniform float glow_big = 1.5;

varying vec4 tint;
varying vec3 facet;

void vertex() {
	tint = COLOR;
	facet = NORMAL;
}

void fragment() {
	vec3 hue = tint.rgb;
	float worth = tint.a;

	// A glint that sweeps round the facets, a little out of step on each gem.
	float sweep = sin(TIME * 3.0 + facet.x * 4.0 + facet.z * 3.0 + facet.y * 2.0);
	float glint = pow(max(sweep, 0.0), 12.0);

	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);

	ALBEDO = hue * 0.8;
	ROUGHNESS = 0.32;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	EMISSION = hue * mix(glow_small, glow_big, worth)
		+ vec3(1.0, 0.98, 0.92) * glint * (0.5 + worth * 1.0)
		+ mix(hue, vec3(1.0), 0.3) * rim * 0.3;
}
