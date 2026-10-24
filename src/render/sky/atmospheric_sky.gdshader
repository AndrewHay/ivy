shader_type sky;
render_mode use_half_res_pass, use_debanding;

uniform vec4 sky_top_color : source_color = vec4(0.361, 0.561, 0.722, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.784, 0.851, 0.91, 1.0);
uniform float sky_curve : hint_range(0.0, 1.0) = 0.12;
uniform float sky_energy : hint_range(0.0, 4.0) = 1.4;
uniform vec4 ground_bottom_color : source_color = vec4(0.08, 0.09, 0.06, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.35, 0.38, 0.32, 1.0);
uniform float ground_curve : hint_range(0.0, 1.0) = 0.04;
uniform float ground_energy : hint_range(0.0, 4.0) = 1.0;
uniform float sun_angle_max = 0.35;
uniform float sun_curve : hint_range(0.0, 1.0) = 0.12;

uniform float cloud_cover : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.12;
uniform float cloud_plane_scale : hint_range(0.05, 1.5) = 0.34;
uniform float cloud_zenith_bias : hint_range(0.05, 0.8) = 0.32;
uniform float cloud_horizon_fade : hint_range(0.02, 0.5) = 0.2;
uniform float cloud_far_clip : hint_range(4.0, 24.0) = 13.0;
uniform vec2 cloud_wind_dir = vec2(1.0, 0.18);
uniform float cloud_advect_speed : hint_range(0.0, 0.2) = 0.0042;
uniform vec3 cloud_tint : source_color = vec3(0.88, 0.90, 0.93);
uniform float cloud_brightness : hint_range(0.2, 1.5) = 0.42;
uniform float cloud_sky_cap : hint_range(0.85, 1.8) = 0.96;
uniform float twilight_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 twilight_rim_color : source_color = vec3(1.0, 0.55, 0.32);
uniform float mie_g : hint_range(0.0, 0.99) = 0.82;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.65;

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 sky_gradient(vec3 eyedir) {
	float v_angle = acos(clamp(eyedir.y, -1.0, 1.0));
	float c = 1.0 - v_angle / (PI * 0.5);
	vec3 sky = mix(sky_horizon_color.rgb, sky_top_color.rgb,
		clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	sky *= sky_energy;

	// Below the horizon: stay dark so sky ambient does not wash out the meadow plane.
	if (eyedir.y < 0.0) {
		sky = ground_bottom_color.rgb * ground_energy;
	}
	return sky;
}

vec3 apply_sun_disc(vec3 sky, vec3 eyedir) {
	if (!LIGHT0_ENABLED) {
		return sky;
	}
	float sun_angle = acos(clamp(dot(LIGHT0_DIRECTION, eyedir), -1.0, 1.0));
	if (sun_angle < LIGHT0_SIZE) {
		return LIGHT0_COLOR * LIGHT0_ENERGY;
	}
	if (sun_angle < sun_angle_max) {
		float c2 = (sun_angle - LIGHT0_SIZE) / max(sun_angle_max - LIGHT0_SIZE, 1e-4);
		vec3 sun_halo = LIGHT0_COLOR * LIGHT0_ENERGY;
		sun_halo = mix(sun_halo, vec3(1.0, 0.55, 0.25), twilight_glow * 0.35);
		return mix(sun_halo, sky, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0));
	}
	return sky;
}

// Flat cloud layer: xz / (y + bias). Horizon stretches coords (distant); zenith stays
// smooth — no polar/azimuth mapping (that pinches into a circle).
vec3 cloud_layer_coords(vec3 eyedir) {
	float y = eyedir.y;
	float denom = max(y, 0.02) + cloud_zenith_bias;
	vec2 plane = eyedir.xz / denom;
	float dist = min(length(plane), cloud_far_clip);
	plane *= dist / max(length(plane), 1e-4);
	plane *= cloud_plane_scale;
	float layer_z = mix(0.35, 1.5, smoothstep(0.1, 0.65, y));
	vec3 p = vec3(plane.x, plane.y, layer_z);
	p += eyedir * 0.22;
	return p;
}

// Nubis-inspired billows on a flat layer, advected in plane space.
float cloud_noise_shape(vec3 eyedir, vec3 wind) {
	vec3 p = cloud_layer_coords(eyedir);
	p.xy += wind.xy;
	float alt = eyedir.y;
	float puff_scale = mix(1.35, 0.72, smoothstep(0.05, 0.55, alt));
	vec3 curl = vec3(
		fbm(p * puff_scale + vec3(4.1, 0.0, 2.7)),
		fbm(p * puff_scale + vec3(1.3, 3.2, 0.0)) * 0.12,
		fbm(p * puff_scale + vec3(0.0, 2.1, 5.4))
	) * mix(0.22, 0.38, alt);
	p += curl;
	float base = fbm(p * 0.82 * puff_scale);
	float billow = 1.0 - abs(fbm(p * 2.4 * puff_scale + vec3(9.2, 3.1, 1.4)) - 0.5) * 2.0;
	float detail_w = smoothstep(0.08, 0.42, alt);
	float detail = fbm(p * 5.2 * puff_scale + vec3(17.0, 4.0, 11.0)) * 0.26 * detail_w;
	return mix(base, billow, mix(0.28, 0.48, alt)) - detail;
}

