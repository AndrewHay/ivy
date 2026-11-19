## ivy-82zn.14.14 (WP1) — VillageLandform: noise variants, offset search, AC-LT-SITE, search budget.
## SD-VILLAGE-TERRAIN-17 / -18, AR-LF-D4, AR-LF-API, AR-LF-GAP-1.
extends GutTest

const VillageLandform = preload("res://src/playground/village_landform.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")

const _SEEDS: Array[int] = [1, 7, 12]


func _ctx_for(noise: int, seed: int = 7) -> Dictionary:
	var p := VillageTerrainParams.production()
	p.landform_noise = noise
	return VillageLandform.make_ctx(seed, p, Vector2(123.0, -456.0), 0.0)


func test_landform_salt_is_new_stream() -> void:
	assert_eq(VillageLayout.VILLAGE_LANDFORM_SALT, 0x7E44A2, "SD-17 landform salt")
	assert_eq(VillageLandform.landform_seed(7), VillageLayout._derive(7, 0x7E44A2), "landform seed")
	assert_eq(VillageLandform.detail_seed(7), VillageLayout._derive(7, VillageLayout.VILLAGE_TERRAIN_SALT),
		"detail keeps the existing terrain stream")


func test_noise_variants_stay_in_unit_range() -> void:
	for noise in [VillageLandform.NOISE_FBM, VillageLandform.NOISE_BILLOW,
			VillageLandform.NOISE_DDF, VillageLandform.NOISE_RIDGED]:
		var ctx := _ctx_for(noise)
		var lo := INF
		var hi := -INF
		for i in range(600):
			var q := Vector2(float(i % 30) * 37.0 - 500.0, float(i / 30) * 41.0 - 400.0)
			var n := VillageLandform.noise01(q, ctx)
			assert_true(is_finite(n), "noise %d finite" % noise)
			lo = minf(lo, n)
			hi = maxf(hi, n)
		assert_true(lo >= 0.0 and hi <= 1.0, "noise %d in [0, 1] (got %.3f..%.3f)" % [noise, lo, hi])
		assert_gt(hi - lo, 0.2, "noise %d is not constant" % noise)


func test_billow_soft_abs_has_no_valley_crease() -> void:
	## A plain abs() makes a gradient crease in every valley (dark line under the slope shader);
	## the soft abs keeps the second difference small everywhere (SD-17 noise table).
	## Test: at the sharpest valley found, halving h must quarter the second difference (C1 /
	## smooth: ratio ≈ 4); a gradient crease would only halve it (ratio ≈ 2).
	var ctx := _ctx_for(VillageLandform.NOISE_BILLOW)
	var d2 := func(p: Vector2, h: float) -> float:
		return absf(VillageLandform.L(p + Vector2(h, 0.0), ctx) - 2.0 * VillageLandform.L(p, ctx)
			+ VillageLandform.L(p - Vector2(h, 0.0), ctx))
	var worst := 0.0
	var at := Vector2.ZERO
	for line in range(6):
		var z := -300.0 + float(line) * 113.0
		var x := -400.0
		while x < 400.0:
			var v: float = d2.call(Vector2(x, z), 0.5)
			if v > worst:
				worst = v
				at = Vector2(x, z)
			x += 0.5
	# Refine to the local max on a 5 cm grid, then compare h = 0.5 and 0.25.
	var best := at
	for k in range(-10, 11):
		var p := at + Vector2(float(k) * 0.05, 0.0)
		if float(d2.call(p, 0.25)) > float(d2.call(best, 0.25)):
			best = p
	var ratio: float = float(d2.call(best, 0.5)) / maxf(float(d2.call(best, 0.25)), 1e-9)
	assert_gt(ratio, 3.0, "billow valley is C1: d2(0.5)/d2(0.25) = %.2f (crease ≈ 2), d2 %.4f m" % [ratio, worst])


