## Top-down + grazing falloff band pattern capture (ivy-k9r0 smooth diagnose).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"


func _ready() -> void:
	var outdir := "/Users/andrewhay/github/ivy/.tmp/grass_density_60"
	var tag := "before_smooth"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
		if arg.begins_with("--tag="):
			tag = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return

	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(30):
		await get_tree().process_frame
	main.call("apply_village_mode_live", "generated_village", 1)
	for _i in range(18):
		await get_tree().process_frame
	var world: Node3D = main.get_node("World")
	_disable_grass_visibility_cull(main)
	var pivot: Vector3 = world.get_orbit_pivot()
	var g := Vector2(pivot.x, pivot.z)
	var cam := Camera3D.new()
	world.add_child(cam)

	var shots := [
		{
			"name": "smooth_%s_topdown_falloff" % tag,
			"eye": Vector3(g.x + 0.05, 95.0, g.y),
			"look": Vector3(g.x, 0.0, g.y),
		},
		{
			"name": "smooth_%s_graze_falloff" % tag,
			"eye": Vector3(g.x, 6.0, g.y + 48.0),
			"look": Vector3(g.x, 0.0, g.y + 56.0),
		},
		{
			"name": "smooth_%s_high_lawn" % tag,
			"eye": Vector3(pivot.x, 14.0, pivot.z + 26.0),
			"look": Vector3(pivot.x, pivot.y, pivot.z),
		},
	]
	for s in shots:
		cam.global_transform = Transform3D(Basis.looking_at(s["look"] - s["eye"], Vector3.UP), s["eye"])
		cam.make_current()
		for _f in range(12):
			await get_tree().process_frame
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		var path := outdir.path_join("%s.png" % s["name"])
		get_viewport().get_texture().get_image().save_png(path)
		print("[smooth-capture] ", path)

	get_tree().quit(0)


func _disable_grass_visibility_cull(root: Node) -> void:
	var boosted := 0
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.instance_count < 8:
			continue
		mmi.visibility_range_begin = 0.0
		mmi.visibility_range_end = 0.0
		mmi.visibility_range_end_margin = 0.0
		boosted += 1
	print("[smooth-capture] visibility boost multimeshes=", boosted)