float cloud_density(vec3 eyedir, vec3 wind) {
	if (eyedir.y < 0.02) {
		return 0.0;
	}
	float n = cloud_noise_shape(eyedir, wind);
	float threshold = 1.0 - cloud_cover;
	float d = smoothstep(threshold - cloud_softness, threshold + cloud_softness, n);
	float y = eyedir.y;
	float horizon_fade = smoothstep(0.02, cloud_horizon_fade, y);
	float dist = min(length(eyedir.xz / max(y, 0.04)), cloud_far_clip);
	float far_haze = 1.0 - smoothstep(cloud_far_clip * 0.55, cloud_far_clip, dist);
	float overhead_weight = mix(0.38, 0.78, smoothstep(0.12, 0.5, y));
	return d * horizon_fade * far_haze * overhead_weight;
}

float mie_phase(float cos_theta) {
	float g2 = mie_g * mie_g;
	float denom = pow(max(1.0 + g2 - 2.0 * mie_g * cos_theta, 1e-4), 1.5);
	return (1.0 - g2) / denom;
}

float cloud_density_edge(vec3 eyedir, vec3 wind) {
	float eps = 0.014;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), eyedir));
	if (length(right) < 1e-4) {
		right = vec3(1.0, 0.0, 0.0);
	}
	vec3 up_t = normalize(cross(eyedir, right));
	float d = cloud_density(eyedir, wind);
	float dx = cloud_density(normalize(eyedir + right * eps), wind) - d;
	float dy = cloud_density(normalize(eyedir + up_t * eps), wind) - d;
	return sqrt(dx * dx + dy * dy) / eps;
}

vec3 wind_offset() {
	vec2 dir = normalize(cloud_wind_dir + vec2(1e-4));
	float t = TIME * cloud_advect_speed;
	return vec3(dir.x * t, dir.y * t, 0.0);
}

void sky() {
	vec3 wind = wind_offset();

	if (AT_HALF_RES_PASS) {
		float density = cloud_density(EYEDIR, wind);
		COLOR = vec3(density);
		ALPHA = density;
	} else {
		vec3 sky = sky_gradient(EYEDIR);
		sky = apply_sun_disc(sky, EYEDIR);

		float density = cloud_density(EYEDIR, wind);
		if (density > 0.04 && EYEDIR.y > 0.0) {
			vec3 sky_ref = sky;
			vec3 lit_cloud = mix(sky_ref, cloud_tint * sky_energy * cloud_brightness, 0.62);
			float self_shadow = smoothstep(0.28, 0.88, density);
			lit_cloud *= mix(0.42, 0.78, self_shadow);

			if (LIGHT0_ENABLED) {
				float n_dot_l = max(dot(normalize(EYEDIR + vec3(0.0, 0.35, 0.0)), LIGHT0_DIRECTION), 0.0);
				vec3 sun_hit = LIGHT0_COLOR * LIGHT0_ENERGY * 0.28;
				lit_cloud = mix(lit_cloud, mix(sky_ref, sun_hit, 0.42), n_dot_l * 0.22);
			}
			float sky_lum = dot(sky_ref, vec3(0.299, 0.587, 0.114));
			float cloud_lum = dot(lit_cloud, vec3(0.299, 0.587, 0.114));
			float cap = sky_lum * cloud_sky_cap + 0.015;
			if (cloud_lum > cap) {
				lit_cloud *= cap / cloud_lum;
			}
			float mix_amt = density * mix(0.36, 0.5, smoothstep(0.2, 0.8, density));
			sky = mix(sky, lit_cloud, mix_amt);

			if (LIGHT0_ENABLED) {
				float cos_theta = dot(EYEDIR, LIGHT0_DIRECTION);
				float mie = mie_phase(cos_theta);
				float edge = cloud_density_edge(EYEDIR, wind);
				float rim_mask = smoothstep(0.08, 0.5, density) * edge;
				vec3 rim_col = mix(vec3(1.0), twilight_rim_color, twilight_glow);
				rim_col *= LIGHT0_COLOR;
				sky += rim_col * mie * rim_mask * rim_strength * LIGHT0_ENERGY * sky_energy * 0.18;
			}
		}

		if (twilight_glow > 0.0 && EYEDIR.y > -0.05 && EYEDIR.y < 0.35) {
			float band = 1.0 - abs(EYEDIR.y - 0.08) / 0.28;
			band = clamp(band, 0.0, 1.0);
			vec3 glow = twilight_rim_color * twilight_glow * band * sky_energy;
			if (LIGHT0_ENABLED) {
				float toward_sun = max(dot(normalize(vec3(LIGHT0_DIRECTION.x, 0.0, LIGHT0_DIRECTION.z)),
					normalize(vec3(EYEDIR.x, 0.0, EYEDIR.z))), 0.0);
				glow *= 0.35 + 0.65 * toward_sun;
			}
			sky += glow * 0.22;
		}

		float final_lum = dot(sky, vec3(0.299, 0.587, 0.114));
		if (final_lum > 1.02) {
			sky *= 1.02 / final_lum;
		}
		COLOR = sky;
	}
}
