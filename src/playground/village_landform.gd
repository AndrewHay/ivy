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
## Ranks verified exactly (p95 FD) for the generator's rank retry (AR-LF-D5: up to 3).
const VERIFY_RANKS := 3
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
	return float(ctx["params"].landform_height_m) * noise01(landform_q(xz, ctx), ctx)


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
	for i in range(offsets.size()):
		var ctx := base_ctx.duplicate()
		ctx["offset"] = offsets[i]
		var c := _evaluate_coarse(ctx, params, i, hero_q, d_hero, d_h0, nodes, d_grid)
		if bool(c["pass"]):
			passing.append(c)
		else:
			failing.append(c)
	passing.sort_custom(_by_score)
	# Exact p95 on the best passing candidates (rank order) until VERIFY_RANKS pass. Passing
	# candidates beyond that stay "pass" with verified = false (every coarse rule held).
	var verified: Array[Dictionary] = []
	var unverified: Array[Dictionary] = []
	var d_fd := {}
	for c: Dictionary in passing:
		if verified.size() >= VERIFY_RANKS:
			c["verified"] = false
			unverified.append(c)
			continue
		var ctx := base_ctx.duplicate()
		ctx["offset"] = c["offset"]
		var p95 := _exact_p95(ctx, nodes, d_grid, d_fd)
		(c["measures"] as Dictionary)["p95_v"] = p95
		c["verified"] = true
		if p95 <= params.village_slope_p95_max_deg:
			verified.append(c)
		else:
			c["pass"] = false
			c["score"] = INF
			c["violation"] = (p95 - params.village_slope_p95_max_deg) / 4.0
			failing.append(c)
	failing.sort_custom(_by_violation)
	var out: Array[Dictionary] = []
	out.append_array(verified)
	out.append_array(unverified)
	out.append_array(failing)
	return out


static func _by_score(a: Dictionary, b: Dictionary) -> bool:
	if float(a["score"]) != float(b["score"]):
		return float(a["score"]) < float(b["score"])
	return int(a["index"]) < int(b["index"])


static func _by_violation(a: Dictionary, b: Dictionary) -> bool:
	if float(a["violation"]) != float(b["violation"]):
		return float(a["violation"]) < float(b["violation"])
	return int(a["index"]) < int(b["index"])


static func make_ctx_light(norm_seed: int, params, offset: Vector2, rot_deg: float) -> Dictionary:
	## make_ctx without the hero mean (the search computes its own hero plane).
	var r := deg_to_rad(rot_deg)
	return {
		"l_seed": landform_seed(norm_seed), "d_seed": detail_seed(norm_seed), "offset": offset,
		"rot_deg": rot_deg, "cos": cos(r), "sin": sin(r), "params": params, "y_hero_raw": 0.0,
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
		"span_v": NAN, "p95_v": NAN, "plaza_tilt_deg": NAN,
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
	if d_fd.is_empty():
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
	var pm := _plane_measures(_plane_from_offsets(hero_q, zs))
	var m := {"s_hero": pm["slope_deg"], "aspect_deg": pm["aspect_deg"]}
	var nodes := _search_nodes(VillageLayout.VILLAGE_GREEN_G)
	var pts: PackedVector2Array = nodes["pts"]
	var d_grid := PackedFloat32Array()
	for p: Vector2 in pts:
		d_grid.append(D(p, ctx))
	_grid_measures(ctx, params, nodes, d_grid, raw_y(h0, ctx), m)
	m["p95_v"] = _exact_p95(ctx, nodes, d_grid, {})
	var viol := _range_violation(float(m["s_hero"]), params.hero_site_slope_min_deg,
		params.hero_site_slope_max_deg, maxf(params.hero_site_slope_max_deg, 1.0))
	viol += _grid_violation(m, params)
	viol += maxf(0.0, float(m["p95_v"]) - params.village_slope_p95_max_deg) / 4.0
	return {"index": index, "offset": offset, "rot_deg": rot_deg, "pass": viol <= 0.0,
		"score": _score(m, params), "violation": viol, "measures": m}


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


static func ring_width(r_c: float, s_deg: float, ring_max_deg: float, w_min: float, w_max: float) -> Dictionary:
	## SD-19: w = 1.5·tan(s)·r_c / (tan(ring_max) − 1.25·tan(s)), clamped to [w_min, w_max].
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

