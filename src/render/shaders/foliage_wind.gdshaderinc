// SD-WIND-1 shared vertex breeze (consumers set uniforms).

uniform float wind_phase = 0.0;
uniform float wind_strength = 0.0;
uniform vec2 wind_direction_xz = vec2(1.0, 0.0);
uniform float wind_freq_scale = 1.0;
uniform float wind_amplitude = 0.08;


void foliage_wind_displace(inout vec3 vertex, float height_weight, float instance_hash) {
	if (wind_strength < 0.001) {
		return;
	}
	float h = clamp(height_weight, 0.0, 1.0);
	vec3 dir = normalize(vec3(wind_direction_xz.x, 0.03, wind_direction_xz.y));
	float ph = wind_phase * wind_freq_scale + instance_hash;
	float sway = sin(ph) * 0.65 + sin(ph * 2.41 + instance_hash * 6.28) * 0.35;
	vertex += dir * sway * wind_strength * wind_amplitude * h;
}
