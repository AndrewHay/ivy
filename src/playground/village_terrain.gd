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
## Open-lawn relief envelope (pad quiet/fade, pond/hero/plaza fades) lives on
## VillageTerrainParams as live playground knobs (ivy-82zn.14.1).
## Pad targets: low-frequency base (no knolls) + neighbour height relaxation (AC-VT5 / bold relief).
const _PAD_LOWPASS_FEATURE_SCALE := 2.0
const _PAD_LOWPASS_OCTAVES := 1
const _PAD_SKIRT_GRADE_SAFETY := 0.90
const _PAD_SKIRT_MARGIN_M := 1.35
const _PAD_RELAX_ITERS := 16
const _PAD_RELAX_PAIR_SHRINK := 0.52
const _PAD_COTTAGE_HALF_REACH_M := 5.5
const _PAD_SKIRT_ABS_CAP_M := 18.0
## Peak-to-mean grade of the pad skirt profile: w_blend = smooth(fer) is a smoothstep of a
## smoothstep (peak 1.5 × 1.5 = 2.25 × mean). Was 1.55 (single smoothstep); harmless while every
## pad sat at datum, but with the swell (ivy-82zn.14.1) pads sit 0.1-0.3 m off the field and the
## skirt hit 9.0-9.2° on paths (seeds 2, 8). Sizes the skirt and the pad-vs-field lip clamp.
const _PAD_SKIRT_PEAK_FACTOR := 2.6

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
## Village swell noise seed offset from the terrain seed (deterministic, no global state).
const _SWELL_SEED_SALT := 7919
## Swell ramps from swell_sun_corridor_gain back to full over this many degrees outside a corridor.
const _SWELL_SUN_RAMP_DEG := 15.0
## Plaza swell bound keeps the hero-skirt ramp this fraction under the slope cap.
const _SWELL_PLAZA_GRADE_SAFETY := 0.80
## Pad↔plaza height budget divisor: two overlapping smoothstep skirts peak near 2× mean grade.
const _PAD_PLAZA_RAMP_PEAK := 2.2

# ── Village hill / two-layer heightfield (ivy-82zn.14.10, plan ivy-82zn.14.9) ─────────────────
# sample_y = Y_BASE + hero(paths(L_t + R)):
#   P    village-scale hill (hill_y): crest +hill_rise_m around the hero, 0 from the village edge out
#   L    large layer = P + village swell (_large_raw)
#   L_t  L terraced: cottage pads, the pond and (plaza_hill_follow < 1) the plaza are levelled at
#        relaxed L anchors with banks <= hill_bank_max_deg (_large_terraced)
#   R    detail layer = the pre-hill sampler minus swell and path corridor (detail_y): base noise,
#        knolls, plaza / pond / pad stamps, hero disc target 0; the height caps clamp R only
#   paths graded path spine as a smooth correction faded over the 5 m corridor (no replace step)
#   hero flat disc at hero_datum_y, blended over hero_skirt_m
## Public alias for tests / probes.
const PATH_CORRIDOR_OUTER_M := _PATH_CORRIDOR_OUTER_M
## Every relief fade ramp is at least this wide in the sampler. A 0 m fade made a C0 cliff at the
## hero ring / plaza edge / pond ring that the 2 m lawn mesh drew as a dark contour line.
const RELIEF_FADE_FLOOR_M := 1.0
## Bounds of a terrace's estimated bank reach (masks for tests / path grading; not the surface).
const _TERRACE_SKIRT_MIN_M := 1.0
const _TERRACE_SKIRT_MAX_M := 40.0
## Terrace bank cone slope = tan(hill_bank_max_deg) × this. 1.0: the cones are exact, and the
## total-bank limit (35°) leaves the headroom for the detail layer; 0.95 cost seeds 13 / 30 the
## one-cottage fall (dense pad chains can only step down c × the gaps between them).
const _TERRACE_BANK_SAFETY := 1.0
## Fraction of the hill's run (u) over which the fall eases to 0 slope at the end.
const _HILL_TOE_U := 0.1
## Large-layer flank cap beyond the hero ring (2° under the 30° open-lawn limit for the detail layer).
const _HILL_FLANK_MAX_DEG := 28.0
## Path correction fades to 0 over this beyond a pad edge, so pad interiors are never re-seated.
const _PATH_PAD_FADE_M := 1.0
## Bank-outline clearance of the pond water (AC: water <= lowest bank outline point - 2 cm).
const POND_WATER_BANK_CLEAR_M := 0.02

static var _village_edge_key: String = ""
static var _village_edge_r: float = INF
static var _terrace_key: String = ""
static var _terrace_items: Array = []
static var _pond_outline_min_cache: Dictionary = {}


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
	_sig_batch_begin(params)
	# Pre-compute knoll centres once per sample (shared between _compose_base and stamps)
	var kc := _knoll_centres_cached(layout, params)
	var h := _total_height(xz, layout, params, t_seed, kc)
	_sig_batch_end()
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


static func apply_ground_material(mat: ShaderMaterial, params: VillageTerrainParams) -> void:
	## Lawn slope shading + height tint uniforms for village_ground.gdshader (ivy-82zn.14.1).
	## Shared by VillageBackdrop (game) and VillageTerrainPlayground — no demo fork.
	mat.set_shader_parameter("terrain_slope_dark", params.ground_slope_dark)
	mat.set_shader_parameter("terrain_slope_full_deg", params.ground_slope_full_deg)
	mat.set_shader_parameter("terrain_height_tint", params.ground_height_tint)
	mat.set_shader_parameter("terrain_height_range_m", params.ground_height_range_m)


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
	## Same code path as the time-sliced job (lut_job_begin / lut_job_step), run to completion.
	var job := lut_job_begin(layout, params, t_seed, cell_m)
	lut_job_step(job, -1)
	return job["lut"]


static func lut_job_begin(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		cell_m: float = 1.0) -> Dictionary:
	## Resumable build_sample_lut (ivy-82zn.14.7): the playground steps it a few ms per frame so
	## the window never freezes. Cells are filled in the same row-major order with the same calls,
	## so the finished data is identical to a one-shot build. `params` must not be mutated while
	## the job runs (the playground hands it a snapshot). Done jobs carry the LUT in job["lut"].
	var cache_key := _sample_lut_cache_key(layout, params, t_seed, cell_m)
	if _sample_lut_cache.has(cache_key):
		return {"done": true, "lut": _sample_lut_cache[cache_key], "progress": 1.0}
	var g := layout.hamlet_centre_xz
	var half := layout.lawn_radius + cell_m
	var step := maxf(cell_m, 0.1)
	var cols := int(ceil(2.0 * half / step)) + 1
	var rows := cols
	var data := PackedFloat32Array()
	data.resize(cols * rows)
	var origin := g - Vector2(half, half)
	var job := {
		"done": false,
		"progress": 0.0,
		"layout": layout,
		"params": params,
		"t_seed": t_seed,
		"key": cache_key,
		"origin": origin,
		"step": step,
		"cols": cols,
		"rows": rows,
		"data": data,
		"next": 0,
	}
	if params.variant == 1 or not layout.is_generated:
		# Flat / classic: LUT is all zeros — no noise needed.
		job["next"] = cols * rows
		_lut_job_finish(job)
	return job


static func lut_job_step(job: Dictionary, budget_usec: int) -> bool:
	## Fill cells until the budget (µs) runs out; budget < 0 runs to completion. Returns done.
	if job["done"]:
		return true
	var layout: VillageLayout = job["layout"]
	var params: VillageTerrainParams = job["params"]
	var t_seed: int = job["t_seed"]
	var origin: Vector2 = job["origin"]
	var step: float = job["step"]
	var cols: int = job["cols"]
	var total: int = cols * int(job["rows"])
	var data: PackedFloat32Array = job["data"]
	var g := layout.hamlet_centre_xz
	var lawn_r := layout.lawn_radius
	var i: int = job["next"]
	var t_end := Time.get_ticks_usec() + budget_usec
	_sig_batch_begin(params)
	# Pre-compute knoll centres once (avoids LCG rejection-sampling per cell).
	var kc := _knoll_centres_cached(layout, params)
	while i < total:
		var row := i / cols
		var col := i % cols
		var xz := origin + Vector2(float(col) * step, float(row) * step)
		if xz.distance_to(g) >= lawn_r:
			data[i] = 0.0
		else:
			data[i] = _total_height(xz, layout, params, t_seed, kc)
		i += 1
		if budget_usec >= 0 and Time.get_ticks_usec() >= t_end:
			break
	_sig_batch_end()
	job["next"] = i
	job["data"] = data
	job["progress"] = float(i) / float(maxi(total, 1))
	if i >= total:
		_lut_job_finish(job)
	return job["done"]


