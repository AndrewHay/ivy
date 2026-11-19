## VillageLandform — static, pure landform maths for the landscape-first village terrain.
## SD-VILLAGE-TERRAIN-17 (L, D, sun cap), -18 (offset search), -19 (site plane, ring width);
## AR-LF-API / AR-LF-D4. No state: every function takes a ctx from make_ctx.
##
## Frames: xz is backdrop-local (the layout frame). H0 = HERO_DOOR_STOOP, G = VILLAGE_GREEN_G.
## Compass azimuths: 0 = north (−Z), 90 = east (+X).
class_name VillageLandform
extends RefCounted

const HillsNoise = preload("res://src/playground/hills_noise.gd")

const NOISE_FBM := 0
const NOISE_BILLOW := 1
const NOISE_DDF := 2
const NOISE_RIDGED := 3

## Soft abs width for billow / ridged (SD-17 noise table: a plain abs creases every valley).
const SOFT_ABS_K := 0.15
## Offset search (SD-18): candidates uniform in ±CANDIDATE_RANGE_M per axis.
const CANDIDATE_RANGE_M := 2000.0
## Village disc for span / p95 (about G) and the hero ring disc (about H0, AR-LF-GAP-1).
const VILLAGE_R_M := 46.0
const HERO_RING_R_M := 40.0
const SEARCH_GRID_M := 4.0
## Plaza raw tilt hard rule in the search (AR-LF-GAP-4).
const PLAZA_RAW_TILT_MAX_DEG := 10.0
## Sun cap ramps in over d = 12 → 20 m from H0 (SD-17 §4).
const SUN_RAMP_START_M := 12.0
const SUN_RAMP_LEN_M := 8.0
## Raw LUT extent about G (AR-LF-API raw_lut).
const RAW_LUT_R_M := 62.0
## Offset ranks the generator tries (AR-LF-D5: up to 3). rank_offsets verifies rank 0 exactly
## (FD p95 + hero_ring_ok); the generator verifies ranks 1–2 lazily (verify_candidate).
const VERIFY_RANKS := 3
## Measured ring (SD-VILLAGE-TERRAIN-19, ivy-82zn.14.22): width ladder step, overlap tolerance and
## the node grid. Constants, not knobs.
const RING_LADDER_STEP_M := 0.5
const RING_OVERLAP_TOL_DEG := 3.0
const RING_GRID_M := 1.0
## DDF gradient finite-difference step in noise space (well conditioned: simplex is smooth).
const _DDF_H := 0.01


# ── Seeds and context ─────────────────────────────────────────────────────────

static func landform_seed(norm_seed: int) -> int:
	return VillageLayout._derive(norm_seed, VillageLayout.VILLAGE_LANDFORM_SALT)


static func detail_seed(norm_seed: int) -> int:
	return VillageLayout._derive(norm_seed, VillageLayout.VILLAGE_TERRAIN_SALT)


static func make_ctx(norm_seed: int, params, offset: Vector2 = Vector2.ZERO, rot_deg: float = 0.0) -> Dictionary:
	## {l_seed, d_seed, offset, rot_deg, cos, sin, params, y_hero_raw, s_hero}. y_hero_raw = mean of
	## L + D over the hero core (SD-19 hero target, raw and pre-cap).
	var r := deg_to_rad(rot_deg)
	var ctx := {
		"l_seed": landform_seed(norm_seed),
		"d_seed": detail_seed(norm_seed),
		"offset": offset,
		"rot_deg": rot_deg,
		"cos": cos(r),
		"sin": sin(r),
		"params": params,
	}
	ctx["_fbm"] = _fbm_prep(int(ctx["l_seed"]), params)
	var hero := disc_plane(VillageLandform.raw_y.bind(ctx), VillageLayout.HERO_DOOR_STOOP,
		params.hero_flat_r_m, 1.0)
	ctx["y_hero_raw"] = hero["mean"]
	ctx["s_hero"] = hero["slope_deg"]
	return ctx


# ── Noise (SD-VILLAGE-TERRAIN-17 §1 table) ────────────────────────────────────

static func landform_q(xz: Vector2, ctx: Dictionary) -> Vector2:
	## q = R(rot) · (xz − H0) + H0 + offset.
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var d := xz - h0
	var c: float = ctx["cos"]
	var s: float = ctx["sin"]
	return Vector2(c * d.x - s * d.y, s * d.x + c * d.y) + h0 + (ctx["offset"] as Vector2)


static func noise01(q: Vector2, ctx: Dictionary) -> float:
	var p = ctx["params"]
	var seed: int = ctx["l_seed"]
	match int(p.landform_noise):
		NOISE_BILLOW:
			return _billow01(q, seed, p)
		NOISE_DDF:
			return _ddf01(q, seed, p)
		NOISE_RIDGED:
			return _ridged01(q, seed, p)
	return HillsNoise.fbm_height_01(q, seed, p.landform_wavelength_m, p.landform_octaves,
		p.landform_persistence, p.landform_warp)


static func _sabs(s: float) -> float:
	return sqrt(s * s + SOFT_ABS_K * SOFT_ABS_K)


static func _billow01(q: Vector2, seed: int, p) -> float:
	var wp := HillsNoise.domain_warp(q, seed, p.landform_wavelength_m, p.landform_warp)
	var amp := 1.0
	var freq := 1.0 / maxf(p.landform_wavelength_m, 1.0)
	var sum := 0.0
	var norm := 0.0
	for i in range(maxi(int(p.landform_octaves), 1)):
		sum += amp * (1.0 - 2.0 * _sabs(HillsNoise._noise2d(wp * freq, seed + i * 7919)))
		norm += amp
		amp *= p.landform_persistence
		freq *= 2.0
	var lo := 1.0 - 2.0 * _sabs(1.0)
	var hi := 1.0 - 2.0 * SOFT_ABS_K
	return clampf((sum / norm - lo) / (hi - lo), 0.0, 1.0)


static func _ridged01(q: Vector2, seed: int, p) -> float:
	var wp := HillsNoise.domain_warp(q, seed, p.landform_wavelength_m, p.landform_warp)
	var amp := 1.0
	var freq := 1.0 / maxf(p.landform_wavelength_m, 1.0)
	var sum := 0.0
	var norm := 0.0
	for i in range(maxi(int(p.landform_octaves), 1)):
		var t := 1.0 - _sabs(HillsNoise._noise2d(wp * freq, seed + i * 7919))
		sum += amp * t * t
		norm += amp
		amp *= p.landform_persistence
		freq *= 2.0
	var hi := (1.0 - SOFT_ABS_K) * (1.0 - SOFT_ABS_K)
	return clampf((sum / norm) / hi, 0.0, 1.0)


static func _ddf01(q: Vector2, seed: int, p) -> float:
	## Quilez derivative-damped fBm: sum += a·s / (1 + k·|d|²), d = accumulated octave gradient in
	## octave noise coordinates (forward differences on the smooth simplex, h = 0.01).
	var wp := HillsNoise.domain_warp(q, seed, p.landform_wavelength_m, p.landform_warp)
	var amp := 1.0
	var freq := 1.0 / maxf(p.landform_wavelength_m, 1.0)
	var sum := 0.0
	var norm := 0.0
	var d := Vector2.ZERO
	for i in range(maxi(int(p.landform_octaves), 1)):
		var o_seed: int = seed + i * 7919
		var u := wp * freq
		var s := _simplex1(u, o_seed)
		var sx := _simplex1(u + Vector2(_DDF_H, 0.0), o_seed)
		var sz := _simplex1(u + Vector2(0.0, _DDF_H), o_seed)
		d += Vector2(sx - s, sz - s) / _DDF_H
		sum += amp * s / (1.0 + p.landform_ddf_k * d.length_squared())
		norm += amp
		amp *= p.landform_persistence
		freq *= 2.0
	return clampf((sum / norm) * 0.5 + 0.5, 0.0, 1.0)


