extends GutTest

const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")

## Re-baselined ivy-89a6: production forest is CamSun lawn backdrop (variant 0), not +Z wedge.
const _PARITY_SEEDS: Array[int] = [1, 7, 12, 240424020]
const _BASELINE_HASHES: Dictionary = {
	1: "29|aa79ed4c03b31dfb41a23c83e420ef15875c8d7643469d5cbad45bc17507fd94",
	7: "32|4f644a35e5dff05a58be0f2dc97857fbfd39f76dea64ec4d5633c3f98c1b3fdf",
	12: "29|16dd706feefcb53c3545bff11d3643ef8be9e6f20cb429f6462add8d642dd783",
	240424020: "33|edc9b7dc98208210240d019248840ba04ee1e104579f4bfcd0265fda9f291642",
}


static func _hash_positions(xf: Array) -> String:
	var parts: PackedStringArray = []
	for t in xf:
		var tr := t as Transform3D
		parts.append(
			"%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
				tr.origin.x, tr.origin.y, tr.origin.z,
				tr.basis.get_euler().y, tr.basis.get_scale().x, tr.basis.get_scale().y])
	parts.sort()
	var joined := ",".join(parts)
	return "%d|%s" % [xf.size(), joined.sha256_text()]


func test_forest_production_matches_pre_refactor_baseline() -> void:
	var params := ForestParams.production()
	assert_eq(params.variant, 0, "production variant")
	for seed: int in _PARITY_SEEDS:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			fail_test("unexpected fallback seed %d" % seed)
			return
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var via_api := VillageScatterPositions.forest_tree_positions(layout)
		var via_placement := ForestPlacement.forest_tree_positions(layout, params)
		var h_api := _hash_positions(via_api)
		var h_place := _hash_positions(via_placement)
		assert_eq(h_api, _BASELINE_HASHES[seed], "seed %d API hash" % seed)
		assert_eq(h_place, h_api, "seed %d placement must match API" % seed)
