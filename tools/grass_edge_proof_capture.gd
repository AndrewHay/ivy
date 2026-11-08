## Proof shots at lawn edge: grass 40->15 meeting treeline (ivy-k9r0).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")


func _ready() -> void:
	var outdir := "/Users/andrewhay/github/ivy/.tmp/grass_density_60"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	await _capture_mode(outdir, GameModes.CLASSIC, 0, "classic")
	await _capture_mode(outdir, GameModes.GENERATED, 1, "generated")
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
	var cam := Camera3D.new()
	world.add_child(cam)
	var shots := _shots_for(label, world)
	for shot in shots:
		cam.global_transform = _xform(shot["eye"], shot["look"])
		cam.make_current()
		for _f in range(10):
			await get_tree().process_frame
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		var path := outdir.path_join("proof_%s_%s.png" % [label, shot["name"]])
		get_viewport().get_texture().get_image().save_png(path)
		print("[edge-proof] ", path)
	main.queue_free()
	for _f in range(2):
		await get_tree().process_frame


func _shots_for(label: String, world: Node3D) -> Array:
	if label == "classic":
		return [
			{
				"name": "edge_eye_out",
				"eye": Vector3(8.5, 2.6, 11.0),
				"look": Vector3(16.5, 0.6, 18.8),
			},
			{
				"name": "edge_oblique",
				"eye": Vector3(-4.0, 11.0, 9.0),
				"look": Vector3(14.0, 0.0, 18.5),
			},
		]
	var pivot: Vector3 = world.get_orbit_pivot()
	var g := Vector2(pivot.x, pivot.z)
	var r := VillageLayout.GENERATED_LAWN_RADIUS
	return [
		{
			"name": "edge_eye_out",
			"eye": Vector3(g.x + 6.0, 2.6, g.y + r - 4.5),
			"look": Vector3(g.x + 2.0, 0.7, g.y + r + 5.0),
		},
		{
			"name": "edge_oblique",
			"eye": Vector3(g.x - 12.0, 18.0, g.y + r - 12.0),
			"look": Vector3(g.x, 0.2, g.y + r),
		},
	]


func _xform(eye: Vector3, look: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
