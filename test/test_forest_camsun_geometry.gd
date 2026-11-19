extends GutTest

const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")


func test_old_wedge_variant5_behind_camsun_not_in_fov() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := ForestParams.production()
	params.variant = 5
	var trees := ForestPlacement.forest_tree_xz(layout, params)
	assert_eq(ForestPlaygroundCamera.count_trees_in_camsun_fov(trees), 0,
		"legacy +Z wedge (variant 5) should be behind CamSun")


func test_production_backdrop_visible_in_camsun() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := ForestParams.production()
	assert_eq(params.variant, 0, "production")
	var trees := VillageScatterPositions.forest_tree_xz(layout)
	# AR-NOFOG contract change: no haze gate; the FOV count is the whole test.
	var stats := ForestPlaygroundCamera.count_trees_visible_in_camsun(trees)
	assert_eq(stats.keys(), ["in_fov"], "only the FOV count is returned")
	assert_gte(stats["in_fov"], 12,
		"production backdrop: >=12 trees in CamSun view (got %d)" % stats["in_fov"])
