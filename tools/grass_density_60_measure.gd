## Before/after village grass QA — scatter counts, gen time, FPS, screenshots (ivy-k9r0).
## Output dir name grass_density_60 is legacy; targets 40 core / 15 edge blades/m².
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")

const _CAMERAS: Array = [
	[26.0, 14.0, "high"],
	[12.0, 2.0, "eye"],
]
const _EDGE_LOOK: Dictionary = {
	"classic": [Vector3(6.0, 2.8, 20.0), Vector3(0.0, 0.5, 15.0)],
	"generated": [Vector3(0.0, 6.0, 48.0), Vector3(0.0, 0.0, 56.0)],
}

const _WARMUP_FRAMES := 60
const _FPS_SAMPLES := 120
const _PRESENT_TIMEOUT_MS := 4000
const _COTTAGE_MARGIN := VillageScatterPositions.COTTAGE_MARGIN


func _ready() -> void:
	var outdir := "/Users/andrewhay/github/ivy/.tmp/grass_density_60"
	var phase := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
		if arg.begins_with("--phase="):
			phase = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)

	_print_scatter_metrics("classic", _classic_ctx())
	_print_scatter_metrics("generated", _generated_ctx(1))

	if DisplayServer.get_name() == "headless":
		print("[grass-density-60] headless — skipping screenshots/FPS")
		get_tree().quit(0)
		return

	var w := get_window()
	if w != null and w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()

	await _capture_mode_visuals(outdir, phase, GameModes.CLASSIC, 0, "classic")
	await _capture_mode_visuals(outdir, phase, GameModes.GENERATED, 1, "generated")

	print("[grass-density-60] done → ", outdir)
	get_tree().quit(0)


func _classic_ctx() -> VillageGrassExclusionContext:
	var path_stones := VillageScatterPositions.path_stone_transforms(
		VillageBackdrop.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).length() < 4.5 \
				or VillageBackdrop.inside_any_cottage(Vector2(cx, cz), 0.2))
	var bushes := VillageScatterPositions.bush_common_positions()
	return VillageGrassExclusionContext.for_village(path_stones, bushes)


func _generated_ctx(seed: int) -> VillageGrassExclusionContext:
	var layout := VillageLayout.generate(seed)
	if layout.fallback:
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
		func(p: Vector2) -> bool: return layout.inside_any_cottage(p, _COTTAGE_MARGIN),
		path_stones, bushes, layout.hamlet_centre_xz, VillageLayout.HERO_DOOR_STOOP, true,
		layout.cottages)


func _print_scatter_metrics(label: String, ctx: VillageGrassExclusionContext) -> void:
	if ctx == null:
		printerr("[grass-density-60] ", label, " ctx null")
		return
	var t0 := Time.get_ticks_usec()
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var gen_us := Time.get_ticks_usec() - t0
	var centre := ctx.grid_centre_xz if ctx.generated_grass else Vector2.ZERO
	var max_r := 0.0
	for t in grass:
		max_r = maxf(max_r, Vector2(t.origin.x, t.origin.z).distance_to(centre))
	var r_edge := VillageScatterPositions.grass_radial_edge_m(ctx)
	var r_flat := VillageScatterPositions.grass_radial_flat_m(r_edge)
	print(
		"[grass-density-60] scatter %s count=%d gen_ms=%.2f max_r=%.3f r_edge=%.1f r_flat=%.1f"
		% [label, grass.size(), gen_us / 1000.0, max_r, r_edge, r_flat])
	_print_annulus_table(label, grass, centre, r_edge, r_flat)


