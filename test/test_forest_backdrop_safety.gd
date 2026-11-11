## ivy-89a6: production forest backdrop must not violate scatter safety (seeds 1..30 + fallback).
extends GutTest

const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")
const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")

const _PATH_CLEAR_M := 0.55
const _COTTAGE_GROW_M := 0.45


static func _path_clearance_ok(p: Vector2, layout: VillageLayout) -> bool:
	var segs: Array = layout.path_polylines()
	var d: float = VillageScatterPositions.min_xz_dist_to_path_segments(p, segs)
	return d >= _PATH_CLEAR_M


static func _violations_for_layout(layout: VillageLayout) -> PackedStringArray:
	var issues: PackedStringArray = []
	if not layout.is_generated:
		return issues
	var params := ForestParams.production()
	var trees := ForestPlacement.forest_tree_xz(layout, params)
	var g := layout.hamlet_centre_xz
	for i in trees.size():
		var p: Vector2 = trees[i]
		if VillageLayout.inside_cottages(layout.cottages, p, _COTTAGE_GROW_M):
			issues.append("seed cottage@%d (%s)" % [i, p])
		if VillageScatterPositions.blocks_scatter_at(p):
			issues.append("pond/block@%d (%s)" % [i, p])
		if not _path_clearance_ok(p, layout):
			issues.append("path@%d (%s)" % [i, p])
		if ForestPlacement.forest_blocks_camsun_view(p, params):
			issues.append("camsun_corridor@%d (%s)" % [i, p])
		if p.distance_to(VillageLayout.HERO_DOOR_STOOP) < params.backdrop_min_hero_dist_m:
			issues.append("hero@%d (%s)" % [i, p])
		if p.distance_to(g) > layout.lawn_radius + 0.01:
			issues.append("outside_lawn@%d dist=%.2f" % [i, p.distance_to(g)])
	return issues


func test_production_forest_safe_seeds_1_through_30() -> void:
	var total_issues := 0
	for seed in range(1, 31):
		var layout := VillageLayout.generate(seed)
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var issues := _violations_for_layout(layout)
		total_issues += issues.size()
		assert_eq(issues.size(), 0,
			"seed %d: %d violations — %s" % [seed, issues.size(), ", ".join(issues).substr(0, 200)])
	assert_lte(total_issues, 0)


func test_authored_layout_forest_ring_nonempty() -> void:
	var layout := VillageLayout.authored()
	assert_false(layout.is_generated)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var trees := ForestPlacement.forest_tree_positions(layout, ForestParams.production())
	assert_gte(trees.size(), 1, "authored classic ring places trees")