func test_derivative_damped_gradients_are_finite_and_bounded() -> void:
	var ctx := _ctx_for(VillageLandform.NOISE_DDF)
	var worst := 0.0
	for i in range(400):
		var p := Vector2(float(i % 20) * 9.0 - 90.0, float(i / 20) * 9.0 - 90.0)
		var y0 := VillageLandform.L(p, ctx)
		var yx := VillageLandform.L(p + Vector2(0.5, 0.0), ctx)
		var yz := VillageLandform.L(p + Vector2(0.0, 0.5), ctx)
		var s := rad_to_deg(atan(Vector2(yx - y0, yz - y0).length() / 0.5))
		assert_true(is_finite(s), "DDF slope finite")
		worst = maxf(worst, s)
	assert_lt(worst, 35.0, "DDF slope stays well conditioned (max %.1f°)" % worst)


func test_rank_offsets_candidate_zero_and_count() -> void:
	var p := VillageTerrainParams.production()
	var ranked := VillageLandform.rank_offsets(7, p)
	assert_eq(ranked.size(), p.landform_offset_candidates, "one entry per candidate")
	var found_zero := false
	for c: Dictionary in ranked:
		if int(c["index"]) == 0:
			found_zero = true
			assert_eq(c["offset"], Vector2.ZERO, "candidate 0 is the (0, 0) offset")
	assert_true(found_zero, "candidate 0 present")


func test_rank_offsets_is_deterministic_and_ordered() -> void:
	var p := VillageTerrainParams.production()
	var a := VillageLandform.rank_offsets(12, p)
	var b := VillageLandform.rank_offsets(12, p)
	assert_eq(a.size(), b.size(), "same count")
	for i in range(a.size()):
		assert_eq(a[i]["index"], b[i]["index"], "same order at %d" % i)
		assert_eq(a[i]["offset"], b[i]["offset"], "same offset at %d" % i)
	## SD-28 §2 (2026-11-18): passing = storey group (storey_frac >= storey_ground_frac_min) by score,
	## then the rest by storey_frac descending; failing by violation.
	var seen_fail := false
	var seen_rest := false
	var last_score := -INF
	var last_frac := INF
	var last_viol := -INF
	for c: Dictionary in a:
		if bool(c["pass"]):
			assert_false(seen_fail, "passing candidates come before failing ones")
			var frac := float((c["measures"] as Dictionary).get("storey_frac", -1.0))
			if frac >= p.storey_ground_frac_min:
				assert_false(seen_rest, "storey group comes first")
				assert_true(float(c["score"]) >= last_score, "storey group sorted by score")
				last_score = float(c["score"])
			else:
				seen_rest = true
				assert_true(frac <= last_frac, "rest sorted by storey_frac descending")
				last_frac = frac
		else:
			seen_fail = true
			assert_true(float(c["violation"]) >= last_viol, "failing sorted by violation")
			last_viol = float(c["violation"])


func test_storey_rule_off_reproduces_the_score_ranking() -> void:
	## SD-28 §2 parity: storey_ground_frac_min = 0 turns the rule off: passing purely by score (ties on
	## index), exactly the pre-SD-28 order, and no storey measure is computed.
	var p := VillageTerrainParams.production()
	p.storey_ground_frac_min = 0.0
	var ranked := VillageLandform.rank_offsets(7, p)
	var last_score := -INF
	var last_index := -1
	for c: Dictionary in ranked:
		if not bool(c["pass"]):
			break
		var s := float(c["score"])
		assert_true(s > last_score or (s == last_score and int(c["index"]) > last_index), "pure score order")
		assert_false((c["measures"] as Dictionary).has("storey_frac"), "no storey measure when off")
		last_score = s
		last_index = int(c["index"])


