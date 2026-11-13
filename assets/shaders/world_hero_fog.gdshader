shader_type fog;

uniform vec3 hero_anchor = vec3(0.0, 1.0, -15.0);
uniform vec3 haze_albedo = vec3(0.92, 0.91, 0.88);
uniform vec3 haze_glow = vec3(0.78, 0.84, 0.91);
uniform float glow_strength = 3.2;
uniform float clear_radius = 20.0;
uniform float clear_onset_pad = 42.0;
uniform float thick_radius = 130.0;
uniform float outer_radius = 300.0;
uniform float max_density = 0.09;
uniform int falloff_kind = 1;

float smooth01(float d, float begin, float end, int kind) {
	if (d <= begin) {
		return 0.0;
	}
	if (d >= end) {
		return 1.0;
	}
	float span = max(end - begin, 0.001);
	float t = clamp((d - begin) / span, 0.0, 1.0);
	if (kind == 0) {
		return t;
	}
	if (kind == 1) {
		return t * t * (3.0 - 2.0 * t);
	}
	return 1.0 - exp(-3.5 * t);
}

float density_for_distance(float d) {
	if (d <= clear_radius) {
		return 0.0;
	}
	float pad = max(clear_onset_pad, 8.0);
	float onset = smooth01(d, clear_radius, clear_radius + pad, 1);
	if (onset <= 0.0) {
		return 0.0;
	}
	float outer = max(outer_radius, thick_radius + 1.0);
	if (d >= outer) {
		return 0.0;
	}
	float rise = smooth01(d, clear_radius, thick_radius, falloff_kind);
	float fall = 1.0 - smooth01(d, thick_radius, outer, 1);
	return max_density * onset * rise * fall;
}

void fog() {
	vec3 wp = WORLD_POSITION;
	float d = distance(vec2(wp.x, wp.z), vec2(hero_anchor.x, hero_anchor.z));
	float dens = max(0.0, density_for_distance(d));
	DENSITY = dens;
	ALBEDO = haze_albedo;
	EMISSION = haze_glow * dens * glow_strength;
}
