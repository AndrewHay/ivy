shader_type spatial;
// unshaded: bypass Godot engine Lambert so ALBEDO is the final rendered colour.
// The shader does its own directional lighting (warm/cool ndl) to match the scene sun.
// Engine depth + volumetric fog provide atmosphere (matches World/Ground; ivy-ska0.2).
render_mode cull_back, unshaded;

#include "res://src/render/shaders/wind_gust.gdshaderinc"

// Calibrated rendered lawn colour — set by apply_terrain_shader to the measured
// pixel colour of the rendered lawn surface.  With unshaded mode, the meadow_ring
// blend at r = lawn_radius outputs this value directly, closing the seam.
uniform vec3 u_lawn_colour : source_color = vec3(0.270, 0.350, 0.210);
// Hill base colours (rework5 pre-lighting values, kept unchanged for rework6).
// With unshaded mode these render ~1.67× darker than the old double-lit output.
uniform vec3 u_meadow_near : source_color = vec3(0.22, 0.38, 0.17);
uniform vec3 u_meadow_mid  : source_color = vec3(0.25, 0.38, 0.28);
// Patch noise colours (rework5 values).
uniform vec3 patch_hi : source_color = vec3(0.34, 0.46, 0.24);
uniform vec3 patch_lo : source_color = vec3(0.20, 0.32, 0.16);
uniform float patch_scale    : hint_range(0.05, 2.0,  0.01) = 0.18;
uniform float patch_contrast : hint_range(0.0,  1.0,  0.01) = 0.22;
uniform float sun_warmth     : hint_range(0.0,  0.5,  0.01) = 0.22;
uniform vec2  u_hamlet_xz    = vec2(0.0, 0.0);
uniform float u_lawn_radius  = 56.0;
uniform vec3  u_horizon_rgb  = vec3(0.78, 0.85, 0.91);
uniform vec3  u_sun_dir      = vec3(0.35, 0.78, 0.52);
uniform float u_twilight     : hint_range(0.0, 1.0) = 0.0;
// Ridge layer geometry — set by apply_terrain_shader from HillsParams.
// Defaults match rework5 production values so the shader is safe before any call.
uniform float u_layer_dist_0  : hint_range(50.0, 400.0) = 155.0;
uniform float u_layer_dist_1  : hint_range(50.0, 400.0) = 190.0;
uniform float u_layer_dist_2  : hint_range(50.0, 400.0) = 225.0;
uniform float u_layer_dist_3  : hint_range(50.0, 400.0) = 260.0;
uniform float u_layer_width_0 : hint_range(1.0,  80.0)  = 28.0;
uniform float u_layer_width_1 : hint_range(1.0,  80.0)  = 32.0;
uniform float u_layer_width_2 : hint_range(1.0,  80.0)  = 36.0;
uniform float u_layer_width_3 : hint_range(1.0,  80.0)  = 40.0;
// Weighted blend weights per layer: layer 0 always 0.0; layers 1-3 set by apply_terrain_shader.
// Must match the GDScript layer_t_for_radius weights (0.0 / 0.35 / 0.70 / 1.0).
uniform float u_layer_weight_1 : hint_range(0.0, 1.0) = 0.35;
uniform float u_layer_weight_2 : hint_range(0.0, 1.0) = 0.70;
uniform float u_layer_weight_3 : hint_range(0.0, 1.0) = 1.0;
// Azimuth wedge — set by apply_terrain_shader from HillsParams.
// Outside the wedge, hill-layer colouring fades to plain meadow tone.
// Convention: centre_rad 0 = north (−Z); positive = clockwise (east = +π/2).
uniform float u_azimuth_centre_rad    : hint_range(-3.14159, 3.14159) = 0.0;
uniform float u_azimuth_half_width_rad: hint_range(0.0, 3.14159) = 0.959931;  // 55°
uniform float u_azimuth_fade_width_rad: hint_range(0.0, 3.14159) = 0.349066;  // 20°

