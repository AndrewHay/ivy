extends SceneTree

func _initialize() -> void:
	var layout := VillageLayout.generate(1)
	if layout.fallback:
		push_error("layout fallback")
		quit(1)
		return
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var path_stones := VillageScatterPositions.path_stone_transforms(
		layout.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).distance_to(VillageLayout.HERO_DOOR_STOOP) < 4.5 \
				or layout.inside_any_cottage(Vector2(cx, cz), 0.2),
		layout.stone_seed, layout.min_stone_spacing)
	var bushes := VillageScatterPositions.bush_common_positions(
		layout.cottages, layout.bush_filler_inner, layout.bush_filler_outer,
		layout.hamlet_centre_xz)
	var ctx := VillageGrassExclusionContext.for_layout(
		layout.paths,
		func(p: Vector2) -> bool: return layout.inside_any_cottage(p, VillageScatterPositions.COTTAGE_MARGIN),
		path_stones, bushes, layout.hamlet_centre_xz, VillageLayout.HERO_DOOR_STOOP, true,
		layout.cottages)
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var g := ctx.grid_centre_xz
	for r in [42.0, 46.0, 50.0]:
		var cv := VillageScatterPositions.measure_patch_density_cv(grass, g, r)
		var target := VillageScatterPositions.grass_target_density_m2(r, VillageScatterPositions.GRASS_RADIAL_EDGE_GENERATED_M)
		print("[patch-cv] r=%.0f target=%.1f cv=%.3f" % [r, target, cv])
	quit(0)