func test_storey_rule_puts_storey_ground_first() -> void:
	## SD-28 §2: storey nodes (|p-G| <= 42, |p-H0| >= 14, outside the plaza keep, 1 m FD slope of
	## L+D <= max_site_slope_deg); storey_frac = share >= storey_ground_m off y_hero_raw. Rank 0 of
	## the probe seeds meets the 10 % minimum.
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var ranked := VillageLandform.rank_offsets(seed, p)
		var m: Dictionary = ranked[0]["measures"]
		assert_true(m.has("storey_frac") and m.has("storey_max"), "seed %d storey measures" % seed)
		gut.p("seed %d rank 0 storey_frac %.3f storey_max %.2f m" % [seed, m.get("storey_frac", -1.0),
			m.get("storey_max", -1.0)])
		assert_between(float(m["storey_frac"]), 0.0, 1.0, "fraction in [0, 1]")
		assert_gte(float(m["storey_frac"]), p.storey_ground_frac_min, "seed %d rank 0 meets the minimum" % seed)


func test_storey_soft_flag_when_no_candidate_meets_the_minimum() -> void:
	## SD-28 §2: if the rank used is below the minimum, terrain_diag.storey_soft (not offset_fallback).
	var p := VillageTerrainParams.production()
	p.storey_ground_frac_min = 1.0
	var layout := VillageLayout.generate(7, p)
	assert_false(layout.fallback, "generated")
	assert_true(bool(layout.terrain_diag.get("storey_soft", false)), "storey_soft set")
	assert_false(bool(layout.terrain_diag.get("offset_fallback", true)), "not an offset fallback")
	var q := VillageTerrainParams.production()
	var l2 := VillageLayout.generate(7, q)
	assert_false(bool(l2.terrain_diag.get("storey_soft", false)), "production seed 7 meets the minimum")


func test_rank_offsets_measures_follow_the_hard_rules() -> void:
	var p := VillageTerrainParams.production()
	var best: Dictionary = VillageLandform.rank_offsets(7, p)[0]
	var m: Dictionary = best["measures"]
	for key in ["s_hero", "up_hero", "down_hero", "aspect_deg", "span_v", "p95_v", "plaza_tilt_deg"]:
		assert_true(m.has(key), "measure %s present" % key)
	if bool(best["pass"]):
		assert_between(float(m["s_hero"]), p.hero_site_slope_min_deg, p.hero_site_slope_max_deg, "s_hero")
		assert_gte(float(m["up_hero"]), p.hero_not_crest_m, "not a crest")
		assert_gte(float(m["down_hero"]), p.hero_not_hollow_m, "not a hollow")
		assert_between(float(m["span_v"]), p.relief_span_min_m, p.relief_span_max_m, "village span")
		assert_lte(float(m["p95_v"]), p.village_slope_p95_max_deg, "village slope p95")
		assert_lte(float(m["plaza_tilt_deg"]), 10.0, "plaza raw tilt hard rule (AR-LF-GAP-4)")


func test_manual_mode_skips_the_search() -> void:
	var p := VillageTerrainParams.production()
	p.landform_offset_mode = VillageTerrainParams.OFFSET_MANUAL
	p.landform_offset_x = 321.0
	p.landform_offset_z = -77.0
	p.landform_rot_deg = 30.0
	var ranked := VillageLandform.rank_offsets(7, p)
	assert_eq(ranked.size(), 1, "manual = one candidate")
	assert_eq(ranked[0]["offset"], Vector2(321.0, -77.0), "manual offset used as given")
	assert_almost_eq(float(ranked[0]["rot_deg"]), 30.0, 1e-6, "manual rotation used")
	assert_true((ranked[0]["measures"] as Dictionary).has("span_v"), "measures still reported")


func test_ac_lt_site_seeds_pass_without_fallback() -> void:
	## AC-LT-SITE: seeds 1/7/12 choose an offset that passes every SD-18 hard rule.
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		assert_false(layout.fallback, "seed %d generated" % seed)
		var lf: Dictionary = layout.landform
		assert_true(lf.has("index") and lf.has("offset") and lf.has("rank") and lf.has("measures")
			and lf.has("fallback") and lf.has("rot_deg"), "layout.landform shape seed %d" % seed)
		assert_false(bool(lf["fallback"]), "seed %d offset passes the hard rules" % seed)
		assert_false(bool(layout.terrain_diag.get("offset_fallback", true)), "diag flag seed %d" % seed)


