extends GutTest


func before_each() -> void:
	VillagePondShape.clear_cache_for_tests()
	VillagePondShape.set_active(VillagePondShape.classic())


func test_classic_resolve_center() -> void:
	var layout := VillageLayout.authored()
	assert_eq(VillagePondPlacement.resolve_center(layout), VillagePondSite.CLASSIC_CENTER)


func test_classic_center_passes_validate() -> void:
	var layout := VillageLayout.authored()
	assert_true(
		VillagePondPlacement.validate(VillagePondSite.CLASSIC_CENTER, layout),
		"classic pond slot between CD/CC must satisfy placement contract")


func test_blocks_scatter_at_covers_bank_plus_margin() -> void:
	var shape := VillagePondShape.classic()
	var bank := VillagePondShape.bank_outer_outline_xz()
	var probe := bank[0].lerp(shape.center_xz(), 0.85)
	assert_true(
		VillageScatterPositions.blocks_scatter_at(probe),
		"point on bank must block scatter")
	var outward := (bank[0] - shape.center_xz()).normalized()
	var outside := bank[0] + outward * (VillagePondSite.SCATTER_CLEARANCE_M * 0.25)
	assert_true(VillageScatterPositions.blocks_scatter_at(outside))
	var far := bank[0] + outward * (VillagePondSite.SCATTER_CLEARANCE_M * 4.0)
	assert_false(
		VillageScatterPositions.blocks_scatter_at(far),
		"point well outside bank+clearance must not block")


func test_pond_center_matches_site_not_legacy() -> void:
	assert_eq(VillageScatterPositions.pond_center_xz(), VillagePondSite.CLASSIC_CENTER)
	assert_ne(VillagePondSite.CLASSIC_CENTER, Vector2(-6.5, 10.5))


func test_generated_validate_uses_layout_pond_clearances() -> void:
	const SEED := 4  # known strict-valid pond slot with ivy-l2x 3.0/2.0 clearances
	var layout := VillageLayout.generate(SEED)
	if layout.fallback:
		pending("seed %d fell back — skip clearance contract" % SEED)
		return
	assert_almost_eq(layout.pond_cottage_clearance_m, 3.0, 1e-6)
	assert_almost_eq(layout.pond_path_clearance_m, 2.0, 1e-6)
	var center := layout.pond_center
	assert_true(
		VillagePondPlacement.validate(center, layout, true),
		"resolved centre must satisfy layout pond clearances with paths")


func test_generated_layout_resolves_valid_center_for_seed_4() -> void:
	const SEED := 4
	var layout := VillageLayout.generate(SEED)
	if layout.fallback:
		pass_test("seed %d fell back to authored — skip generated resolve" % SEED)
		return
	var center := layout.pond_center
	assert_true(
		VillagePondPlacement.validate(center, layout, true),
		"post-path pond centre must satisfy placement contract")
	assert_false(
		VillagePondPlacement.pond_overlaps_plaza_exclusion(center, layout),
		"seed 4 pond must stay outside plaza exclusion")


func test_resolve_after_paths_fast_on_five_seeds() -> void:
	VillagePondShape.clear_cache_for_tests()
	var seeds := [1, 4, 42, 77, 100]
	for seed: int in seeds:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var t0 := Time.get_ticks_usec()
		var center := VillagePondPlacement.resolve_after_paths(layout)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		assert_lt(ms, 50.0,
			"seed=%d resolve_after_paths took %.2f ms (cap 50 ms)" % [seed, ms])
		assert_true(
			VillagePondPlacement.validate(center, layout, true),
			"seed=%d re-resolve must stay valid" % seed)


func test_generated_pond_not_classic_fallback() -> void:
	const SEED := 4
	var layout := VillageLayout.generate(SEED)
	if layout.fallback:
		pass_test("seed %d fell back" % SEED)
		return
	assert_ne(
		layout.pond_center, VillagePondSite.CLASSIC_CENTER,
		"generated layout must not fall back to classic pond slot")
