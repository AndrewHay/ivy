## Village generator v3: probe seeds, determinism, validation, timing (ivy-oan3.3).
extends GutTest

const _V3 := preload("res://src/world/village_gen/village_generator.gd")
const _Layout := preload("res://src/world/village_layout.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")

## Canonical probe set (quadrants + ms table in village_gen_v3_probe).
const PROBE_SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 240424020]

const TIMING_MEAN_MS_MAX := 600.0
const TIMING_WORST_MS_MAX := 1500.0


func test_probe_seeds_non_fallback_zero_violations_path_kinds() -> void:
	for seed: int in PROBE_SEEDS:
		var layout: VillageLayout = VillageLayout.generate(seed)
		assert_false(layout.fallback, "seed %d must not use authored fallback" % seed)
		var diag: Dictionary = _V3.last_diag
		# ivy-82zn.14.16: a path_cap_fallback layout (SD-20 flag) is a normal generated village whose
		# attempt record failed only on terrain:path_cap.
		assert_true(bool(diag.get("ok", false)) or bool(layout.terrain_diag.get("path_cap_fallback", false)),
			"seed %d last_diag.ok or flagged" % seed)
		var vc: Variant = diag.get("v_counts", {})
		assert_true(vc is Dictionary, "seed %d v_counts" % seed)
		for vk: String in ["v1", "v2", "v3", "v4", "v5", "v6"]:
			assert_eq(int((vc as Dictionary).get(vk, -1)), 0, "seed %s %s" % [str(seed), vk])
		assert_eq(layout.path_kinds.size(), layout.paths.size(), "seed %d path_kinds len" % seed)
		assert_gt(layout.paths.size(), 0, "seed %d paths" % seed)


func test_determinism_same_seed_twice() -> void:
	var seed := 240424020
	var a: VillageLayout = VillageLayout.generate(seed)
	var b: VillageLayout = VillageLayout.generate(seed)
	assert_eq(a.paths.size(), b.paths.size())
	assert_eq(a.path_kinds.size(), b.path_kinds.size())
	assert_eq(a.cottages.size(), b.cottages.size())
	for pi: int in range(a.paths.size()):
		var pa: Array = a.paths[pi] as Array
		var pb: Array = b.paths[pi] as Array
		assert_eq(pa.size(), pb.size(), "path %d vert count" % pi)
		if pa.is_empty():
			continue
		assert_eq(pa[0] as Vector2, pb[0] as Vector2, "path %d start" % pi)
		assert_eq(pa[pa.size() - 1] as Vector2, pb[pb.size() - 1] as Vector2, "path %d end" % pi)


func test_no_relaxed_select_stages_in_diag() -> void:
	for seed: int in PROBE_SEEDS:
		VillageLayout.generate(seed)
		var stage_ms: Dictionary = _V3.last_diag.get("stage_ms", {}) as Dictionary
		for key: String in [
			"5h_append_relaxed_gap_quadrant",
			"5i_append_relaxed_aggressive",
			"5j_select_relaxed_fresh",
			"5k_select_minimal_constraints",
		]:
			assert_false(stage_ms.has(key), "seed %d must not run %s" % [seed, key])


func test_generation_uses_at_most_four_attempts_per_rank() -> void:
	## Contract changed in ivy-82zn.14.16 (AR-LF-D5): 4 attempts per offset rank, up to 3 ranks.
	for seed: int in PROBE_SEEDS:
		VillageLayout.generate(seed)
		var att: int = int(_V3.last_diag.get("attempt", -1))
		assert_gte(att, 0, "seed %d missing attempt in last_diag" % seed)
		assert_lte(att, 3, "seed %d attempt index must be < 4 (got %d)" % [seed, att])
		assert_lte(int(_V3.last_diag.get("rank", -1)), 2, "seed %d rank ≤ 2" % seed)
		assert_lte(int(_V3.last_diag.get("attempts_used", 99)), 12, "seed %d ≤ 12 attempts" % seed)