func test_ac_lt_site_sweep_at_most_two_fallbacks() -> void:
	var p := VillageTerrainParams.production()
	var fallbacks := 0
	for seed in range(1, 21):
		if not bool(VillageLandform.rank_offsets(seed, p)[0]["pass"]):
			fallbacks += 1
	assert_lte(fallbacks, 2, "AC-LT-SITE sweep: %d / 20 seeds fall back" % fallbacks)


func test_search_budget_300_ms() -> void:
	## AC-LT-PERF (search part), restated 2026-11-18 (SD-28 §2, K 128 + storey measure): <= 300 ms.
	var p := VillageTerrainParams.production()
	VillageLandform.rank_offsets(3, p)  # warm the FastNoiseLite cache
	for seed in _SEEDS:
		var t0 := Time.get_ticks_usec()
		VillageLandform.rank_offsets(seed, p)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		gut.p("seed %d offset search %.1f ms" % [seed, ms])
		assert_lte(ms, 300.0, "seed %d offset search %.1f ms" % [seed, ms])


func test_layout_stores_terrain_params_and_search_runs_once() -> void:
	var layout := VillageLayout.generate(7)
	assert_null(layout.terrain_params, "generate(seed) = production params (null)")
	var p := VillageTerrainParams.production()
	p.landform_height_m = 10.0
	var l2 := VillageLayout.generate(7, p)
	assert_eq(l2.terrain_params, p, "generate(seed, params) keeps the params")
	var diag: Dictionary = VillageGeneratorV3.last_diag
	assert_true(diag.has("landform"), "last_diag carries the landform")
	assert_eq(int(diag.get("landform_searches", -1)), 1, "rank_offsets ran once, before the attempt loop")


func test_flat_variant_skips_the_search() -> void:
	var p := VillageTerrainParams.production()
	p.variant = 1
	var layout := VillageLayout.generate(7, p)
	assert_true(layout.landform.is_empty(), "flat variant: no landform")
	assert_eq(int(VillageGeneratorV3.last_diag.get("landform_searches", -1)), 0, "no search")


# ── Measured ring (SD-VILLAGE-TERRAIN-19 steps 1–6, ivy-82zn.14.22 / WP2) ──────

func _plane_grid(slope_deg: float, half: int) -> Dictionary:
	## 1 m grid centred on the origin, U = tan(slope)·x.
	var k := tan(deg_to_rad(slope_deg))
	return VillageLandform.make_ring_grid(Vector2(-half, -half), 2 * half + 1, 2 * half + 1,
		func(xz: Vector2) -> float: return k * xz.x)


func _disc_sdf(grid: Dictionary, r_c: float) -> PackedFloat32Array:
	return VillageLandform.grid_sdf(grid, func(xz: Vector2) -> float: return xz.length() - r_c)


func test_fbm_fast_path_is_bit_identical() -> void:
	## L's prepared fBm path (AC-LT-PERF) must equal the reference formula exactly.
	var p := VillageTerrainParams.production()
	for rot in [0.0, 30.0]:
		var ctx := VillageLandform.make_ctx(7, p, Vector2(123.4, -456.7), rot)
		assert_not_null(ctx.get("_fbm"), "production uses the fast path")
		for i in range(300):
			var xz := Vector2(float(i % 20) * 6.3 - 60.0, float(i / 20) * 7.1 - 55.0)
			var ref := float(p.landform_height_m) * VillageLandform.noise01(VillageLandform.landform_q(xz, ctx), ctx)
			assert_eq(VillageLandform.L(xz, ctx), ref, "L fast path at %s rot %.0f" % [str(xz), rot])
	var pb := VillageTerrainParams.production()
	pb.landform_noise = VillageLandform.NOISE_BILLOW
	assert_null(VillageLandform.make_ctx(7, pb).get("_fbm"), "other noise types use the reference path")


