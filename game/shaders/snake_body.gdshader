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
uniform vec3 frost_color : source_color = vec3(0.48, 0.78, 1.0);
uniform vec3 frost_pale_color : source_color = vec3(0.85, 0.95, 1.0);

uniform float boost : hint_range(0.0, 1.0) = 0.0;
uniform float slow : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float phase : hint_range(0.0, 1.0) = 0.0;
uniform vec3 phase_color : source_color = vec3(1.0, 0.93, 0.36);
uniform vec3 phase_pale_color : source_color = vec3(1.0, 0.99, 0.82);
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

	// A saddle of bright spots running down the back, in the head colour:
	// it is the pattern that makes a tube read as a snake, and it gives each
	// palette a second colour to show off.
	float back = smoothstep(0.2, 0.0, abs(around - 0.25));
	float spots = smoothstep(0.35, 0.8, 0.5 + 0.5 * sin(along * 58.0));
	base = mix(base, head_color * 1.08, back * spots * 0.45 * smoothstep(0.08, 0.2, along));

	// Diamond scales: a couple of percent of shading, just enough to catch
	// the light and stop the body reading as plastic.
	float scales = sin(along * scale_density) * sin(around * TAU_ * 5.0);
	base *= 0.97 + 0.03 * scales;

	// Frost creeping over the skin while the snake is slowed: cold, patchy,
	// and dull rather than shiny, so a curse never looks like a reward.
	if (slow > 0.0) {
		float patches = 0.5 + 0.5 * sin(along * 26.0 + around * TAU_ * 3.0);
		float frost = clamp(slow * (0.45 + 0.55 * patches), 0.0, 1.0);
		base = mix(base, mix(frost_color, frost_pale_color, patches), frost * 0.85);
	}

	ALBEDO = base;
	ROUGHNESS = mix(0.38, 0.22, belly) + slow * 0.3;
	SPECULAR = 0.7;
	METALLIC = 0.0;

	// Rim light: a thin bright edge that separates the snake from the floor.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.5);
	// Whiter than the skin, so the silhouette pops off a bright floor.
	vec3 emission = mix(base, vec3(1.0), 0.35) * rim * 0.3;

	// A slow shimmer of light travelling from head to tail, all the time:
	// the body is always a little alive, even cruising.
	float pulse = pow(max(sin((along * 3.0 - TIME * 0.7) * TAU_), 0.0), 8.0);
	emission += mix(body_color, head_color, 0.6) * pulse * 0.18;

	// The head always glows a little, more so right after a bite.
	float head_mask = smoothstep(0.14, 0.0, along);
	emission += head_color * head_mask * (0.03 + flash * 0.4);

	// Lightning running down the body while the boost is on.
	float wave = sin((along * bands - TIME * band_speed) * TAU_);
	float spark = pow(max(wave, 0.0), 5.0) * boost;
	vec3 electric = mix(boost_color, spark_color, spark);
	emission += electric * (spark * 1.45 + boost * 0.25);
	ALBEDO = mix(ALBEDO, electric, clamp(spark * 0.45, 0.0, 1.0));

	emission *= 1.0 - slow * 0.6;
	emission += frost_color * slow * 0.12;

	// The ghost ring: for one second the snake is barely there. It turns
	// gold, thins out until the floor shows through it, and the rim burns,
	// so the second it lasts is unmistakable from any camera.
	if (phase > 0.0) {
		float shimmer = 0.5 + 0.5 * sin(along * 30.0 - TIME * 9.0);
		vec3 ghost = mix(phase_color, phase_pale_color, shimmer);
		ALBEDO = mix(ALBEDO, ghost, phase * 0.8);
		emission += ghost * phase * (0.5 + rim * 1.6);
		ALPHA = mix(1.0, 0.42, phase);
	}
	EMISSION = emission;
}
