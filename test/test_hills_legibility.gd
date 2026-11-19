extends GutTest
## AR-NOFOG (ivy-82zn.14.32) contract change: the far-ridge-vs-horizon luminance test and the
## mid-vs-far ordering went with the far-ridge cap (the far layers no longer wash toward the sky).
## The near-darker-and-greener-than-mid layer ordering stays.

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsTint = preload("res://src/playground/hills_tint.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")

## Probe radii between ridge centres 155/190/225/260 (rework5).
const _LAYER_R: Array[float] = [165.0, 207.0, 242.0]


func test_near_layer_darker_and_greener_than_mid() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var lums: PackedFloat32Array = []
	var greens: PackedFloat32Array = []
	for r in _LAYER_R:
		var p := Vector3(layout.hamlet_centre_xz.x, 12.0, layout.hamlet_centre_xz.y + r)
		var c := HillsTint.terrain_albedo(p, layout, params, 0.65, r, 12.0, 14.0)
		lums.append(HillsTint.luminance(c))
		greens.append(c.g)
	assert_lt(lums[0], lums[1], "L0 darker than L1 lum %.3f vs %.3f" % [lums[0], lums[1]])
	assert_gt(greens[0] / maxf(lums[0], 0.01), greens[1] / maxf(lums[1], 0.01) + 0.05,
		"L0 greener than L1")
	assert_lte(lums[1], lums[2] + 1e-6, "far layer not darker than mid")


func test_tree_instance_tint_green_multiplier() -> void:
	var layout := VillageLayout.generate(7)
	var params := HillsParams.production()
	var g := layout.hamlet_centre_xz
	var tree := HillsTint.tree_instance_color(Vector3(g.x, 8.0, g.y + 172.0), params, layout)
	assert_gt(HillsTint.luminance(tree), 0.2)
	assert_gt(tree.g, tree.r + 0.08)