func test_ring_constants() -> void:
	assert_eq(VillageLandform.RING_LADDER_STEP_M, 0.5, "SD-19 ladder step")
	assert_eq(VillageLandform.RING_OVERLAP_TOL_DEG, 3.0, "SD-19 overlap tolerance")


func test_measured_ring_flat_ground_passes_at_the_minimum() -> void:
	var g := VillageLandform.make_ring_grid(Vector2(-20, -20), 41, 41, func(_xz: Vector2) -> float: return 0.0)
	var r := VillageLandform.measured_ring(g, _disc_sdf(g, 4.6), 0.0, 3.0, 9.0, 22.0)
	assert_true(bool(r["ok"]), "flat ground passes")
	assert_eq(float(r["w"]), 3.0, "first ladder width")
	assert_almost_eq(float(r["peak_deg"]), 0.0, 1e-4, "no slope")


func test_measured_ring_takes_the_first_passing_ladder_width() -> void:
	# 8°: under the one-sided metric (ivy-82zn.14.23) a 10° plane no longer fits a 4.6 m core.
	var g := _plane_grid(8.0, 20)
	var sdf := _disc_sdf(g, 4.6)
	var r := VillageLandform.measured_ring(g, sdf, 0.0, 3.0, 9.0, 22.0)
	assert_true(bool(r["ok"]), "8° plane: a ring fits")
	var w := float(r["w"])
	assert_lte(float(r["peak_deg"]), 22.0, "peak at w* within the limit")
	assert_gt(w, 3.0, "8° plane needs more than the minimum ring")
	assert_almost_eq(fmod(w - 3.0, 0.5), 0.0, 1e-6, "w* on the 0.5 m ladder")
	var below := VillageLandform.measured_ring(g, sdf, 0.0, w - 0.5, w - 0.5, 22.0)
	assert_false(bool(below["ok"]), "the ladder step below w* fails (first passing width)")
	assert_gt(float(below["peak_deg"]), 22.0, "peak below w* over the limit")


func test_measured_ring_fails_when_no_width_passes() -> void:
	var g := _plane_grid(21.0, 20)
	var r := VillageLandform.measured_ring(g, _disc_sdf(g, 4.6), 0.0, 3.0, 9.0, 22.0)
	assert_false(bool(r["ok"]), "21° plane: no ring meets 22°")
	assert_gt(float(r["best_peak_deg"]), 22.0, "best peak still over")
	assert_between(float(r["best_w"]), 3.0, 9.0, "best width on the ladder")


func test_measured_ring_has_no_overlap_allowance() -> void:
	## SD-19 step 4 (restated, ivy-82zn.14.23): every node is held to 22°, overlap nodes included. A
	## width whose isolated peak lies in (22°, 25°) still fails inside another site's ring.
	var found := false
	for s in [6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0]:
		var g := _plane_grid(s, 20)
		var sdf := _disc_sdf(g, 4.6)
		var w := 3.0
		while w <= 9.0 and not found:
			var iso := VillageLandform.measured_ring(g, sdf, 0.0, w, w, 22.0)
			var pk := float(iso["peak_deg"])
			if pk > 22.2 and pk < 24.8:
				var n_sdf := PackedFloat32Array()
				n_sdf.resize(sdf.size())
				n_sdf.fill(9.99)
				var nb := [{"sdf": n_sdf, "target": 0.0, "w": 10.0}]
				var ov := VillageLandform.measured_ring(g, sdf, 0.0, w, w, 22.0, nb)
				assert_false(bool(ov["ok"]), "%.0f° plane, w %.1f: peak %.1f° fails inside another ring too" % [s, w, pk])
				found = true
			w += 0.5
		if found:
			break
	assert_true(found, "a (22°, 25°) case exists in the plane sweep")


