## Tests for hills rework 4: north-only wedge constraint and colour seam parity.
## Spec: hills only in north (−Z direction), east/west flat, smooth falloff.
## North = phi=PI in placement coords (atan2(dx,dz) where +Z=south).
extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const HillsFogTint = preload("res://src/playground/hills_fog_tint.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")
const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")

## Epsilon for "flat ground" checks: hill terrain ≤ lawn + this.
const FLAT_EPS := 0.25

## Radii to probe for east/west flatness (span the full hill annulus rework5: 100-310m).
const FLAT_PROBE_RADII: Array[float] = [115.0, 155.0, 190.0, 225.0, 260.0, 295.0]

## North direction in placement coords: phi=PI → Vector2(0, -1) world−Z.
const NORTH_DIR := Vector2(0.0, -1.0)
## East direction: phi=PI/2 → Vector2(1, 0) world +X.
const EAST_DIR := Vector2(1.0, 0.0)
## West direction: phi=−PI/2 → Vector2(−1, 0) world −X.
const WEST_DIR := Vector2(-1.0, 0.0)

## Colour tolerance for seam match (L1 distance between RGB values).
## rework5: _L0_GREEN=(0.22,0.38,0.17), diff vs u_meadow_near target ≈ 0.034.
const COLOUR_SEAM_TOL := 0.12


func test_east_horizon_is_flat_production() -> void:
	## East direction (sunrise horizon) must be flat — no hills blocking sunrise.
	for seed in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var params := HillsParams.production()
		var t_seed := HillsHeightfield.terrain_seed(layout, params)
		var g := layout.hamlet_centre_xz
		var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
		for r in FLAT_PROBE_RADII:
			var p := g + EAST_DIR * r
			var y := HillsHeightfield.sample_y(p, layout, params, t_seed)
			assert_lte(y, y_lawn + FLAT_EPS,
				"seed %d east r=%.0f y=%.3f must be flat" % [seed, r, y])


func test_west_horizon_is_flat_production() -> void:
	## West direction (sunset horizon) must be flat — no hills blocking sunset.
	for seed in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var params := HillsParams.production()
		var t_seed := HillsHeightfield.terrain_seed(layout, params)
		var g := layout.hamlet_centre_xz
		var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
		for r in FLAT_PROBE_RADII:
			var p := g + WEST_DIR * r
			var y := HillsHeightfield.sample_y(p, layout, params, t_seed)
			assert_lte(y, y_lawn + FLAT_EPS,
				"seed %d west r=%.0f y=%.3f must be flat" % [seed, r, y])


func test_north_has_height_production() -> void:
	## North (−Z) must have elevated ground in the hill zone.
	for seed in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var params := HillsParams.production()
		var t_seed := HillsHeightfield.terrain_seed(layout, params)
		var g := layout.hamlet_centre_xz
		var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
		var max_lift := 0.0
		for r_i in [80, 90, 97, 110, 117]:
			var p := g + NORTH_DIR * float(r_i)
			var y := HillsHeightfield.sample_y(p, layout, params, t_seed)
			max_lift = maxf(max_lift, y - y_lawn)
		assert_gt(max_lift, 5.0,
			"seed %d north must have > 5 m lift (got %.2f m)" % [seed, max_lift])


func test_no_forest_trees_outside_north_wedge() -> void:
	## No hill tree should be placed strictly outside the azimuth wedge (az_weight = 0).
	## Trees in the smooth fade zone (0 < w < 1) are by design (reduced probability).
	## The hard constraint is: no tree where the wedge weight is exactly 0
	## (i.e., >azimuth_half_width_deg from the centre direction).
	for seed in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var params := HillsParams.production()
		var t_seed := HillsHeightfield.terrain_seed(layout, params)
		var backdrop := VillageScatterPositions.forest_tree_xz(layout)
		var xforms := HillsForestPlacement.hill_forest_transforms(
			layout, params, t_seed, backdrop)
		var g := layout.hamlet_centre_xz
		var far_outside := 0
		for t: Transform3D in xforms:
			var p := Vector2(t.origin.x, t.origin.z)
			var w := HillsHeightfield.azimuth_weight(p, g, params)
			# Strictly outside (w == 0) means the tree is beyond the wedge edge; that's a bug.
			# Trees in fade zone (0 < w < 1) are allowed but rare.
			if w <= 0.001:
				far_outside += 1
		assert_eq(far_outside, 0,
			"seed %d has %d tree(s) strictly outside north wedge" % [seed, far_outside])


