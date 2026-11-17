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
	var seen_fail := false
	var last_score := -INF
	var last_viol := -INF
	for c: Dictionary in a:
		if bool(c["pass"]):
			assert_false(seen_fail, "passing candidates come before failing ones")
			assert_true(float(c["score"]) >= last_score, "passing sorted by score")
			last_score = float(c["score"])
		else:
			seen_fail = true
			assert_true(float(c["violation"]) >= last_viol, "failing sorted by violation")
			last_viol = float(c["violation"])


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


func test_search_budget_150_ms() -> void:
	## AC-LT-PERF (search part): <= 150 ms per generate (GA probe: 76-88 ms).
	var p := VillageTerrainParams.production()
	VillageLandform.rank_offsets(3, p)  # warm the FastNoiseLite cache
	for seed in _SEEDS:
		var t0 := Time.get_ticks_usec()
		VillageLandform.rank_offsets(seed, p)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		assert_lte(ms, 150.0, "seed %d offset search %.1f ms" % [seed, ms])


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
