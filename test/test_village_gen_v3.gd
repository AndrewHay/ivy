## Village generator v3: probe seeds, determinism, validation, timing (ivy-oan3.3).
extends GutTest

const _V3 := preload("res://src/world/village_gen/village_generator.gd")
const _Layout := preload("res://src/world/village_layout.gd")

## Canonical probe set (quadrants + ms table in village_gen_v3_probe).
const PROBE_SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 240424020]

const TIMING_MEAN_MS_MAX := 600.0
const TIMING_WORST_MS_MAX := 1500.0


func test_probe_seeds_non_fallback_zero_violations_path_kinds() -> void:
	for seed: int in PROBE_SEEDS:
		var layout: VillageLayout = VillageLayout.generate(seed)
		assert_false(layout.fallback, "seed %d must not use authored fallback" % seed)
		var diag: Dictionary = _V3.last_diag
		assert_true(bool(diag.get("ok", false)), "seed %d last_diag.ok" % seed)
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


func test_generation_uses_at_most_four_attempts() -> void:
	for seed: int in PROBE_SEEDS:
		VillageLayout.generate(seed)
		var att: int = int(_V3.last_diag.get("attempt", -1))
		assert_gte(att, 0, "seed %d missing attempt in last_diag" % seed)
		assert_lte(att, 3, "seed %d attempt index must be < 4 (got %d)" % [seed, att])


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
		assert_true(bool(_V3.last_diag.get("ok", false)), "seed %d diag ok" % seed)


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