static func _lut_job_finish(job: Dictionary) -> void:
	var built := {
		"origin_xz": job["origin"],
		"cell_m": job["step"],
		"cols": job["cols"],
		"rows": job["rows"],
		"data": job["data"],
	}
	_sample_lut_cache[job["key"]] = built
	job["lut"] = built
	job["done"] = true
	job["progress"] = 1.0


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

	# Quieter base noise near paths (AC-VT7); pad targets skip this (see WP6 stones).
	var path_d := _min_dist_to_paths(xz, layout)
	if apply_path_quiet:
		h *= path_quiet_gain(path_d, params)

	# Additive knolls (SD-VILLAGE-TERRAIN-3 step 2d / SD-VILLAGE-TERRAIN-4 §Knoll placement)
	var knoll_shield := _knoll_shield(path_d, params)
	var pad_skirt_knoll := pad_skirt_outer_m(params, layout, t_seed)
	var pad_knoll_cover := _max_cottage_pad_weight(xz, layout, params, t_seed)
	var pad_knoll_shield := 1.0 - pad_knoll_cover
	var knolls := 0.0
	for c: Vector2 in kc:
		knolls += params.knoll_height_m * _fer(xz.distance_to(c), 0.0, params.knoll_radius_m) * knoll_shield * pad_knoll_shield

	## Base noise takes the full open-lawn envelope. Knolls skip its pad term: their centres
	## already clear every pad by knoll_radius_m (_knoll_rejected), and multiplying a tall
	## mound flank by the pad fade ramp steepened it past 8° (ivy-82zn.14.1, seed 5).
	var feature_scale := _feature_relief_scale(xz, layout, params)
	h *= _pad_relief_scale(xz, layout, params) * feature_scale
	h += knolls * feature_scale
	## ivy-82zn.14.10: the village swell moved to the large layer (_large_raw), so the stamp anchors
	## ride the hill + swell through the terraces; this is the detail layer R only.

	# Clamp and rim taper (SD-VILLAGE-TERRAIN-3 step 2e-f) — detail layer only, never the hill.
	h = clampf(h, -params.max_depression_m, params.max_rise_m)
	h *= _rim_taper(r, layout.lawn_radius, params.rim_blend_m)
	return h


static func path_quiet_gain(path_d: float, params: VillageTerrainParams) -> float:
	## Base-noise multiplier vs distance to the nearest path: the quiet floor (0.38 / 0.52) on the
	## stones, 1 from _PATH_CORRIDOR_OUTER_M out. ivy-sx7x: was lerp(floor, 1, _fer(d)) — full noise
	## beside paths and the quiet floor over the whole open lawn.
	var quiet_floor := 0.38 if params.base_feature_m < 40.0 else 0.52
	return lerpf(quiet_floor, 1.0, 1.0 - _fer(path_d, 0.0, _PATH_CORRIDOR_OUTER_M))


static func _knoll_shield(path_d: float, params: VillageTerrainParams) -> float:
	## Knoll weight vs distance to the nearest path: 0 on the path stones, 1 at ≥ knoll_radius_m
	## beyond them (ivy-82zn.14.1: was un-inverted _fer, which applied knolls only beside paths
	## and zeroed them on open lawn). Shared with tools/probe_village_relief.gd (ivy-82zn.14.5).
	return 1.0 - _fer(path_d, _PATH_STONE_HALF_M, _PATH_STONE_HALF_M + params.knoll_radius_m)


# ── Village swell (ivy-82zn.14.1, architect plan ivy-82zn.14.4) ───────────────
# Every stamp anchor (pad heights, plaza target, pond target, path spine) is compose(anchor), and
# the pad / feature fades are 0 there, so without this field all anchors sat at exactly 0 m.

