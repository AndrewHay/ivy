shader_type spatial;
// unshaded: bypass Godot engine Lambert so ALBEDO is the final rendered colour.
// The shader does its own directional lighting (warm/cool ndl) to match the scene sun.
// AR-NOFOG (ivy-82zn.14.32): no fog, no horizon / haze blend of any kind; the far mesh renders its
// meadow colours as they are, out to the horizon skirt (VillageTerrain.R_SKIRT_M).
// ivy-82zn.14.36: not `unshaded` any more; the hand-lit colour goes out as EMISSION over a black albedo
// (same pixels as unshaded) so the seam ring can be engine-lit like the lawn.
render_mode cull_back;

#include "res://src/render/shaders/wind_gust.gdshaderinc"
// Same slope / height factors as the lawn (AR-LF-D9). Applied to the u_lawn_colour seam override
// (weighted by meadow_ring), so at r_j the far mesh returns u_lawn_colour × the lawn's factors.
// u_terrain_tint_on = false (default; classic / flat legacy) keeps the old output (INV-15).
#include "res://src/render/shaders/terrain_tint.gdshaderinc"
// The lawn's ground look (textures, under-tree texture, saturation) for the lit ring (ivy-82zn.17.1).
#include "res://src/render/shaders/ground_look.gdshaderinc"
uniform bool u_terrain_tint_on = false;

// Calibrated rendered lawn colour — set by apply_terrain_shader to the measured
// pixel colour of the rendered lawn surface.  With unshaded mode, the meadow_ring
// blend at r = lawn_radius outputs this value directly, closing the seam.
uniform vec3 u_lawn_colour : source_color = vec3(0.204, 0.261, 0.127);
// ivy-82zn.14.36 seam variant: engine-lit lawn albedo near the join (see fragment()). The lawn
// defaults mirror village_ground.gdshader (base_color, patch_scale, patch_contrast).
uniform bool  u_seam_lit = false;
uniform vec3  u_lawn_base : source_color = vec3(0.30, 0.44, 0.22);
uniform float u_lawn_patch_scale = 0.22;
uniform float u_lawn_patch_contrast = 0.26;
uniform float u_seam_albedo_gain : hint_range(0.3, 2.0, 0.01) = 1.0;
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
// Horizon skirt (AR-NOFOG-EDGE, HillsTint.layer_t_for_radius): past u_r_outer the layer weights are
// read at u_r_outer (no Gaussian underflow ring) and fade to 0 over u_skirt_ease → plain meadow.
uniform float u_r_outer       = 310.0;
uniform float u_skirt_ease    = 600.0;
// Azimuth wedge — set by apply_terrain_shader from HillsParams.
// Outside the wedge, hill-layer colouring fades to plain meadow tone.
// Convention: centre_rad 0 = north (−Z); positive = clockwise (east = +π/2).
uniform float u_azimuth_centre_rad    : hint_range(-3.14159, 3.14159) = 0.0;
uniform float u_azimuth_half_width_rad: hint_range(0.0, 3.14159) = 0.959931;  // 55°
uniform float u_azimuth_fade_width_rad: hint_range(0.0, 3.14159) = 0.349066;  // 20°

varying vec3 v_world_pos;
varying vec3 v_world_nrm;
varying float v_local_y;