func test_typed_sdf_grids_match_the_callable_form() -> void:
	## AR-LF-PERF P6b: grid_sdf_rect / grid_sdf_disc are typed loops with the same formula.
	var g := VillageLandform.make_ring_grid(Vector2(-13, -7), 29, 23, func(_xz: Vector2) -> float: return 0.0)
	var rect := Rect2(Vector2(-3.3, -1.7), Vector2(5.4, 7.4))
	assert_eq(VillageLandform.grid_sdf_rect(g, rect),
		VillageLandform.grid_sdf(g, func(p: Vector2) -> float: return VillageTerrain.rect_sdf(p, rect)), "rect sdf")
	var c := Vector2(0.0, 2.59)
	assert_eq(VillageLandform.grid_sdf_disc(g, c, 7.0),
		VillageLandform.grid_sdf(g, func(p: Vector2) -> float: return p.distance_to(c) - 7.0), "disc sdf")


func test_measured_ring_uses_one_sided_differences() -> void:
	## SD-19 step 3 (restated): gx = max(|y[i+1] − y[i]|, |y[i] − y[i−1]|). A 0.5 m spike on one node
	## just outside the blend reads 14° by central differences (h/2 on its neighbours, 0 on itself)
	## but 35° one-sided, so the ring fails.
	var g := VillageLandform.make_ring_grid(Vector2(-20, -20), 41, 41, func(xz: Vector2) -> float:
		return 0.5 if xz == Vector2(8, 0) else 0.0)
	var sdf := _disc_sdf(g, 4.6)
	var r := VillageLandform.measured_ring(g, sdf, 0.0, 3.0, 3.0, 22.0)
	assert_false(bool(r["ok"]), "spike caught by the one-sided metric")
	assert_almost_eq(float(r["peak_deg"]), rad_to_deg(atan(sqrt(0.5))), 0.01, "peak = atan(sqrt(gx² + gz²)), gx = gz = 0.5")


func test_measured_ring_accepts_a_per_node_target() -> void:
	## Plaza ring: the candidate's target is a plane per node. Blending a 15° plane toward itself
	## leaves it at 15°, so the first ladder width passes.
	var g := _plane_grid(15.0, 20)
	var k := tan(deg_to_rad(15.0))
	var t := PackedFloat32Array()
	t.resize(41 * 41)
	for iz in range(41):
		for ix in range(41):
			t[iz * 41 + ix] = k * float(ix - 20)
	var r := VillageLandform.measured_ring(g, _disc_sdf(g, 4.6), t, 5.0, 10.0, 22.0)
	assert_true(bool(r["ok"]), "per-node target accepted")
	assert_eq(float(r["w"]), 5.0, "first width")
	assert_almost_eq(float(r["peak_deg"]), 15.0, 0.01, "plane slope kept")


func test_rank_offsets_hero_ring_ok_on_rank_zero() -> void:
	## SD-18 hero_ring_ok: rank 0 is verified (exact p95 + measured hero ring w* in [4, 10]); the
	## later passing candidates are verified lazily by the generator (verified = false, AC-LT-PERF).
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var ranked := VillageLandform.rank_offsets(seed, p)
		var c0: Dictionary = ranked[0]
		assert_true(bool(c0["pass"]) and bool(c0.get("verified", false)), "seed %d rank 0 verified" % seed)
		var m: Dictionary = c0["measures"]
		assert_true(bool(m.get("hero_ring_ok", false)), "seed %d rank 0 hero ring ok" % seed)
		assert_between(float(m.get("hero_ring_w", -1.0)), p.hero_ring_min_m, p.hero_ring_max_m,
			"seed %d hero ring w in its clamp" % seed)
		assert_lte(float(m.get("hero_ring_peak_deg", 99.0)), p.ring_max_slope_deg, "peak at w*")
		var lazy := 0
		for c: Dictionary in ranked:
			if bool(c["pass"]) and not bool(c.get("verified", false)):
				lazy += 1
		assert_gte(lazy, VillageLandform.VERIFY_RANKS - 1, "seed %d: ranks 1–2 left for the generator" % seed)


