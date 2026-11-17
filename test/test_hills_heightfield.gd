extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")


func test_lawn_grid_is_the_village_field() -> void:
	## ivy-82zn.14.14 contract change (AR-LF-D3): inside the lawn the hills no longer pin to the lawn
	## datum; HillsHeightfield.sample_y IS VillageTerrain.sample_y for generated variant 0.
	const VillageTerrain = preload("res://src/playground/village_terrain.gd")
	const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
	var layout := VillageLayout.generate(7)
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var vp := VillageTerrainParams.production()
	var g := layout.hamlet_centre_xz
	for ix in range(9):
		for iz in range(9):
			var r := layout.lawn_radius * float(ix) / 8.0 * 0.98
			var a := float(iz) / 8.0 * TAU
			var p := g + Vector2(sin(a) * r, cos(a) * r)
			assert_eq(HillsHeightfield.sample_y(p, layout, params, t_seed),
				VillageTerrain.sample_y(p, layout, vp, 0), "delegation at %s" % p)


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