func test_path_outcome_boundaries() -> void:
	## SD-20 + AR-LF-PERF P4: pass ≤ cap; near miss ≤ cap + path_near_miss_deg; else retry.
	var p := VillageTerrainParams.production()
	assert_eq(_V3._path_outcome(14.0, p), _V3.PATH_PASS, "at the cap")
	assert_eq(_V3._path_outcome(14.5, p), _V3.PATH_NEAR_MISS, "within 1°")
	assert_eq(_V3._path_outcome(15.0, p), _V3.PATH_NEAR_MISS, "exactly cap + 1°")
	assert_eq(_V3._path_outcome(15.01, p), _V3.PATH_RETRY, "over the near miss")
	p.path_near_miss_deg = 0.0
	assert_eq(_V3._path_outcome(14.01, p), _V3.PATH_RETRY, "near miss 0 = SD-20 rule")


func test_path_retry_budget_one_more_attempt_once_acceptable() -> void:
	## AR-LF-PERF P5: once the rank holds a path-only layout ≤ path_steep_accept_deg, one more
	## attempt runs, then the best is kept with path_cap_fallback (no rank move).
	var p := VillageTerrainParams.production()
	p.max_path_slope_deg = 0.01
	p.path_near_miss_deg = 0.0
	p.path_steep_accept_deg = 90.0
	var layout: VillageLayout = VillageLayout.generate(1, p)
	var att: Array = _V3.last_diag["attempts"]
	var first := -1
	for i in range(att.size()):
		if String(att[i]["fail_reason"]) == "terrain:path_cap":
			first = i
			break
	assert_gte(first, 0, "a path-only failure happened")
	assert_eq(att.size(), mini(first + 2, 4), "exactly one more attempt after the first acceptable path-only layout")
	for a: Dictionary in att:
		assert_eq(int(a["rank"]), 0, "no rank move for a path-only failure ≤ 18°")
	assert_true(bool(layout.terrain_diag.get("path_cap_fallback", false)), "kept with the flag")
	assert_false(layout.fallback, "not authored")


func test_path_near_miss_is_accepted_at_once() -> void:
	var p := VillageTerrainParams.production()
	p.max_path_slope_deg = 0.01
	p.path_near_miss_deg = 90.0
	var layout: VillageLayout = VillageLayout.generate(1, p)
	assert_true(bool(layout.terrain_diag.get("path_near_miss", false)), "near-miss flag")
	assert_true(bool(layout.terrain_diag.get("path_cap_fallback", false)), "flagged")
	var att: Array = _V3.last_diag["attempts"]
	var n_pc := 0
	for a: Dictionary in att:
		if String(a["fail_reason"]) == "terrain:path_cap":
			n_pc += 1
	assert_eq(n_pc, 1, "returned on the first path-only attempt (the near miss)")
	assert_eq(String(att[att.size() - 1]["fail_reason"]), "terrain:path_cap", "it is the last attempt run")


func test_pond_loop_reorder_picks_the_same_centre() -> void:
	## AR-LF-PERF P3: slope first, validate only flat sites (then steep ones by ascending slope);
	## same centre as the old validate-everything loop on seeds 1–20 × attempts 0–3.
	var p := VillageTerrainParams.production()
	var g := _Layout.VILLAGE_GREEN_G
	var plaza_rect := _Layout.plaza_rect_at(g, _Layout.PLAZA_SIDE_L)
	for seed in range(1, 21):
		var ranked := VillageLandform.rank_offsets(seed, p)
		var lf := _V3.landform_for_rank(seed, p, ranked, 0)
		var site := VillageSiteTerrain.for_landform(seed, p, lf)
		for attempt in range(4):
			var st := _V3._attempt_seed(seed, attempt)
			var new: Dictionary = _V3._choose_pond(seed, st, g, plaza_rect, site)
			var old := _old_pond_loop(seed, st, g, plaza_rect, site)
			assert_eq(new["centre"], old["centre"], "seed %d attempt %d pond centre" % [seed, attempt])
			assert_eq(new["try_st"], old["try_st"], "seed %d attempt %d RNG stream" % [seed, attempt])
			assert_eq(bool(new["steep"]), bool(old["steep"]), "seed %d attempt %d steep flag" % [seed, attempt])


