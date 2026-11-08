extends SceneTree

func _initialize() -> void:
	_print_mode("classic", _classic())
	_print_mode("generated", _generated())
	quit(0)


func _print_mode(label: String, ctx: VillageGrassExclusionContext) -> void:
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var centre := ctx.grid_centre_xz if ctx.generated_grass else Vector2.ZERO
	var r_edge := VillageScatterPositions.grass_radial_edge_m(ctx)
	var r_flat := VillageScatterPositions.grass_radial_flat_m(r_edge)
	var p_core := VillageScatterPositions.find_open_grass_patch_centre(
		ctx, centre, r_flat * 0.55 if ctx.generated_grass else 9.5, 11)
	var p_mid := VillageScatterPositions.find_open_grass_patch_centre(
		ctx, centre, r_flat + (r_edge - r_flat) * 0.5, 22)
	var p_edge := VillageScatterPositions.find_open_grass_patch_centre(
		ctx, centre, r_edge - 0.9, 33)
	for tag in ["core", "mid", "edge"]:
		var p: Vector2
		var target: float
		match tag:
			"core":
				p = p_core
				target = VillageScatterPositions.GRASS_DENSITY_CORE_PER_M2
			"mid":
				p = p_mid
				target = VillageScatterPositions.grass_target_density_m2(p.distance_to(centre), r_edge)
			"edge":
				p = p_edge
				target = VillageScatterPositions.grass_target_density_m2(p.distance_to(centre), r_edge)
		if is_inf(p.x):
			print("[patch-table] %s %s UNFOUND" % [label, tag])
			continue
		var d := VillageScatterPositions.measure_patch_density_m2(grass, p)
		print(
			"[patch-table] %s %s r=%.1f meas=%.1f target=%.1f err=%.0f%%"
			% [label, tag, p.distance_to(centre), d, target, 100.0 * (d - target) / target])
	

func _classic() -> VillageGrassExclusionContext:
	var path_stones := VillageScatterPositions.path_stone_transforms(
		VillageBackdrop.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).length() < 4.5 \
				or VillageBackdrop.inside_any_cottage(Vector2(cx, cz), 0.2))
	var bushes := VillageScatterPositions.bush_common_positions()
	return VillageGrassExclusionContext.for_village(path_stones, bushes)


func _generated() -> VillageGrassExclusionContext:
	var layout := VillageLayout.generate(1)
	if layout.fallback:
		push_error("fallback")
		return null
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
	return VillageGrassExclusionContext.for_layout(
		layout.paths,
		func(p: Vector2) -> bool: return layout.inside_any_cottage(p, VillageScatterPositions.COTTAGE_MARGIN),
		path_stones, bushes, layout.hamlet_centre_xz, VillageLayout.HERO_DOOR_STOOP, true,
		layout.cottages)
