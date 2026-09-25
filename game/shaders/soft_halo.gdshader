shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

// A soft round pool of coloured light lying on the floor: under every gem,
// and as the shockwave of an explosion. The colour comes from the instance
// (or the material), its alpha from how strong the pool should be.

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 0 draws a filled pool, higher values hollow it out into a ring.
uniform float hollow : hint_range(0.0, 1.0) = 0.0;
uniform float strength = 1.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 centred = UV * 2.0 - 1.0;
	float radius = length(centred);
	float pool = smoothstep(1.0, 0.0, radius);
	if (hollow > 0.0) {
		float band = 1.0 - smoothstep(0.0, 0.18, abs(radius - (1.0 - 0.2)));
		pool = mix(pool, band, hollow);
	}
	vec4 c = color * tint;
	ALBEDO = c.rgb * pool * c.a * strength;
	ALPHA = 1.0;
}