func test_lazy_verification_for_later_ranks() -> void:
	## The generator verifies rank 1+ (p95 + hero ring) when it reaches it (landform_for_rank).
	var p := VillageTerrainParams.production()
	var ranked := VillageLandform.rank_offsets(1, p)
	var r1 := -1
	for i in range(1, ranked.size()):
		if bool(ranked[i]["pass"]) and not bool(ranked[i].get("verified", true)):
			r1 = i
			break
	assert_gt(r1, 0, "a lazily verified passing rank exists")
	var c: Dictionary = ranked[r1].duplicate(true)
	var ok := VillageLandform.verify_candidate(1, p, c)
	assert_true(bool(c["verified"]), "verified after the lazy check")
	assert_eq(bool(c["pass"]), ok, "pass flag follows the check")
	var hr := VillageLandform.hero_ring(1, p, ranked[r1]["offset"])
	if float((c["measures"] as Dictionary).get("p95_v", 99.0)) <= p.village_slope_p95_max_deg:
		assert_almost_eq(float(c["measures"]["hero_ring_w"]), float(hr["w"]), 1e-6, "lazy w* = direct measurement")
		assert_eq(ok, bool(hr["ok"]), "pass reflects hero_ring_ok")


func test_rank_offsets_hero_ring_failure_moves_the_offset() -> void:
	## SD-18 / SD-19 worked numbers: seed 7's old rank 0 (idx 20) has no hero ring ≤ 10 m; the new
	## rank 0 is idx 36. Pinned to the pre-SD-28 search (K 64, storey rule off, the parity setting)
	## because it characterises the hero-ring hard rule on a known candidate, not the ordering.
	var p := VillageTerrainParams.production()
	p.landform_offset_candidates = 64
	p.storey_ground_frac_min = 0.0
	var ranked := VillageLandform.rank_offsets(7, p)
	assert_eq(int(ranked[0]["index"]), 36, "seed 7 rank 0 moves to idx 36")
	var old: Dictionary = {}
	for c: Dictionary in ranked:
		if int(c["index"]) == 20:
			old = c
	assert_false(old.is_empty(), "idx 20 present")
	assert_false(bool(old["pass"]), "idx 20 fails hero_ring_ok")
	assert_gt(float((old["measures"] as Dictionary).get("hero_ring_peak_deg", 0.0)), p.ring_max_slope_deg,
		"failing peak recorded")
	assert_false(bool((old["measures"] as Dictionary).get("hero_ring_ok", true)), "flag recorded")


func test_rank_zero_passes_plaza_ring_ok() -> void:
	## SD-18 plaza_ring_ok (ivy-82zn.14.23): the plaza ring is measured (ladder 5–10 m, per-node
	## plane target, nothing replayed); rank 0 passes and stores plaza_ring_w.
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var m: Dictionary = VillageLandform.rank_offsets(seed, p)[0]["measures"]
		assert_true(bool(m.get("plaza_ring_ok", false)), "seed %d rank 0 plaza ring ok" % seed)
		assert_between(float(m.get("plaza_ring_w", -1.0)), p.plaza_ring_m, p.plaza_ring_max_m, "plaza w in its clamp")
		assert_lte(float(m.get("plaza_ring_peak_deg", 99.0)), p.ring_max_slope_deg, "plaza peak at w*")