static var _simplex1_cache: Dictionary = {}


static func _simplex1(p: Vector2, seed: int) -> float:
	## Single-octave simplex (FRACTAL_NONE). HillsNoise._noise2d is FastNoiseLite's default 5-octave
	## fractal; its high octaves put a huge Hessian into the DDF gradient (58° spikes, probe
	## .tmp/landscape_first/ddf_probe.gd), so the derivative-damped variant uses this one.
	var n: FastNoiseLite = _simplex1_cache.get(seed)
	if n == null:
		n = FastNoiseLite.new()
		n.seed = seed
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		n.frequency = 1.0
		_simplex1_cache[seed] = n
	return n.get_noise_2d(p.x, p.y)


# ── Raw field ─────────────────────────────────────────────────────────────────

static func L(xz: Vector2, ctx: Dictionary) -> float:
	var f: Variant = ctx.get("_fbm")
	if f != null:
		return _l_fbm(xz, ctx, f)
	return float(ctx["params"].landform_height_m) * noise01(landform_q(xz, ctx), ctx)


static func _fbm_prep(l_seed: int, p) -> Variant:
	## Prepared production-fBm landform (NOISE_FBM): the FastNoiseLite handles and constants of
	## HillsNoise.fbm_height_01 hoisted out of the per-sample path. _l_fbm repeats its arithmetic
	## exactly (same Vector2 / float ops), so L is bit-identical; only the call overhead goes.
	if int(p.landform_noise) != NOISE_FBM:
		return null
	var base: float = p.landform_wavelength_m
	var oct: Array = []
	for i in range(int(p.landform_octaves)):
		oct.append(_hills_noise_handle(l_seed + i * 7919))
	return [
		_hills_noise_handle(l_seed + 17), _hills_noise_handle(l_seed + 23),
		0.4 / maxf(base, 1.0), p.landform_warp * base, Vector2(0.0, float(l_seed % 97) * 0.013),
		1.0 / maxf(base, 1.0), float(p.landform_persistence), oct, float(p.landform_height_m),
	]


static func _hills_noise_handle(seed: int) -> FastNoiseLite:
	HillsNoise._noise2d(Vector2.ZERO, seed)  # creates / caches the handle exactly as HillsNoise does
	return HillsNoise._noise_cache[seed]


static func _l_fbm(xz: Vector2, ctx: Dictionary, f: Array) -> float:
	# landform_q
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var d := xz - h0
	var c: float = ctx["cos"]
	var s: float = ctx["sin"]
	var q := Vector2(c * d.x - s * d.y, s * d.x + c * d.y) + h0 + (ctx["offset"] as Vector2)
	# HillsNoise.domain_warp
	var wf: float = f[2]
	var qq: Vector2 = q * wf + (f[4] as Vector2)
	var qq2 := qq + Vector2(19.1, 7.3)
	var off := Vector2((f[0] as FastNoiseLite).get_noise_2d(qq.x, qq.y),
		(f[1] as FastNoiseLite).get_noise_2d(qq2.x, qq2.y))
	var wp: Vector2 = q + off * float(f[3])
	# HillsNoise.fbm_height_01 octave loop
	var amp := 1.0
	var freq: float = f[5]
	var pers: float = f[6]
	var sum := 0.0
	var norm := 0.0
	for n: FastNoiseLite in (f[7] as Array):
		var pp := wp * freq
		sum += amp * n.get_noise_2d(pp.x, pp.y)
		norm += amp
		amp *= pers
		freq *= 2.0
	if norm < 1e-6:
		return float(f[8]) * 0.5
	return float(f[8]) * clampf(sum / norm * 0.5 + 0.5, 0.0, 1.0)


static func D(xz: Vector2, ctx: Dictionary) -> float:
	## Detail: the gentle lawn undulation, on the existing terrain stream; independent of the offset
	## (the search samples it once per node, AR-LF-D4).
	var p = ctx["params"]
	var n := HillsNoise.fbm_height_01(xz, int(ctx["d_seed"]), p.base_feature_m, p.noise_octaves,
		p.noise_persistence, p.warp_strength)
	return (n - 0.5) * 2.0 * p.base_amplitude_m


static func raw_y(xz: Vector2, ctx: Dictionary) -> float:
	return L(xz, ctx) + D(xz, ctx)


static func cap_sun(f: float, xz: Vector2, ctx: Dictionary, sun_az: Vector2) -> float:
	## SD-17 §4 sun corridor soft cap: only lowers land inside the sunrise / sunset corridors.
	var p = ctx["params"]
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var dv := xz - h0
	var d := dv.length()
	var ramp := smooth01((d - SUN_RAMP_START_M) / SUN_RAMP_LEN_M)
	if ramp <= 0.0:
		return f
	var az := compass_deg(dv)
	var half: float = p.sun_corridor_half_deg
	var outer: float = half + p.sun_corridor_fade_deg
	var w_az := maxf(fer(angle_diff_deg(az, sun_az.x), half, outer),
		fer(angle_diff_deg(az, sun_az.y), half, outer))
	var w := w_az * ramp
	if w <= 0.0:
		return f
	var y_cap: float = float(ctx["y_hero_raw"]) + p.sun_eye_height_m + d * tan(deg_to_rad(p.sun_clear_deg))
	return lerpf(f, smin(f, y_cap, p.sun_cap_soft_m), w)


static func capped_raw_y(xz: Vector2, ctx: Dictionary, sun_az: Vector2) -> float:
	## cap_sun(L + D); the far ridges Rg are 0 inside far_ridge_start_m (village and raw LUT).
	return cap_sun(raw_y(xz, ctx), xz, ctx, sun_az)


# ── Offset search (SD-VILLAGE-TERRAIN-18, AR-LF-D4) ───────────────────────────

static func candidate_offsets(norm_seed: int, k: int) -> Array[Vector2]:
	## Candidate 0 is (0, 0); the rest come from an LCG stream on the landform seed.
	var out: Array[Vector2] = [Vector2.ZERO]
	var st := landform_seed(norm_seed)
	for _i in range(1, k):
		st = VillageScatterPositions.lcg_step(st)
		var x := (VillageScatterPositions.lcg_f01(st) * 2.0 - 1.0) * CANDIDATE_RANGE_M
		st = VillageScatterPositions.lcg_step(st)
		var z := (VillageScatterPositions.lcg_f01(st) * 2.0 - 1.0) * CANDIDATE_RANGE_M
		out.append(Vector2(x, z))
	return out


