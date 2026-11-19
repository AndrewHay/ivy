extends GutTest

const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")

## Re-baselined ivy-89a6: production forest is CamSun lawn backdrop (variant 0), not +Z wedge.
## Re-baselined ivy-82zn.14.35 (human 2026-11-19): the forest algorithm is unchanged, its generated
## layout inputs moved - 937233b (WP2 fit-the-village: cottage/path/pond positions) and d17685e (WP3:
## 16 m spacing, longer paths, lawn 64 m, pines 56-76 m, BACKDROP_COTTAGE_CLEAR_M 0.45 -> 2.0).
const _PARITY_SEEDS: Array[int] = [1, 7, 12, 240424020]
const _BASELINE_HASHES: Dictionary = {
	1: "28|1f7c33f64b664ab80d5a15dd917c03b99c0d081e28314464d3bd229efe5311ca",
	7: "33|edc9b7dc98208210240d019248840ba04ee1e104579f4bfcd0265fda9f291642",
	12: "26|c8747449b65b8b724d5563d8e77f3d9ab346c31e165558b2f7d2245ba87b22f6",
	240424020: "27|80cc3ca2ae2893362684975456eff41ab13c3cc7dd6579f6398b6069c2677df7",
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
