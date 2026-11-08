## Sweep grass_camera dissolve_end and measure FPS (ivy-k9r0 per-blade dissolve).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const _DISSOLVE_ENDS := [24.0, 26.0, 28.0, 30.0, 32.0, 35.0, 40.0, 1.0e6]
const _WARMUP := 45
const _SAMPLES := 90


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[dissolve-fps] requires non-headless")
		get_tree().quit(1)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/grass_density_60"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)

	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(35):
		await get_tree().process_frame
	main.call("apply_village_mode_live", "generated_village", 1)
	for _i in range(20):
		await get_tree().process_frame

	var world: Node3D = main.get_node("World")
	var pivot: Vector3 = world.get_orbit_pivot()
	var g := Vector2(pivot.x, pivot.z)
	var r_edge := VillageLayout.GENERATED_LAWN_RADIUS
	var cam := Camera3D.new()
	world.add_child(cam)
	var shots := _camera_defs(g, pivot, r_edge)
	print("[dissolve-fps] cameras=", shots.size())
	for d1 in _DISSOLVE_ENDS:
		_apply_dissolve(world, d1)
		await get_tree().process_frame
		var label := "off" if d1 > 1.0e5 else "%.0f" % d1
		var row := "[dissolve-fps] d1=%s" % label
		for shot in shots:
			cam.global_transform = _shot_transform(shot)
			cam.make_current()
			var fps := await _measure_fps()
			row += " %s=%.1f" % [shot["label"], fps]
			if shot["label"] == "high" and (label == "off" or label == "30"):
				var tag := "dissolve_nocull" if label == "off" else "dissolve_d1_30"
				await _capture(outdir.path_join("horizon_%s_high.png" % tag))
		print(row)

	get_tree().quit(0)


func _apply_dissolve(root: Node, dissolve_end: float) -> void:
	var classic := dissolve_end > 1.0e5
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		if not n.name.begins_with("Scatter_Grass_Blades_"):
			continue
		var mmi := n as MultiMeshInstance3D
		var mat := mmi.material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("dissolve_start", VillageScatterPositions.GRASS_CAMERA_DISSOLVE_START_M)
			mat.set_shader_parameter(
				"dissolve_end",
				VillageScatterPositions.GRASS_CAMERA_DISSOLVE_END_CLASSIC_M if classic \
						else dissolve_end)
		mmi.visibility_range_end = 0.0
		mmi.visibility_range_end_margin = 0.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _camera_defs(g: Vector2, pivot: Vector3, r_edge: float) -> Array:
	return [
		{
			"label": "high",
			"eye": Vector3(pivot.x, 14.0, pivot.z + 26.0),
			"look": Vector3(pivot.x, pivot.y, pivot.z),
		},
		{
			"label": "centre_across",
			"eye": Vector3(g.x - 2.0, 2.5, g.y - 4.0),
			"look": Vector3(g.x, 1.0, g.y + 30.0),
		},
		{
			"label": "edge_outward",
			"eye": Vector3(g.x, 2.5, g.y + r_edge - 4.0),
			"look": Vector3(g.x, 1.0, g.y + r_edge + 6.0),
		},
		{
			"label": "edge_oblique",
			"eye": Vector3(g.x + 18.0, 22.0, g.y + r_edge - 8.0),
			"look": Vector3(g.x, 0.0, g.y + r_edge),
		},
	]


func _shot_transform(shot: Dictionary) -> Transform3D:
	return Transform3D(Basis.looking_at(shot["look"] - shot["eye"], Vector3.UP), shot["eye"])


func _measure_fps() -> float:
	for _i in range(_WARMUP):
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		await get_tree().process_frame
	var total := 0.0
	for _i in range(_SAMPLES):
		var t0 := Time.get_ticks_usec()
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		await get_tree().process_frame
		total += float(Time.get_ticks_usec() - t0) / 1000.0
	return 1000.0 / (total / float(_SAMPLES))


func _capture(path: String) -> void:
	for _f in range(5):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(path)
	print("[dissolve-fps] saved ", path)