static func _search_nodes(g: Vector2) -> Dictionary:
	## Hero core offsets (1 m grid, r ≤ hero_flat_r handled by the caller) and the 4 m search grid
	## covering the village disc about G and the hero ring disc about H0.
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var pts := PackedVector2Array()
	var in_v := PackedByteArray()
	var in_r := PackedByteArray()
	var in_plaza := PackedByteArray()
	var plaza := VillageLayout.plaza_rect_at(g, VillageLayout.PLAZA_SIDE_L)
	var ext := VILLAGE_R_M + 16.0
	var x := -ext
	while x <= ext:
		var z := -ext
		while z <= ext:
			var p := g + Vector2(x, z)
			var v := Vector2(x, z).length() <= VILLAGE_R_M
			var r := p.distance_to(h0) <= HERO_RING_R_M
			if v or r:
				pts.append(p)
				in_v.append(1 if v else 0)
				in_r.append(1 if r else 0)
				in_plaza.append(1 if plaza.grow(0.01).has_point(p) else 0)
			z += SEARCH_GRID_M
		x += SEARCH_GRID_M
	return {"pts": pts, "in_v": in_v, "in_r": in_r, "in_plaza": in_plaza}


static func rank_offsets(norm_seed: int, params) -> Array[Dictionary]:
	## Ranked candidates: passing (by score, ties on index) then failing (by summed normalised
	## violation). Each: {index, offset, rot_deg, pass, score, violation, measures}. Manual mode
	## returns the one manual candidate. D is sampled once per node; the hero plane rejects early;
	## the exact 1 m FD p95 is verified on the best passing candidates in rank order.
	if int(params.landform_offset_mode) == VillageTerrainParams.OFFSET_MANUAL:
		var off := Vector2(params.landform_offset_x, params.landform_offset_z)
		var c := _evaluate_full(norm_seed, params, -1, off, params.landform_rot_deg)
		var one: Array[Dictionary] = [c]
		return one
	var g := VillageLayout.VILLAGE_GREEN_G
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var base_ctx := make_ctx_light(norm_seed, params, Vector2.ZERO, 0.0)
	var hero_q := _hero_offsets(params.hero_flat_r_m)
	var nodes := _search_nodes(g)
	var pts: PackedVector2Array = nodes["pts"]
	# D once per node (offset independent).
	var d_hero := PackedFloat32Array()
	for q: Vector2 in hero_q:
		d_hero.append(D(h0 + q, base_ctx))
	var d_h0 := D(h0, base_ctx)
	var d_grid := PackedFloat32Array()
	for p: Vector2 in pts:
		d_grid.append(D(p, base_ctx))
	var offsets := candidate_offsets(norm_seed, maxi(int(params.landform_offset_candidates), 1))
	var passing: Array[Dictionary] = []
	var failing: Array[Dictionary] = []
	# SD-VILLAGE-TERRAIN-28 §2 storey rule (off when storey_ground_frac_min <= 0: pure score order).
	var frac_min := float(params.storey_ground_frac_min)
	var storey_on := frac_min > 0.0
	var d_fd := {}
	var storey_mask := _storey_mask(nodes, g, h0) if storey_on else PackedByteArray()
	for i in range(offsets.size()):
		var ctx := base_ctx.duplicate()
		ctx["offset"] = offsets[i]
		var c := _evaluate_coarse(ctx, params, i, hero_q, d_hero, d_h0, nodes, d_grid)
		if bool(c["pass"]):
			if storey_on:
				_ensure_d_fd(base_ctx, nodes, d_fd)
				_storey_measures(ctx, params, nodes, d_grid, d_fd, storey_mask, c["measures"])
			passing.append(c)
		else:
			failing.append(c)
	if storey_on:
		var first: Array[Dictionary] = []
		var rest: Array[Dictionary] = []
		for c: Dictionary in passing:
			if float(c["measures"]["storey_frac"]) >= frac_min:
				first.append(c)
			else:
				rest.append(c)
		first.sort_custom(_by_score)
		rest.sort_custom(_by_storey_frac)
		passing = first
		passing.append_array(rest)
	else:
		passing.sort_custom(_by_score)
	# Verify the best passing candidates in rank order — exact p95, then the measured hero ring
	# (hard rule hero_ring_ok, SD-18 2026-11-17) — until rank 0 passes both. A failure moves the
	# candidate to the failing list. The later passing candidates stay "pass" with verified =
	# false: the generator verifies them (verify_candidate) only when its rank retry reaches them
	# (SD-18 "Cost": lazy checks keep AC-LT-PERF ≤ 150 ms; extended here to the p95 check).
	var verified: Array[Dictionary] = []
	var unverified: Array[Dictionary] = []
	var vc := {"nodes": nodes, "d_grid": d_grid, "d_fd": d_fd, "ring": {}, "plaza": {}, "base_ctx": base_ctx}
	for c: Dictionary in passing:
		if not verified.is_empty():
			c["verified"] = false
			unverified.append(c)
			continue
		if _verify(c, params, vc):
			verified.append(c)
		else:
			failing.append(c)
	failing.sort_custom(_by_violation)
	var out: Array[Dictionary] = []
	out.append_array(verified)
	out.append_array(unverified)
	out.append_array(failing)
	return out


static func _verify(c: Dictionary, params, vc: Dictionary) -> bool:
	## Exact p95 then hero_ring_ok for one coarse-passing candidate; updates c in place
	## (verified, pass, score, violation, measures). vc caches the offset-independent parts.
	var ctx: Dictionary = (vc["base_ctx"] as Dictionary).duplicate()
	ctx["offset"] = c["offset"]
	var m: Dictionary = c["measures"]
	var p95 := _exact_p95(ctx, vc["nodes"], vc["d_grid"], vc["d_fd"])
	m["p95_v"] = p95
	c["verified"] = true
	if p95 > params.village_slope_p95_max_deg:
		c["pass"] = false
		c["score"] = INF
		c["violation"] = (p95 - params.village_slope_p95_max_deg) / 4.0
		return false
	ctx["y_hero_raw"] = float(m["y_hero_raw"])
	# plaza_ring_ok (SD-18, ivy-82zn.14.23), then hero_ring_ok with the plaza replayed.
	var pz := _plaza_ring_cached(ctx, params, vc["plaza"])
	_store_plaza_ring(m, pz["ring"])
	if not bool(pz["ring"]["ok"]):
		c["pass"] = false
		c["score"] = INF
		c["violation"] = _hero_ring_violation(pz["ring"], params)
		return false
	var hr := _hero_ring_cached(ctx, params, vc["ring"], pz["site"])
	_store_hero_ring(m, hr)
	if not bool(hr["ok"]):
		c["pass"] = false
		c["score"] = INF
		c["violation"] = _hero_ring_violation(hr, params)
		return false
	return true


static func verify_candidate(norm_seed: int, params, c: Dictionary) -> bool:
	## Lazy verification of a passing, unverified candidate (generator rank retry, AR-LF-D5).
	if bool(c.get("verified", false)):
		return bool(c["pass"])
	if not bool(c["pass"]):
		return false
	var base_ctx := make_ctx_light(norm_seed, params, Vector2.ZERO, float(c["rot_deg"]))
	var nodes := _search_nodes(VillageLayout.VILLAGE_GREEN_G)
	var d_grid := PackedFloat32Array()
	for p: Vector2 in (nodes["pts"] as PackedVector2Array):
		d_grid.append(D(p, base_ctx))
	return _verify(c, params, {"nodes": nodes, "d_grid": d_grid, "d_fd": {}, "ring": {}, "plaza": {},
		"base_ctx": base_ctx})


