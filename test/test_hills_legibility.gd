extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsFogTint = preload("res://src/playground/hills_fog_tint.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")

## Probe radii between new ridge centres: 80/97/117/134 → sample between ridges.
const _LAYER_R: Array[float] = [165.0, 207.0, 242.0]  # rework5: between ridges 155/190/225/260
const _MIN_GREEN_RATIO_SPREAD := 0.04


func test_layer_albedo_luminance_increases_with_distance() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var lums: PackedFloat32Array = []
	var greens: PackedFloat32Array = []
	for r in _LAYER_R:
		var p := Vector3(layout.hamlet_centre_xz.x, 12.0, layout.hamlet_centre_xz.y + r)
		var c := HillsFogTint.terrain_albedo(
			p, layout, params, 0.65, r, 12.0, 14.0)
		lums.append(HillsFogTint.luminance(c))
		greens.append(c.g)
	assert_lt(lums[0], lums[1], "L0 darker than L1 lum %.3f vs %.3f" % [lums[0], lums[1]])
	assert_lt(lums[1], lums[2], "L1 darker than L2 lum %.3f vs %.3f" % [lums[1], lums[2]])
	assert_gt(greens[0] / maxf(lums[0], 0.01), greens[1] / maxf(lums[1], 0.01) + 0.05)
	assert_gt(greens[1] / maxf(lums[1], 0.01), greens[2] / maxf(lums[2], 0.01) + 0.02)


func test_far_layer_not_lighter_than_horizon() -> void:
	var layout := VillageLayout.generate(7)
	var params := HillsParams.production()
	var g := layout.hamlet_centre_xz
	var hor := HillsFogTint.horizon_reference_color()
	var far := HillsFogTint.terrain_albedo(
		Vector3(g.x, 18.0, g.y + 260.0), layout, params, 0.5, 260.0, 18.0, 10.0)  # rework5: ridge 3
	assert_lte(
		HillsFogTint.luminance(far), HillsFogTint.luminance(hor) * 0.96,
		"far ridge lum %.3f horizon %.3f" % [HillsFogTint.luminance(far), HillsFogTint.luminance(hor)])


func test_eight_bearing_crest_layer_ordering() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var good := 0
	for b in range(8):
		var phi := (float(b) / 8.0) * TAU
		var p2 := g + Vector2(sin(phi), cos(phi)) * 165.0  # rework5: near ridge 0 (155m)
		var y := HillsHeightfield.sample_y(p2, layout, params, t_seed)
		var c0 := HillsFogTint.terrain_albedo(
			Vector3(p2.x, y, p2.y), layout, params, 0.7, 165.0, y - 0.12, 16.0)
		var c2 := HillsFogTint.terrain_albedo(
			Vector3(p2.x, y, p2.y), layout, params, 0.55, 242.0, y - 0.12, 12.0)  # rework5: near ridge 3
		if HillsFogTint.luminance(c0) < HillsFogTint.luminance(c2):
			good += 1
		if (c0.g - c0.r) > (c2.g - c2.r) + _MIN_GREEN_RATIO_SPREAD:
			good += 1
	assert_gte(good, 10, "bearing layer ordering good=%d" % good)


func test_tree_instance_tint_green_multiplier() -> void:
	var layout := VillageLayout.generate(7)
	var params := HillsParams.production()
	var g := layout.hamlet_centre_xz
	var tree := HillsFogTint.tree_instance_color(
		Vector3(g.x, 8.0, g.y + 172.0), params, layout, 0.0, 172.0, Vector3.ZERO)  # rework5: ridge 0 zone
	assert_gt(HillsFogTint.luminance(tree), 0.2)
	assert_gt(tree.g, tree.r + 0.08)