func test_colour_seam_matches_lawn_at_toe() -> void:
	## At the seam (r = lawn_radius + 2 m, just outside the grass disc) the
	## CPU terrain_albedo must blend almost entirely to _LAWN_COLOUR via the
	## meadow_ring calibration added in rework6.
	## This tests the HillsFogTint GDScript path, not the shader directly.
	var lawn_base := Color(0.270, 0.350, 0.210)  # _LAWN_COLOUR rework6 calibration
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var g := layout.hamlet_centre_xz
	## Probe at r = lawn_radius + 2 m: meadow_ring ≈ 0.96 → ~96% blend toward lawn colour.
	var seam_r := layout.lawn_radius + 2.0
	var p := g + NORTH_DIR * seam_r
	var p3 := Vector3(p.x, VillageBackdrop.LAWN_GROUND_Y_OFFSET, p.y)
	var c := HillsFogTint.terrain_albedo(p3, layout, params, 0.65, seam_r, 0.0, 0.0)
	## L1 colour difference: abs(r-r0) + abs(g-g0) + abs(b-b0)
	var diff := absf(c.r - lawn_base.r) + absf(c.g - lawn_base.g) + absf(c.b - lawn_base.b)
	assert_lt(diff, COLOUR_SEAM_TOL,
		"seam colour c=(%.3f,%.3f,%.3f) vs lawn=(%.3f,%.3f,%.3f) diff=%.3f"
		% [c.r, c.g, c.b, lawn_base.r, lawn_base.g, lawn_base.b, diff])


func test_azimuth_weight_north_is_one() -> void:
	## azimuth_weight at exactly north should be 1.0.
	var params := HillsParams.production()
	var g := Vector2(0.0, 0.0)
	var north_pt := g + NORTH_DIR * 100.0  # Vector2(0, -100)
	var w := HillsHeightfield.azimuth_weight(north_pt, g, params)
	assert_almost_eq(w, 1.0, 0.001, "north azimuth weight must be 1.0")


func test_azimuth_weight_east_is_zero() -> void:
	## azimuth_weight at due east (90° from north) must be 0 (outside ±55° wedge).
	var params := HillsParams.production()
	var g := Vector2(0.0, 0.0)
	var east_pt := g + EAST_DIR * 100.0  # Vector2(100, 0)
	var w := HillsHeightfield.azimuth_weight(east_pt, g, params)
	assert_almost_eq(w, 0.0, 0.001, "east azimuth weight must be 0 (outside wedge)")


func test_azimuth_weight_west_is_zero() -> void:
	## azimuth_weight at due west (90° from north) must be 0 (outside ±55° wedge).
	var params := HillsParams.production()
	var g := Vector2(0.0, 0.0)
	var west_pt := g + WEST_DIR * 100.0  # Vector2(-100, 0)
	var w := HillsHeightfield.azimuth_weight(west_pt, g, params)
	assert_almost_eq(w, 0.0, 0.001, "west azimuth weight must be 0 (outside wedge)")


func test_azimuth_weight_smooth_fade() -> void:
	## At the wedge edge (half_width_deg), weight is 0; just inside, > 0.
	var params := HillsParams.production()
	var g := Vector2(0.0, 0.0)
	## half_width_deg=55: at exactly 55° off north → weight = 0.
	## At 54° off north → weight > 0 (in fade zone).
	var hw_rad := deg_to_rad(params.azimuth_half_width_deg)
	# Point at exactly half_width angle: phi = PI - hw_rad (half_width degrees east of north)
	var phi_at_edge := PI - hw_rad
	var pt_at_edge := g + Vector2(sin(phi_at_edge), cos(phi_at_edge)) * 100.0
	var w_edge := HillsHeightfield.azimuth_weight(pt_at_edge, g, params)
	assert_almost_eq(w_edge, 0.0, 0.01, "weight at wedge edge must be 0")
	# Point 2° inside the edge
	var phi_inside := PI - hw_rad + deg_to_rad(2.0)
	var pt_inside := g + Vector2(sin(phi_inside), cos(phi_inside)) * 100.0
	var w_inside := HillsHeightfield.azimuth_weight(pt_inside, g, params)
	assert_gt(w_inside, 0.0, "weight 2° inside edge must be > 0")