func _old_pond_loop(norm: int, st: int, g: Vector2, plaza_rect: Rect2, site: VillageSiteTerrain) -> Dictionary:
	## Reference copy of the WP2 loop before AR-LF-PERF P3 (validate every try).
	var cands: Array = []
	var n_flat := 0
	var try_st := _Layout._derive(st, 0x2D88B021)
	for _pi: int in range(48):
		try_st = VillageScatterPositions.lcg_step(try_st ^ norm)
		var r := lerpf(16.0, 34.0, VillageScatterPositions.lcg_f01(try_st))
		try_st = VillageScatterPositions.lcg_step(try_st)
		var phi := deg_to_rad(lerpf(_Layout.FAN_PHI_MIN_DEG, _Layout.FAN_PHI_MAX_DEG, VillageScatterPositions.lcg_f01(try_st)))
		var c := g + Vector2(r * sin(phi), -r * cos(phi))
		var trial := VillageLayout.new()
		trial.is_generated = true
		trial.hamlet_centre_xz = g
		trial.plaza_rect = plaza_rect
		trial.lawn_radius = _Layout.GENERATED_LAWN_RADIUS
		trial.pond_cottage_clearance_m = _Layout.GENERATED_POND_COTTAGE_CLEARANCE_M
		trial.pond_path_clearance_m = _Layout.GENERATED_POND_PATH_CLEARANCE_M
		trial.cottages = []
		if VillagePondPlacement.validate(c, trial, false):
			var ps := site.pond_site(c)
			cands.append({"centre": c, "slope_deg": ps["slope_deg"], "mean": ps["mean"]})
			if float(ps["slope_deg"]) <= site.params.pond_max_site_slope_deg:
				n_flat += 1
				if n_flat >= VillagePondPlacement.POND_TERRAIN_CANDIDATES:
					break
	var ch := VillagePondPlacement.choose_terrain_site(cands, site.params.pond_max_site_slope_deg)
	return {"centre": ch.get("centre", Vector2.ZERO), "steep": ch.get("steep", false), "try_st": try_st}


func test_reserve_grid_copy_equals_a_fresh_build() -> void:
	## AR-LF-PERF P6a: the attempt-independent blocks are built once and copied per attempt.
	var g := _Layout.VILLAGE_GREEN_G
	var cottage_keep := _Layout.plaza_cottage_keep_clear_rect(g, _Layout.PLAZA_SIDE_L)
	var base: VillageOccupancyGrid = _V3._reserve_base_grid(g, cottage_keep)
	var a: VillageOccupancyGrid = base.copy()
	var b: VillageOccupancyGrid = _V3._reserve_base_grid(g, cottage_keep)
	a.block_circle(Vector2(10, -30), 7.0)
	b.block_circle(Vector2(10, -30), 7.0)
	assert_eq(a._blocked, b._blocked, "copied grid = fresh grid")
	assert_ne(base._blocked, a._blocked, "the base is not mutated by an attempt")


func test_path_cap_failure_retries_ranks_then_keeps_least_violating_layout() -> void:
	## SD-20 / AR-LF-D5 (rewritten ivy-82zn.14.24): impossible cap, no near miss, nothing acceptable
	## (accept 0.01): every rank's best path-only layout is over the accept limit, so all 3 ranks ×
	## 4 attempts run; the least-violating generated layout is kept with path_cap_fallback, never the
	## authored fallback.
	var p := VillageTerrainParams.production()
	p.max_path_slope_deg = 0.01
	p.path_steep_accept_deg = 0.01
	p.path_near_miss_deg = 0.0
	var layout: VillageLayout = VillageLayout.generate(1, p)
	var d: Dictionary = _V3.last_diag
	assert_false(layout.fallback, "not the authored fallback")
	assert_true(layout.is_generated, "generated layout kept")
	assert_true(bool(layout.terrain_diag.get("path_cap_fallback", false)), "path_cap_fallback set")
	var ranks := {}
	var pc_fails := 0
	for a: Dictionary in d["attempts"]:
		ranks[int(a["rank"])] = true
		if String(a["fail_reason"]) == "terrain:path_cap":
			pc_fails += 1
	assert_eq(ranks.size(), 3, "three offset ranks tried")
	assert_eq((d["attempts"] as Array).size(), 12, "4 attempts per rank")
	assert_gt(pc_fails, 0, "path-cap failures recorded")
	assert_gt(float(layout.terrain_diag.get("max_path_slope_deg", 0.0)), 0.01, "its path slope is reported")


