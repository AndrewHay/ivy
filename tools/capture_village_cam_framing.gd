## CamTop framing for ivy-0ka QA — classic vs generated (seed 1).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")


func _ready() -> void:
	var outdir := "/Users/andrewhay/github/ivy/.tmp/village_gen/ivy-0ka"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)

	for mode_pair in [[GameModes.CLASSIC, 0, "classic"], [GameModes.GENERATED, 1, "generated"]]:
		await _capture_mode(outdir, mode_pair[0], int(mode_pair[1]), String(mode_pair[2]))

	print("[ivy-0ka-capture] done → ", outdir)
	get_tree().quit(0)


func _capture_mode(outdir: String, mode_id: String, seed: int, label: String) -> void:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(35):
		await get_tree().process_frame
	if main.has_method("apply_village_mode_live"):
		main.call("apply_village_mode_live", mode_id, seed)
	for _i in range(12):
		await get_tree().process_frame

	var world: Node3D = main.get_node("World")
	var rig: Node3D = world.get_node("CameraRig") as Node3D
	var cam_top: Camera3D = rig.get_node("CamTop") as Camera3D
	for c in rig.get_children():
		if c is Camera3D:
			(c as Camera3D).current = (c == cam_top)
	for _f in range(8):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)

	var path := outdir.path_join("camtop_%s.png" % label)
	get_viewport().get_texture().get_image().save_png(path)
	print("[ivy-0ka-capture] ", path, " rig_scale=", rig.scale.x)
	main.queue_free()
	for _f in range(3):
		await get_tree().process_frame