func _capture_mode_visuals(
		outdir: String, phase: String, mode_id: String, seed: int, label: String) -> void:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(30):
		await get_tree().process_frame
	main.call("apply_village_mode_live", mode_id, seed)
	for _i in range(15):
		await get_tree().process_frame

	var world: Node3D = main.get_node("World")
	var orbit_cam := Camera3D.new()
	orbit_cam.name = "GrassDensityMeasureCam"
	world.add_child(orbit_cam)
	var pivot: Vector3 = world.get_orbit_pivot()

	for cam_def in _CAMERAS:
		var radius: float = cam_def[0]
		var height: float = cam_def[1]
		var cam_label: String = cam_def[2]
		var eye := Vector3(pivot.x, height, pivot.z + radius)
		orbit_cam.look_at_from_position(eye, Vector3(pivot.x, minf(pivot.y, height), pivot.z))
		orbit_cam.make_current()
		for _f in range(8):
			await get_tree().process_frame
		if not await _present_fresh_frame():
			printerr("[grass-density-60] no frame for %s %s" % [label, cam_label])
			continue
		var path := outdir.path_join("%s_%s_%s.png" % [phase, label, cam_label])
		get_viewport().get_texture().get_image().save_png(path)
		print("[grass-density-60] saved ", path)

	if _EDGE_LOOK.has(label):
		var pair: Array = _EDGE_LOOK[label]
		orbit_cam.look_at_from_position(pair[0], pair[1])
		orbit_cam.make_current()
		for _f in range(8):
			await get_tree().process_frame
		if await _present_fresh_frame():
			var edge_path := outdir.path_join("%s_%s_edge_trees.png" % [phase, label])
			get_viewport().get_texture().get_image().save_png(edge_path)
			print("[grass-density-60] saved ", edge_path)

	var t_boot0 := Time.get_ticks_msec()
	# FPS at high camera
	orbit_cam.look_at_from_position(
		Vector3(pivot.x, 14.0, pivot.z + 26.0),
		Vector3(pivot.x, pivot.y, pivot.z))
	orbit_cam.make_current()
	for _i in range(_WARMUP_FRAMES):
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		await get_tree().process_frame
	var total_ms := 0.0
	for _i in range(_FPS_SAMPLES):
		var t0 := Time.get_ticks_usec()
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		await get_tree().process_frame
		total_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	var mean_ms := total_ms / float(_FPS_SAMPLES)
	var mean_fps := 1000.0 / mean_ms if mean_ms > 0.0 else 0.0
	print("[grass-density-60] fps %s mean=%.1f (high cam, %d samples)" % [label, mean_fps, _FPS_SAMPLES])
	print("[grass-density-60] village_live_ms %s=%d" % [label, t_boot0])

	main.queue_free()
	for _f in range(3):
		await get_tree().process_frame


func _annulus_density(grass: Array, centre: Vector2, r0: float, r1: float) -> float:
	var n := 0
	for t in grass:
		var r := Vector2(t.origin.x, t.origin.z).distance_to(centre)
		if r >= r0 and r < r1:
			n += 1
	var area := PI * (r1 * r1 - r0 * r0)
	if area <= 0.0:
		return 0.0
	return float(n) / area


func _print_annulus_table(label: String, grass: Array, centre: Vector2, r_edge: float, r_flat: float) -> void:
	var bands: Array = []
	bands.append([8.0, minf(10.5, r_flat * 0.9), "core_sample"])
	bands.append([r_flat, r_flat + (r_edge - r_flat) * 0.33, "fall_A"])
	bands.append([r_flat + (r_edge - r_flat) * 0.33, r_flat + (r_edge - r_flat) * 0.66, "fall_B"])
	bands.append([r_edge - 1.0, r_edge - 0.05, "edge"])
	for b in bands:
		var d := _annulus_density(grass, centre, b[0], b[1])
		print("[grass-density-60]   %s %s [%.1f,%.1f) = %.1f/m2" % [label, b[2], b[0], b[1], d])


func _present_fresh_frame() -> bool:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
		return true
	var drawn := [false]
	var on_draw := func() -> void: drawn[0] = true
	RenderingServer.frame_post_draw.connect(on_draw, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + _PRESENT_TIMEOUT_MS
	while not drawn[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if RenderingServer.frame_post_draw.is_connected(on_draw):
		RenderingServer.frame_post_draw.disconnect(on_draw)
	return drawn[0]
