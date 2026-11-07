extends GutTest

const VillageBackdropScene = preload("res://src/world/village_backdrop.tscn")


func before_each() -> void:
	VillagePondShape.set_active(VillagePondShape.classic())


func test_pond_meshes_exist() -> void:
	var backdrop: VillageBackdrop = VillageBackdropScene.instantiate()
	add_child_autofree(backdrop)
	await get_tree().process_frame
	assert_not_null(backdrop.get_node_or_null("PondWater"))
	assert_not_null(backdrop.get_node_or_null("PondBank"))


func test_clover_scatter_on_pond_bank_only() -> void:
	var layers := VillageScatterPositions.clover_layers()
	var total := 0
	for piece in VillageScatterPositions.CLOVER_PIECES:
		var transforms: Array = layers[piece]
		total += transforms.size()
		for t_raw in transforms:
			var t := t_raw as Transform3D
			var p := Vector2(t.origin.x, t.origin.z)
			assert_true(
				VillageScatterPositions.is_on_pond_clover_bank(p),
				"clover at %s must lie on pond bank annulus" % str(p))
	assert_gte(total, VillageScatterPositions.CLOVER_MIN_INSTANCES)
	assert_eq(total, VillageScatterPositions.clover_bank_instance_count())


func test_no_plants_inside_pond_water_after_generated_grass_leak() -> void:
	## Regression: generated grass tests set VillagePondShape.active to hamlet pond;
	## plant_layers() must still reject classic pond sites (polar placement is pivot-centred).
	var layout := VillageLayout.generate(4242)
	if layout.fallback:
		pending("fallback layout")
		return
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var path_stones := VillageScatterPositions.path_stone_transforms(
		layout.path_polylines(), func(_x, _z): return false)
	var bushes := VillageScatterPositions.bush_common_positions(
		layout.cottages, layout.bush_filler_inner, layout.bush_filler_outer,
		layout.hamlet_centre_xz)
	var ctx := VillageGrassExclusionContext.for_layout(
		layout.paths,
		func(p: Vector2) -> bool: return layout.inside_any_cottage(p, 0.35),
		path_stones, bushes, layout.hamlet_centre_xz, VillageLayout.HERO_DOOR_STOOP, true,
		layout.cottages)
	VillageScatterPositions.grass_blade_positions(ctx)
	## Next backdrop build re-activates its own pond; grass-session statics must not leak.
	VillagePondShape.set_active(VillagePondShape.classic())
	var classic := VillagePondShape.classic()
	for key in ["Plant_7", "Plant_7_Big"]:
		for t_raw in VillageScatterPositions.plant_layers()[key]:
			var p := Vector2((t_raw as Transform3D).origin.x, (t_raw as Transform3D).origin.z)
			assert_false(classic._is_in_water(p, 0.0),
				"plant at %s must not sit in classic pond water after generated grass" % str(p))


func test_no_plants_inside_pond_water() -> void:
	var layers := VillageScatterPositions.plant_layers()
	for key in ["Plant_7", "Plant_7_Big"]:
		for t_raw in layers[key]:
			var t := t_raw as Transform3D
			var p := Vector2(t.origin.x, t.origin.z)
			assert_false(
				VillageScatterPositions.is_in_pond_water(p),
				"plant at %s must not sit in pond water" % str(p))


func test_grass_allowed_on_outer_bank() -> void:
	var inner := VillagePondShape.water_render_outline_xz()
	var outer := VillagePondShape.bank_outer_outline_xz()
	var n := mini(inner.size(), outer.size())
	var saw_outer := false
	for i in range(0, n, maxi(1, n / 48)):
		var p := inner[i].lerp(outer[i], 0.82)
		if VillagePondShape.bank_shoreline_along(p) >= VillagePondSite.GRASS_BANK_MIN_ALONG:
			assert_false(
				VillageScatterPositions.blocks_grass_at(p),
				"outer bank at %s should allow blade grass" % str(p))
			saw_outer = true
	assert_true(saw_outer, "expected samples on outer bank band")


func test_no_grass_inside_pond_water() -> void:
	var path_stones := VillageScatterPositions.path_stone_transforms(
		VillageBackdrop.path_polylines(),
		func(_cx: float, _cz: float) -> bool: return false)
	var bushes := VillageScatterPositions.bush_common_positions()
	var ctx := VillageGrassExclusionContext.for_village(path_stones, bushes)
	for t in VillageScatterPositions.grass_blade_positions(ctx):
		var p := Vector2(t.origin.x, t.origin.z)
		assert_false(
			VillageScatterPositions.is_in_pond_water(p),
			"grass tuft at %s must not sit in pond water" % str(p))


func test_clover_multimeshes_in_backdrop() -> void:
	var backdrop: VillageBackdrop = VillageBackdropScene.instantiate()
	add_child_autofree(backdrop)
	await get_tree().process_frame
	for piece in VillageScatterPositions.CLOVER_PIECES:
		var node_name := "Scatter_Clover_%s" % piece
		var mmi := backdrop.get_node_or_null(node_name) as MultiMeshInstance3D
		assert_not_null(mmi, "expected %s" % node_name)
		assert_gt(mmi.multimesh.instance_count, 0)
