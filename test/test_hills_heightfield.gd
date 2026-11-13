extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")


func test_lawn_grid_sanctity() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	for ix in range(9):
		for iz in range(9):
			var fx := float(ix) / 8.0
			var fz := float(iz) / 8.0
			var r := layout.lawn_radius * fx * 0.98
			var p := g + Vector2(sin(fz * TAU) * r, cos(fz * TAU) * r)
			var y := HillsHeightfield.sample_y(p, layout, params, t_seed)
			assert_lte(y, y_lawn + 0.15, "lawn sample %s y=%.3f" % [p, y])


func test_determinism_same_seed() -> void:
	var layout := VillageLayout.generate(12)
	var params := HillsParams.production()
	var t := HillsHeightfield.terrain_seed(layout, params)
	var probe := layout.hamlet_centre_xz + Vector2(80.0, 20.0)
	var y1 := HillsHeightfield.sample_y(probe, layout, params, t)
	var y2 := HillsHeightfield.sample_y(probe, layout, params, t)
	assert_almost_eq(y1, y2, 1e-5)


func test_variant1_legacy_ramp_sample() -> void:
	var layout := VillageLayout.generate(7)
	var params := HillsParams.production()
	params.variant = 1
	var t := HillsHeightfield.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var inner := layout.hill_inner
	var mid := g + Vector2(0.0, (inner + 140.0) * 0.5)
	var y := HillsHeightfield.sample_y(mid, layout, params, t)
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	assert_gt(y, y_lawn + 2.0)