func test_seed_16_moves_off_a_failing_plaza_ring() -> void:
	## SD-18: seed 16's old rank 0 has no plaza ring ≤ 10 m, so the search moves to its next candidate.
	## Pinned to the pre-SD-28 search (K 64, storey rule off) for the same reason as the seed-7 test.
	var p := VillageTerrainParams.production()
	p.landform_offset_candidates = 64
	p.storey_ground_frac_min = 0.0
	var ranked := VillageLandform.rank_offsets(16, p)
	var failed := false
	for c: Dictionary in ranked:
		var m: Dictionary = c["measures"]
		if bool(c.get("verified", false)) and m.has("plaza_ring_ok") and not bool(m["plaza_ring_ok"]):
			failed = true
			assert_false(bool(c["pass"]), "plaza-ring failure fails the offset")
			assert_gt(float(m["plaza_ring_peak_deg"]), p.ring_max_slope_deg, "failing plaza peak recorded")
	assert_true(failed, "a verified seed-16 candidate failed plaza_ring_ok")
	assert_true(bool(ranked[0]["measures"].get("plaza_ring_ok", false)), "rank 0 passes")


func test_layout_stores_plaza_ring_w_and_the_field_uses_it() -> void:
	var p := VillageTerrainParams.production()
	var layout := VillageLayout.generate(7)
	assert_between(float(layout.landform.get("plaza_ring_w", -1.0)), p.plaza_ring_m, p.plaza_ring_max_m,
		"layout.landform.plaza_ring_w")
	var f = VillageTerrain.field(layout, p)
	for s: Dictionary in f.sites:
		if s["kind"] == "plaza":
			assert_eq(float(s["w"]), float(layout.landform["plaza_ring_w"]), "field plaza w = stored")


func test_layout_stores_hero_ring_w() -> void:
	var p := VillageTerrainParams.production()
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		assert_between(float(layout.landform.get("hero_ring_w", -1.0)), p.hero_ring_min_m, p.hero_ring_max_m,
			"seed %d layout.landform.hero_ring_w" % seed)


func test_manual_mode_reports_the_hero_ring() -> void:
	var p := VillageTerrainParams.production()
	p.landform_offset_mode = VillageTerrainParams.OFFSET_MANUAL
	var best: Dictionary = VillageLandform.rank_offsets(1, VillageTerrainParams.production())[0]
	p.landform_offset_x = (best["offset"] as Vector2).x
	p.landform_offset_z = (best["offset"] as Vector2).y
	var c: Dictionary = VillageLandform.rank_offsets(1, p)[0]
	var m: Dictionary = c["measures"]
	assert_true(m.has("hero_ring_ok") and m.has("hero_ring_peak_deg"), "manual mode measures the hero ring")
	assert_almost_eq(float(m["hero_ring_w"]), float((best["measures"] as Dictionary)["hero_ring_w"]), 1e-6,
		"same w* as the search")


func test_ring_width_worked_numbers() -> void:
	## SD-VILLAGE-TERRAIN-19 worked numbers (ring max 22°).
	var a := VillageLandform.ring_width(4.6, 8.0, 22.0, 3.0, 9.0)
	assert_almost_eq(float(a["w"]), 4.2, 0.15, "cottage s 8°")
	assert_true(bool(a["ok"]), "8° ok")
	var b := VillageLandform.ring_width(4.6, 10.0, 22.0, 3.0, 9.0)
	assert_almost_eq(float(b["w"]), 6.6, 0.15, "cottage s 10°")
	var c := VillageLandform.ring_width(7.0, 9.0, 22.0, 4.0, 10.0)
	assert_almost_eq(float(c["w"]), 8.1, 0.15, "hero s 9°")
	var flat := VillageLandform.ring_width(4.6, 0.0, 22.0, 3.0, 9.0)
	assert_almost_eq(float(flat["w"]), 3.0, 1e-6, "flat site uses the ring minimum")
	var steep := VillageLandform.ring_width(4.6, 17.0, 22.0, 3.0, 9.0)
	assert_false(bool(steep["ok"]), "denominator <= 0 rejects")
	var wide := VillageLandform.ring_width(4.6, 13.0, 22.0, 3.0, 9.0)
	assert_false(bool(wide["ok"]), "unclamped w > max rejects")
