shader_type spatial;
// Playground-only relief debug shader — never used in production.
// SD-VILLAGE-TERRAIN-9 / AR-VT-PLAYGROUND: height-band tint (cool=low, warm=high),
// contour lines every contour_m, slope shading from vertex normals.
// Disc clip (discard outside lawn_radius) fixes the Cartesian-grid stair-step edge.
// Vertical exaggeration applied in vertex() so geometry reads on raking cameras.
render_mode unshaded, blend_mix, cull_back;

// ── Debug uniforms ────────────────────────────────────────────────────────────
/// Vertical exaggeration (debug only, never production). 1.0 = true scale.
uniform float ve_scale : hint_range(0.5, 8.0, 0.1) = 1.0;
/// Contour line spacing in metres.
uniform float contour_m : hint_range(0.05, 1.0, 0.05) = 0.2;
/// Contour line half-width in metres.
uniform float contour_width_m : hint_range(0.01, 0.15, 0.01) = 0.025;
/// Contour line darkness (0=invisible, 1=black).
uniform float contour_strength : hint_range(0.0, 1.0, 0.05) = 0.7;
/// Slope shading strength (0=flat-lit, 1=full normal shading).
uniform float slope_shade_strength : hint_range(0.0, 1.0, 0.05) = 0.7;
/// Height at which color is "mid" green (usually 0.0 = datum).
uniform float h_zero : hint_range(-0.5, 0.5, 0.05) = 0.0;
/// Height range for full cool→warm ramp (±h_range from h_zero).
uniform float h_range : hint_range(0.05, 2.0, 0.05) = 0.8;
/// Hamlet centre X (world).
uniform float g_x = 0.0;
/// Hamlet centre Z (world).
uniform float g_z = 0.0;
/// Lawn disc radius (world metres) — vertices outside are discarded.
uniform float disc_r = 40.0;

// ── Varyings ──────────────────────────────────────────────────────────────────
varying float v_height;        // raw world Y before VE (for contours / color)
varying vec3  v_world_normal;  // pre-VE world normal
varying vec2  v_world_xz;      // world XZ for disc clip

// ── Vertex ────────────────────────────────────────────────────────────────────
void vertex() {
	// World position before VE
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_height    = world.y;
	v_world_xz  = world.xz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Apply vertical exaggeration to VERTEX (model space y == height since no mesh scale).
	// Normals are NOT recomputed here — slope shading uses pre-baked normals, which is
	// a known approximation; the visual purpose is to make subtle slopes obvious.
	VERTEX.y *= ve_scale;
}

// ── Helpers ───────────────────────────────────────────────────────────────────
vec3 height_color(float h) {
	// Three-stop ramp: cool (low) → mid-green (datum) → warm (high).
	float t = clamp((h - h_zero) / max(h_range, 0.001), -1.0, 1.0);
	// t in [-1, 1]: -1 = deepest depression, +1 = highest rise.
	vec3 cool  = vec3(0.18, 0.38, 0.68);  // blue-grey = low/depression
	vec3 mid   = vec3(0.24, 0.52, 0.18);  // lawn green = datum
	vec3 warm  = vec3(0.88, 0.56, 0.10);  // amber = high/knoll
	if (t < 0.0) {
		return mix(mid, cool, -t);
	} else {
		return mix(mid, warm, t);
	}
}

float contour_line(float h) {
	// Returns 0 on a contour line, 1 elsewhere.
	float h_mod = mod(h, contour_m);
	float w = contour_width_m;
	float f = min(h_mod, contour_m - h_mod);
	return smoothstep(0.0, w, f);
}

// ── Fragment ──────────────────────────────────────────────────────────────────
void fragment() {
	// Disc clip — eliminates the Cartesian-grid stair-step edge.
	float r = length(v_world_xz - vec2(g_x, g_z));
	// Smooth sub-pixel anti-alias at the disc boundary (px ~ 0.5 m at top view dist).
	float disc_alpha = smoothstep(disc_r + 0.3, disc_r - 0.3, r);
	if (disc_alpha < 0.01) {
		discard;
	}

	// Height-band tinting.
	vec3 col = height_color(v_height);

	// Contour lines.
	float cl = contour_line(v_height);
	col = mix(col * (1.0 - contour_strength), col, cl);

	// Slope shading from pre-baked world normal (dot with up).
	float up_dot = clamp(dot(v_world_normal, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
	float shade = mix(1.0, 0.35 + 0.65 * up_dot, slope_shade_strength);
	col *= shade;

	// Thin disc-edge fade.
	col *= disc_alpha;

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	ALPHA = disc_alpha;
}