static func _by_score(a: Dictionary, b: Dictionary) -> bool:
	if float(a["score"]) != float(b["score"]):
		return float(a["score"]) < float(b["score"])
	return int(a["index"]) < int(b["index"])


static func _by_storey_frac(a: Dictionary, b: Dictionary) -> bool:
	## SD-28 §2: the candidates below the storey minimum, most storey ground first (ties: index).
	var fa := float(a["measures"]["storey_frac"])
	var fb := float(b["measures"]["storey_frac"])
	if fa != fb:
		return fa > fb
	return int(a["index"]) < int(b["index"])


## SD-28 §2 storey nodes (offset independent part): search 4 m village nodes with |p − G| ≤ 42 m,
## |p − H0| ≥ 14 m, outside the plaza cottage keep-clear rect. The slope part is per candidate.
const STOREY_R_MAX_M := 42.0
const STOREY_HERO_CLEAR_M := 14.0


static func _storey_mask(nodes: Dictionary, g: Vector2, h0: Vector2) -> PackedByteArray:
	var pts: PackedVector2Array = nodes["pts"]
	var in_v: PackedByteArray = nodes["in_v"]
	var keep := VillageLayout.plaza_cottage_keep_clear_rect(g, VillageLayout.PLAZA_SIDE_L)
	var out := PackedByteArray()
	out.resize(pts.size())
	for k in range(pts.size()):
		var p := pts[k]
		var ok := in_v[k] == 1 and p.distance_to(g) <= STOREY_R_MAX_M and p.distance_to(h0) >= STOREY_HERO_CLEAR_M \
			and not keep.has_point(p)
		out[k] = 1 if ok else 0
	return out


static func _storey_measures(ctx: Dictionary, params, nodes: Dictionary, d_grid: PackedFloat32Array,
		d_fd: Dictionary, mask: PackedByteArray, m: Dictionary) -> void:
	## storey_frac = share of buildable storey nodes (1 m FD slope of L + D ≤ max_site_slope_deg) with
	## |L + D − y_hero_raw| ≥ storey_ground_m; storey_max = the max |L + D − y_hero_raw| over them.
	var pts: PackedVector2Array = nodes["pts"]
	var fdx: PackedFloat32Array = d_fd["x"]
	var fdz: PackedFloat32Array = d_fd["z"]
	var lim := tan(deg_to_rad(params.max_site_slope_deg))
	var lim2 := lim * lim
	var yh := float(m["y_hero_raw"])
	var h := float(params.storey_ground_m)
	var n := 0
	var hit := 0
	var mx := 0.0
	for k in range(pts.size()):
		if mask[k] != 1:
			continue
		var p := pts[k]
		var y := L(p, ctx) + d_grid[k]
		var gx := L(p + Vector2(1.0, 0.0), ctx) + fdx[k] - y
		var gz := L(p + Vector2(0.0, 1.0), ctx) + fdz[k] - y
		if gx * gx + gz * gz > lim2:
			continue
		n += 1
		var dh := absf(y - yh)
		mx = maxf(mx, dh)
		if dh >= h:
			hit += 1
	m["storey_frac"] = float(hit) / float(n) if n > 0 else 0.0
	m["storey_max"] = mx


static func _ensure_d_fd(ctx: Dictionary, nodes: Dictionary, d_fd: Dictionary) -> void:
	## D at the +x / +z neighbours of the village nodes (offset independent), shared by the storey
	## measure and the exact p95.
	if not d_fd.is_empty():
		return
	var pts: PackedVector2Array = nodes["pts"]
	var in_v: PackedByteArray = nodes["in_v"]
	var dx := PackedFloat32Array()
	var dz := PackedFloat32Array()
	dx.resize(pts.size())
	dz.resize(pts.size())
	for k in range(pts.size()):
		if in_v[k] == 1:
			dx[k] = D(pts[k] + Vector2(1.0, 0.0), ctx)
			dz[k] = D(pts[k] + Vector2(0.0, 1.0), ctx)
	d_fd["x"] = dx
	d_fd["z"] = dz


static func _by_violation(a: Dictionary, b: Dictionary) -> bool:
	if float(a["violation"]) != float(b["violation"]):
		return float(a["violation"]) < float(b["violation"])
	return int(a["index"]) < int(b["index"])


static func make_ctx_light(norm_seed: int, params, offset: Vector2, rot_deg: float) -> Dictionary:
	## make_ctx without the hero mean (the search computes its own hero plane).
	var r := deg_to_rad(rot_deg)
	var l_seed := landform_seed(norm_seed)
	return {
		"l_seed": l_seed, "d_seed": detail_seed(norm_seed), "offset": offset,
		"rot_deg": rot_deg, "cos": cos(r), "sin": sin(r), "params": params, "y_hero_raw": 0.0,
		"_fbm": _fbm_prep(l_seed, params),
	}