void vertex() {
	v_local_y = VERTEX.y;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float patch_noise_s(vec2 xz, float scale) {
	vec2 p = xz * scale;
	float a = hash21(floor(p));
	float b = hash21(floor(p) + vec2(1.0, 0.0));
	float c = hash21(floor(p) + vec2(0.0, 1.0));
	float d = hash21(floor(p) + vec2(1.0, 1.0));
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float patch_noise(vec2 xz) {
	return patch_noise_s(xz, patch_scale);
}

// layer_t_for_r: Gaussian-weighted blend of four ridge layers → scalar in [0,1].
// Layer distances and widths are set as uniforms by apply_terrain_shader (hills_tint.gd)
// so they stay in sync with GDScript HillsParams without hardcoded literals.
// Weights match HillsTint.layer_t_for_radius: 0.0 / 0.35 / 0.70 / 1.0.
float layer_t_for_r(float r_in) {
	float planar_r = min(r_in, u_r_outer);
	float fade = 1.0 - smoothstep(u_r_outer, u_r_outer + u_skirt_ease, r_in);
	float t0 = exp(-0.5 * pow((planar_r - u_layer_dist_0) / max(u_layer_width_0, 0.01), 2.0));
	float t1 = exp(-0.5 * pow((planar_r - u_layer_dist_1) / max(u_layer_width_1, 0.01), 2.0));
	float t2 = exp(-0.5 * pow((planar_r - u_layer_dist_2) / max(u_layer_width_2, 0.01), 2.0));
	float t3 = exp(-0.5 * pow((planar_r - u_layer_dist_3) / max(u_layer_width_3, 0.01), 2.0));
	float s = t0 + t1 + t2 + t3 + 1e-4;
	return clamp((t0 * 0.0 + t1 * u_layer_weight_1 + t2 * u_layer_weight_2 + t3 * u_layer_weight_3) / s, 0.0, 1.0) * fade;
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
	// so the terrain renders as plain meadow, not hill-green layered ridges.
	// We scale layer_t by the wedge weight so outside the wedge eff_layer_t=0 →
	// u_meadow_near (plain meadow tone).
	float wedge_w = azimuth_wedge_weight(world_xz);
	float eff_layer_t = layer_t * wedge_w;
	float flat_sector = 1.0 - wedge_w;

	// --- Hill base colour (varies with ridge distance, wedge-gated) ---
	vec3 layer_col = mix(u_meadow_near, u_meadow_mid, smoothstep(0.12, 0.52, eff_layer_t));

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
	// Ground saturation applies to the hand-lit far colour too (ivy-82zn.17.1; 1 = unchanged).
	col = ground_saturate(col);

	// Seam calibration (applied AFTER lighting):
	// Override with the measured rendered lawn colour at r = lawn_radius,
	// smoothly releasing to the lit hill colour by r = lawn_radius + 50 m.
	// This closes the razor-line seam visible between the grass disc and the hill terrain.
	float tint_f = 1.0;
	if (u_terrain_tint_on) {
		float ny_t = clamp(normalize(v_world_nrm).y, 0.0, 1.0);
		tint_f = terrain_slope_dim(ny_t) * terrain_height_factor(v_local_y);
	}
	if (u_seam_lit) {
		// ivy-82zn.14.36: near the lawn the far mesh is the lawn's own ground (same albedo formula as
		// village_ground.gdshader, times u_seam_albedo_gain) lit by the engine like the lawn, so the
		// join follows the sun at every hour. Past the ring the hand-lit colour is emitted unchanged.
		float nl = patch_noise_s(world_xz, u_lawn_patch_scale);
		vec3 lawn_alb = mix(u_lawn_base, mix(patch_lo, patch_hi, nl), u_lawn_patch_contrast);
		float lg = ivy_gust_at(world_xz);
		lawn_alb *= 1.0 + (lg - 0.5) * 0.10 * ivy_wind_strength;
		vec3 n_ts;
		lawn_alb = ground_albedo(world_xz, lawn_alb, u_lawn_base, n_ts);
		if (u_ground_tex_on) {
			n_ts.xy *= meadow_ring;
			NORMAL = normalize((VIEW_MATRIX * vec4(ground_world_normal(v_world_nrm, normalize(n_ts)), 0.0)).xyz);
		}
		lawn_alb *= u_seam_albedo_gain * tint_f;
		ALBEDO   = lawn_alb * meadow_ring;
		EMISSION = col * (1.0 - meadow_ring);
		SPECULAR = 0.5 * meadow_ring;
	} else {
		ALBEDO   = vec3(0.0);
		EMISSION = mix(col, u_lawn_colour * tint_f, meadow_ring);
		SPECULAR = 0.0;
	}
	ROUGHNESS = 1.0;
	METALLIC  = 0.0;
}
