extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")


func test_hill_forest_positions_pass_site_ok() -> void:
	for seed in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var params := HillsParams.production()
		var t_seed := HillsHeightfield.terrain_seed(layout, params)
		var backdrop := ForestPlacement.forest_tree_xz(layout, ForestParams.production())
		var xforms := HillsForestPlacement.hill_forest_transforms(
			layout, params, t_seed, backdrop)
		assert_gt(xforms.size(), 0, "seed %d hill forest" % seed)
		for t: Transform3D in xforms:
			var p := Vector2(t.origin.x, t.origin.z)
			assert_true(
				HillsForestPlacement.site_ok_hill(p, layout, params, backdrop),
				"seed %d pos %s" % [seed, p])