static func _hero_offsets(radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := int(floor(radius))
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			if float(ix * ix + iz * iz) <= radius * radius:
				out.append(Vector2(float(ix), float(iz)))
	return out


static func _plane_from_offsets(qs: PackedVector2Array, zs: PackedFloat32Array) -> Dictionary:
	## Least-squares plane z = a·x + b·y + c through points at offsets qs (centred sums).
	var n := qs.size()
	if n < 3:
		return {"a": 0.0, "b": 0.0, "c": zs[0] if n > 0 else 0.0, "mean": zs[0] if n > 0 else 0.0}
	var mx := 0.0
	var my := 0.0
	var mz := 0.0
	for i in range(n):
		mx += qs[i].x
		my += qs[i].y
		mz += zs[i]
	mx /= n
	my /= n
	mz /= n
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	var sxz := 0.0
	var syz := 0.0
	for i in range(n):
		var dx := qs[i].x - mx
		var dy := qs[i].y - my
		var dz := zs[i] - mz
		sxx += dx * dx
		syy += dy * dy
		sxy += dx * dy
		sxz += dx * dz
		syz += dy * dz
	var det := sxx * syy - sxy * sxy
	var a := 0.0
	var b := 0.0
	if absf(det) > 1e-9:
		a = (sxz * syy - syz * sxy) / det
		b = (syz * sxx - sxz * sxy) / det
	return {"a": a, "b": b, "c": mz - a * mx - b * my, "mean": mz, "mx": mx, "my": my}


static func _plane_measures(pl: Dictionary) -> Dictionary:
	var grad := Vector2(float(pl["a"]), float(pl["b"]))
	var slope := rad_to_deg(atan(grad.length()))
	var aspect := compass_deg(-grad) if grad.length() > 1e-9 else 180.0
	return {"slope_deg": slope, "aspect_deg": aspect}


static func _evaluate_coarse(
		ctx: Dictionary, params, index: int, hero_q: PackedVector2Array, d_hero: PackedFloat32Array,
		d_h0: float, nodes: Dictionary, d_grid: PackedFloat32Array) -> Dictionary:
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var zs := PackedFloat32Array()
	zs.resize(hero_q.size())
	for k in range(hero_q.size()):
		zs[k] = L(h0 + hero_q[k], ctx) + d_hero[k]
	var pl := _plane_from_offsets(hero_q, zs)
	var pm := _plane_measures(pl)
	var s_hero: float = pm["slope_deg"]
	var m := {
		"s_hero": s_hero, "aspect_deg": pm["aspect_deg"], "up_hero": NAN, "down_hero": NAN,
		"span_v": NAN, "p95_v": NAN, "plaza_tilt_deg": NAN, "y_hero_raw": float(pl["mean"]),
	}
	var viol := _range_violation(s_hero, params.hero_site_slope_min_deg, params.hero_site_slope_max_deg,
		maxf(params.hero_site_slope_max_deg, 1.0))
	var c := {"index": index, "offset": ctx["offset"], "rot_deg": float(ctx["rot_deg"]), "pass": false,
		"score": INF, "violation": 0.0, "measures": m}
	if viol > 0.0:
		# Early out: the grid is skipped; grid rules count as maximally violated for ranking.
		c["violation"] = viol + 3.0
		return c
	_grid_measures(ctx, params, nodes, d_grid, L(h0, ctx) + d_h0, m)
	viol += _grid_violation(m, params)
	c["violation"] = viol
	if viol <= 0.0:
		c["pass"] = true
		c["score"] = _score(m, params)
	return c


static func _grid_measures(ctx: Dictionary, params, nodes: Dictionary, d_grid: PackedFloat32Array,
		y_h0: float, m: Dictionary) -> void:
	var pts: PackedVector2Array = nodes["pts"]
	var in_v: PackedByteArray = nodes["in_v"]
	var in_r: PackedByteArray = nodes["in_r"]
	var in_pl: PackedByteArray = nodes["in_plaza"]
	var lo := INF
	var hi := -INF
	var rlo := INF
	var rhi := -INF
	var plaza_q := PackedVector2Array()
	var plaza_z := PackedFloat32Array()
	for k in range(pts.size()):
		var y := L(pts[k], ctx) + d_grid[k]
		if in_v[k] == 1:
			lo = minf(lo, y)
			hi = maxf(hi, y)
		if in_r[k] == 1:
			rlo = minf(rlo, y)
			rhi = maxf(rhi, y)
		if in_pl[k] == 1:
			plaza_q.append(pts[k])
			plaza_z.append(y)
	m["span_v"] = hi - lo
	m["up_hero"] = rhi - y_h0
	m["down_hero"] = y_h0 - rlo
	m["plaza_tilt_deg"] = _plane_measures(_plane_from_offsets(plaza_q, plaza_z))["slope_deg"]


static func _exact_p95(ctx: Dictionary, nodes: Dictionary, d_grid: PackedFloat32Array, d_fd: Dictionary) -> float:
	## 95th percentile of the 1 m forward-difference slope of L + D at the village 4 m nodes.
	## d_fd caches D at the +x / +z neighbours (offset independent) across candidates.
	var pts: PackedVector2Array = nodes["pts"]
	var in_v: PackedByteArray = nodes["in_v"]
	_ensure_d_fd(ctx, nodes, d_fd)
	var fdx: PackedFloat32Array = d_fd["x"]
	var fdz: PackedFloat32Array = d_fd["z"]
	var sl: Array[float] = []
	for k in range(pts.size()):
		if in_v[k] != 1:
			continue
		var p := pts[k]
		var y := L(p, ctx) + d_grid[k]
		var yx := L(p + Vector2(1.0, 0.0), ctx) + fdx[k]
		var yz := L(p + Vector2(0.0, 1.0), ctx) + fdz[k]
		sl.append(rad_to_deg(atan(Vector2(yx - y, yz - y).length())))
	sl.sort()
	return sl[mini(int(sl.size() * 0.95), sl.size() - 1)]


static func _evaluate_full(norm_seed: int, params, index: int, offset: Vector2, rot_deg: float) -> Dictionary:
	## Every measure for one candidate (manual mode; also the playground readout).
	var ctx := make_ctx_light(norm_seed, params, offset, rot_deg)
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var hero_q := _hero_offsets(params.hero_flat_r_m)
	var zs := PackedFloat32Array()
	for q: Vector2 in hero_q:
		zs.append(raw_y(h0 + q, ctx))
	var hpl := _plane_from_offsets(hero_q, zs)
	var pm := _plane_measures(hpl)
	var m := {"s_hero": pm["slope_deg"], "aspect_deg": pm["aspect_deg"], "y_hero_raw": float(hpl["mean"])}
	var nodes := _search_nodes(VillageLayout.VILLAGE_GREEN_G)
	var pts: PackedVector2Array = nodes["pts"]
	var d_grid := PackedFloat32Array()
	for p: Vector2 in pts:
		d_grid.append(D(p, ctx))
	_grid_measures(ctx, params, nodes, d_grid, raw_y(h0, ctx), m)
	var d_fd := {}
	m["p95_v"] = _exact_p95(ctx, nodes, d_grid, d_fd)
	if float(params.storey_ground_frac_min) > 0.0:
		# SD-28 §2 readout (manual mode has one candidate: no ordering).
		_storey_measures(ctx, params, nodes, d_grid, d_fd,
			_storey_mask(nodes, VillageLayout.VILLAGE_GREEN_G, h0), m)
	var viol := _range_violation(float(m["s_hero"]), params.hero_site_slope_min_deg,
		params.hero_site_slope_max_deg, maxf(params.hero_site_slope_max_deg, 1.0))
	viol += _grid_violation(m, params)
	viol += maxf(0.0, float(m["p95_v"]) - params.village_slope_p95_max_deg) / 4.0
	# Plaza and hero ring hard rules (SD-18 2026-11-17): reported, a failure makes pass = false.
	ctx["y_hero_raw"] = float(m["y_hero_raw"])
	var pz := _plaza_ring_cached(ctx, params, {})
	_store_plaza_ring(m, pz["ring"])
	if not bool(pz["ring"]["ok"]):
		viol += _hero_ring_violation(pz["ring"], params)
	var hr := _hero_ring_cached(ctx, params, {}, pz["site"])
	_store_hero_ring(m, hr)
	if not bool(hr["ok"]):
		viol += _hero_ring_violation(hr, params)
	return {"index": index, "offset": offset, "rot_deg": rot_deg, "pass": viol <= 0.0,
		"score": _score(m, params), "violation": viol, "measures": m}


static func hero_ring(norm_seed: int, params, offset: Vector2, rot_deg: float = 0.0) -> Dictionary:
	## Measured hero ring for one offset (SD-19 on exact cap_sun(L + D) about H0, T = core mean of
	## L + D, the measured plaza replayed). {ok, w, peak_deg, best_w, best_peak_deg}. Used for ranks
	## the search did not verify and by the field when no width is stored.
	var ctx := make_ctx(norm_seed, params, offset, rot_deg)
	var pz := _plaza_ring_cached(ctx, params, {})
	return _hero_ring_cached(ctx, params, {}, pz["site"])


static func plaza_ring(norm_seed: int, params, offset: Vector2, rot_deg: float = 0.0) -> Dictionary:
	## Measured plaza ring for one offset (SD-18 plaza_ring_ok). {ok, w, peak_deg, ...}.
	var ctx := make_ctx(norm_seed, params, offset, rot_deg)
	return _plaza_ring_cached(ctx, params, {})["ring"]


static func _plaza_ring_cached(ctx: Dictionary, params, cache: Dictionary) -> Dictionary:
	## {ring, site}: the plaza site (VillageTerrainField.plaza_site on exact U, the field's own
	## helper) with w = the measured width (best width on failure). cache: D per lattice node
	## (offset independent), shared across candidates. ctx must carry y_hero_raw (sun cap).
	if cache.is_empty():
		cache["d"] = {}
		cache["d_ctx"] = ctx
		cache["sun_az"] = VillageTerrain.sun_corridor_azimuths()
	var dmap: Dictionary = cache["d"]
	var d_ctx: Dictionary = cache["d_ctx"]
	var sun_az: Vector2 = cache["sun_az"]
	var u_fn := func(q: Vector2) -> float:
		var key := Vector2i(roundi(q.x * 2.0), roundi(q.y * 2.0))
		var dv: Variant = dmap.get(key)
		if dv == null:
			dv = D(q, d_ctx)
			dmap[key] = dv
		return cap_sun(L(q, ctx) + float(dv), q, ctx, sun_az)
	var g := VillageLayout.VILLAGE_GREEN_G
	var rect := VillageLayout.plaza_rect_at(g, VillageLayout.PLAZA_SIDE_L)
	var site := VillageTerrainField.plaza_site(u_fn, rect, params, params.plaza_ring_m)
	var ring := VillageTerrainField.measure_plaza_ring(u_fn, site, params)
	site["w"] = float(ring["w"])
	site["bound_r"] = rect.size.length() * 0.5 + float(ring["w"])
	return {"ring": ring, "site": site}


static func _store_plaza_ring(m: Dictionary, pr: Dictionary) -> void:
	m["plaza_ring_ok"] = bool(pr["ok"])
	m["plaza_ring_w"] = float(pr["w"])
	m["plaza_ring_peak_deg"] = float(pr["peak_deg"])


static func _hero_ring_cached(ctx: Dictionary, params, cache: Dictionary, plaza: Dictionary = {}) -> Dictionary:
	## cache: grid geometry, core sdf and D per node (offset independent), shared across candidates.
	## ctx must carry the candidate's y_hero_raw (the sun cap reads it). plaza: the measured plaza
	## site, replayed as a "before" site (baked into U; SD-19 step 2).
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var r_c: float = params.hero_flat_r_m
	var w_max: float = params.hero_ring_max_m
	if cache.is_empty():
		var hh := r_c + w_max + 2.0
		var n := int(ceil(2.0 * hh / RING_GRID_M)) + 1
		var origin := h0 - Vector2(hh, hh)
		var sdf := PackedFloat32Array()
		var dd := PackedFloat32Array()
		sdf.resize(n * n)
		dd.resize(n * n)
		dd.fill(NAN)
		for iz in range(n):
			for ix in range(n):
				var p := origin + Vector2(float(ix), float(iz)) * RING_GRID_M
				sdf[iz * n + ix] = p.distance_to(h0) - r_c
		cache["n"] = n
		cache["origin"] = origin
		cache["sdf"] = sdf
		cache["d"] = dd
		cache["d_ctx"] = ctx
		cache["sun_az"] = VillageTerrain.sun_corridor_azimuths()
	var n2: int = cache["n"]
	var o: Vector2 = cache["origin"]
	var d2: PackedFloat32Array = cache["d"]
	var d_ctx: Dictionary = cache["d_ctx"]
	var sun_az: Vector2 = cache["sun_az"]
	# Lazy U (exact cap_sun(L + D), D cached per node across candidates): only the nodes the
	# ladder reaches are sampled.
	var has_plaza := not plaza.is_empty()
	var u_fn := func(p2: Vector2, k: int) -> float:
		if is_nan(d2[k]):
			d2[k] = D(p2, d_ctx)
		var u := cap_sun(L(p2, ctx) + d2[k], p2, ctx, sun_az)
		if has_plaza:
			u = VillageTerrainField.apply_site(plaza, p2, u, params)
		return u
	var grid := {"origin": o, "nx": n2, "nz": n2, "u_fn": u_fn}
	return measured_ring(grid, cache["sdf"], float(ctx["y_hero_raw"]), params.hero_ring_min_m, w_max,
		params.ring_max_slope_deg)


static func _store_hero_ring(m: Dictionary, hr: Dictionary) -> void:
	m["hero_ring_ok"] = bool(hr["ok"])
	m["hero_ring_w"] = float(hr["w"])
	m["hero_ring_peak_deg"] = float(hr["peak_deg"])


static func _hero_ring_violation(hr: Dictionary, params) -> float:
	## SD-18: (best ladder peak − ring_max_slope_deg) / 4.
	return maxf(0.0, float(hr["best_peak_deg"]) - params.ring_max_slope_deg) / 4.0


static func _range_violation(v: float, lo: float, hi: float, scale: float) -> float:
	return (maxf(0.0, lo - v) + maxf(0.0, v - hi)) / maxf(scale, 1e-3)


static func _grid_violation(m: Dictionary, params) -> float:
	var v := 0.0
	v += maxf(0.0, params.hero_not_crest_m - float(m["up_hero"])) / maxf(params.hero_not_crest_m, 0.5)
	v += maxf(0.0, params.hero_not_hollow_m - float(m["down_hero"])) / maxf(params.hero_not_hollow_m, 0.5)
	v += _range_violation(float(m["span_v"]), params.relief_span_min_m, params.relief_span_max_m,
		maxf(params.relief_span_max_m - params.relief_span_min_m, 1.0))
	v += maxf(0.0, float(m["plaza_tilt_deg"]) - PLAZA_RAW_TILT_MAX_DEG) / PLAZA_RAW_TILT_MAX_DEG
	return v


static func _score(m: Dictionary, params) -> float:
	## SD-18: |span − target| + 0.5 · max(0, |Δang(aspect, 180°)| − 90°) / 90° (south-facing pref).
	var da := angle_diff_deg(float(m["aspect_deg"]), 180.0)
	return absf(float(m["span_v"]) - params.relief_span_target_m) + 0.5 * maxf(0.0, da - 90.0) / 90.0


# ── Raw LUT, site plane, ring width (SD-VILLAGE-TERRAIN-19) ───────────────────

static func raw_lut(ctx: Dictionary, sun_az: Vector2, cell_m: float = 2.0) -> Dictionary:
	## Capped raw field (cap_sun(L + D)) over r ≤ RAW_LUT_R_M about G, in the
	## VillageTerrain.lut_sample format {origin_xz, cell_m, cols, rows, data}.
	var g := VillageLayout.VILLAGE_GREEN_G
	var step := maxf(cell_m, 0.1)
	var cols := int(ceil(2.0 * RAW_LUT_R_M / step)) + 1
	var origin := g - Vector2(RAW_LUT_R_M, RAW_LUT_R_M)
	var data := PackedFloat32Array()
	data.resize(cols * cols)
	for iz in range(cols):
		for ix in range(cols):
			data[iz * cols + ix] = capped_raw_y(origin + Vector2(float(ix) * step, float(iz) * step), ctx, sun_az)
	return {"origin_xz": origin, "cell_m": step, "cols": cols, "rows": cols, "data": data}


static func site_plane(lut: Dictionary, core: Rect2) -> Dictionary:
	## Plane fit of the LUT over the core on a 1 m grid: {slope_deg, aspect_deg, mean, a, b, c}.
	return site_plane_fn(VillageTerrain.lut_sample.bind(lut), core, 1.0)


static func site_plane_fn(fn: Callable, core: Rect2, step: float = 1.0) -> Dictionary:
	## Plane fit of fn(xz) over a rect on a `step` grid including both edges.
	var nx := maxi(1, ceili(core.size.x / step))
	var nz := maxi(1, ceili(core.size.y / step))
	var qs := PackedVector2Array()
	var zs := PackedFloat32Array()
	for iz in range(nz + 1):
		for ix in range(nx + 1):
			var p := core.position + Vector2(core.size.x * float(ix) / nx, core.size.y * float(iz) / nz)
			qs.append(p)
			zs.append(float(fn.call(p)))
	return _plane_result(qs, zs)


static func disc_plane(fn: Callable, centre: Vector2, radius: float, step: float = 1.0) -> Dictionary:
	## Plane fit of fn(xz) over a disc on a `step` grid about centre.
	var qs := PackedVector2Array()
	var zs := PackedFloat32Array()
	var n := int(floor(radius / step))
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var q := Vector2(float(ix), float(iz)) * step
			if q.length_squared() <= radius * radius + 1e-6:
				qs.append(centre + q)
				zs.append(float(fn.call(centre + q)))
	return _plane_result(qs, zs)


static func _plane_result(qs: PackedVector2Array, zs: PackedFloat32Array) -> Dictionary:
	var pl := _plane_from_offsets(qs, zs)
	var pm := _plane_measures(pl)
	return {"slope_deg": pm["slope_deg"], "aspect_deg": pm["aspect_deg"], "mean": pl["mean"],
		"a": pl["a"], "b": pl["b"], "c": pl["c"]}


static func make_ring_grid(origin: Vector2, nx: int, nz: int, u_fn: Callable,
		sdf_fn: Callable = Callable(), sdf_max: float = INF) -> Dictionary:
	## 1 m node grid for the measured ring (SD-19 step 1): {origin, nx, nz, u}. With sdf_fn, nodes
	## with sdf ≥ sdf_max are never read by measured_ring and are left at 0 (saves samples).
	var u := PackedFloat32Array()
	u.resize(nx * nz)
	for iz in range(nz):
		for ix in range(nx):
			var p := origin + Vector2(float(ix), float(iz)) * RING_GRID_M
			if sdf_fn.is_valid() and float(sdf_fn.call(p)) >= sdf_max:
				continue
			u[iz * nx + ix] = float(u_fn.call(p))
	return {"origin": origin, "nx": nx, "nz": nz, "u": u}


static func grid_sdf(grid: Dictionary, sdf_fn: Callable) -> PackedFloat32Array:
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var o: Vector2 = grid["origin"]
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	for iz in range(nz):
		for ix in range(nx):
			out[iz * nx + ix] = float(sdf_fn.call(o + Vector2(float(ix), float(iz)) * RING_GRID_M))
	return out


static func grid_sdf_rect(grid: Dictionary, rect: Rect2) -> PackedFloat32Array:
	## grid_sdf with VillageTerrain.rect_sdf, as a typed loop (AR-LF-PERF P6b; bit-identical).
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var o: Vector2 = grid["origin"]
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	var c := rect.get_center()
	var hx := rect.size.x * 0.5
	var hz := rect.size.y * 0.5
	for iz in range(nz):
		for ix in range(nx):
			var p := o + Vector2(float(ix), float(iz)) * RING_GRID_M
			var dx := absf(p.x - c.x) - hx
			var dz := absf(p.y - c.y) - hz
			if dx <= 0.0 and dz <= 0.0:
				out[iz * nx + ix] = maxf(dx, dz)
			else:
				out[iz * nx + ix] = Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()
	return out


static func grid_sdf_disc(grid: Dictionary, centre: Vector2, r_c: float) -> PackedFloat32Array:
	## grid_sdf with distance − r_c, as a typed loop (AR-LF-PERF P6b; bit-identical).
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var o: Vector2 = grid["origin"]
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	for iz in range(nz):
		for ix in range(nx):
			out[iz * nx + ix] = (o + Vector2(float(ix), float(iz)) * RING_GRID_M).distance_to(centre) - r_c
	return out


static func measured_ring(grid: Dictionary, sdf: PackedFloat32Array, target: Variant, w_min: float,
		w_max: float, ring_max_deg: float, before: Array = [], after: Array = []) -> Dictionary:
	## SD-VILLAGE-TERRAIN-19 measured ring width (ivy-82zn.14.22, steps 2–4 restated ivy-82zn.14.23),
	## the one helper shared by the offset search (hero, plaza), the plot sampler (pads) and the field
	## (recompute when no stored width). grid: make_ring_grid (1 m); sdf: the candidate core's signed
	## distance per node; target: a float, or a PackedFloat32Array per node (the plaza plane); before /
	## after: sites the field applies before / after this one ([{sdf, target, w}] with scalar targets,
	## field priority order: already-selected pads, then the candidate, then the hero; per-node sites
	## such as the plaza and the pond are baked into the grid's U by the caller). For each w on the
	## 0.5 m ladder [w_min, w_max], searched upward (peak(w) is not monotone, so no bisection):
	## y_w = after(lerp(before(U), T, fer(sdf, 0, w))); slope by ONE-SIDED 1 m differences
	## (gx = max(|y[i+1] − y[i]|, |y[i] − y[i−1]|), gz likewise) at nodes with −1 < sdf < w + 1; pass if
	## every node ≤ ring_max_deg, overlap nodes included (no allowance: RING_OVERLAP_TOL_DEG is only the
	## AC-LT-RING field-test margin). First passing w wins; none ⇒ ok false.
	## Returns {ok, w, peak_deg, best_w, best_peak_deg}; on failure w = best_w (lowest peak).
	## A grid may carry "u_fn" (Callable(p: Vector2, k: int) -> float) instead of a filled "u": U is
	## then sampled lazily, bucket by bucket, only as far as the ladder reaches (AC-LT-PERF).
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var n := nx * nz
	var origin: Vector2 = grid["origin"]
	var u_fn: Callable = grid.get("u_fn", Callable())
	var lazy := u_fn.is_valid()
	var base: PackedFloat32Array
	if lazy:
		base = PackedFloat32Array()
		base.resize(n)
	else:
		base = (grid["u"] as PackedFloat32Array).duplicate()
	var per_node := target is PackedFloat32Array
	var t_arr: PackedFloat32Array = target if per_node else PackedFloat32Array()
	var t_const: float = 0.0 if per_node else float(target)
	# Bucket the nodes the ladder can touch (sdf < w_max + 2: band nodes plus their FD neighbours)
	# by ladder step, so step i only visits sdf < w_i (blend) and −1 < sdf < w_i + 1 (slope).
	var step := RING_LADDER_STEP_M
	var steps := maxi(0, int(round((w_max - w_min) / step)))
	var nb := steps + 5
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(nb)
	for b in range(nb):
		buckets[b] = PackedInt32Array()
	var deep := PackedInt32Array()  # sdf ≤ −1: blended, never slope-checked
	for k in range(n):
		var d := sdf[k]
		if d >= w_max + 2.0:
			continue
		var ix := k % nx
		var iz := k / nx
		var edge := ix == 0 or iz == 0 or ix == nx - 1 or iz == nz - 1
		if d <= -1.0:
			deep.append(k)
			continue
		var bi := 0 if d < w_min else mini(nb - 1, 1 + int(floor((d - w_min) / step)))
		# Edge nodes are blended but not slope-checked: tag with the sign bit.
		buckets[bi].append(-k - 1 if edge else k)
	# base = before(U), ba = after(base) (the surface where the candidate does not reach), y = the
	# candidate surface; filled per bucket on demand.
	var ba := PackedFloat32Array()
	ba.resize(n)
	var y := PackedFloat32Array()
	y.resize(n)
	var ctx_fill := {"base": base, "ba": ba, "y": y, "lazy": lazy, "u_fn": u_fn, "origin": origin,
		"nx": nx, "before": before, "after": after}
	_fill_nodes(ctx_fill, deep)
	var filled := -1
	var lim2 := pow(tan(deg_to_rad(ring_max_deg)), 2.0)
	var best_w := w_min
	var best_pk2 := INF
	for i in range(steps + 1):
		var w := w_min + step * float(i)
		# Nodes read at this step: sdf < w + 2 = buckets 0..i+4.
		while filled < mini(i + 4, nb - 1):
			filled += 1
			_fill_nodes(ctx_fill, buckets[filled])
		# Blend: sdf < w is buckets 0..i (plus the deep core).
		_blend_ring(y, base, sdf, deep, per_node, t_arr, t_const, w, after)
		for b in range(i + 1):
			_blend_ring(y, base, sdf, buckets[b], per_node, t_arr, t_const, w, after)
		# Slope: −1 < sdf < w + 1 is buckets 0..i+2 (1 m = 2 ladder steps), filtered exactly.
		var peak2 := 0.0
		var ok := true
		var hopeless := false
		for b in range(mini(i + 3, nb)):
			for kt: int in buckets[b]:
				if kt < 0:
					continue
				if sdf[kt] >= w + 1.0:
					continue
				var yk := y[kt]
				var gx := maxf(absf(y[kt + 1] - yk), absf(yk - y[kt - 1]))
				var gz := maxf(absf(y[kt + nx] - yk), absf(yk - y[kt - nx]))
				var g2 := gx * gx + gz * gz
				if g2 > peak2:
					peak2 = g2
				if g2 > lim2:
					ok = false
				# A failing step whose partial peak already exceeds the best peak cannot change the
				# result (best = lowest peak over the ladder): stop scanning it.
				if not ok and peak2 >= best_pk2:
					hopeless = true
					break
			if hopeless:
				break
		if hopeless:
			continue
		if peak2 < best_pk2:
			best_pk2 = peak2
			best_w = w
		if ok:
			var pk := rad_to_deg(atan(sqrt(peak2)))
			return {"ok": true, "w": w, "peak_deg": pk, "best_w": w, "best_peak_deg": pk}
	var best := rad_to_deg(atan(sqrt(best_pk2)))
	return {"ok": false, "w": best_w, "peak_deg": best, "best_w": best_w, "best_peak_deg": best}


static func _blend_ring(y: PackedFloat32Array, base: PackedFloat32Array, sdf: PackedFloat32Array,
		idx: PackedInt32Array, per_node: bool, t_arr: PackedFloat32Array, t_const: float, w: float,
		after: Array) -> void:
	## y[k] = after(lerp(base, T, fer(sdf, 0, w))) for the (sign-tagged) nodes in idx with sdf < w.
	var inv := 1.0 / maxf(w, 1e-6)
	for kt: int in idx:
		var k := kt if kt >= 0 else -kt - 1
		var d := sdf[k]
		if d >= w:
			continue
		var f := 1.0
		if d > 0.0:
			var t := d * inv
			f = 1.0 - t * t * (3.0 - 2.0 * t)
		var tk: float = t_arr[k] if per_node else t_const
		var v := base[k] + (tk - base[k]) * f
		for a: Dictionary in after:
			var as2: PackedFloat32Array = a["sdf"]
			var aw: float = a["w"]
			if as2[k] < aw:
				v = lerpf(v, float(a["target"]), fer(as2[k], 0.0, aw))
		y[k] = v


static func _fill_nodes(c: Dictionary, idx: PackedInt32Array) -> void:
	## U (lazy grids), base = before(U), ba = after(base), y = ba for the (sign-tagged) nodes.
	var base: PackedFloat32Array = c["base"]
	var ba: PackedFloat32Array = c["ba"]
	var y: PackedFloat32Array = c["y"]
	var lazy: bool = c["lazy"]
	var u_fn: Callable = c["u_fn"]
	var o: Vector2 = c["origin"]
	var nx: int = c["nx"]
	var before: Array = c["before"]
	var after: Array = c["after"]
	for kt: int in idx:
		var k := kt if kt >= 0 else -kt - 1
		var v: float
		if lazy:
			v = float(u_fn.call(o + Vector2(float(k % nx), float(k / nx)) * RING_GRID_M, k))
		else:
			v = base[k]
		for b: Dictionary in before:
			var bs: PackedFloat32Array = b["sdf"]
			if bs[k] < float(b["w"]):
				v = lerpf(v, float(b["target"]), fer(bs[k], 0.0, float(b["w"])))
		base[k] = v
		for a: Dictionary in after:
			var as2: PackedFloat32Array = a["sdf"]
			if as2[k] < float(a["w"]):
				v = lerpf(v, float(a["target"]), fer(as2[k], 0.0, float(a["w"])))
		ba[k] = v
		y[k] = v


static func ring_width(r_c: float, s_deg: float, ring_max_deg: float, w_min: float, w_max: float) -> Dictionary:
	## SD-19 plane-slope formula — SUPERSEDED 2026-11-17 (ivy-82zn.14.22): no longer decides any
	## ring (measured_ring does); kept only as a readout estimate.
	## w = 1.5·tan(s)·r_c / (tan(ring_max) − 1.25·tan(s)), clamped to [w_min, w_max].
	## ok = false when the denominator is ≤ 0 or the unclamped w exceeds w_max.
	var ts := tan(deg_to_rad(maxf(s_deg, 0.0)))
	var den := tan(deg_to_rad(ring_max_deg)) - 1.25 * ts
	if den <= 0.0:
		return {"w": w_max, "ok": false, "w_raw": INF}
	var w := 1.5 * ts * r_c / den
	return {"w": clampf(w, w_min, w_max), "ok": w <= w_max, "w_raw": w}


# ── C1 primitives (SD-VILLAGE-TERRAIN-3) ──────────────────────────────────────

static func smooth01(t: float) -> float:
	var tc := clampf(t, 0.0, 1.0)
	return tc * tc * (3.0 - 2.0 * tc)


static func fer(d: float, r_core: float, r_outer: float) -> float:
	## 1 inside r_core, smooth fall to 0 at r_outer.
	if r_outer <= r_core:
		return 1.0 if d <= r_core else 0.0
	return 1.0 - smooth01((d - r_core) / (r_outer - r_core))


static func smin(a: float, b: float, k: float) -> float:
	## C1 polynomial smooth-min (SD-17 §4).
	if k <= 0.0:
		return minf(a, b)
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


static func compass_deg(v: Vector2) -> float:
	## Compass azimuth of a direction in xz: 0 = north (−Z), 90 = east (+X). [0, 360).
	return fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)


static func angle_diff_deg(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)

