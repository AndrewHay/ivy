## Before/after grass anchor evidence (ivy-j68r) — generated seed 1, three cameras.
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/vlr/grass_anchor"
	var tag := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
		if arg.begins_with("--tag="):
			tag = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)

	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(30):
		await get_tree().process_frame
	main.call("apply_village_mode_live", GameModes.GENERATED, 1)
	for _i in range(20):
		await get_tree().process_frame

	var world: Node3D = main.get_node("World")
	var pivot: Vector3 = world.get_orbit_pivot()
	var g := Vector2(pivot.x, pivot.z)
	var hero := g + VillageLayout.HERO_DOOR_STOOP
	var rig: Node3D = world.get_node("CameraRig") as Node3D
	var cam_sun: Camera3D = rig.get_node("CamSun") as Camera3D

	var shots: Array = [
		{
			"name": "%s_a_camsun" % tag,
			"mode": "camsun",
		},
		{
			"name": "%s_b_far_30m" % tag,
			"mode": "custom",
			"eye": _eye_30m_from_hero(hero, pivot.y),
			"look": Vector3(g.x, 0.3, g.y + VillageLayout.GENERATED_LAWN_RADIUS * 0.35),
		},
		{
			"name": "%s_c_oblique_lawn" % tag,
			"mode": "custom",
			"eye": Vector3(pivot.x, 22.0, pivot.z + 42.0),
			"look": Vector3(g.x, 0.0, g.y + 8.0),
		},
	]

	var lawn_bounds := world.get_village_lawn_camera_bounds() if world.has_method(
		"get_village_lawn_camera_bounds") else {}
	var extra_cam := Camera3D.new()
	world.add_child(extra_cam)
	for s in shots:
		var cam: Camera3D
		if s["mode"] == "camsun":
			cam = cam_sun
		else:
			cam = extra_cam
			var eye: Vector3 = s["eye"]
			if not lawn_bounds.is_empty():
				eye = CameraBounds.clamp_free_camera_eye(
					eye, lawn_bounds["centre_xz"], lawn_bounds["radius"], lawn_bounds["margin"])
			cam.global_transform = Transform3D(
				Basis.looking_at(s["look"] - eye, Vector3.UP), eye)
		cam.make_current()
		for _f in range(14):
			await get_tree().process_frame
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		var path := outdir.path_join("%s.png" % s["name"])
		get_viewport().get_texture().get_image().save_png(path)
		print("[grass-anchor-capture] ", path)

	main.queue_free()
	get_tree().quit(0)


static func _eye_30m_from_hero(hero: Vector2, ground_y: float) -> Vector3:
	var offset := Vector2(1.0, 0.72).normalized() * 30.0
	return Vector3(hero.x + offset.x, 2.8, hero.y + offset.y)