varying vec3 v_world_pos;
varying vec3 v_world_nrm;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float patch_noise(vec2 xz) {
	vec2 p = xz * patch_scale;
	float a = hash21(floor(p));
	float b = hash21(floor(p) + vec2(1.0, 0.0));
	float c = hash21(floor(p) + vec2(0.0, 1.0));
	float d = hash21(floor(p) + vec2(1.0, 1.0));
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// layer_t_for_r: Gaussian-weighted blend of four ridge layers → scalar in [0,1].
// Layer distances and widths are set as uniforms by apply_terrain_shader (HillsFogTint.gd)
// so they stay in sync with GDScript HillsParams without hardcoded literals.
// Weights match HillsFogTint.layer_t_for_radius: 0.0 / 0.35 / 0.70 / 1.0.
float layer_t_for_r(float planar_r) {
	float t0 = exp(-0.5 * pow((planar_r - u_layer_dist_0) / max(u_layer_width_0, 0.01), 2.0));
	float t1 = exp(-0.5 * pow((planar_r - u_layer_dist_1) / max(u_layer_width_1, 0.01), 2.0));
	float t2 = exp(-0.5 * pow((planar_r - u_layer_dist_2) / max(u_layer_width_2, 0.01), 2.0));
	float t3 = exp(-0.5 * pow((planar_r - u_layer_dist_3) / max(u_layer_width_3, 0.01), 2.0));
	float s = t0 + t1 + t2 + t3 + 1e-4;
	return clamp((t0 * 0.0 + t1 * u_layer_weight_1 + t2 * u_layer_weight_2 + t3 * u_layer_weight_3) / s, 0.0, 1.0);
}

// azimuth_wedge_weight: 1.0 inside the north wedge, 0.0 outside, smooth taper at edges.
// Mirrors HillsHeightfield.azimuth_weight (GDScript) but reads from uniforms.
// phi = atan(dx, dz): phi=0 → +Z (south), phi=PI → −Z (north).
// north_phi = PI − centre_rad; diff = |shortest arc from phi to north_phi|.
float azimuth_wedge_weight(vec2 xz) {
	if (u_azimuth_half_width_rad >= (PI - 0.001)) return 1.0;
	vec2 d = xz - u_hamlet_xz;
	if (dot(d, d) < 0.01) return 1.0;
	float phi = atan(d.x, d.y);
	float north_phi = PI - u_azimuth_centre_rad;
	float diff = abs(mod(phi - north_phi + PI, 2.0 * PI) - PI);
	float hw = u_azimuth_half_width_rad;
	float fw = max(u_azimuth_fade_width_rad, 0.001);
	float inner_edge = max(hw - fw, 0.0);
	if (diff <= inner_edge) return 1.0;
	if (diff >= hw) return 0.0;
	return 1.0 - smoothstep(inner_edge, hw, diff);
}

void fragment() {
	vec2 world_xz = v_world_pos.xz;
	float planar_r = length(world_xz - u_hamlet_xz);
	float layer_t  = layer_t_for_r(planar_r);

	// Azimuth wedge: hill colouring is only valid inside the north wedge.
	// Outside the wedge the heightfield is flat (azimuth_weight=0 in GDScript),
	// so the terrain should render as plain meadow fading to haze — not
	// hill-green layered ridges. We scale layer_t by the wedge weight so
	// outside the wedge eff_layer_t=0 → u_meadow_near (plain meadow tone).
	float wedge_w = azimuth_wedge_weight(world_xz);
	float eff_layer_t = layer_t * wedge_w;

	// --- Hill base colour (varies with ridge distance, wedge-gated) ---
	vec3 layer_col = mix(u_meadow_near, u_meadow_mid, smoothstep(0.12, 0.52, eff_layer_t));
	// East/west flat sectors: ink toward horizon tone from the lawn edge so a green
	// ridge never meets the sky (north wedge keeps hill-green layers).
	float flat_sector = 1.0 - wedge_w;
	vec3 flat_tone = mix(u_horizon_rgb * 0.62, u_horizon_rgb * 0.90,
		smoothstep(u_lawn_radius + 22.0, 105.0, planar_r));
	float flat_far = smoothstep(u_lawn_radius + 8.0, u_lawn_radius + 28.0, planar_r);
	layer_col = mix(layer_col, flat_tone, flat_sector * flat_far * 0.92);

	// Far-ridge cap: blend toward washed-out sky at the outermost ring.
	vec3 far_cap = u_horizon_rgb * 0.86;
	layer_col = mix(layer_col, far_cap, smoothstep(0.42, 1.0, eff_layer_t));

	// Patch noise for meadow variation; attenuated near the lawn seam.
	float meadow_ring = 1.0 - smoothstep(u_lawn_radius, u_lawn_radius + 50.0, planar_r);
	float n           = patch_noise(world_xz);
	vec3  patch_col   = mix(patch_lo, patch_hi, n);
	float patch_wt    = patch_contrast * 0.55 * (1.0 - meadow_ring * 0.7);
	vec3  col         = mix(layer_col, patch_col, patch_wt);

	// Gust shimmer.
	float g = ivy_gust_at(world_xz);
	col *= 1.0 + (g - 0.5) * 0.06 * ivy_wind_strength;

	// Manual directional lighting (sun direction hardcoded to match scene sun).
	// With unshaded mode this replaces the engine Lambert; no double-multiply.
	vec3  sun_dir = normalize(u_sun_dir);
	float ndl     = clamp(dot(normalize(v_world_nrm), sun_dir), 0.0, 1.0);
	vec3  warm    = vec3(1.10 + sun_warmth, 1.04 + sun_warmth * 0.45, 0.90);
	vec3  cool    = vec3(0.78, 0.86, 0.94);
	col *= mix(cool, warm, ndl);
	col *= mix(1.0, 0.78, u_twilight * (0.35 + flat_sector * 0.65));

	// Luminance cap: hills must not outshine the sky horizon.
	float hor_lum = dot(u_horizon_rgb, vec3(0.299, 0.587, 0.114));
	float lum     = dot(col, vec3(0.299, 0.587, 0.114));
	if (lum > hor_lum * 0.94) {
		col *= (hor_lum * 0.90) / max(lum, 1e-4);
	}

	// Seam calibration (applied AFTER lighting):
	// Override with the measured rendered lawn colour at r = lawn_radius,
	// smoothly releasing to the lit hill colour by r = lawn_radius + 50 m.
	// This closes the razor-line seam visible between the grass disc and the hill terrain.
	col = mix(col, u_lawn_colour, meadow_ring);

	ALBEDO    = col;
	ROUGHNESS = 0.96;
	METALLIC  = 0.0;
}
