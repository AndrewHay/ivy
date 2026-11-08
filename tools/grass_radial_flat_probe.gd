extends SceneTree

func _initialize() -> void:
	var layout := VillageLayout.generate(1)
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
	var r_edge := VillageScatterPositions.grass_radial_edge_m(ctx)
	var r_flat := VillageScatterPositions.grass_radial_flat_m(r_edge)
	print("[flat-probe] r_flat=%.2f" % r_flat)
	for r0 in range(int((r_flat - 3.0) * 2), int((r_flat + 4.0) * 2)):
		var a := float(r0) * 0.5
		var b := a + 0.5
		var d := _annulus_density(grass, g, a, b)
		var t := VillageScatterPositions.grass_target_density_m2((a + b) * 0.5, r_edge)
		print("[flat-probe] [%.1f,%.1f) meas=%.1f target=%.1f delta=%.1f%%" % [a, b, d, t, 100.0 * (d - t) / t if t > 0 else 0.0])
	quit(0)


func _annulus_density(grass: Array, centre: Vector2, r0: float, r1: float) -> float:
	var n := 0
	for t in grass:
		var r := Vector2(t.origin.x, t.origin.z).distance_to(centre)
		if r >= r0 and r < r1:
			n += 1
	var area := PI * (r1 * r1 - r0 * r0)
	return float(n) / area if area > 0.0 else 0.0
