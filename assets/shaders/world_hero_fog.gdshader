shader_type fog;

uniform vec3 hero_anchor = vec3(0.0, 1.0, -15.0);
uniform vec3 haze_albedo = vec3(0.92, 0.91, 0.88);
uniform vec3 haze_glow = vec3(0.78, 0.84, 0.91);
uniform float glow_strength = 3.2;
uniform float clear_radius = 20.0;
uniform float thick_radius = 80.0;
uniform float max_density = 0.22;
uniform int falloff_kind = 1;

float falloff_t(float d) {
	float span = max(thick_radius - clear_radius, 0.001);
	float t = clamp((d - clear_radius) / span, 0.0, 1.0);
	if (falloff_kind == 0) {
		return t;
	}
	if (falloff_kind == 1) {
		return t * t * (3.0 - 2.0 * t);
	}
	return 1.0 - exp(-3.5 * t);
}

void fog() {
	vec3 wp = WORLD_POSITION;
	float d = distance(vec2(wp.x, wp.z), vec2(hero_anchor.x, hero_anchor.z));
	float dens = max(0.0, max_density * falloff_t(d));
	DENSITY = dens;
	ALBEDO = haze_albedo;
	EMISSION = haze_glow * dens * glow_strength;
}
