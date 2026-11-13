## ivy-ska0: CamSun + edge_outward stills for rolling hills before/after evidence.
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hills_evidence_capture: headless produces no PNG on macOS")
		get_tree().quit(1)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/hills/before"
	var seeds: Array = [1, 7, 12]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
		if arg.begins_with("--seeds="):
			seeds.clear()
			for part in String(arg.get_slice("=", 1)).split(","):
				part = part.strip_edges()
				if part.is_valid_int():
					seeds.append(int(part))
	DirAccess.make_dir_recursive_absolute(outdir)

	for seed in seeds:
		await _capture_seed(outdir, int(seed))
	get_tree().quit(0)


func _capture_seed(outdir: String, seed: int) -> void:
	var main := await _boot_generated(seed)
	var world: Node3D = main.get_node("World")
	var sky: SkySun = world.get_sky_sun()
	sky.set_fog_model(HeroFog.FogModel.WORLD_AROUND_HERO)
	sky.set_fog_anchor(world.call("_hero_fog_anchor_world"))
	for _f in range(12):
		await get_tree().process_frame
	var shots := _shot_specs(world)
	var extra := Camera3D.new()
	world.add_child(extra)
	for s in shots:
		var cam: Camera3D
		if s.get("use_camsun", false):
			cam = world.get_node("CameraRig/CamSun")
		else:
			cam = extra
			cam.global_transform = s["xf"]
		cam.make_current()
		for _f in range(24):
			await get_tree().process_frame
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		var path := outdir.path_join("seed%d_%s.png" % [seed, s["name"]])
		get_viewport().get_texture().get_image().save_png(path)
		print("[hills-evidence] ", path)
	main.queue_free()
	for _i in range(8):
		await get_tree().process_frame


func _shot_specs(world: Node3D) -> Array:
	var pivot: Vector3 = world.get_orbit_pivot()
	var hero := Vector2(pivot.x, pivot.z) + VillageLayout.HERO_DOOR_STOOP
	var bounds: Dictionary = world.get_village_lawn_camera_bounds()
	var centre: Vector2 = bounds.get("centre_xz", Vector2(hero.x, hero.y))
	var lawn_r: float = bounds.get("radius", 56.0)
	var margin: float = bounds.get("margin", 2.0)
	var allowed := maxf(lawn_r - margin, 2.0)
	var toward_hero := (Vector2(hero.x, hero.y) - centre)
	var dir_in := toward_hero.normalized() if toward_hero.length() > 0.1 else Vector2(0.0, -1.0)
	var dir_out := -dir_in
	var edge_out := CameraBounds.clamp_free_camera_eye(
		Vector3(centre.x + dir_out.x * allowed, 5.0, centre.y + dir_out.y * allowed),
		centre, lawn_r, margin)
	var look_out := Vector3(
		edge_out.x + dir_out.x * 150.0, 1.5, edge_out.z + dir_out.y * 150.0)
	var look_village := Vector3(hero.x, 1.2, hero.y)
	var side_dir := Vector2(-dir_in.y, dir_in.x).normalized()
	var edge_side := CameraBounds.clamp_free_camera_eye(
		Vector3(centre.x + side_dir.x * allowed, 5.0, centre.y + side_dir.y * allowed),
		centre, lawn_r, margin)
	var look_side := Vector3(
		edge_side.x + side_dir.x * 120.0, 1.5, edge_side.z + side_dir.y * 120.0)
	return [
		{"name": "camsun", "use_camsun": true},
		{
			"name": "edge_outward",
			"xf": Transform3D(Basis.looking_at(look_out - edge_out, Vector3.UP), edge_out),
		},
		{
			"name": "edge_inward",
			"xf": Transform3D(Basis.looking_at(look_village - edge_out, Vector3.UP), edge_out),
		},
		{
			"name": "edge_side",
			"xf": Transform3D(Basis.looking_at(look_side - edge_side, Vector3.UP), edge_side),
		},
	]


func _boot_generated(seed: int) -> Node:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(28):
		await get_tree().process_frame
	main.call("apply_village_mode_live", GameModes.GENERATED, seed)
	for _i in range(20):
		await get_tree().process_frame
	return main
