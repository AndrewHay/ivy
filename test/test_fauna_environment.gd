extends GutTest

const VillageBackdropScene = preload("res://src/world/village_backdrop.tscn")


func before_each() -> void:
	FaunaIntegration.set_gut_fauna_test_active(true)


func after_each() -> void:
	FaunaIntegration.set_gut_fauna_test_active(false)



func test_export_anchor_counts() -> void:
	var backdrop: VillageBackdrop = VillageBackdropScene.instantiate()
	add_child_autofree(backdrop)
	await get_tree().process_frame
	var env := backdrop.export_fauna_anchors()
	var flowers := 0
	var clover := 0
	for a in env.anchors:
		if a.kind == FaunaConstants.AnchorKind.FLOWER:
			flowers += 1
		elif a.kind == FaunaConstants.AnchorKind.CLOVER:
			clover += 1
	assert_gte(flowers, 40,
		"expect cluster blooms + path-side petals as flower anchors")
	assert_eq(clover, VillageScatterPositions.clover_bank_instance_count(),
		"pond clover rings export as CLOVER anchors")
	assert_eq(env.anchors.size(), flowers + clover)


func test_flower_anchors_in_garden_ring() -> void:
	var backdrop: VillageBackdrop = VillageBackdropScene.instantiate()
	add_child_autofree(backdrop)
	await get_tree().process_frame
	var env := backdrop.export_fauna_anchors()
	var flowers := 0
	for a in env.anchors:
		if a.kind != FaunaConstants.AnchorKind.FLOWER:
			continue
		flowers += 1
		var r := Vector2(a.local_transform.origin.x, a.local_transform.origin.z).length()
		assert_true(r >= FaunaConstants.GARDEN_RING_INNER_M)
		assert_true(r <= FaunaConstants.GARDEN_RING_OUTER_M)
	assert_gte(flowers, 40)


func test_clover_anchors_pass_ladybird_gating() -> void:
	var backdrop: VillageBackdrop = VillageBackdropScene.instantiate()
	add_child_autofree(backdrop)
	await get_tree().process_frame
	var env := backdrop.export_fauna_anchors()
	for a in env.anchors:
		if a.kind != FaunaConstants.AnchorKind.CLOVER:
			continue
		assert_true(
			FaunaGating.anchor_in_species_ring(FaunaConstants.Species.LADYBIRD, a),
			"pond CLOVER anchors must be eligible for ladybird spawn")


func test_clover_anchors_on_pond_bank() -> void:
	var backdrop: VillageBackdrop = VillageBackdropScene.instantiate()
	add_child_autofree(backdrop)
	await get_tree().process_frame
	var env := backdrop.export_fauna_anchors()
	var clover := 0
	for a in env.anchors:
		if a.kind != FaunaConstants.AnchorKind.CLOVER:
			continue
		clover += 1
		var p := Vector2(a.local_transform.origin.x, a.local_transform.origin.z)
		assert_true(VillageScatterPositions.is_on_pond_clover_bank(p))
	assert_eq(clover, VillageScatterPositions.clover_bank_instance_count())


func test_hero_weight_monotone_with_radius() -> void:
	var backdrop: VillageBackdrop = VillageBackdropScene.instantiate()
	add_child_autofree(backdrop)
	await get_tree().process_frame
	var env := backdrop.export_fauna_anchors()
	var saw_soft_band := false
	for a in env.anchors:
		var r := Vector2(a.local_transform.origin.x, a.local_transform.origin.z).length()
		if r < FaunaConstants.HERO_HARD_EXCLUSION_M:
			assert_eq(a.hero_weight, 0.0)
		elif r >= FaunaConstants.HERO_SOFT_FADE_M:
			assert_almost_eq(a.hero_weight, 1.0, 1e-5)
		else:
			saw_soft_band = true
			assert_true(a.hero_weight > 0.0 and a.hero_weight < 1.0)
	assert_true(saw_soft_band, "expected at least one anchor in the 5–7 m soft band")