func test_offset_fallback_still_tries_three_ranks() -> void:
	## AR-LF-D5 / SD-18 "no passing candidate": the least-violating offsets are ranks 0..2. Seed 7 with
	## billow noise has no passing candidate and site rejection starves plot selection on every
	## offset, so all 3 ranks × 4 attempts run before the (non-path) authored fallback.
	var p := VillageTerrainParams.production()
	p.landform_noise = VillageLandform.NOISE_BILLOW
	var layout: VillageLayout = VillageLayout.generate(7, p)
	assert_false(bool(VillageLandform.rank_offsets(7, p)[0]["pass"]), "precondition: no passing offset")
	var ranks := {}
	for a: Dictionary in _V3.last_diag["attempts"]:
		ranks[int(a["rank"])] = true
	assert_eq(ranks.size(), 3, "three least-violating offsets tried")
	assert_true(layout.fallback, "plot-select failures (not path) end on the authored fallback")


func test_flat_variant_has_no_terrain_rules() -> void:
	## Flat A/B: no site fn, no pond slope rule, no path cap (unchanged behaviour).
	var p := VillageTerrainParams.production()
	p.variant = 1
	p.max_path_slope_deg = 0.01
	var layout: VillageLayout = VillageLayout.generate(1, p)
	assert_false(layout.fallback, "flat generates")
	assert_false(layout.terrain_diag.has("path_cap_fallback"), "no path cap when flat")
	for spec: Dictionary in layout.cottages:
		assert_false(spec.has("ring_w"), "no measured ring when flat")


func test_last_diag_records_attempt_timeline() -> void:
	VillageLayout.generate(9)
	var attempts: Variant = _V3.last_diag.get("attempts", [])
	assert_true(attempts is Array, "attempts log must be an array")
	assert_gt((attempts as Array).size(), 0, "attempts log non-empty")
	for att_raw: Variant in attempts as Array:
		var att: Dictionary = att_raw as Dictionary
		assert_true(att.has("ms"), "each attempt has ms")
		assert_true(att.has("stage_reached"), "each attempt has stage_reached")


func test_seed_7_places_eight_cottages_without_fallback() -> void:
	var layout: VillageLayout = VillageLayout.generate(7)
	assert_false(layout.fallback, "seed 7 must generate after quadrant-targeted capacity branches")
	assert_eq(layout.cottages.size(), VillageLayout.GENERATED_HAMLET_COUNT)


func test_qa_sweep_fallback_seeds_58_77_94_generate() -> void:
	for seed: int in [58, 77, 94]:
		var layout: VillageLayout = VillageLayout.generate(seed)
		assert_false(layout.fallback, "QA sweep fallback seed %d" % seed)
		assert_true(bool(_V3.last_diag.get("ok", false)) or bool(layout.terrain_diag.get("path_cap_fallback", false)),
			"seed %d diag ok or flagged (path_cap_fallback)" % seed)


func test_probe_seeds_timing_slack() -> void:
	var sum_ms := 0.0
	var worst := 0.0
	for seed: int in PROBE_SEEDS:
		var t0 := Time.get_ticks_usec()
		var layout: VillageLayout = VillageLayout.generate(seed)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		sum_ms += ms
		worst = maxf(worst, ms)
		assert_false(layout.fallback, "timing seed %d" % seed)
	var mean := sum_ms / float(PROBE_SEEDS.size())
	assert_lte(mean, TIMING_MEAN_MS_MAX, "mean ms (DESIGN V7)")
	assert_lte(worst, TIMING_WORST_MS_MAX, "worst ms (DESIGN V7)")

