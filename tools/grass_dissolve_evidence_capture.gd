## Evidence PNGs for per-blade camera dissolve (ivy-k9r0).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/grass_density_60"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)
	await _capture_mode(outdir, GameModes.GENERATED, 1, "generated")
	await _capture_mode(outdir, GameModes.CLASSIC, 0, "classic")
	get_tree().quit(0)


func _capture_mode(outdir: String, mode_id: String, seed: int, label: String) -> void:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(30):
		await get_tree().process_frame
	main.call("apply_village_mode_live", mode_id, seed)
	for _i in range(18):
		await get_tree().process_frame
	var world: Node3D = main.get_node("World")
	var pivot: Vector3 = world.get_orbit_pivot()
	var g := Vector2(pivot.x, pivot.z)
	var r := VillageLayout.GENERATED_LAWN_RADIUS if label == "generated" else 19.0
	var cam := Camera3D.new()
	world.add_child(cam)
	var shots := [
		{
			"name": "dissolve_%s_high" % label,
			"eye": Vector3(pivot.x, 14.0, pivot.z + 26.0),
			"look": Vector3(pivot.x, minf(pivot.y, 14.0), pivot.z),
			"use_look_at_from_position": true,
		},
		{
			"name": "dissolve_%s_band_oblique" % label,
			"eye": Vector3(g.x + 4.0, 8.0, g.y + 22.0),
			"look": Vector3(g.x + 12.0, 0.2, g.y + 38.0),
		},
		{
			"name": "dissolve_%s_topdown_cam" % label,
			"eye": Vector3(pivot.x + 0.05, 55.0, pivot.z + 8.0),
			"look": Vector3(pivot.x, 0.0, pivot.z + 14.0),
		},
		{
			"name": "dissolve_%s_band_close" % label,
			"eye": Vector3(g.x + 2.0, 2.4, g.y + 24.0),
			"look": Vector3(g.x + 14.0, 0.3, g.y + 32.0),
		},
		{
			"name": "dissolve_%s_edge_treeline" % label,
			"eye": Vector3(g.x, 6.0, g.y + 48.0),
			"look": Vector3(g.x, 0.0, g.y + r),
		},
	]
	for s in shots:
		if s.has("use_look_at_from_position"):
			cam.look_at_from_position(s["eye"], s["look"])
		else:
			cam.global_transform = Transform3D(Basis.looking_at(s["look"] - s["eye"], Vector3.UP), s["eye"])
		cam.make_current()
		for _f in range(12):
			await get_tree().process_frame
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		var path := outdir.path_join("%s.png" % s["name"])
		get_viewport().get_texture().get_image().save_png(path)
		print("[dissolve-capture] ", path)
	main.queue_free()
	for _f in range(2):
		await get_tree().process_frame
