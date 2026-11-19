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
	## ivy-82zn.14.18 (WP3): GENERATED_HILL_INNER retired; generated readers use lawn_radius (64).
	var inner := layout.lawn_radius
	var mid := g + Vector2(0.0, (inner + 140.0) * 0.5)
	var y := HillsHeightfield.sample_y(mid, layout, params, t)
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	assert_gt(y, y_lawn + 2.0)


func test_generated_radii_wp3() -> void:
	## WP3 radii pins (SD-VILLAGE-TERRAIN-21): lawn 64; the flat-legacy ramp (variant 1) starts outside
	## the lawn (lawn_radius + 2, was the literal 58 = 56 + 2), so the flat A/B lawn is never overlapped.
	var layout := VillageLayout.generate(7)
	assert_almost_eq(layout.lawn_radius, 64.0, 1e-6, "lawn 64")
	var params := HillsParams.production()
	params.variant = 1
	var t := HillsHeightfield.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	for r in [10.0, 40.0, 63.9, 65.9]:
		assert_almost_eq(HillsHeightfield.sample_y(g + Vector2(r, 0.0), layout, params, t), y_lawn, 1e-6,
			"flat legacy at r %.1f is the lawn datum" % r)
	assert_gt(HillsHeightfield.sample_y(g + Vector2(70.0, 0.0), layout, params, t), y_lawn,
		"ramp rises outside lawn_radius + 2")