static func _swell_raw(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## S_raw: one-octave, un-warped noise × swell_amp_m, faded to 0 before the rim band, and
	## optionally scaled down inside the E/W sun corridors (swell_sun_corridor_gain).
	if params.swell_amp_m <= 0.0:
		return 0.0
	var g := layout.hamlet_centre_xz
	var r := xz.distance_to(g)
	var n01 := HillsNoise.fbm_height_01(xz, t_seed + _SWELL_SEED_SALT, params.swell_feature_m, 1, 0.4, 0.0)
	var s := (n01 - 0.5) * 2.0 * params.swell_amp_m
	var rim_fade := maxf(params.swell_rim_fade_m, 0.01)
	var rim_in := layout.lawn_radius - params.rim_blend_m - rim_fade
	s *= 1.0 - _smooth(clampf((r - rim_in) / rim_fade, 0.0, 1.0))
	if params.swell_sun_corridor_gain < 1.0:
		var az := _azimuth_from_g_deg(xz, g)
		var d_sun := minf(_angular_diff_deg(az, _SUN_EAST_AZ_DEG), _angular_diff_deg(az, _SUN_WEST_AZ_DEG))
		var t := _smooth(clampf((d_sun - params.knoll_sun_corridor_half_deg) / _SWELL_SUN_RAMP_DEG, 0.0, 1.0))
		s *= lerpf(params.swell_sun_corridor_gain, 1.0, t)
	return s


static func _swell_hero(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## S_hero: S_raw, 0 on the hero flat disc + skirt, full swell_hero_fade_m beyond.
	var d_hero := xz.distance_to(VillageLayout.HERO_DOOR_STOOP)
	var w := _smooth(clampf((d_hero - params.hero_flat_r_m - params.hero_skirt_m)
		/ maxf(params.swell_hero_fade_m, 0.01), 0.0, 1.0))
	if w <= 0.0:
		return 0.0
	return _swell_raw(xz, layout, params, t_seed) * w


# ── Village hill P and the large layer (ivy-82zn.14.10) ──────────────────────

static func hill_centre(layout: VillageLayout, params: VillageTerrainParams) -> Vector2:
	## Hill centre: the hero stoop moved toward the hamlet centre G by hill_centre_shift.
	return VillageLayout.HERO_DOOR_STOOP.lerp(layout.hamlet_centre_xz, clampf(params.hill_centre_shift, 0.0, 1.0))


static func hill_crest_r(params: VillageTerrainParams) -> float:
	## Flat crest radius: hero flat disc + hero skirt + hill_crest_extra_m.
	return maxf(params.hero_flat_r_m, 0.0) + maxf(params.hero_skirt_m, 0.0) + maxf(params.hill_crest_extra_m, 0.0)


static func village_edge_r(layout: VillageLayout, params: VillageTerrainParams) -> float:
	## Distance from the hill centre to the farthest grown cottage-pad corner + hill_end_margin_m
	## (INF without cottages). Cached per layout + the params it reads.
	var key := "%d|%d|%.5f|%.5f|%.5f" % [layout.generation_seed, layout.cottages.size(),
		params.hill_centre_shift, params.hill_end_margin_m, params.pad_margin_m]
	if key == _village_edge_key:
		return _village_edge_r
	var c := hill_centre(layout, params)
	var r := -1.0
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
				Vector2(rect.position.x, rect.end.y)]:
			r = maxf(r, corner.distance_to(c))
	_village_edge_r = INF if r < 0.0 else r + params.hill_end_margin_m
	_village_edge_key = key
	return _village_edge_r


static func _ray_to_circle(c: Vector2, dir: Vector2, centre: Vector2, radius: float) -> float:
	## Distance from c along unit dir to the circle (centre, radius); c inside the circle.
	var oc := c - centre
	var b := dir.dot(oc)
	var cc := oc.dot(oc) - radius * radius
	return -b + sqrt(maxf(b * b - cc, 0.0))


static func hill_y(xz: Vector2, layout: VillageLayout, params: VillageTerrainParams) -> float:
	## P (local frame, rim datum 0): hill_rise_m on the crest (d <= hill_crest_r), falling along each
	## ray from the hill centre to 0 at D = min(village edge, rim band inner circle); 0 beyond, so 0
	## in the whole rim band (AC-VT8 untouched). u = (d - r_c) / (D - r_c), t = u^hill_falloff_pow,
	## S = lerp(t, smoothstep(t), hill_shoulder), P = rise × (1 − S). Same as tools/probe_village_hill.gd.
	if params.variant == 1 or not layout.is_generated or params.hill_rise_m == 0.0:
		return 0.0
	var g := layout.hamlet_centre_xz
	var r_in := layout.lawn_radius - params.rim_blend_m
	## 1 mm guard: P is ~1e-6 m (not 0) at the band edge from float rounding of the ray distance.
	if xz.distance_to(g) >= r_in - 0.001:
		return 0.0
	var c := hill_centre(layout, params)
	var d := xz.distance_to(c)
	var r_c := hill_crest_r(params)
	if d <= r_c:
		return params.hill_rise_m
	var dir := (xz - c) / d
	var d_end := minf(_ray_to_circle(c, dir, g, r_in), village_edge_r(layout, params))
	if d >= d_end:
		return 0.0
	var u := clampf((d - r_c) / maxf(d_end - r_c, 0.5), 0.0, 1.0)
	var t := pow(u, maxf(params.hill_falloff_pow, 0.05))
	var s := lerpf(t, _smooth(t), clampf(params.hill_shoulder, 0.0, 1.0))
	## Toe: ease the last _HILL_TOE_U of the fall into the edge with zero slope (C1). With a shoulder
	## < 1 the profile otherwise met 0 at an angle — a crease at the village edge / rim band that the
	## 1 m grass LUT and the 2 m mesh drew as a line. Only lowers P near the edge.
	s = lerpf(s, 1.0, _smooth((u - (1.0 - _HILL_TOE_U)) / _HILL_TOE_U))
	## Same at the crest edge: the fall starts with zero slope (no crease at the hero ring).
	s *= _smooth(u / _HILL_TOE_U)
	return params.hill_rise_m * (1.0 - s)


static func hero_datum_y(layout: VillageLayout, params: VillageTerrainParams) -> float:
	## Local terrain height of the hero flat disc (= P at the stoop). World lowers VillageBackdrop
	## and the ground plane by this so the hero ground stays at world y = 0 (option A datum).
	## 0 for variant 1 / classic (AC-VT1 / INV-15).
	if params.variant == 1 or not layout.is_generated:
		return 0.0
	return Y_BASE + hill_y(VillageLayout.HERO_DOOR_STOOP, layout, params)


static func _large_raw(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## L = P + village swell (the swell is 0 on the hero disc + skirt and fades before the rim band).
	return hill_y(xz, layout, params) + _swell_hero(xz, layout, params, t_seed)


# ── Terraces on the large layer (slope-bounded cone clamp) ───────────────────
# Each terrace (cottage pad rect, pond rim circle, level plaza rect) is levelled at an anchor.
# L_t = max(lower, min(L, upper)) where lower / upper are the max / min of cones of slope
# c = tan(hill_bank_max_deg) × _TERRACE_BANK_SAFETY standing on every terrace core, plus the hero
# ring (datum, tan 8° across the hero skirt, then c) and the rim band (0). Min / max / clamp of
# c-Lipschitz functions are c-Lipschitz, so no bank is steeper than the cap (where L itself is
# gentler), with no skirt widths to tune. Inside a core both envelopes equal the anchor when the
# anchors are consistent (|a_i − a_j| <= c × gap_ij), which the relaxation below arranges.

static func _terrace_cone_slope(params: VillageTerrainParams) -> float:
	return tan(deg_to_rad(clampf(params.hill_bank_max_deg, 1.0, 80.0))) * _TERRACE_BANK_SAFETY


static func _hero_cone_drop(d_from_stoop: float, params: VillageTerrainParams) -> float:
	## How far the ground may leave the hero datum at this distance from the stoop: 0 on the flat
	## disc, tan 8° (× 0.9) across the hero skirt (AC: hero ring <= 8°), then the flank cap — so the
	## large layer's flank (steepest behind the hero, where the lawn rim is ~30 m away) stays at most
	## _HILL_FLANK_MAX_DEG and the detail layer on top keeps the open lawn <= 30°.
	var d := maxf(d_from_stoop - params.hero_flat_r_m, 0.0)
	var skirt := maxf(params.hero_skirt_m, 0.0)
	return tan(deg_to_rad(8.0)) * 0.9 * minf(d, skirt) + _hill_flank_slope(params) * maxf(d - skirt, 0.0)


static func _hill_flank_slope(params: VillageTerrainParams) -> float:
	return minf(tan(deg_to_rad(_HILL_FLANK_MAX_DEG)), _terrace_cone_slope(params))


static func _terraces(layout: VillageLayout, params: VillageTerrainParams, t_seed: int) -> Array:
	var gen := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	var key := "%d|%d|n%d|h%d" % [gen, t_seed, layout.cottages.size(), _params_sig_hash(params)]
	if key == _terrace_key:
		return _terrace_items
	var items: Array = []
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		items.append({"pad": true, "circle": false, "rect": rect, "centre": rect.get_center(),
			"radius": 0.0, "strength": 1.0, "anchor": _large_raw(rect.get_center(), layout, params, t_seed)})
	var pond_c := layout.pond_center
	if pond_c != Vector2.ZERO:
		var r_rim := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m
		items.append({"pad": false, "circle": true, "rect": Rect2(pond_c - Vector2(r_rim, r_rim), Vector2(2.0 * r_rim, 2.0 * r_rim)),
			"centre": pond_c, "radius": r_rim, "strength": 1.0,
			"anchor": _large_raw(pond_c, layout, params, t_seed)})
	if layout.plaza_rect.has_area() and params.plaza_hill_follow < 1.0:
		items.append({"pad": false, "circle": false, "plaza": true, "rect": layout.plaza_rect,
			"centre": layout.plaza_rect.get_center(), "radius": 0.0,
			"anchor": _large_raw(layout.plaza_rect.get_center(), layout, params, t_seed)})
	# Relaxation to consistent anchors (|a_i − a_j| <= c × gap_ij, cores inside the hero and rim
	# envelopes). Bounds per terrace: the hero envelope at its nearest core point (a floor and a
	# cap) and the rim envelope at its farthest (a cap). Floors propagate to neighbours (a terrace
	# below a floored one is filled just enough). Then lower-only: the higher of a pair is cut down,
	# never the lower filled, so relaxation adds to the hero-to-edge fall (AC: >= one cottage).
	var c := _terrace_cone_slope(params)
	var datum := hill_y(VillageLayout.HERO_DOOR_STOOP, layout, params)
	var g_lawn := layout.hamlet_centre_xz
	var r_in := layout.lawn_radius - params.rim_blend_m
	var floors := PackedFloat32Array()
	var caps := PackedFloat32Array()
	var ring_r := maxf(params.hero_flat_r_m, 0.0) + maxf(params.hero_skirt_m, 0.0)
	for it: Dictionary in items:
		it["far"] = _terrace_far_r(it, g_lawn)
		# No terrace cone may reach into the hero ring (it would set the ring slope to c, not 8°):
		# |a − datum| <= c × (distance from the core to the ring's outer edge).
		var d_near := maxf(_terrace_sdf(VillageLayout.HERO_DOOR_STOOP, it), 0.0)
		var d_ring := maxf(d_near - ring_r, 0.0)
		var hero_drop := minf(_hill_flank_slope(params) * d_ring, c * _cone_run(d_ring))
		var rim_room := c * _cone_run(maxf(r_in - float(it["far"]), 0.0))
		floors.append(maxf(datum - hero_drop, -rim_room))
		caps.append(minf(datum + hero_drop, rim_room))
	var budgets := {}
	for i in range(items.size()):
		for j in range(i + 1, items.size()):
			var gap := _terrace_gap(items[i], items[j]) if not items[i]["circle"] \
				else _terrace_gap(items[j], items[i])
			## c × run(gap). Exact consistency with rounded feet would need c × 2 run(gap / 2) (the
			## cones meet midway), but that tighter budget cascaded hero floors outward and cost seed 13
			## 1.6 m of fall; the residual conflicts (lo > hi, < c × foot / 2 = 0.3 m, between close
			## pads only) resolve to the lower envelope, still within the bank cap.
			budgets[Vector2i(i, j)] = c * _cone_run(gap)
	for _iter in range(_PAD_RELAX_ITERS * 2):
		var raised := false
		for key_ij: Vector2i in budgets:
			var b_ij: float = budgets[key_ij]
			if floors[key_ij.y] < floors[key_ij.x] - b_ij - 1e-5:
				floors[key_ij.y] = floors[key_ij.x] - b_ij
				raised = true
			elif floors[key_ij.x] < floors[key_ij.y] - b_ij - 1e-5:
				floors[key_ij.x] = floors[key_ij.y] - b_ij
				raised = true
		if not raised:
			break
	for k in range(items.size()):
		items[k]["anchor"] = maxf(minf(float(items[k]["anchor"]), caps[k]), floors[k])
	for _iter in range(_PAD_RELAX_ITERS * 4):
		var moved := false
		for key_ij: Vector2i in budgets:
			var b_ij: float = budgets[key_ij]
			var ai: float = items[key_ij.x]["anchor"]
			var aj: float = items[key_ij.y]["anchor"]
			if ai > aj + b_ij + 1e-5 and ai > floors[key_ij.x] + 1e-5:
				items[key_ij.x]["anchor"] = maxf(aj + b_ij, floors[key_ij.x])
				moved = true
			elif aj > ai + b_ij + 1e-5 and aj > floors[key_ij.y] + 1e-5:
				items[key_ij.y]["anchor"] = maxf(ai + b_ij, floors[key_ij.y])
				moved = true
		if not moved:
			break
	for it: Dictionary in items:
		it["skirt"] = _terrace_reach(it, layout, params, t_seed, c)
	_terrace_items = items
	_terrace_key = key
	return items


static func _terrace_reach(
		it: Dictionary,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		c_aim: float) -> float:
	## How far beyond its core a terrace's bank can reach (masks for tests / path grading only; the
	## surface itself needs no width): the core edge is |anchor − L(c)| + a·g off L, and the cone
	## (slope c) closes on L (slope g) at c − g per metre.
	var centre: Vector2 = it["centre"]
	var e := 1.0
	var gx := (_large_raw(centre + Vector2(e, 0.0), layout, params, t_seed)
		- _large_raw(centre - Vector2(e, 0.0), layout, params, t_seed)) / (2.0 * e)
	var gz := (_large_raw(centre + Vector2(0.0, e), layout, params, t_seed)
		- _large_raw(centre - Vector2(0.0, e), layout, params, t_seed)) / (2.0 * e)
	var g := sqrt(gx * gx + gz * gz)
	var a: float = it["radius"]
	if not it["circle"]:
		var half: Vector2 = (it["rect"] as Rect2).size * 0.5
		a = (half.x * absf(gx) + half.y * absf(gz)) / g if g > 1e-6 else maxf(half.x, half.y)
	var dh0 := absf(float(it["anchor"]) - _large_raw(centre, layout, params, t_seed)) + a * g
	return clampf(dh0 / maxf(c_aim - g, 0.05), _TERRACE_SKIRT_MIN_M, _TERRACE_SKIRT_MAX_M)


static func _terrace_far_r(it: Dictionary, g: Vector2) -> float:
	## Farthest point of a terrace core from the hamlet centre G.
	if it["circle"]:
		return (it["centre"] as Vector2).distance_to(g) + float(it["radius"])
	var rc: Rect2 = it["rect"]
	var far := 0.0
	for corner: Vector2 in [rc.position, Vector2(rc.end.x, rc.position.y), rc.end, Vector2(rc.position.x, rc.end.y)]:
		far = maxf(far, corner.distance_to(g))
	return far


static func _terrace_sdf(xz: Vector2, it: Dictionary) -> float:
	if it["circle"]:
		return xz.distance_to(it["centre"] as Vector2) - float(it["radius"])
	return _rect_sdf(xz, it["rect"] as Rect2)


static func _terrace_gap(a: Dictionary, b: Dictionary) -> float:
	## Gap between a rect terrace core and another terrace core (rect or circle).
	if b["circle"]:
		return maxf(_rect_sdf(b["centre"] as Vector2, a["rect"] as Rect2) - float(b["radius"]), 0.0)
	return _rect_gap(a["rect"] as Rect2, b["rect"] as Rect2)


static func _large_terraced(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## L_t: L clamped between the terrace / hero / rim cone envelopes (see the section comment).
	## A level plaza (plaza_hill_follow < 1) is a terrace blended in by (1 − follow).
	var l := _large_raw(xz, layout, params, t_seed)
	var items := _terraces(layout, params, t_seed)
	var c := _terrace_cone_slope(params)
	## Hard envelopes (lo / hi: exact cores, final clamp) and smooth ones (los / his: rounded ridges
	## and valleys where two cones meet, so the 1 m LUT and the 2 m mesh follow them).
	var env := [-INF, INF, -INF, INF]  # lo, hi, los, his
	var env_p := [-INF, INF, -INF, INF]
	var has_plaza := false
	for it: Dictionary in items:
		var d := _cone_run(maxf(_terrace_sdf(xz, it), 0.0))
		var a: float = it["anchor"]
		if it.get("plaza", false):
			has_plaza = true
			_env_add(env_p, a - c * d, a + c * d)
			continue
		_env_add(env, a - c * d, a + c * d)
	var datum := hill_y(VillageLayout.HERO_DOOR_STOOP, layout, params)
	var drop := _hero_cone_drop(xz.distance_to(VillageLayout.HERO_DOOR_STOOP), params)
	_env_add(env, datum - drop, datum + drop)
	var rim_room := c * maxf(layout.lawn_radius - params.rim_blend_m - xz.distance_to(layout.hamlet_centre_xz), 0.0)
	_env_add(env, -rim_room, rim_room)
	## Where envelopes conflict (lo > hi: a level terrace that cannot fit between the hero ring and
	## the rim band) the lower envelope wins; max / min keep it c-Lipschitz either way.
	var h := _soft_clamp(l, env)
	if has_plaza:
		_env_add(env_p, env[0], env[1])
		_env_add(env_p, env[2], env[3], true)
		var hp := _soft_clamp(l, env_p)
		h = lerpf(h, hp, 1.0 - clampf(params.plaza_hill_follow, 0.0, 1.0))
	return h


static func _env_add(env: Array, lo_v: float, hi_v: float, smooth_only: bool = false) -> void:
	## Fold one cone pair into [lo, hi, smooth lo, smooth hi].
	if not smooth_only:
		env[0] = maxf(env[0], lo_v)
		env[1] = minf(env[1], hi_v)
	env[2] = lo_v if is_inf(env[2]) else _smax(env[2], lo_v, _TERRACE_ROUND_M)
	env[3] = hi_v if is_inf(env[3]) else _smin(env[3], hi_v, _TERRACE_ROUND_M)


## Bank top / toe rounding height (m). A hard clamp leaves a crease where a bank cone meets the
## hill; the 1 m grass / scatter LUT then misses the crease by up to ~13 cm (AC-VT9: 6 cm), and the
## 2 m lawn mesh shades it as a hard line. Rounded over ~k / slope-change metres.
const _TERRACE_ROUND_M := 0.6


## Bank foot rounding (m): a terrace cone rises as d² / 2r over the first r metres out of its core,
## then at full slope (C1 at the core edge, still <= c, core exactly flat).
## 0.3 m: every gap between two terraces loses c × foot / 2 of allowed step (1.0 m cost seeds 13 /
## 30 up to 0.9 m of the hero-to-edge fall through dense pad chains).
const _TERRACE_FOOT_M := 0.3


static func _cone_run(d: float) -> float:
	if d < _TERRACE_FOOT_M:
		return d * d / (2.0 * _TERRACE_FOOT_M)
	return d - _TERRACE_FOOT_M * 0.5


static func _soft_clamp(l: float, env: Array) -> float:
	## clamp(l, lo, hi) on the smooth envelopes with the l-vs-envelope corners rounded (polynomial
	## smooth max / min keep the slope a convex mix of the inputs', so the bank cap holds), then a
	## hard clamp to the hard envelopes so a core (lo == hi) is exactly its anchor. lo > hi
	## (conflict): lo wins, as the hard clamp would.
	var lo: float = env[0]
	var hi: float = env[1]
	if lo >= hi:
		return lo
	## Rounding scales down where the envelopes are tight (rim band edge, near a core): with a fixed
	## 0.6 m it pulled a hill-free lawn 6 cm toward the lower bound just inside the rim band.
	var k := minf(_TERRACE_ROUND_M, 0.5 * (hi - lo))
	if k <= 1e-4:
		return clampf(l, lo, hi)
	var s := _smax(l, env[2], k)
	s = _smin(s, env[3], k)
	return clampf(s, lo, hi)


static func _smin(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


static func _smax(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return maxf(a, b) + h * h * k * 0.25


static func detail_y(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## R: the detail layer alone (no hill, no swell, no path correction) — tests / probes.
	if params.variant == 1 or not layout.is_generated:
		return 0.0
	if xz.distance_to(layout.hamlet_centre_xz) >= layout.lawn_radius:
		return 0.0
	_sig_batch_begin(params)
	var kc := _knoll_centres_cached(layout, params)
	var h := _detail(xz, layout, params, t_seed, kc)
	_sig_batch_end()
	return h


static func _detail(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> float:
	return _apply_stamps(_compose_base_with_knolls(xz, layout, params, t_seed, kc), xz, layout, params, t_seed, kc)


static func _total_no_path(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> float:
	return _large_terraced(xz, layout, params, t_seed) + _detail(xz, layout, params, t_seed, kc)


static func _total_height(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> float:
	## Local h (sample_y − Y_BASE) inside the lawn disc: L_t + R, path correction, hero disc.
	var h := _total_no_path(xz, layout, params, t_seed, kc)
	h += _path_correction(xz, layout, params, t_seed, kc)
	return _apply_hero(h, xz, layout, params)


static func _apply_hero(
		h: float,
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams) -> float:
	## Hero flat disc at the hero datum, blended over hero_skirt_m (fix 3: the old 0.5 m pull to 0
	## made a ring cliff when the hero fades were 0).
	var datum := hill_y(VillageLayout.HERO_DOOR_STOOP, layout, params)
	var d := xz.distance_to(VillageLayout.HERO_DOOR_STOOP)
	if d < params.hero_flat_r_m:
		return datum
	if params.hero_skirt_m > 0.0 and d < params.hero_flat_r_m + params.hero_skirt_m:
		return lerpf(datum, h, _smooth((d - params.hero_flat_r_m) / params.hero_skirt_m))
	if params.hero_skirt_m <= 0.0 and params.hero_flat_r_m <= 0.0 and d <= 0.0:
		return datum
	return h


static func _pad_core_cover(xz: Vector2, layout: VillageLayout, params: VillageTerrainParams) -> float:
	## 1 inside any grown pad rect, fading to 0 over _PATH_PAD_FADE_M outside it.
	var cover := 0.0
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var sdf := _rect_sdf(xz, rect)
		if sdf >= _PATH_PAD_FADE_M:
			continue
		cover = maxf(cover, _fer(sdf, 0.0, _PATH_PAD_FADE_M))
	return cover


static func _pad_bank_weight(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## 1 on a pad or where a pad's terrace cone binds (its bank), easing to 0 as the cone clears L
	## by 0.7 m of cone run, and over the detail pad skirt. Path grading: door connectors may take
	## the bank, lanes keep max_path_slope_deg.
	var items := _terraces(layout, params, t_seed)
	var c := _terrace_cone_slope(params)
	var l := _large_raw(xz, layout, params, t_seed)
	var w := 0.0
	for i in range(layout.cottages.size()):
		var it: Dictionary = items[i]
		var d := maxf(_rect_sdf(xz, it["rect"] as Rect2), 0.0)
		w = maxf(w, _fer(d, 0.0, _cottage_pad_skirt_at(i, layout, params, t_seed)))
		var a: float = it["anchor"]
		var run := _cone_run(d)
		var clear := minf(a + c * run - l, l - (a - c * run))
		w = maxf(w, _fer(clear, 0.0, c * 0.7 + _TERRACE_ROUND_M * 0.25))
	return w


static func in_any_pad_terrace(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> bool:
	## True on a cottage pad or its bank, + ~0.7 m — the masks of the slope tests (AC 4): within
	## the detail pad skirt + 1 m of a grown pad rect, or where a pad's terrace cone is within 0.7 m
	## of binding (exact, from the surface; no estimated skirt width).
	if params.variant == 1 or not layout.is_generated:
		return false
	var items := _terraces(layout, params, t_seed)
	var c := _terrace_cone_slope(params)
	var l := _large_raw(xz, layout, params, t_seed)
	var margin := c * 0.7 + _TERRACE_ROUND_M * 0.25
	for i in range(layout.cottages.size()):
		var it: Dictionary = items[i]
		var d := maxf(_rect_sdf(xz, it["rect"] as Rect2), 0.0)
		if d < _cottage_pad_skirt_at(i, layout, params, t_seed) + 1.0:
			return true
		var a: float = it["anchor"]
		var run := _cone_run(d)
		if a + c * run - l < margin or l - (a - c * run) < margin:
			return true
	return false


static func pad_terrace_reach_m(layout: VillageLayout, params: VillageTerrainParams, t_seed: int) -> float:
	## Widest pad bank (terrace skirt or detail pad skirt) — tests / probes.
	var items := _terraces(layout, params, t_seed)
	var reach := pad_skirt_outer_m(params, layout, t_seed)
	for i in range(layout.cottages.size()):
		reach = maxf(reach, float(items[i]["skirt"]))
	return reach


static func pond_terrace_outer_m(layout: VillageLayout, params: VillageTerrainParams, t_seed: int) -> float:
	## Distance from the pond centre beyond which neither the basin nor the pond terrace reaches.
	var r_rim := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m
	var outer := r_rim + params.pond_skirt_m + 1.0
	for it: Dictionary in _terraces(layout, params, t_seed):
		if it["circle"]:
			outer = maxf(outer, float(it["radius"]) + float(it["skirt"]) + 1.0)
	return outer


# ── Path correction (ivy-82zn.14.10 fix 1) ────────────────────────────────────

static func _path_correction(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> float:
	## The graded path spine as a correction (spine − raw ground at the foot), faded to 0 over the
	## 5 m corridor and near pads. Was a hard replace inside 5 m: a C0 step on both sides of every
	## path that the 2 m lawn mesh drew as dark parallel lines (ivy-82zn.14.9 diagnosis 1).
	var hit := _closest_on_paths(xz, layout)
	var dist: float = hit["dist"]
	if dist >= _PATH_CORRIDOR_OUTER_M:
		return 0.0
	var w := _fer(dist, _PATH_FLAT_CORE_M, _PATH_CORRIDOR_OUTER_M)
	if w <= 0.0:
		return 0.0
	w *= 1.0 - _pad_core_cover(xz, layout, params)
	if w <= 0.0:
		return 0.0
	_ensure_path_spine(layout, params, t_seed, kc)
	return w * _path_spine_delta(hit)


static func _apply_stamps(
		h: float,
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> float:
	## Detail layer R (ivy-82zn.14.10): ascending-priority stamp chain base < plaza < pond < pads <
	## hero (SD-VILLAGE-TERRAIN-4). Each stamp: h = lerp(h, h_target, w). Last wins where they overlap.

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
	# Every caller passes h = _compose_base_with_knolls(xz) (default path quiet), so after the plaza
	# and pond stamps above h is exactly _height_through_pond_at(xz): hand it over, not recompute.
	var pad_blend := _blended_cottage_pad_height(xz, layout, params, t_seed, kc, h)
	if pad_blend["active"]:
		h = pad_blend["h"]

	# ── Priority 5: Hero sanctum — highest (SD-VILLAGE-TERRAIN-4 §Hero sanctum) ──
	# Detail layer only: R → 0 over the hero skirt and 0 on the disc; the total height then pins the
	# disc to the hero datum (_apply_hero). Paths are a correction on the total (_path_correction).
	var d_hero := xz.distance_to(VillageLayout.HERO_DOOR_STOOP)
	var w_hero := _fer(d_hero, params.hero_flat_r_m, params.hero_flat_r_m + params.hero_skirt_m)
	if w_hero > 0.0:
		h = lerpf(h, 0.0, w_hero)

	# Final safety clamp (SD-VILLAGE-TERRAIN-3 step 4) — detail layer only, never the hill.
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
	## Base noise uses pad × feature terms; knolls use the feature term only (ivy-82zn.14.1).
	return _pad_relief_scale(xz, layout, params) * _feature_relief_scale(xz, layout, params)


static func _pad_relief_scale(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams) -> float:
	## Relief quiet near cottage pads (open_lawn_pad_quiet_m, then open_lawn_pad_fade_m ramp).
	var pad_scale := 1.0
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var dout := maxf(_rect_sdf(xz, rect), 0.0)
		var t := clampf(
			(dout - params.open_lawn_pad_quiet_m) / maxf(params.open_lawn_pad_fade_m, RELIEF_FADE_FLOOR_M), 0.0, 1.0)
		pad_scale = minf(pad_scale, _smooth(t))
	return pad_scale


static func _feature_relief_scale(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams) -> float:
	## Relief quiet near the hero disc, plaza and pond (their *_relief_fade_m ramps).
	var scale := 1.0
	var d_hero := xz.distance_to(VillageLayout.HERO_DOOR_STOOP)
	## Fades floored at RELIEF_FADE_FLOOR_M (ivy-82zn.14.10 fix 2): 0 made C0 rings.
	var hero_t := clampf((d_hero - params.hero_flat_r_m)
			/ maxf(params.hero_relief_fade_m, RELIEF_FADE_FLOOR_M), 0.0, 1.0)
	scale *= _smooth(hero_t)
	if layout.plaza_rect.has_area():
		var plaza_out := maxf(_rect_sdf(xz, layout.plaza_rect), 0.0)
		var plaza_t := clampf(plaza_out / maxf(params.plaza_relief_fade_m, RELIEF_FADE_FLOOR_M), 0.0, 1.0)
		scale *= _smooth(plaza_t)
	var d_pond := xz.distance_to(layout.pond_center)
	var r_rim := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m
	var pond_t := clampf((d_pond - r_rim * 0.85) / maxf(params.pond_relief_fade_m, RELIEF_FADE_FLOOR_M), 0.0, 1.0)
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
	return "%d|%d|n%d|h%d" % [gen, t_seed, layout.cottages.size(), _params_sig_hash(params)]


## Params signature hash memo (ivy-82zn.14.7). to_dict() walks get_property_list(), and every
## cache-key check (pad table per cottage, path spine, LUT) re-ran it, many times per sample.
## Inside a sig batch the params object cannot change, so its hash is computed once. Outside a
## batch, or for a different params object, the hash is recomputed as before.
static var _sig_batch_params: VillageTerrainParams = null
static var _sig_batch_hash: int = 0
static var _sig_batch_depth: int = 0


static func _sig_batch_begin(params: VillageTerrainParams) -> void:
	if _sig_batch_depth == 0:
		_sig_batch_params = params
		_sig_batch_hash = hash(_params_signature_dict(params))
	_sig_batch_depth += 1


static func _sig_batch_end() -> void:
	_sig_batch_depth = maxi(_sig_batch_depth - 1, 0)
	if _sig_batch_depth == 0:
		_sig_batch_params = null


static func _params_sig_hash(params: VillageTerrainParams) -> int:
	if _sig_batch_depth > 0 and params == _sig_batch_params:
		return _sig_batch_hash
	return hash(_params_signature_dict(params))


static func _params_signature_dict(params: VillageTerrainParams) -> Dictionary:
	## Height-shaping params for cache keys (layout_seed is keyed separately; wanderer is a consumer).
	var pdict := params.to_dict()
	pdict.erase("layout_seed")
	pdict.erase("wanderer_follow_terrain")
	return pdict


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
	## The plaza is a fixed participant (ivy-82zn.14.1): with the swell it is off datum, and a pad
	## skirt that runs into the plaza skirt must not step between the two flat heights (seed 17
	## path 8.27° at (-11.3, -16.5), pad skirt 1.7 m from the pad, 2 m from the plaza rect).
	## Budget: grown-pad-rect to plaza-rect gap × grade cap / _PAD_PLAZA_RAMP_PEAK, because the pad
	## skirt and the plaza skirt are two overlapping smoothsteps (peak grade ~2× the mean).
	var has_plaza := layout.plaza_rect.has_area()
	var h_plaza := 0.0
	var plaza_dh_max := PackedFloat32Array()
	plaza_dh_max.resize(n)
	var pad_rects: Array[Rect2] = []
	for i in range(n):
		pad_rects.append(VillageBackdrop.cottage_exterior_rect(layout.cottages[i]).grow(params.pad_margin_m))
	if has_plaza:
		h_plaza = _compose_base_with_knolls(layout.plaza_rect.get_center(), layout, params, t_seed, kc) \
			+ params.plaza_relief_m
		for i in range(n):
			plaza_dh_max[i] = grade_cap * maxf(_rect_gap(pad_rects[i], layout.plaza_rect), 0.5) / _PAD_PLAZA_RAMP_PEAK
	for _iter in range(_PAD_RELAX_ITERS):
		if has_plaza:
			for i in range(n):
				heights[i] = clampf(heights[i], h_plaza - plaza_dh_max[i], h_plaza + plaza_dh_max[i])
		for i in range(n):
			for j in range(i + 1, n):
				var gap := maxf(centres[i].distance_to(centres[j]) - _PAD_COTTAGE_HALF_REACH_M, 2.0)
				## Same two-skirt budget as the plaza for neighbours whose skirts meet (ivy-82zn.14.1:
				## swell put pads at different heights; seeds 2 and 8 hit 9.0-9.2° between two skirts).
				var max_dh := minf(grade_cap * gap,
					grade_cap * maxf(_rect_gap(pad_rects[i], pad_rects[j]), 0.5) / _PAD_PLAZA_RAMP_PEAK)
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
				_PAD_SKIRT_PEAK_FACTOR * dh_need / maxf(grade_probe, 0.01) + 0.5)
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
		kc: Array[Vector2],
		h_through_pond: float = NAN) -> Dictionary:
	## Partition-of-unity pad stamp: avoids sequential lerp resets from near-zero weights (AC-VT5).
	## h_through_pond: _height_through_pond_at(xz) when the caller already has it (ivy-82zn.14.7:
	## _apply_stamps and the path spine computed it twice per point); NAN = compute it here.
	var pad_data := _cottage_pad_layout_cached(layout, params, t_seed)
	var skirts: PackedFloat32Array = pad_data["skirts"]
	var h_outer := h_through_pond if not is_nan(h_through_pond) \
		else _height_through_pond_at(xz, layout, params, t_seed, kc)
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
		var lip_m := pad_skirt * grade_cap / _PAD_SKIRT_PEAK_FACTOR
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


static func _rect_gap(a: Rect2, b: Rect2) -> float:
	## Shortest distance between two axis-aligned rects (0 when they touch or overlap).
	var d := (a.get_center() - b.get_center()).abs() - (a.size + b.size) * 0.5
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()


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
	## Every params field _knoll_rejected reads must be here (ivy-82zn.14.5, review MINOR-2).
	return "%d|ls%d|v%d|k%d|kh%.4f|kr%.3f|ks%.2f|khc%.2f|ksun%.1f|pm%.3f|kpc%.3f|kpd%.3f|rb%.3f" % [
		layout.generation_seed if layout.generation_seed > 0 else params.layout_seed,
		params.layout_seed, params.variant, params.knoll_count,
		params.knoll_height_m, params.knoll_radius_m, params.knoll_min_sep_m,
		params.knoll_hero_clear_m, params.knoll_sun_corridor_half_deg,
		params.pad_margin_m, params.knoll_path_clear_m, params.knoll_pad_clear_m,
		params.rim_blend_m]


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
	_terrace_key = ""
	_terrace_items = []
	_village_edge_key = ""
	_pond_outline_min_cache.clear()


static func _sample_lut_cache_key(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		cell_m: float) -> String:
	var gen := layout.generation_seed if layout.is_generated else 0
	return "%d|%d|%.5f|%d" % [gen, t_seed, cell_m, _params_sig_hash(params)]


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
	# Rim band: the whole footprint must end before the rim taper starts (ivy-82zn.14.5). A mound
	# flank inside the 5 m rim smoothstep makes a 14-17° scarp at the lawn edge (review MAJOR-1).
	if p.distance_to(g) + params.knoll_radius_m > layout.lawn_radius - params.rim_blend_m:
		return true
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
	## ivy-82zn.14.1: own knob (was knoll_radius_m); knoll_shield still tapers the mound to 0 at
	## the stones, so a centre closer than one radius only lowers the path-side flank.
	if _min_dist_to_paths(p, layout) < params.knoll_path_clear_m:
		return true
	# Too close to any cottage pad — same rule as paths, so the mound flank stays off the pad
	# relief-fade ramp (ivy-82zn.14.1: taller knolls hit ~11° there on seed 5).
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		if _rect_sdf(p, rect) < params.knoll_pad_clear_m:
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


static func _path_spine_delta(path_hit: Dictionary) -> float:
	## Graded spine minus raw ground at the path foot q (0 where the raw ground is within the grade
	## cap). Chains are indexed like layout.path_polylines(); _ensure_path_spine must have run.
	if _path_spine_chains.is_empty():
		return 0.0
	var chain_idx := 0
	var key: String = path_hit.get("cache_key", "")
	if key.contains("|"):
		chain_idx = int(key.split("|")[0])
	if chain_idx < 0 or chain_idx >= _path_spine_chains.size():
		return 0.0
	var chain: Dictionary = _path_spine_chains[chain_idx]
	var pts: PackedVector2Array = chain["pts"]
	if pts.size() < 2:
		return 0.0
	return _height_on_polyline_chain(path_hit["point"] as Vector2, pts, chain["delta"])


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
		pts: PackedVector2Array, hs: PackedFloat32Array, max_grads: PackedFloat32Array) -> void:
	## Grade clamp with a per-sample cap (a segment may use the larger of its two ends' caps).
	if pts.size() < 2:
		return
	for _clamp in range(14):
		for i in range(1, pts.size()):
			var seg_len := pts[i].distance_to(pts[i - 1])
			var max_dh := maxf(max_grads[i], max_grads[i - 1]) * maxf(seg_len, 0.01)
			var dh := hs[i] - hs[i - 1]
			if absf(dh) > max_dh:
				hs[i] = hs[i - 1] + signf(dh) * max_dh
		for i in range(pts.size() - 2, -1, -1):
			var seg_len := pts[i + 1].distance_to(pts[i])
			var max_dh := maxf(max_grads[i], max_grads[i + 1]) * maxf(seg_len, 0.01)
			var dh := hs[i] - hs[i + 1]
			if absf(dh) > max_dh:
				hs[i] = hs[i + 1] + signf(dh) * max_dh


static func _ensure_path_spine(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		kc: Array[Vector2]) -> void:
	## Spine heights read the whole ground (hill, swell, terraces, detail, hero), so the key hashes
	## every param, as the pad and LUT caches do (ivy-82zn.14.1: swell knobs).
	var key := "%d|%d|k%s|h%d" % [
		layout.generation_seed, t_seed, _knoll_cache_key(layout, params),
		_params_sig_hash(params)]
	if key == _path_spine_built_key:
		return
	if _path_spine_building:
		return
	_path_spine_building = true
	## Lanes: max_path_slope_deg. Door connectors on a pad bank may take the bank (hill_bank_max_deg),
	## blended by how far into the bank the sample is, so the clamp never builds a ramp out of a pad.
	var lane_grad := tan(deg_to_rad(clampf(params.max_path_slope_deg, 0.0, 85.0))) * _PATH_SPINE_GRADE_SAFETY
	var bank_grad := maxf(lane_grad, tan(deg_to_rad(clampf(params.hill_bank_max_deg, 0.0, 85.0))) * 1.25)
	_path_spine_chains.clear()
	## One chain per layout polyline, in order (empty when degenerate), so _closest_on_paths'
	## polyline index addresses its chain.
	var empty := {"pts": PackedVector2Array(), "hs": PackedFloat32Array(), "delta": PackedFloat32Array()}
	for polyline: Variant in layout.path_polylines():
		var poly: Array = polyline as Array
		if poly.size() < 2:
			_path_spine_chains.append(empty)
			continue
		var pts := PackedVector2Array()
		var hs := PackedFloat32Array()
		var grads := PackedFloat32Array()
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
			## Raw = the final ground without the path correction (hill terraces + detail + hero).
			hs.append(_apply_hero(_total_no_path(p, layout, params, t_seed, kc), p, layout, params))
			## On a pad (+ the correction fade) the spine is nearly ungraded (grade 4 = 76°), so a
			## lane's correction is caught back to ~0 within ~0.2 m there, before _path_correction
			## fades it out: no step at the door.
			if _pad_core_cover(p, layout, params) > 0.0:
				grads.append(4.0)
			else:
				grads.append(lerpf(lane_grad, bank_grad, _pad_bank_weight(p, layout, params, t_seed)))
			dist_along += _PATH_SPINE_SAMPLE_M
		## Always end on the polyline's last point (junction partners link to it).
		var p_end: Vector2 = poly[poly.size() - 1] as Vector2
		if not pts.is_empty() and p_end.distance_to(pts[pts.size() - 1]) >= 0.04:
			pts.append(p_end)
			hs.append(_apply_hero(_total_no_path(p_end, layout, params, t_seed, kc), p_end, layout, params))
			grads.append(4.0 if _pad_core_cover(p_end, layout, params) > 0.0
				else lerpf(lane_grad, bank_grad, _pad_bank_weight(p_end, layout, params, t_seed)))
		if pts.size() < 2:
			_path_spine_chains.append(empty)
			continue
		var raw := hs.duplicate()
		_clamp_path_spine_chain(pts, hs, grads)
		_path_spine_chains.append({"pts": pts, "hs": hs, "raw": raw, "grads": grads})
	_join_path_spine_chains()
	for chain: Dictionary in _path_spine_chains:
		var hs: PackedFloat32Array = chain["hs"]
		if hs.is_empty():
			continue
		var raw: PackedFloat32Array = chain["raw"]
		var delta := PackedFloat32Array()
		delta.resize(hs.size())
		for i in range(hs.size()):
			delta[i] = hs[i] - raw[i]
		chain["delta"] = delta
	_path_spine_built_key = key
	_path_spine_building = false


static func _join_path_spine_chains() -> void:
	## Grade every chain as one graph: samples of different polylines within 0.35 m of each other
	## (junctions, shared stretches) are linked like neighbours on a chain. Graded alone, two lanes
	## meeting at a junction disagreed by up to 0.6 m and the correction jumped where the nearest
	## polyline switched. Sweeps alternate chain clamps and junction links until nothing moves.
	var links: Array = []  # [chain_a, i_a, chain_b, i_b, len]
	var cell := 0.5
	var grid := {}
	for ci in range(_path_spine_chains.size()):
		var pts: PackedVector2Array = _path_spine_chains[ci]["pts"]
		for i in range(pts.size()):
			var k := Vector2i(floori(pts[i].x / cell), floori(pts[i].y / cell))
			if not grid.has(k):
				grid[k] = []
			(grid[k] as Array).append(Vector2i(ci, i))
	for ci in range(_path_spine_chains.size()):
		var pts: PackedVector2Array = _path_spine_chains[ci]["pts"]
		for i in range(pts.size()):
			var k := Vector2i(floori(pts[i].x / cell), floori(pts[i].y / cell))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var kk := k + Vector2i(dx, dz)
					if not grid.has(kk):
						continue
					for other: Vector2i in grid[kk]:
						if other.x <= ci:
							continue
						var q: Vector2 = (_path_spine_chains[other.x]["pts"] as PackedVector2Array)[other.y]
						var dd := pts[i].distance_to(q)
						if dd <= 0.35:
							links.append([ci, i, other.x, other.y, dd])
	if links.is_empty():
		return
	for _sweep in range(24):
		var moved := false
		for l: Array in links:
			var ha: PackedFloat32Array = _path_spine_chains[l[0]]["hs"]
			var hb: PackedFloat32Array = _path_spine_chains[l[2]]["hs"]
			var ga: PackedFloat32Array = _path_spine_chains[l[0]]["grads"]
			var gb: PackedFloat32Array = _path_spine_chains[l[2]]["grads"]
			## True link length (a 0.25 m floor let a 0.13 m junction link take 31°).
			var max_dh := maxf(ga[l[1]], gb[l[3]]) * maxf(float(l[4]), 0.01)
			var dh := ha[l[1]] - hb[l[3]]
			if absf(dh) <= max_dh + 1e-5:
				continue
			## Meet in the middle. (Packed arrays read out of a Dictionary are written back.)
			var mid := (ha[l[1]] + hb[l[3]]) * 0.5
			ha[l[1]] = mid + signf(dh) * max_dh * 0.5
			hb[l[3]] = mid - signf(dh) * max_dh * 0.5
			_path_spine_chains[l[0]]["hs"] = ha
			_path_spine_chains[l[2]]["hs"] = hb
			moved = true
		if not moved:
			break
		for chain: Dictionary in _path_spine_chains:
			var hs: PackedFloat32Array = chain["hs"]
			if hs.size() >= 2:
				_clamp_path_spine_chain(chain["pts"], hs, chain["grads"])
				chain["hs"] = hs


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
	var step := maxf(params.terrain_mesh_step_m, 0.1)
	var lut := build_sample_lut(layout, params, t_seed, step)
	var mesh := mesh_from_lut(layout, step, lut)
	if mesh != null:
		_displaced_mesh_cache[mesh_key] = mesh
		return mesh
	# Fallback: coarser grid
	var lut2 := build_sample_lut(layout, params, t_seed, 3.5)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_cartesian_disc_lut(st2, layout, layout.hamlet_centre_xz, layout.lawn_radius, 3.5, lut2)
	var mesh_fb := st2.commit()
	_displaced_mesh_cache[mesh_key] = mesh_fb
	return mesh_fb


static func mesh_from_lut(layout: VillageLayout, step: float, lut: Dictionary) -> ArrayMesh:
	## Cartesian disc mesh at `step` from an already-built LUT (shared by build_mesh and the
	## playground's coarse preview / time-sliced rebuild, ivy-82zn.14.7). Null when no triangles.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := _append_cartesian_disc_lut(
		st, layout, layout.hamlet_centre_xz, layout.lawn_radius, step, lut)
	if tris <= 0:
		return null
	return st.commit()


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


# ── Rendered lawn surface (ivy-82zn.14.10: pond bank drape) ───────────────────

static func mesh_surface_lut(layout: VillageLayout, params: VillageTerrainParams) -> Dictionary:
	## The LUT build_mesh triangulates (terrain_mesh_step_m cells; cached). {} for flat / classic.
	if params.variant == 1 or not layout.is_generated:
		return {}
	return build_sample_lut(layout, params, terrain_seed(layout, params), maxf(params.terrain_mesh_step_m, 0.1))


static func mesh_surface_y_from_lut(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		lut: Dictionary) -> float:
	## Height of the rendered LawnTerrain at xz: the same two triangles per cell as
	## _append_cartesian_disc_lut ([c0, c1, c2], [c0, c2, c3]), not the bilinear LUT and not the
	## exact sample_y. The pond bank ring drapes on this so it never pokes through or hides.
	if lut.is_empty() or params.variant == 1 or not layout.is_generated:
		return VillageBackdrop.LAWN_GROUND_Y_OFFSET
	var step: float = maxf(float(lut["cell_m"]), 0.1)
	var g := layout.hamlet_centre_xz
	var x0 := g.x - layout.lawn_radius
	var z0 := g.y - layout.lawn_radius
	var ix := floori((xz.x - x0) / step)
	var iz := floori((xz.y - z0) / step)
	var ax0 := x0 + float(ix) * step
	var az0 := z0 + float(iz) * step
	var ax1 := ax0 + step
	var az1 := az0 + step
	var fx := clampf((xz.x - ax0) / step, 0.0, 1.0)
	var fz := clampf((xz.y - az0) / step, 0.0, 1.0)
	var y0 := lut_sample(lut, Vector2(ax0, az0))
	var y1 := lut_sample(lut, Vector2(ax1, az0))
	var y2 := lut_sample(lut, Vector2(ax1, az1))
	var y3 := lut_sample(lut, Vector2(ax0, az1))
	var y: float
	if fx >= fz:
		y = y0 + fx * (y1 - y0) + fz * (y2 - y1)
	else:
		y = y0 + fz * (y3 - y0) + fx * (y2 - y3)
	return Y_BASE + y


static func mesh_surface_y(xz: Vector2, layout: VillageLayout, params: VillageTerrainParams) -> float:
	return mesh_surface_y_from_lut(xz, layout, params, mesh_surface_lut(layout, params))


static func max_mesh_cell_slope_deg(layout: VillageLayout, params: VillageTerrainParams) -> float:
	## Steepest triangle of the rendered lawn mesh (cliff guard, AC 4 'no lawn cell > 40°').
	var lut := mesh_surface_lut(layout, params)
	if lut.is_empty():
		return 0.0
	var step: float = float(lut["cell_m"])
	var g := layout.hamlet_centre_xz
	var outer := layout.lawn_radius
	var cols := int(ceil(2.0 * outer / step))
	var worst := 0.0
	for iz in range(cols):
		for ix in range(cols):
			var ax0 := g.x - outer + float(ix) * step
			var az0 := g.y - outer + float(iz) * step
			var c := [Vector2(ax0, az0), Vector2(ax0 + step, az0), Vector2(ax0 + step, az0 + step),
				Vector2(ax0, az0 + step)]
			var inside := 0
			for cp: Vector2 in c:
				if cp.distance_to(g) < outer:
					inside += 1
			if inside == 0:
				continue
			var y0 := lut_sample(lut, c[0])
			var y1 := lut_sample(lut, c[1])
			var y2 := lut_sample(lut, c[2])
			var y3 := lut_sample(lut, c[3])
			var ga := Vector2(y1 - y0, y2 - y1) / step
			var gb := Vector2(y2 - y3, y3 - y0) / step
			worst = maxf(worst, maxf(ga.length(), gb.length()))
	return rad_to_deg(atan(worst))


# ── Pond water level (ivy-82zn.14.10, single source for game + playground) ─────

static func pond_bank_outline_min_y(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	## Lowest sample_y along the pond's bank outer outline (cached per layout + params).
	var key := "%d|%d|%d|%s" % [layout.generation_seed, t_seed, _params_sig_hash(params), str(layout.pond_center)]
	if _pond_outline_min_cache.has(key):
		return _pond_outline_min_cache[key]
	var lo := INF
	for xz in VillagePondShape.at(layout.pond_center).bank_outer_outline_world_xz():
		lo = minf(lo, sample_y(xz, layout, params, t_seed))
	_pond_outline_min_cache[key] = lo
	return lo


static func pond_water_y(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		outline_min_y: float = NAN) -> float:
	## Water surface: basin anchor + lip − inset, never above the lowest bank outline point −
	## POND_WATER_BANK_CLEAR_M (so the water cannot spill over the draped bank). outline_min_y: a
	## precomputed pond_bank_outline_min_y (the playground slices that); NAN = compute it here.
	## Classic / variant 1: VillageBackdrop.POND_WATER_Y_OFFSET (INV-15).
	if params.variant == 1 or not layout.is_generated:
		return VillageBackdrop.POND_WATER_Y_OFFSET
	var floor_y := sample_y(layout.pond_center, layout, params, t_seed)
	var nominal := floor_y - params.pond_depth_m + params.pond_lip_rise_m - params.pond_water_inset_m
	var lo := outline_min_y
	if is_nan(lo):
		lo = pond_bank_outline_min_y(layout, params, t_seed)
	return minf(nominal, lo - POND_WATER_BANK_CLEAR_M)


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
	return Y_BASE + _total_height(xz, layout, params, t_seed, kc)


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
