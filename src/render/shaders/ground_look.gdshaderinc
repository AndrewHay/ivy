// Ground look (ivy-82zn.17.1): ambientCG CC0 grass textures, an under-tree texture and a saturation
// control, shared by the lawn (village_ground.gdshader) and the lit meadow ring of the far hills
// (village_ground_hills.gdshader), so the two stay one ground across the join loop.
// Uniforms are set by GroundLook.apply (src/world/ground_look.gd) from VillageTerrainParams.
// Defaults (texture off, saturation 1) leave both shaders' output unchanged.

uniform bool  u_ground_tex_on = false;
uniform sampler2D u_grass_open_albedo  : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D u_grass_open_normal  : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D u_grass_shade_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D u_grass_shade_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Tree cover (0..1 closeness to the nearest canopy), baked by GroundLook.tree_mask over a world rect.
uniform sampler2D u_tree_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec4  u_tree_mask_rect = vec4(0.0, 0.0, 1.0, 1.0);  // world xz origin (xy), world xz size (zw)
uniform float u_ground_tex_scale_m = 3.0;
uniform float u_ground_tex_strength = 1.0;
uniform float u_ground_tex_brightness = 1.0;
uniform float u_ground_macro = 0.6;
uniform float u_ground_saturation = 1.0;
uniform float u_ground_normal_strength = 0.6;
uniform float u_shade_tex_strength = 1.0;
uniform float u_shade_edge_lo = 0.15;
uniform float u_shade_edge_hi = 0.55;

// Second tile sample: rotated ~37° and scaled 1.37×, so the two repeats never line up.
const mat2 GROUND_ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

float ground_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 ground_saturate(vec3 c) {
	float l = ground_luma(c);
	return max(mix(vec3(l), c, u_ground_saturation), vec3(0.0));
}

float ground_hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float ground_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = ground_hash(i);
	float b = ground_hash(i + vec2(1.0, 0.0));
	float c = ground_hash(i + vec2(0.0, 1.0));
	float d = ground_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 0 in the open, 1 under a canopy (smoothstep of the baked closeness).
float ground_shade_at(vec2 xz) {
	vec2 uv = (xz - u_tree_mask_rect.xy) / u_tree_mask_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	float c = texture(u_tree_mask, uv).r;
	return smoothstep(u_shade_edge_lo, max(u_shade_edge_hi, u_shade_edge_lo + 1e-3), c) * u_shade_tex_strength;
}

vec3 ground_unpack_normal(vec4 t) {
	// NormalGL (green = +v in the image's upward direction); Godot UV v runs down the image.
	vec3 n = t.xyz * 2.0 - 1.0;
	n.y = -n.y;
	return n;
}

// Texture albedo (open grass mixed to under-tree grass by `shade`) and its tangent-space normal.
vec3 ground_tex_albedo(vec2 xz, float shade, out vec3 n_ts) {
	vec2 ua = xz / u_ground_tex_scale_m;
	vec2 ub = GROUND_ROT * (xz / (u_ground_tex_scale_m * 1.37)) + vec2(0.37, 0.71);
	float w = smoothstep(0.3, 0.7, ground_vnoise(xz * 0.09));
	vec3 a = mix(texture(u_grass_open_albedo, ua).rgb, texture(u_grass_shade_albedo, ua).rgb, shade);
	vec3 b = mix(texture(u_grass_open_albedo, ub).rgb, texture(u_grass_shade_albedo, ub).rgb, shade);
	vec3 na = mix(ground_unpack_normal(texture(u_grass_open_normal, ua)),
		ground_unpack_normal(texture(u_grass_shade_normal, ua)), shade);
	vec3 nb = mix(ground_unpack_normal(texture(u_grass_open_normal, ub)),
		ground_unpack_normal(texture(u_grass_shade_normal, ub)), shade);
	nb.xy = transpose(GROUND_ROT) * nb.xy;  // back into the ua frame
	n_ts = normalize(mix(na, nb, w));
	return mix(a, b, w);
}

// The ground albedo: proc_col is the shader's procedural albedo (base + patches + gust), proc_base its
// base colour. With the texture on, the texture replaces it (by u_ground_tex_strength) and keeps the
// procedural patches as large-scale brightness variation (u_ground_macro). n_ts is flat when off.
vec3 ground_albedo(vec2 xz, vec3 proc_col, vec3 proc_base, out vec3 n_ts) {
	n_ts = vec3(0.0, 0.0, 1.0);
	vec3 c = proc_col;
	if (u_ground_tex_on) {
		float shade = ground_shade_at(xz);
		vec3 t = ground_tex_albedo(xz, shade, n_ts) * u_ground_tex_brightness;
		float macro = ground_luma(proc_col) / max(ground_luma(proc_base), 1e-3);
		t *= mix(1.0, macro, u_ground_macro);
		c = mix(proc_col, t, u_ground_tex_strength);
		n_ts.xy *= u_ground_normal_strength * u_ground_tex_strength;
		n_ts = normalize(n_ts);
	}
	return ground_saturate(c);
}

// Blurred texture colour of the ground at xz (open → under-tree by the tree mask), for things standing
// on the ground (grass blades, ivy-82zn.17.2). A high mip of the first tile sample: the blade takes the
// ground's local hue, not its per-pixel grain. Brightness knob applied; saturation is the caller's.
vec3 ground_tex_mean(vec2 xz) {
	float shade = ground_shade_at(xz);
	vec2 ua = xz / u_ground_tex_scale_m;
	vec3 c = mix(textureLod(u_grass_open_albedo, ua, 5.0).rgb, textureLod(u_grass_shade_albedo, ua, 5.0).rgb, shade);
	return c * u_ground_tex_brightness;
}

// World normal from a tangent-space ground normal: u along +X, v along +Z (uv = xz / scale).
vec3 ground_world_normal(vec3 n_world, vec3 n_ts) {
	vec3 N = normalize(n_world);
	vec3 T = normalize(vec3(1.0, 0.0, 0.0) - N * N.x);
	vec3 B = cross(T, N);
	return normalize(T * n_ts.x + B * n_ts.y + N * n_ts.z);
}
