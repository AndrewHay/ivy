extends GutTest

const PlaygroundScene = preload("res://scenes/playground/forest_playground.tscn")
const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")


func test_playground_scene_loads_and_builds_trees() -> void:
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	var mm := root.get_node_or_null("Stage/ForestMultiMesh") as MultiMeshInstance3D
	assert_not_null(mm, "ForestMultiMesh should exist")
	assert_not_null(mm.multimesh)
	assert_gte(mm.multimesh.instance_count, 26, "production should place many trees")


func test_variants_place_trees_outside_hero_and_cottages() -> void:
	for variant in range(6):
		var params := ForestParams.production()
		params.variant = variant
		if variant == 1:
			params.apply_preset("Deep wedge")
		elif variant == 2:
			params.apply_preset("Arc ring behind hero")
		elif variant == 3:
			params.apply_preset("Wedge + CamSun gap flanks")
		elif variant == 4:
			params.apply_preset("Tree backdrop behind the village")
		elif variant == 5:
			params.apply_preset("Old: behind the camera")
		var layout := VillageLayout.generate(7)
		if layout.fallback:
			continue
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var xf := ForestPlacement.forest_tree_positions(layout, params)
		assert_gte(xf.size(), 26, "variant %d tree count" % variant)
		var hero := VillageLayout.HERO_DOOR_STOOP
		for i in xf.size():
			var p := Vector2(xf[i].origin.x, xf[i].origin.z)
			assert_gt(p.distance_to(hero), 4.0,
				"variant %d tree %d too close to hero" % [variant, i])
			for spec: Dictionary in layout.cottages:
				var rect := VillageBackdrop.cottage_exterior_rect(spec)
				assert_false(rect.has_point(p),
					"variant %d tree %d inside cottage" % [variant, i])
