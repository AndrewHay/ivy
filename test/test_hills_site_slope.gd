extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")


func test_site_ok_hill_rejects_excessive_slope() -> void:
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var backdrop := ForestPlacement.forest_tree_xz(layout, ForestParams.production())
	var g := layout.hamlet_centre_xz
	var steep: Vector2 = g
	var best_slope := 0.0
	for ir in range(24):
		for ia in range(36):
			var r := lerpf(params.forest_r_min_m, params.forest_r_max_m, float(ir) / 23.0)
			var a := (float(ia) / 36.0) * TAU
			var p := g + Vector2(sin(a) * r, cos(a) * r)
			var slope := HillsHeightfield.sample_slope_deg(p, layout, params, t_seed)
			if slope > best_slope:
				best_slope = slope
				steep = p
	if best_slope <= params.slope_max_deg:
		pass_test("no steep site in grid (max %.1f°)" % best_slope)
		return
	assert_false(
		HillsForestPlacement.site_ok_hill(steep, layout, params, backdrop),
		"site_ok_hill must reject slope %.1f° > max %.1f°" % [best_slope, params.slope_max_deg])
