shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The snake skin.
//
// UV.x runs from the nose (0) to the tail tip (1), UV.y goes around the
// body, which is everything the look needs: the length drives the colour
// gradient and the electric bands of the boost, the angle drives the belly
// and the scales.

uniform vec3 head_color : source_color = vec3(0.47, 1.0, 0.59);
uniform vec3 body_color : source_color = vec3(0.0, 0.78, 0.35);
uniform vec3 tail_color : source_color = vec3(0.0, 0.33, 0.18);
uniform vec3 belly_color : source_color = vec3(0.78, 0.95, 0.7);
uniform vec3 boost_color : source_color = vec3(1.0, 0.86, 0.28);
uniform vec3 spark_color : source_color = vec3(1.0, 0.98, 0.78);

uniform float boost : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float bands = 7.0;
uniform float band_speed = 2.2;
uniform float scale_density = 42.0;

const float TAU_ = 6.28318530718;

varying float along;
varying float around;

void vertex() {
	along = UV.x;
	around = UV.y;
}

void fragment() {
	// Head to tail gradient, the same one the game has always had.
	vec3 base = mix(head_color, body_color, smoothstep(0.0, 0.15, along));
	base = mix(base, tail_color, pow(clamp((along - 0.15) / 0.85, 0.0, 1.0), 0.65));

	// A paler belly, fading out on the flanks.
	float belly = smoothstep(0.22, 0.0, abs(around - 0.75));
	base = mix(base, belly_color * 0.75, belly * 0.5);

	// Diamond scales: a couple of percent of shading, just enough to catch
	// the light and stop the body reading as plastic.
	float scales = sin(along * scale_density) * sin(around * TAU_ * 5.0);
	base *= 0.97 + 0.03 * scales;

	ALBEDO = base;
	ROUGHNESS = mix(0.55, 0.25, belly);
	SPECULAR = 0.55;
	METALLIC = 0.0;

	// Rim light: a thin bright edge that separates the snake from the floor.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.5);
	vec3 emission = base * rim * 0.22;

	// The head always glows a little, more so right after a bite.
	float head_mask = smoothstep(0.14, 0.0, along);
	emission += head_color * head_mask * (0.03 + flash * 0.4);

	// Lightning running down the body while the boost is on.
	float wave = sin((along * bands - TIME * band_speed) * TAU_);
	float spark = pow(max(wave, 0.0), 5.0) * boost;
	vec3 electric = mix(boost_color, spark_color, spark);
	emission += electric * (spark * 1.45 + boost * 0.25);
	ALBEDO = mix(ALBEDO, electric, clamp(spark * 0.45, 0.0, 1.0));

	EMISSION = emission;
}
