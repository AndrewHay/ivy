## VillageTerrain — pure-math in-village lawn heightfield sampler.
## Static API; mirrors HillsHeightfield. Single source of truth for all lawn
## placement Y inside r ≤ layout.lawn_radius (SD-VILLAGE-TERRAIN-3 / AR-VT-FILES).
##
## Composition: sample_y = Y_BASE + _apply_stamps(_compose_base(xz), xz, …)
##   _compose_base = SD steps 1-2 (no stamps), AR-VT-DECIDE-2 / AR-VT-GAP-4.
##   _apply_stamps = ascending-priority lerp chain (base < plaza < pond < pads < hero),
##   SD-VILLAGE-TERRAIN-4.
##
## Determinism: terrain_seed = _derive(generation_seed, VILLAGE_TERRAIN_SALT),
##   knoll stream uses VILLAGE_TERRAIN_KNOLL_SALT (SD-VILLAGE-TERRAIN-5).
##
## Flat-legacy / classic gate: variant==1 or not layout.is_generated → Y_BASE=0.0
##   everywhere; all consumers pass through unchanged (INV-15, AR-VT-DECIDE-3).
class_name VillageTerrain
extends RefCounted

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const HillsNoise = preload("res://src/playground/hills_noise.gd")
const VillagePondSite = preload("res://src/world/village_pond_site.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

## Datum: current World/Ground plane and today's scatter-root plane (SD-VILLAGE-TERRAIN-2).
const Y_BASE := 0.0
## Sun rise / set azimuth constants (compass: 0=north/−Z, 90=east/+X).
## Knoll rejection corridor: within knoll_sun_corridor_half_deg of these (SD-VILLAGE-TERRAIN-4).
const _SUN_EAST_AZ_DEG := 90.0
const _SUN_WEST_AZ_DEG := 270.0
## Path corridor for AC-VT7: flatten cross-path relief along every polyline (SD-VILLAGE-TERRAIN-7).
const _PATH_STONE_HALF_M := 0.55
## Flat spine core ≥ stone half-width + sample_slope_deg eps so FD neighbours stay on spine.
const _PATH_FLAT_CORE_M := 1.05
const _PATH_CORRIDOR_OUTER_M := 5.0
const _PATH_VERTEX_SMOOTH_PTS := 5
## Open-lawn relief envelope: full scale beyond this SDF outside cottage pads.
const _OPEN_LAWN_PAD_QUIET_M := 2.25
const _OPEN_LAWN_PAD_FADE_M := 14.0
## Pond / hero / plaza relief quiet zones (m beyond feature edge).
const _POND_RELIEF_FADE_M := 12.0
const _HERO_RELIEF_FADE_M := 10.0
const _PLAZA_RELIEF_FADE_M := 10.0
## Pad targets: low-frequency base (no knolls) + neighbour height relaxation (AC-VT5 / bold relief).
const _PAD_LOWPASS_FEATURE_SCALE := 2.0
const _PAD_LOWPASS_OCTAVES := 1
const _PAD_SKIRT_GRADE_SAFETY := 0.90
const _PAD_SKIRT_MARGIN_M := 1.35
const _PAD_RELAX_ITERS := 16
const _PAD_RELAX_PAIR_SHRINK := 0.52
const _PAD_COTTAGE_HALF_REACH_M := 5.5
const _PAD_SKIRT_ABS_CAP_M := 18.0

static var _path_spine_built_key: String = ""
## One resampled+grade-clamped chain per layout path polyline (no phantom inter-poly bridges).
static var _path_spine_chains: Array = []
static var _path_spine_building: bool = false
static var _knoll_centres_cache_key: String = ""
static var _knoll_centres_cache: Array[Vector2] = []
static var _cottage_pad_cache_key: String = ""
static var _cottage_pad_heights: PackedFloat32Array = PackedFloat32Array()
static var _cottage_pad_skirts: PackedFloat32Array = PackedFloat32Array()
static var _cottage_pad_max_skirt: float = 2.0
static var _cottage_pad_cache_building: bool = false
static var _sample_lut_cache: Dictionary = {}
static var _displaced_mesh_cache: Dictionary = {}
const _PATH_SPINE_SAMPLE_M := 0.25
const _PATH_SPINE_GRADE_SAFETY := 0.985


# ── Public API ─────────────────────────────────────────────────────────────────

static func terrain_seed(layout: VillageLayout, params: VillageTerrainParams) -> int:
	## Derive terrain LCG seed. Mirrors HillsHeightfield.terrain_seed (SD-VILLAGE-TERRAIN-5).
	var norm := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	return VillageLayout._derive(norm, VillageLayout.VILLAGE_TERRAIN_SALT)


static func sample_y(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## Single source of truth for lawn placement Y (SD-VILLAGE-TERRAIN-3 / AR-VT-GOAL).
	## Returns Y_BASE (0.0) for variant==1 / classic layouts / outside-disc (INV-15).
	if params.variant == 1 or not layout.is_generated:
		return Y_BASE
	var g := layout.hamlet_centre_xz
	var r := xz.distance_to(g)
	# SD step 1: outside disc → datum (hills domain)
	if r >= layout.lawn_radius:
		return Y_BASE
	# Pre-compute knoll centres once per sample (shared between _compose_base and stamps)
	var kc := _knoll_centres_cached(layout, params)
	var h := _compose_base_with_knolls(xz, layout, params, t_seed, kc)
	h = _apply_stamps(h, xz, layout, params, t_seed, kc)
	return Y_BASE + h


static func sample_normal(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		eps: float = 0.35) -> Vector3:
	## Central-difference normal; returns Vector3.UP where degenerate (SD-VILLAGE-TERRAIN-3).
	var yx := sample_y(xz + Vector2(eps, 0.0), layout, params, t_seed)
	var yxm := sample_y(xz - Vector2(eps, 0.0), layout, params, t_seed)
	var yz := sample_y(xz + Vector2(0.0, eps), layout, params, t_seed)
	var yzm := sample_y(xz - Vector2(0.0, eps), layout, params, t_seed)
	var dx := (yx - yxm) / maxf(2.0 * eps, 0.01)
	var dz := (yz - yzm) / maxf(2.0 * eps, 0.01)
	if not is_finite(dx) or not is_finite(dz):
		return Vector3.UP
	var n := Vector3(-dx, 1.0, -dz)
	if n.length_squared() < 1e-12:
		return Vector3.UP
	return n.normalized()


static func sample_slope_deg(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		eps: float = 0.545) -> float:
	## Slope in degrees at xz (mirrors HillsHeightfield.sample_slope_deg).
	var yx := sample_y(xz + Vector2(eps, 0.0), layout, params, t_seed)
	var yxm := sample_y(xz - Vector2(eps, 0.0), layout, params, t_seed)
	var yz := sample_y(xz + Vector2(0.0, eps), layout, params, t_seed)
	var yzm := sample_y(xz - Vector2(0.0, eps), layout, params, t_seed)
	var ddx := (yx - yxm) / maxf(2.0 * eps, 0.01)
	var ddz := (yz - yzm) / maxf(2.0 * eps, 0.01)
	return rad_to_deg(atan(sqrt(ddx * ddx + ddz * ddz)))


static func build_mesh(layout: VillageLayout, params: VillageTerrainParams) -> ArrayMesh:
	## Cartesian-grid displaced LawnTerrain mesh (SD-VILLAGE-TERRAIN-8 / AR-VT-DECIDE-3).
	## Flat/classic returns a lightweight fan mesh for byte-parity (AR-VT-DECIDE-1 §Node naming).
	if params.variant == 1 or not layout.is_generated:
		return _build_flat_fan(layout)
	return _build_displaced_mesh(layout, params)


static func knoll_centres(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> Array[Vector2]:
	## Deterministic seeded knoll centres for probes and field (SD-VILLAGE-TERRAIN-4).
	## t_seed is accepted for API symmetry; knolls use the dedicated knoll sub-salt.
	return _knoll_centres_cached(layout, params)


static func build_sample_lut(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		cell_m: float = 1.0) -> Dictionary:
	## Coarse bilinear grid over disc bbox for grass LUT (SD-VILLAGE-TERRAIN-7 / AR-VT-WIRE).
	## Returns: {origin_xz: Vector2, cell_m: float, cols: int, rows: int, data: PackedFloat32Array}
	## Perf: pre-computes knoll_centres once to avoid per-cell LCG rejection-sampling.
	## Cached per (generation_seed, terrain seed, params height signature, cell_m) — ivy-4ehy.
	var cache_key := _sample_lut_cache_key(layout, params, t_seed, cell_m)
	if _sample_lut_cache.has(cache_key):
		return _sample_lut_cache[cache_key]
	var g := layout.hamlet_centre_xz
	var half := layout.lawn_radius + cell_m
	var step := maxf(cell_m, 0.1)
	var cols := int(ceil(2.0 * half / step)) + 1
	var rows := cols
	var data := PackedFloat32Array()
	data.resize(cols * rows)
	var origin := g - Vector2(half, half)
	if params.variant == 1 or not layout.is_generated:
		# Flat / classic: LUT is all zeros — no noise needed.
		var flat_lut := {
			"origin_xz": origin,
			"cell_m": step,
			"cols": cols,
			"rows": rows,
			"data": data,
		}
		_sample_lut_cache[cache_key] = flat_lut
		return flat_lut
	# Pre-compute knoll centres once (avoids LCG rejection-sampling per cell).
	var kc := _knoll_centres_cached(layout, params)
	var lawn_r := layout.lawn_radius
	for row in range(rows):
		for col in range(cols):
			var xz := origin + Vector2(float(col) * step, float(row) * step)
			if xz.distance_to(g) >= lawn_r:
				data[row * cols + col] = 0.0
				continue
			var h0 := _compose_base_with_knolls(xz, layout, params, t_seed, kc)
			data[row * cols + col] = _apply_stamps(h0, xz, layout, params, t_seed, kc)
	var built := {
		"origin_xz": origin,
		"cell_m": step,
		"cols": cols,
		"rows": rows,
		"data": data,
	}
	_sample_lut_cache[cache_key] = built
	return built


static func lut_sample(lut: Dictionary, xz: Vector2) -> float:
	## Bilinear sample from a LUT built by build_sample_lut (grass Y bake only).
	var origin: Vector2 = lut["origin_xz"]
	var cell: float = lut["cell_m"]
	var cols: int = lut["cols"]
	var rows: int = lut["rows"]
	var data: PackedFloat32Array = lut["data"]
	var fx := (xz.x - origin.x) / maxf(cell, 0.001)
	var fz := (xz.y - origin.y) / maxf(cell, 0.001)
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var ix1 := clampi(ix, 0, cols - 1)
	var ix2 := clampi(ix + 1, 0, cols - 1)
	var iz1 := clampi(iz, 0, rows - 1)
	var iz2 := clampi(iz + 1, 0, rows - 1)
	var v00: float = data[iz1 * cols + ix1]
	var v10: float = data[iz1 * cols + ix2]
	var v01: float = data[iz2 * cols + ix1]
	var v11: float = data[iz2 * cols + ix2]
	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), tz)


static func lut_sample_normal(lut: Dictionary, xz: Vector2) -> Vector3:
	## FD upward normal from LUT — 4 bilinear lookups, no full-noise evaluation.
	## Used for grass blade tilt bake (WP5 / AR-VT-WIRE).
	## eps = half a LUT cell for single-step accuracy.
	var eps: float = (lut["cell_m"] as float) * 0.5
	var yx := lut_sample(lut, xz + Vector2(eps, 0.0))
	var yxm := lut_sample(lut, xz - Vector2(eps, 0.0))
	var yz := lut_sample(lut, xz + Vector2(0.0, eps))
	var yzm := lut_sample(lut, xz - Vector2(0.0, eps))
	## Vector3(-(df/dx)*2eps, 2eps, -(df/dz)*2eps) = Vector3(yxm-yx, 2eps, yzm-yz)
	return Vector3(yxm - yx, 2.0 * eps, yzm - yz).normalized()


# ── Composition (AR-VT-DECIDE-2 / SD-VILLAGE-TERRAIN-3) ───────────────────────

static func _compose_base(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## SD steps 1-2 only (no stamps). Private helper for stamp h_target queries (AR-VT-GAP-4).
	## Returns relative displacement h (not Y_BASE+h).
	if params.variant == 1 or not layout.is_generated:
		return 0.0
	var kc := _knoll_centres_internal(layout, params)
	return _compose_base_with_knolls(xz, layout, params, t_seed, kc)


static func _compose_base_with_knolls(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2],
		apply_path_quiet: bool = true) -> float:
	## Core base-field computation with pre-fetched knoll centres (avoids redundant recompute).
	if params.variant == 1 or not layout.is_generated:
		return 0.0
	var g := layout.hamlet_centre_xz
	var r := xz.distance_to(g)
	if r >= layout.lawn_radius:
		return 0.0

	# Base noise (SD-VILLAGE-TERRAIN-3 step 2a)
	var n01 := HillsNoise.fbm_height_01(
		xz, t_seed, params.base_feature_m,
		params.noise_octaves, params.noise_persistence, params.warp_strength)
	var h := (n01 - 0.5) * 2.0 * params.base_amplitude_m

	# Biases (SD-VILLAGE-TERRAIN-3 step 2b-c)
	var phi := atan2(xz.x - g.x, xz.y - g.y)
	var bias := lerpf(1.0, params.center_bias_gain,
		1.0 - clampf(r / maxf(layout.lawn_radius, 0.01), 0.0, 1.0))
	var dir := 1.0 + params.dir_bias_gain * cos(deg_to_rad(params.dir_bias_phi_deg) - phi)
	h *= bias * dir

	# Quieter base noise in open lawn near paths (AC-VT7); spine targets skip this (see WP6 stones).
	var path_d := _min_dist_to_paths(xz, layout)
	if apply_path_quiet:
		var path_quiet := _fer(path_d, 0.0, _PATH_CORRIDOR_OUTER_M)
		var quiet_floor := 0.38 if params.base_feature_m < 40.0 else 0.52
		h *= lerpf(quiet_floor, 1.0, path_quiet)

	# Additive knolls (SD-VILLAGE-TERRAIN-3 step 2d / SD-VILLAGE-TERRAIN-4 §Knoll placement)
	var knoll_shield := _fer(path_d, _PATH_STONE_HALF_M, _PATH_STONE_HALF_M + params.knoll_radius_m)
	var pad_skirt_knoll := pad_skirt_outer_m(params, layout, t_seed)
	var pad_knoll_cover := _max_cottage_pad_weight(xz, layout, params, t_seed)
	var pad_knoll_shield := 1.0 - pad_knoll_cover
	for c: Vector2 in kc:
		h += params.knoll_height_m * _fer(xz.distance_to(c), 0.0, params.knoll_radius_m) * knoll_shield * pad_knoll_shield

	h *= _open_lawn_relief_scale(xz, layout, params, path_d)

	# Clamp and rim taper (SD-VILLAGE-TERRAIN-3 step 2e-f)
	h = clampf(h, -params.max_depression_m, params.max_rise_m)
	h *= _rim_taper(r, layout.lawn_radius, params.rim_blend_m)
	return h


static func _apply_stamps(
		h: float,
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> float:
	## Ascending-priority stamp chain: base < plaza < pond < pads < hero (SD-VILLAGE-TERRAIN-4).
	## Each stamp: h = lerp(h, h_target, w).  Last wins where they overlap.

	# ── Priority 2: Plaza (SD-VILLAGE-TERRAIN-4 §Plaza) ───────────────────────
	if layout.plaza_rect.has_area():
		var rect := layout.plaza_rect
		var plaza_centre := rect.get_center()
		var sdf := _rect_sdf(xz, rect)
		var w_plaza := _fer(sdf, 0.0, params.plaza_skirt_m)
		if w_plaza > 0.0:
			var h_plaza := _compose_base_with_knolls(plaza_centre, layout, params, t_seed, kc) \
				+ params.plaza_relief_m
			h = lerpf(h, h_plaza, w_plaza)

	# ── Priority 3: Pond basin (SD-VILLAGE-TERRAIN-4 §Pond basin) ─────────────
	var pond_c := layout.pond_center
	var d_pond := xz.distance_to(pond_c)
	var r_floor := VillagePondSite.MEAN_WATER_RADIUS_M * params.pond_floor_scale
	var r_rim := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m
	var w_pond := _fer(d_pond, r_floor, r_rim + params.pond_skirt_m)
	if w_pond > 0.0:
		var t_basin := clampf(d_pond / maxf(r_rim, 0.01), 0.0, 1.0)
		var basin := params.pond_depth_m * (1.0 - _smooth(t_basin))
		var sigma := maxf(params.pond_lip_sigma_m, 0.01)
		var lip := params.pond_lip_rise_m * exp(
			-((d_pond - r_rim) * (d_pond - r_rim)) / (2.0 * sigma * sigma))
		var h_pond := _compose_base_with_knolls(pond_c, layout, params, t_seed, kc) + basin + lip
		h = lerpf(h, h_pond, w_pond)

	# ── Priority 4: Cottage pads (SD-VILLAGE-TERRAIN-4 §Cottage pads) ─────────
	var pad_blend := _blended_cottage_pad_height(xz, layout, params, t_seed, kc)
	if pad_blend["active"]:
		h = pad_blend["h"]

	var path_hit := _closest_on_paths(xz, layout)
	## Entire pad skirt band (including on path spine) — path must not re-seat here (AC-VT5 / AC-VT7).
	var in_pad_skirt: bool = _in_cottage_pad_skirt(xz, layout, params, t_seed)
	var stoop := VillageLayout.HERO_DOOR_STOOP
	var d_hero := xz.distance_to(stoop)

	var path_corridor: bool = path_hit.dist < _PATH_CORRIDOR_OUTER_M \
			and not in_pad_skirt and d_hero >= params.hero_flat_r_m
	var spine_h := 0.0
	if path_corridor:
		spine_h = _path_spine_height(path_hit, layout, params, t_seed, kc)
		h = spine_h

	# ── Priority 5: Hero sanctum — highest (SD-VILLAGE-TERRAIN-4 §Hero sanctum) ──
	var w_hero := _fer(d_hero, params.hero_flat_r_m, params.hero_flat_r_m + params.hero_skirt_m)
	if w_hero > 0.0:
		var h_hero_tgt := 0.0
		if path_hit.dist <= _PATH_FLAT_CORE_M and d_hero >= params.hero_flat_r_m:
			h_hero_tgt = h
		h = lerpf(h, h_hero_tgt, w_hero)

	# Re-seat path grade after hero skirt; hero flat disc stays datum (AC-VT7 + sanctum).
	if path_corridor:
		h = spine_h
	## Soft hero disc edge so FD slope stencil does not see a cliff (AC-VT7 + sanctum).
	var hero_edge := params.hero_flat_r_m + 0.5
	## Skip on pad skirts — hero pull to datum fights AC-VT5 pad grade near G-facing cottages.
	if d_hero < hero_edge and path_hit.dist > _PATH_FLAT_CORE_M and not in_pad_skirt:
		var t_e := clampf((d_hero - params.hero_flat_r_m) / maxf(hero_edge - params.hero_flat_r_m, 0.01), 0.0, 1.0)
		h = lerpf(0.0, h, _smooth(t_e))

	if path_corridor:
		h = spine_h

	if d_hero < params.hero_flat_r_m:
		h = 0.0

	# Final safety clamp (SD-VILLAGE-TERRAIN-3 step 4)
	h = clampf(h, -(params.max_depression_m + 0.05), params.max_rise_m + 0.05)

	return h


# ── Smooth blend primitives (SD-VILLAGE-TERRAIN-3 §Smooth falloff primitives) ──

static func _smooth(t: float) -> float:
	## C1 smoothstep, t in [0, 1]. (SD-VILLAGE-TERRAIN-3 §smooth)
	var tc := clampf(t, 0.0, 1.0)
	return tc * tc * (3.0 - 2.0 * tc)


static func _rim_taper(r: float, lawn_radius: float, rim_blend_m: float) -> float:
	## 1 inside disc, tapers → 0 at r = lawn_radius. (SD-VILLAGE-TERRAIN-3 §rim_taper)
	var t := (r - (lawn_radius - rim_blend_m)) / maxf(rim_blend_m, 0.001)
	return 1.0 - _smooth(clampf(t, 0.0, 1.0))


static func _fer(d: float, r_core: float, r_skirt: float) -> float:
	## Flat-core-then-skirt weight: 1 inside r_core, 0 at/after r_skirt. (SD-VILLAGE-TERRAIN-3 §fer)
	if r_skirt <= r_core:
		return 1.0 if d <= r_core else 0.0
	return 1.0 - _smooth(clampf((d - r_core) / maxf(r_skirt - r_core, 0.001), 0.0, 1.0))


static func _inside_any_pad_interior(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams) -> bool:
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		if _rect_sdf(xz, rect) < 0.0:
			return true
	return false


static func _max_cottage_pad_weight(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	var pad := _cottage_pad_layout_cached(layout, params, t_seed)
	var skirts: PackedFloat32Array = pad["skirts"]
	var w_max := 0.0
	var ci := 0
	for spec: Dictionary in layout.cottages:
		var skirt_m: float = skirts[ci]
		ci += 1
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var sdf := _rect_sdf(xz, rect)
		if sdf > skirt_m + 0.1:
			continue
		w_max = maxf(w_max, _fer(sdf, 0.0, skirt_m))
	return w_max


static func _open_lawn_relief_scale(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		_path_d: float) -> float:
	## Attenuates relief only near stamp cores; mechanical pad skirt is handled by pad blend (AC-VT5).
	var pad_scale := 1.0
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var dout := maxf(_rect_sdf(xz, rect), 0.0)
		var t := clampf(
			(dout - _OPEN_LAWN_PAD_QUIET_M) / maxf(_OPEN_LAWN_PAD_FADE_M, 0.01), 0.0, 1.0)
		pad_scale = minf(pad_scale, _smooth(t))
	var scale := pad_scale
	var d_hero := xz.distance_to(VillageLayout.HERO_DOOR_STOOP)
	var hero_t := clampf((d_hero - params.hero_flat_r_m)
			/ maxf(_HERO_RELIEF_FADE_M, 0.01), 0.0, 1.0)
	scale *= _smooth(hero_t)
	if layout.plaza_rect.has_area():
		var plaza_out := maxf(_rect_sdf(xz, layout.plaza_rect), 0.0)
		var plaza_t := clampf(plaza_out / maxf(_PLAZA_RELIEF_FADE_M, 0.01), 0.0, 1.0)
		scale *= _smooth(plaza_t)
	var d_pond := xz.distance_to(layout.pond_center)
	var r_rim := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m
	var pond_t := clampf((d_pond - r_rim * 0.85) / maxf(_POND_RELIEF_FADE_M, 0.01), 0.0, 1.0)
	scale *= _smooth(pond_t)
	return scale


static func _clamp_h_to_pad_owner_grade(
		h: float,
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> float:
	var owner := _min_pad_skirt_owner(xz, layout, params)
	if not owner["found"]:
		return h
	var grade_cap := tan(deg_to_rad(params.pad_edge_slope_max_deg)) * 0.96
	var h_edge := _cottage_pad_height_at(
		owner["index"] as int, owner["centre"] as Vector2,
		layout, params, t_seed, kc)
	var dh_max := grade_cap * maxf(owner["sdf"] as float, 0.0)
	return clampf(h, h_edge - dh_max, h_edge + dh_max)


static func _cottage_pad_layout_uniform_fallback(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> Dictionary:
	## Non-reentrant pad table while the full skirt solver runs (prevents compose↔cache cycles).
	var n := layout.cottages.size()
	var heights := PackedFloat32Array()
	var skirts := PackedFloat32Array()
	heights.resize(n)
	skirts.resize(n)
	var skirt_u := _pad_skirt_outer_m_fallback(params)
	for i in range(n):
		var spec: Dictionary = layout.cottages[i]
		heights[i] = _compose_lowpass_for_pad(spec["centre"] as Vector2, layout, params, t_seed)
		skirts[i] = skirt_u
	return {"heights": heights, "skirts": skirts, "max_skirt": skirt_u}


static func _compose_lowpass_for_pad(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## Low-frequency base only (no knolls / open-lawn attenuation) for pad datum targets.
	if params.variant == 1 or not layout.is_generated:
		return 0.0
	var g := layout.hamlet_centre_xz
	var r := xz.distance_to(g)
	if r >= layout.lawn_radius:
		return 0.0
	var feature := params.base_feature_m * _PAD_LOWPASS_FEATURE_SCALE
	var n01 := HillsNoise.fbm_height_01(
		xz, t_seed, feature, _PAD_LOWPASS_OCTAVES,
		params.noise_persistence, params.warp_strength * 0.65)
	var h := (n01 - 0.5) * 2.0 * params.base_amplitude_m
	var phi := atan2(xz.x - g.x, xz.y - g.y)
	var bias := lerpf(1.0, params.center_bias_gain,
		1.0 - clampf(r / maxf(layout.lawn_radius, 0.01), 0.0, 1.0))
	var dir := 1.0 + params.dir_bias_gain * cos(deg_to_rad(params.dir_bias_phi_deg) - phi)
	h *= bias * dir
	h = clampf(h, -params.max_depression_m, params.max_rise_m)
	h *= _rim_taper(r, layout.lawn_radius, params.rim_blend_m)
	return h


static func _cottage_pad_cache_signature(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> String:
	var gen := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	var pdict := params.to_dict()
	pdict.erase("layout_seed")
	pdict.erase("wanderer_follow_terrain")
	return "%d|%d|n%d|h%d" % [gen, t_seed, layout.cottages.size(), hash(pdict)]


static func _cottage_pad_layout_cached(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> Dictionary:
	var key := _cottage_pad_cache_signature(layout, params, t_seed)
	if key == _cottage_pad_cache_key and _cottage_pad_heights.size() == layout.cottages.size():
		return {
			"heights": _cottage_pad_heights,
			"skirts": _cottage_pad_skirts,
			"max_skirt": _cottage_pad_max_skirt,
		}
	if _cottage_pad_cache_building:
		return _cottage_pad_layout_uniform_fallback(layout, params, t_seed)
	_cottage_pad_cache_building = true
	var n := layout.cottages.size()
	var heights := PackedFloat32Array()
	var skirts := PackedFloat32Array()
	heights.resize(n)
	skirts.resize(n)
	var centres: Array[Vector2] = []
	var kc := _knoll_centres_cached(layout, params)
	for i in range(n):
		var spec: Dictionary = layout.cottages[i]
		var centre := spec["centre"] as Vector2
		centres.append(centre)
		heights[i] = _compose_base_with_knolls(centre, layout, params, t_seed, kc, false)
		if centre.distance_to(VillageLayout.HERO_DOOR_STOOP) < params.hero_flat_r_m:
			heights[i] = 0.0
	var grade_cap := tan(deg_to_rad(params.pad_edge_slope_max_deg)) * _PAD_SKIRT_GRADE_SAFETY
	for _iter in range(_PAD_RELAX_ITERS):
		for i in range(n):
			for j in range(i + 1, n):
				var gap := maxf(centres[i].distance_to(centres[j]) - _PAD_COTTAGE_HALF_REACH_M, 2.0)
				var max_dh := grade_cap * gap
				var dh := heights[i] - heights[j]
				if absf(dh) <= max_dh:
					continue
				var pull := (absf(dh) - max_dh) * _PAD_RELAX_PAIR_SHRINK
				heights[i] -= signf(dh) * pull
				heights[j] += signf(dh) * pull
	var max_skirt := params.pad_skirt_m
	var cardinals := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	var grade_probe := tan(deg_to_rad(params.pad_edge_slope_max_deg)) * 0.96
	for i in range(n):
		var dh_need := 0.0
		for j in range(n):
			if i == j:
				continue
			dh_need = maxf(dh_need, absf(heights[i] - heights[j]))
		var skirt_est := params.pad_skirt_m
		for _pass in range(4):
			for dir: Vector2 in cardinals:
				var p_edge := centres[i] + dir * skirt_est
				var h_edge := _compose_base_with_knolls(p_edge, layout, params, t_seed, kc, false)
				dh_need = maxf(dh_need, absf(heights[i] - h_edge))
			skirt_est = maxf(
				skirt_est,
				1.55 * dh_need / maxf(grade_probe, 0.01) + 0.5)
		var skirt_i := maxf(params.pad_skirt_m, skirt_est)
		skirt_i = minf(skirt_i, _PAD_SKIRT_ABS_CAP_M)
		skirts[i] = skirt_i
		max_skirt = maxf(max_skirt, skirt_i)
	_cottage_pad_cache_key = key
	_cottage_pad_heights = heights
	_cottage_pad_skirts = skirts
	_cottage_pad_max_skirt = max_skirt
	_cottage_pad_cache_building = false
	return {"heights": heights, "skirts": skirts, "max_skirt": max_skirt}


static func _cottage_pad_height_at(
		index: int,
		fallback_centre: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		_kc: Array[Vector2]) -> float:
	var pad := _cottage_pad_layout_cached(layout, params, t_seed)
	var heights: PackedFloat32Array = pad["heights"]
	if index >= 0 and index < heights.size():
		return heights[index]
	return _compose_lowpass_for_pad(fallback_centre, layout, params, t_seed)


static func _cottage_pad_skirt_at(
		index: int,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	var pad := _cottage_pad_layout_cached(layout, params, t_seed)
	var skirts: PackedFloat32Array = pad["skirts"]
	if index >= 0 and index < skirts.size():
		return skirts[index]
	return params.pad_skirt_m


static func _blended_cottage_pad_height(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> Dictionary:
	## Partition-of-unity pad stamp: avoids sequential lerp resets from near-zero weights (AC-VT5).
	var pad_data := _cottage_pad_layout_cached(layout, params, t_seed)
	var skirts: PackedFloat32Array = pad_data["skirts"]
	var h_outer := _height_through_pond_at(xz, layout, params, t_seed, kc)
	var grade_cap := tan(deg_to_rad(params.pad_edge_slope_max_deg)) * 0.96
	var w_sum := 0.0
	var w_max := 0.0
	var h_weighted := 0.0
	var ci := 0
	for spec: Dictionary in layout.cottages:
		var centre := spec["centre"] as Vector2
		var pad_skirt := skirts[ci]
		ci += 1
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var sdf := _rect_sdf(xz, rect)
		if sdf > pad_skirt + 0.1:
			continue
		var w_pad := _fer(sdf, 0.0, pad_skirt)
		if w_pad <= 0.0:
			continue
		var lip_m := pad_skirt * grade_cap / 1.55
		var h_pad := _cottage_pad_height_at(ci - 1, centre, layout, params, t_seed, kc)
		h_pad = clampf(h_pad, h_outer - lip_m, h_outer + lip_m)
		w_sum += w_pad
		w_max = maxf(w_max, w_pad)
		h_weighted += w_pad * h_pad
	if w_sum <= 0.0 or w_max <= 0.0:
		return {"active": false, "h": h_outer}
	var h_tgt := h_weighted / w_sum
	## Smooth the partition weight so fer-edge ∂h/∂sdf stays inside pad grade cap at high relief.
	var w_blend := _smooth(clampf(w_max, 0.0, 1.0))
	var h_blend := lerpf(h_outer, h_tgt, w_blend)
	h_blend = _clamp_h_to_pad_owner_grade(h_blend, xz, layout, params, t_seed, kc)
	return {"active": true, "h": h_blend}


static func _min_pad_rect_sdf(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams) -> float:
	return _min_pad_skirt_owner(xz, layout, params)["sdf"]


static func _min_pad_skirt_owner(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams) -> Dictionary:
	## Min signed rect SDF over all cottage pads and the pad that attains it (multi-pad AC-VT5).
	var min_sdf := INF
	var owner_centre := Vector2.ZERO
	var found := false
	var idx := -1
	for i in layout.cottages.size():
		var spec: Dictionary = layout.cottages[i]
		var centre := spec["centre"] as Vector2
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var psdf := _rect_sdf(xz, rect)
		if psdf < min_sdf:
			min_sdf = psdf
			owner_centre = centre
			idx = i
			found = true
	return {"sdf": min_sdf, "centre": owner_centre, "index": idx, "found": found}


static func _in_cottage_pad_skirt(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> bool:
	for i in layout.cottages.size():
		var spec: Dictionary = layout.cottages[i]
		var outer := _cottage_pad_skirt_at(i, layout, params, t_seed)
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var sdf := _rect_sdf(xz, rect)
		if sdf >= -0.05 and sdf <= outer + 0.05:
			return true
	return false


static func pad_skirt_outer_m(
		params: VillageTerrainParams,
		layout: VillageLayout = null,
		t_seed: int = -1) -> float:
	## Public skirt width for probes; layout-aware when provided (SD-VILLAGE-TERRAIN-4).
	if (layout != null and t_seed >= 0 and layout.cottages.size() > 0
			and not _cottage_pad_cache_building):
		return _cottage_pad_layout_cached(layout, params, t_seed)["max_skirt"]
	return _pad_skirt_outer_m_fallback(params)


static func _pad_skirt_outer_m_fallback(params: VillageTerrainParams) -> float:
	## Conservative fallback when layout is unavailable (knoll shield upper bound).
	var cap_grad := tan(deg_to_rad(params.pad_edge_slope_max_deg)) * _PAD_SKIRT_GRADE_SAFETY
	var delta_h := params.base_amplitude_m * 2.0 + params.knoll_height_m * 1.25
	return maxf(params.pad_skirt_m, minf(_PAD_SKIRT_ABS_CAP_M, delta_h / cap_grad + _PAD_SKIRT_MARGIN_M))


static func _rect_sdf(xz: Vector2, rect: Rect2) -> float:
	## Signed distance to rect: negative inside, 0 on boundary, positive outside.
	## Used for fer_rect stamps. (SD-VILLAGE-TERRAIN-3 §fer_rect)
	var cx := rect.position.x + rect.size.x * 0.5
	var cz := rect.position.y + rect.size.y * 0.5
	var hx := rect.size.x * 0.5
	var hz := rect.size.y * 0.5
	var dx := absf(xz.x - cx) - hx
	var dz := absf(xz.y - cz) - hz
	if dx <= 0.0 and dz <= 0.0:
		return maxf(dx, dz)  # negative inside
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


# ── Knoll placement (SD-VILLAGE-TERRAIN-4 §Knoll placement) ───────────────────

static func _knoll_cache_key(layout: VillageLayout, params: VillageTerrainParams) -> String:
	return "%d|ls%d|v%d|k%d|kh%.4f|kr%.3f|ks%.2f|khc%.2f|ksun%.1f" % [
		layout.generation_seed if layout.generation_seed > 0 else params.layout_seed,
		params.layout_seed, params.variant, params.knoll_count,
		params.knoll_height_m, params.knoll_radius_m, params.knoll_min_sep_m,
		params.knoll_hero_clear_m, params.knoll_sun_corridor_half_deg]


static func _knoll_centres_cached(
		layout: VillageLayout,
		params: VillageTerrainParams) -> Array[Vector2]:
	var key := _knoll_cache_key(layout, params)
	if key == _knoll_centres_cache_key:
		return _knoll_centres_cache
	_knoll_centres_cache.assign(_knoll_centres_internal(layout, params))
	_knoll_centres_cache_key = key
	return _knoll_centres_cache


static func clear_knoll_centres_cache() -> void:
	## Test / playground hook: force recomputation on next sample (knob edits).
	_knoll_centres_cache_key = ""
	_knoll_centres_cache.clear()
	_cottage_pad_cache_key = ""
	_cottage_pad_heights = PackedFloat32Array()
	_cottage_pad_skirts = PackedFloat32Array()
	_cottage_pad_max_skirt = 2.0
	_sample_lut_cache.clear()
	_displaced_mesh_cache.clear()
	_path_spine_built_key = ""
	_path_spine_chains.clear()


static func _sample_lut_cache_key(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		cell_m: float) -> String:
	var gen := layout.generation_seed if layout.is_generated else 0
	var pdict := params.to_dict()
	pdict.erase("layout_seed")
	pdict.erase("wanderer_follow_terrain")
	return "%d|%d|%.5f|%d" % [gen, t_seed, cell_m, hash(pdict)]


static func _knoll_centres_internal(
		layout: VillageLayout,
		params: VillageTerrainParams) -> Array[Vector2]:
	## Core knoll placement algorithm. Shared by public API and _compose_base.
	## Deterministic: derived from VILLAGE_TERRAIN_KNOLL_SALT (SD-VILLAGE-TERRAIN-5).
	if params.variant == 1 or not layout.is_generated or params.knoll_count <= 0:
		return []
	var norm := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	var knoll_seed := VillageLayout._derive(norm, VillageLayout.VILLAGE_TERRAIN_KNOLL_SALT)
	var g := layout.hamlet_centre_xz
	var r_min := layout.lawn_radius * 0.25
	var r_max := layout.lawn_radius * 0.85
	var centres: Array[Vector2] = []
	var state := knoll_seed
	var attempts := params.knoll_count * 200
	for _i in range(attempts):
		if centres.size() >= params.knoll_count:
			break
		state = VillageScatterPositions.lcg_step(state)
		var phi := (VillageScatterPositions.lcg_f01(state) * TAU) - PI
		state = VillageScatterPositions.lcg_step(state)
		var r := r_min + VillageScatterPositions.lcg_f01(state) * (r_max - r_min)
		var p := g + Vector2(sin(phi), cos(phi)) * r
		if _knoll_rejected(p, g, centres, layout, params):
			continue
		centres.append(p)
	return centres


static func _knoll_rejected(
		p: Vector2,
		g: Vector2,
		accepted: Array[Vector2],
		layout: VillageLayout,
		params: VillageTerrainParams) -> bool:
	## Returns true if the candidate knoll centre p should be rejected (SD-VILLAGE-TERRAIN-4).
	# Hero clearance
	if p.distance_to(VillageLayout.HERO_DOOR_STOOP) < params.knoll_hero_clear_m:
		return true
	# Inside any cottage footprint
	if layout.inside_any_cottage(p, 1.0):
		return true
	# Too close to pond
	if p.distance_to(layout.pond_center) < VillagePondSite.BANK_OUTER_M + params.knoll_radius_m:
		return true
	# Too close to any path — centre must be ≥ knoll_radius from path (full skirt clears polyline)
	if _min_dist_to_paths(p, layout) < params.knoll_radius_m:
		return true
	# Sun east/west corridor (SD-VILLAGE-TERRAIN-4 / SD-VILLAGE-TERRAIN-7 §camera/sun)
	var az := _azimuth_from_g_deg(p, g)
	if _angular_diff_deg(az, _SUN_EAST_AZ_DEG) < params.knoll_sun_corridor_half_deg:
		return true
	if _angular_diff_deg(az, _SUN_WEST_AZ_DEG) < params.knoll_sun_corridor_half_deg:
		return true
	# Minimum separation between accepted centres
	for c: Vector2 in accepted:
		if p.distance_to(c) < params.knoll_min_sep_m:
			return true
	return false


static func _azimuth_from_g_deg(p: Vector2, g: Vector2) -> float:
	## Compass azimuth from G to p: 0=north(−Z), 90=east(+X). Returns [0, 360).
	var dx := p.x - g.x
	var dz := p.y - g.y
	var az := rad_to_deg(atan2(dx, -dz))
	if az < 0.0:
		az += 360.0
	return az


static func _angular_diff_deg(a: float, b: float) -> float:
	## Smallest unsigned angular distance between two compass degrees. Returns [0, 180].
	var diff := absf(fmod(a - b, 360.0))
	if diff > 180.0:
		diff = 360.0 - diff
	return diff


static func _min_dist_to_paths(p: Vector2, layout: VillageLayout) -> float:
	## Minimum distance from p to any segment in any path polyline.
	var min_d := INF
	for polyline: Variant in layout.path_polylines():
		var pts: Array = polyline as Array
		var n := pts.size()
		for i in range(n - 1):
			var a: Vector2 = pts[i] as Vector2
			var b: Vector2 = pts[i + 1] as Vector2
			var d := _seg_dist(p, a, b)
			if d < min_d:
				min_d = d
	return min_d


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	## Distance from point p to line segment [a, b].
	var ab := b - a
	var len_sq := ab.dot(ab)
	if len_sq < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _closest_on_paths(p: Vector2, layout: VillageLayout) -> Dictionary:
	## Closest point on any path segment: {dist, point, tangent, cache_key, seg_t}.
	var best_dist := INF
	var best_pt := p
	var best_tan := Vector2.RIGHT
	var best_key := ""
	var best_t := 0.0
	var pi := 0
	for polyline: Variant in layout.path_polylines():
		var pts: Array = polyline as Array
		var n := pts.size()
		for i in range(n - 1):
			var a: Vector2 = pts[i] as Vector2
			var b: Vector2 = pts[i + 1] as Vector2
			var ab := b - a
			var len_sq := ab.dot(ab)
			var t := 0.0
			if len_sq > 1e-6:
				t = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
			var q := a + ab * t
			var d := p.distance_to(q)
			if d < best_dist:
				best_dist = d
				best_pt = q
				best_tan = ab.normalized() if len_sq > 1e-6 else Vector2.RIGHT
				best_key = "%d|%d" % [pi, i]
				best_t = t
		pi += 1
	return {"dist": best_dist, "point": best_pt, "tangent": best_tan,
			"cache_key": best_key, "seg_t": best_t}


static func _height_through_pond_at(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2],
		apply_path_quiet: bool = true) -> float:
	## Stamp chain through pond (no path / pads / hero) for path-spine targets (AC-VT7).
	var h := _compose_base_with_knolls(xz, layout, params, t_seed, kc, apply_path_quiet)
	if layout.plaza_rect.has_area():
		var rect := layout.plaza_rect
		var plaza_centre := rect.get_center()
		var sdf := _rect_sdf(xz, rect)
		var w_plaza := _fer(sdf, 0.0, params.plaza_skirt_m)
		if w_plaza > 0.0:
			var h_plaza := _compose_base_with_knolls(plaza_centre, layout, params, t_seed, kc) \
				+ params.plaza_relief_m
			h = lerpf(h, h_plaza, w_plaza)
	var pond_c := layout.pond_center
	var d_pond := xz.distance_to(pond_c)
	var r_floor := VillagePondSite.MEAN_WATER_RADIUS_M * params.pond_floor_scale
	var r_rim := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m
	var w_pond := _fer(d_pond, r_floor, r_rim + params.pond_skirt_m)
	if w_pond > 0.0:
		var t_basin := clampf(d_pond / maxf(r_rim, 0.01), 0.0, 1.0)
		var basin := params.pond_depth_m * (1.0 - _smooth(t_basin))
		var sigma := maxf(params.pond_lip_sigma_m, 0.01)
		var lip := params.pond_lip_rise_m * exp(
			-((d_pond - r_rim) * (d_pond - r_rim)) / (2.0 * sigma * sigma))
		var h_pond := _compose_base_with_knolls(pond_c, layout, params, t_seed, kc) + basin + lip
		h = lerpf(h, h_pond, w_pond)
	return h


static func _path_spine_height(
		path_hit: Dictionary,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> float:
	## Grade-limited height on a 0.25 m resampled path spine (AC-VT7).
	_ensure_path_spine(layout, params, t_seed, kc)
	var q: Vector2 = path_hit["point"]
	if _path_spine_chains.is_empty():
		return _height_through_pond_at(q, layout, params, t_seed, kc)
	var chain_idx := 0
	var key: String = path_hit.get("cache_key", "")
	if key.contains("|"):
		chain_idx = clampi(int(key.split("|")[0]), 0, _path_spine_chains.size() - 1)
	var chain: Dictionary = _path_spine_chains[chain_idx]
	var pts: PackedVector2Array = chain["pts"]
	var hs: PackedFloat32Array = chain["hs"]
	if pts.size() < 2:
		return _height_through_pond_at(q, layout, params, t_seed, kc)
	return _height_on_polyline_chain(q, pts, hs)


static func _height_on_polyline_chain(
		q: Vector2, pts: PackedVector2Array, hs: PackedFloat32Array) -> float:
	var best_dist := INF
	var best_h := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var len_sq := ab.dot(ab)
		var t := 0.0
		if len_sq > 1e-6:
			t = clampf((q - a).dot(ab) / len_sq, 0.0, 1.0)
		var foot := a + ab * t
		var d := q.distance_to(foot)
		if d < best_dist:
			best_dist = d
			best_h = lerpf(hs[i], hs[i + 1], t)
	return best_h


static func _clamp_path_spine_chain(
		pts: PackedVector2Array, hs: PackedFloat32Array, max_grad: float) -> void:
	if pts.size() < 2:
		return
	for _clamp in range(14):
		for i in range(1, pts.size()):
			var seg_len := pts[i].distance_to(pts[i - 1])
			var max_dh := max_grad * maxf(seg_len, _PATH_SPINE_SAMPLE_M)
			var dh := hs[i] - hs[i - 1]
			if absf(dh) > max_dh:
				hs[i] = hs[i - 1] + signf(dh) * max_dh
		for i in range(pts.size() - 2, -1, -1):
			var seg_len := pts[i + 1].distance_to(pts[i])
			var max_dh := max_grad * maxf(seg_len, _PATH_SPINE_SAMPLE_M)
			var dh := hs[i] - hs[i + 1]
			if absf(dh) > max_dh:
				hs[i] = hs[i + 1] + signf(dh) * max_dh


static func _ensure_path_spine(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> void:
	var key := "%d|%d|v%d|s%.2f|k%s" % [
		layout.generation_seed, t_seed, params.variant, params.max_path_slope_deg,
		_knoll_cache_key(layout, params)]
	if key == _path_spine_built_key:
		return
	if _path_spine_building:
		return
	_path_spine_building = true
	var max_grad := tan(deg_to_rad(params.max_path_slope_deg)) * _PATH_SPINE_GRADE_SAFETY
	_path_spine_chains.clear()
	for polyline: Variant in layout.path_polylines():
		var poly: Array = polyline as Array
		if poly.size() < 2:
			continue
		var pts := PackedVector2Array()
		var hs := PackedFloat32Array()
		var total := _polyline_length(poly)
		var dist_along := 0.0
		var guard := 0
		var max_samples := int(total / _PATH_SPINE_SAMPLE_M) + 8
		while dist_along <= total + 0.001:
			guard += 1
			if guard > maxi(max_samples, 8):
				break
			var p := _point_along_polyline_open(poly, dist_along)
			if not pts.is_empty() and p.distance_to(pts[pts.size() - 1]) < 0.04:
				dist_along += _PATH_SPINE_SAMPLE_M
				continue
			pts.append(p)
			var hv := _height_through_pond_at(p, layout, params, t_seed, kc, true)
			if p.distance_to(VillageLayout.HERO_DOOR_STOOP) < params.hero_flat_r_m:
				hv = 0.0
			hs.append(hv)
			dist_along += _PATH_SPINE_SAMPLE_M
		if pts.size() < 2:
			continue
		_clamp_path_spine_chain(pts, hs, max_grad)
		_path_spine_chains.append({"pts": pts, "hs": hs})
	_path_spine_built_key = key
	_path_spine_building = false


static func _polyline_length(poly: Array) -> float:
	var total := 0.0
	for i in range(poly.size() - 1):
		total += (poly[i] as Vector2).distance_to(poly[i + 1] as Vector2)
	return total


static func _point_along_polyline_open(poly: Array, dist: float) -> Vector2:
	var remaining := dist
	for i in range(poly.size() - 1):
		var a: Vector2 = poly[i] as Vector2
		var b: Vector2 = poly[i + 1] as Vector2
		var seg_len := a.distance_to(b)
		if remaining <= seg_len or i == poly.size() - 2:
			var t := clampf(remaining / maxf(seg_len, 1e-6), 0.0, 1.0)
			return a.lerp(b, t)
		remaining -= seg_len
	return poly[poly.size() - 1] as Vector2


# ── Mesh builders (SD-VILLAGE-TERRAIN-8 / AR-VT-DECIDE-3) ─────────────────────

static func _build_displaced_mesh(
		layout: VillageLayout, params: VillageTerrainParams) -> ArrayMesh:
	## Cartesian grid clipped to disc; one coarse LUT at mesh step, bilinear Y/normals (AR-VT-DECIDE-3).
	var t_seed := terrain_seed(layout, params)
	var mesh_key := "%s|mesh" % _sample_lut_cache_key(
		layout, params, t_seed, maxf(params.terrain_mesh_step_m, 0.1))
	if _displaced_mesh_cache.has(mesh_key):
		return _displaced_mesh_cache[mesh_key]
	var g := layout.hamlet_centre_xz
	var outer := layout.lawn_radius
	var step := maxf(params.terrain_mesh_step_m, 0.1)
	var lut := build_sample_lut(layout, params, t_seed, step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := _append_cartesian_disc_lut(st, layout, g, outer, step, lut)
	if tris > 0:
		var mesh := st.commit()
		_displaced_mesh_cache[mesh_key] = mesh
		return mesh
	# Fallback: coarser grid
	var lut2 := build_sample_lut(layout, params, t_seed, 3.5)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_cartesian_disc_lut(st2, layout, g, outer, 3.5, lut2)
	var mesh_fb := st2.commit()
	_displaced_mesh_cache[mesh_key] = mesh_fb
	return mesh_fb


static func _append_cartesian_disc_lut(
		st: SurfaceTool,
		layout: VillageLayout,
		g: Vector2,
		outer: float,
		step: float,
		lut: Dictionary) -> int:
	## Returns tri count. Hard-capped at 16k tris (AR-VT-DECIDE-3 §hard cap 16k).
	var tris := 0
	var x0 := g.x - outer
	var z0 := g.y - outer
	var cols := int(ceil(2.0 * outer / step))
	for iz in range(cols):
		for ix in range(cols):
			var ax0 := x0 + float(ix) * step
			var az0 := z0 + float(iz) * step
			var ax1 := ax0 + step
			var az1 := az0 + step
			var corners: Array[Vector2] = [
				Vector2(ax0, az0), Vector2(ax1, az0), Vector2(ax1, az1), Vector2(ax0, az1),
			]
			var inside := 0
			for cp: Vector2 in corners:
				if cp.distance_to(g) < outer:
					inside += 1
			if inside == 0:
				continue
			if tris + 2 > 16000:
				return tris
			var tri_list := [[0, 1, 2], [0, 2, 3]]
			for tri: Array in tri_list:
				for idx: int in tri:
					var p2: Vector2 = corners[idx]
					var y := Y_BASE + lut_sample(lut, p2)
					var n := lut_sample_normal(lut, p2)
					st.set_normal(n)
					st.set_color(Color(1, 1, 1, 1))
					st.add_vertex(Vector3(p2.x, y, p2.y))
				tris += 1
	return tris


static func _sample_y_with_kc(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> float:
	## Internal: sample_y with pre-computed knoll centres. Avoids per-vertex LCG recompute.
	if params.variant == 1 or not layout.is_generated:
		return Y_BASE
	var g := layout.hamlet_centre_xz
	var r := xz.distance_to(g)
	if r >= layout.lawn_radius:
		return Y_BASE
	var h := _compose_base_with_knolls(xz, layout, params, t_seed, kc)
	h = _apply_stamps(h, xz, layout, params, t_seed, kc)
	return Y_BASE + h


static func _sample_normal_with_kc(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2],
		eps: float = 0.35) -> Vector3:
	## Internal: sample_normal with pre-computed knoll centres.
	var yx := _sample_y_with_kc(xz + Vector2(eps, 0.0), layout, params, t_seed, kc)
	var yxm := _sample_y_with_kc(xz - Vector2(eps, 0.0), layout, params, t_seed, kc)
	var yz := _sample_y_with_kc(xz + Vector2(0.0, eps), layout, params, t_seed, kc)
	var yzm := _sample_y_with_kc(xz - Vector2(0.0, eps), layout, params, t_seed, kc)
	var dx := (yx - yxm) / maxf(2.0 * eps, 0.01)
	var dz := (yz - yzm) / maxf(2.0 * eps, 0.01)
	if not is_finite(dx) or not is_finite(dz):
		return Vector3.UP
	var n := Vector3(-dx, 1.0, -dz)
	if n.length_squared() < 1e-12:
		return Vector3.UP
	return n.normalized()


static func _build_flat_fan(layout: VillageLayout) -> ArrayMesh:
	## Lightweight fan mesh for flat/classic path — byte-parity node (AR-VT-DECIDE-3 §flat).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 72
	var c := layout.hamlet_centre_xz if layout.is_generated else Vector2.ZERO
	var r := layout.lawn_radius if layout.is_generated else 58.0
	var y := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	for i in range(segs):
		var a0 := (float(i) / segs) * TAU
		var a1 := (float(i + 1) / segs) * TAU
		st.set_normal(Vector3.UP)
		st.set_color(Color(1, 1, 1, 1))
		st.add_vertex(Vector3(c.x, y, c.y))
		st.add_vertex(Vector3(c.x + cos(a0) * r, y, c.y + sin(a0) * r))
		st.add_vertex(Vector3(c.x + cos(a1) * r, y, c.y + sin(a1) * r))
	return st.commit()
