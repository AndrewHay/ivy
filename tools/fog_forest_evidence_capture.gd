## Main-game before/after fog evidence (ivy-89a6). Forest playground shots use CLI on forest_playground.tscn.
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/vlr/fog_forest"
	var tag := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
		if arg.begins_with("--tag="):
			tag = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)

	for seed in [7, 1]:
		await _capture_seed(outdir, tag, seed)
	get_tree().quit(0)


func _capture_seed(outdir: String, tag: String, seed: int) -> void:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(30):
		await get_tree().process_frame
	main.call("apply_village_mode_live", GameModes.GENERATED, seed)
	for _i in range(24):
		await get_tree().process_frame

	var world: Node3D = main.get_node("World")
	var pivot: Vector3 = world.get_orbit_pivot()
	var hero := Vector2(pivot.x, pivot.z) + VillageLayout.HERO_DOOR_STOOP
	var rig: Node3D = world.get_node("CameraRig") as Node3D
	var cam_sun: Camera3D = rig.get_node("CamSun") as Camera3D
	var extra := Camera3D.new()
	world.add_child(extra)

	var shots: Array = [
		{"name": "%s_game_seed%d_camsun" % [tag, seed], "use_camsun": true},
		{
			"name": "%s_game_seed%d_pullback60" % [tag, seed],
			"use_camsun": false,
			"eye": _pullback_from_hero(hero, pivot.y, 60.0),
			"look": Vector3(hero.x, 1.2, hero.y),
		},
	]
	for s in shots:
		var cam: Camera3D = cam_sun if s["use_camsun"] else extra
		if not s["use_camsun"]:
			var eye: Vector3 = s["eye"]
			if world.has_method("get_village_lawn_camera_bounds"):
				var b: Dictionary = world.get_village_lawn_camera_bounds()
				if not b.is_empty():
					eye = CameraBounds.clamp_free_camera_eye(
						eye, b["centre_xz"], b["radius"], b["margin"])
			cam.global_transform = Transform3D(
				Basis.looking_at(s["look"] - eye, Vector3.UP), eye)
		cam.make_current()
		for _f in range(16):
			await get_tree().process_frame
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		var path := outdir.path_join("%s.png" % s["name"])
		get_viewport().get_texture().get_image().save_png(path)
		print("[fog-forest-capture] ", path)

	main.queue_free()
	for _f in range(8):
		await get_tree().process_frame


static func _pullback_from_hero(hero: Vector2, ground_y: float, dist: float) -> Vector3:
	var dir := Vector2(0.85, 0.52).normalized()
	return Vector3(hero.x + dir.x * dist, ground_y + 2.4, hero.y + dir.y * dist)
