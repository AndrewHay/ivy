## Headless timing probe for the village terrain playground rebuild path (ivy-82zn.14.7).
## Times, on one seed with production params: knoll/pad cache warm-up, mesh LUT at the mesh
## step, the coarse preview LUT, the 1 m grass LUT, the old grid-sampled HUD stats, and
## grass blade placement.
##
##   Godot --headless --script res://tools/probe_vt_playground_timing.gd -- [--seed=7]
extends SceneTree

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")


func _init() -> void:
	var seed := 7
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
	var params := VillageTerrainParams.production()
	params.layout_seed = seed
	var layout := VillageLayout.generate(seed)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var t_seed := VillageTerrain.terrain_seed(layout, params)

	VillageTerrain.clear_knoll_centres_cache()
	var t0 := Time.get_ticks_usec()
	VillageTerrain.sample_y(VillageLayout.HERO_DOOR_STOOP, layout, params, t_seed)
	var t_first := Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	for i in range(200):
		VillageTerrain.sample_y(
			layout.hamlet_centre_xz + Vector2(float(i % 20) * 2.0 - 20.0, float(i / 20) * 2.0 - 10.0),
			layout, params, t_seed)
	var t_per := float(Time.get_ticks_usec() - t0) / 200.0

	t0 = Time.get_ticks_usec()
	VillageTerrain.build_mesh(layout, params)
	var t_mesh := Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	VillageTerrain.build_sample_lut(layout, params, t_seed, 6.0)
	var t_coarse := Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	var step := maxf(params.terrain_mesh_step_m * 2.0, 2.0)
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	var x := g.x - r
	var n := 0
	while x <= g.x + r:
		var z := g.y - r
		while z <= g.y + r:
			var xz := Vector2(x, z)
			if xz.distance_to(g) < r:
				VillageTerrain.sample_y(xz, layout, params, t_seed)
				VillageTerrain.sample_slope_deg(xz, layout, params, t_seed)
				n += 1
			z += step
		x += step
	var t_stats := Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	var lut1 := VillageTerrain.build_sample_lut(layout, params, t_seed, 1.0)
	var t_lut1 := Time.get_ticks_usec() - t0
	var lut2 := VillageTerrain.build_sample_lut(
		layout, params, t_seed, maxf(params.terrain_mesh_step_m, 0.1))
	var lut6 := VillageTerrain.build_sample_lut(layout, params, t_seed, 6.0)
	print("[vt-timing] lut_hash step=%d coarse6=%d lut1=%d" % [
		hash(lut2["data"]), hash(lut6["data"]), hash(lut1["data"])])

	# Path spine build: first sample on a path after a cache clear.
	VillageTerrain.clear_knoll_centres_cache()
	VillageTerrain.sample_y(VillageLayout.HERO_DOOR_STOOP, layout, params, t_seed)
	var path0: Array = layout.path_polylines()[0]
	var on_path: Vector2 = (path0[0] as Vector2).lerp(path0[1] as Vector2, 0.5)
	t0 = Time.get_ticks_usec()
	VillageTerrain.sample_y(on_path, layout, params, t_seed)
	var t_spine := Time.get_ticks_usec() - t0
	print("[vt-timing] first_path_sample_ms(spine build)=%.1f" % (t_spine / 1000.0))

	# Grass blade placement (production VillageScatterPositions, same ctx as VillageBackdrop).
	t0 = Time.get_ticks_usec()
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
		func(p: Vector2) -> bool:
			return layout.inside_any_cottage(p, VillageScatterPositions.COTTAGE_MARGIN),
		path_stones, bushes, layout.hamlet_centre_xz, VillageLayout.HERO_DOOR_STOOP, true,
		layout.cottages)
	var t_ctx := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var blades := VillageScatterPositions.grass_blade_positions(ctx)
	var t_blades := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var accents := VillageScatterPositions.grass_wispy_accent_positions(ctx)
	var t_acc := Time.get_ticks_usec() - t0
	print("[vt-timing] grass ctx_ms=%.1f blades_ms=%.1f (n=%d) accents_ms=%.1f (n=%d)" % [
		t_ctx / 1000.0, t_blades / 1000.0, blades.size(), t_acc / 1000.0, accents.size()])

	print("[vt-timing] seed=%d first_sample_ms=%.1f per_sample_ms=%.3f" % [
		seed, t_first / 1000.0, t_per / 1000.0])
	print("[vt-timing] mesh_ms=%.1f coarse6_lut_ms=%.1f old_stats_ms=%.1f (points=%d) lut1_ms=%.1f" % [
		t_mesh / 1000.0, t_coarse / 1000.0, t_stats / 1000.0, n, t_lut1 / 1000.0])
	quit(0)
