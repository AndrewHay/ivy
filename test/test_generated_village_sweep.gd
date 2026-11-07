## Sweep tests for VillageLayout.generate() — v3 path-first (ivy-oan3.9).
extends GutTest

const SWEEP_SEEDS := 50


static func _rect2_corners(rect: Rect2) -> Array[Vector2]:
	return [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]


static func _layout_key(layout: VillageLayout) -> String:
	var parts: Array[String] = []
	for spec: Dictionary in layout.cottages:
		var c: Vector2 = spec["centre"]
		parts.append("%d,%d,%d" % [
			int(round(c.x * 1000.0)), int(round(c.y * 1000.0)), int(spec["yaw_deg"])])
	parts.sort()
	return "|".join(parts)


func after_each() -> void:
	VillageLayout._test_max_darts = -1


func test_inv36_outer_corners() -> void:
	var g := VillageLayout.VILLAGE_GREEN_G
	var corner_max := VillageLayout.HAMLET_MAX_CORNER_FROM_G
	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var g_use := layout.hamlet_centre_xz if layout.is_generated else g
		for spec: Dictionary in layout.cottages:
			var rect := VillageBackdrop.cottage_exterior_rect(spec)
			for corner: Vector2 in _rect2_corners(rect):
				assert_lte(corner.distance_to(g_use), corner_max + 1e-4,
					"seed=%d corner %.3f m from G (max %.1f)" % [
						seed, corner.distance_to(g_use), corner_max])


func test_determinism() -> void:
	var test_seeds := [1, 42, 100, 12345, 200]
	for seed: int in test_seeds:
		var a := VillageLayout.generate(seed)
		var b := VillageLayout.generate(seed)
		assert_eq(a.cottages.size(), b.cottages.size(), "seed=%d cottage count" % seed)
		for i: int in a.cottages.size():
			var ca: Vector2 = a.cottages[i]["centre"]
			var cb: Vector2 = b.cottages[i]["centre"]
			assert_almost_eq(ca.x, cb.x, 1e-4, "seed=%d [%d] cx" % [seed, i])
			assert_almost_eq(ca.y, cb.y, 1e-4, "seed=%d [%d] cy" % [seed, i])
			assert_eq(int(a.cottages[i]["yaw_deg"]), int(b.cottages[i]["yaw_deg"]), "seed=%d yaw" % seed)


func test_edge_seed_zero() -> void:
	var layout := VillageLayout.generate(0)
	assert_false(layout.fallback, "seed=0 must not fall back")
	assert_eq(layout.cottages.size(), VillageLayout.GENERATED_HAMLET_COUNT)
	var layout2 := VillageLayout.generate(0)
	assert_eq(_layout_key(layout), _layout_key(layout2))


func test_edge_seed_negative_one() -> void:
	var layout := VillageLayout.generate(-1)
	assert_false(layout.fallback)
	var norm_seed := -1 & 0x7FFFFFFF
	var layout2 := VillageLayout.generate(norm_seed)
	assert_eq(_layout_key(layout), _layout_key(layout2))


func test_edge_seed_large() -> void:
	const HUGE_SEED: int = 1 << 62
	var layout := VillageLayout.generate(HUGE_SEED)
	assert_eq(layout.cottages.size(), VillageLayout.GENERATED_HAMLET_COUNT)
	assert_eq(_layout_key(layout), _layout_key(VillageLayout.generate(HUGE_SEED)))


func test_network_determinism() -> void:
	var test_seeds := [1, 42, 100, 12345, 200]
	for seed: int in test_seeds:
		var a := VillageLayout.generate(seed)
		var b := VillageLayout.generate(seed)
		assert_eq(a.edges.size(), b.edges.size(), "seed=%d edges" % seed)
		assert_eq(a.paths.size(), b.paths.size(), "seed=%d paths" % seed)


func test_network_path_variability() -> void:
	var edge_keys: Dictionary = {}
	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var parts: Array[String] = []
		for e: Vector2i in layout.edges:
			parts.append("%d_%d" % [mini(e.x, e.y), maxi(e.x, e.y)])
		parts.sort()
		edge_keys["|".join(parts)] = true
	assert_gte(edge_keys.size(), 25, "expected diverse v3 edge sets")  ## half of SWEEP_SEEDS (was 100 of 200)


func test_b2_path_crossings_soft_50_seeds() -> void:
	const MIN_CROSSING_FREE := 45  ## 90% of SWEEP_SEEDS (was 180 of 200)
	var crossing_free := 0
	var generated := 0
	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		generated += 1
		if VillageLayout.path_polylines_crossing_count(layout.paths) == 0:
			crossing_free += 1
	print("[B2] crossing-free %d / %d generated seeds" % [crossing_free, generated])
	assert_gte(crossing_free, MIN_CROSSING_FREE,
		"B2: only %d/%d crossing-free (need ≥%d)" % [crossing_free, generated, MIN_CROSSING_FREE])


func test_b2_pond_outside_plaza_50_seeds() -> void:
	var overlaps := 0
	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		if VillagePondPlacement.pond_overlaps_plaza_exclusion(layout.pond_center, layout):
			overlaps += 1
	assert_eq(overlaps, 0, "pond overlaps plaza on %d seeds" % overlaps)


func test_stone_count_budget() -> void:
	var fails: Array[String] = []
	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var stones := VillageScatterPositions.path_stone_transforms(
			layout.path_polylines(),
			func(cx: float, cz: float) -> bool:
				return Vector2(cx, cz).length() < 4.5 or layout.inside_any_cottage(Vector2(cx, cz), 0.2),
			layout.stone_seed, layout.min_stone_spacing)
		if stones.size() < 150 or stones.size() > 2500:
			fails.append("seed=%d: %d stones" % [seed, stones.size()])
	assert_eq(fails.size(), 0, "stone count out of range:\n%s" % "\n".join(fails))
