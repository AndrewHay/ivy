## ivy-xid2: rolling-hills rework evidence (.tmp/hills/rework/).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _PLAYGROUND := "res://scenes/playground/hills_playground.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")

const _OUT := "/Users/andrewhay/github/ivy/.tmp/hills/rework"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hills_rework_capture: headless produces no PNG on macOS")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_OUT)
	var seeds: Array[int] = [1, 7, 12]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds.clear()
			for part in String(arg.get_slice("=", 1)).split(","):
				if part.strip_edges().is_valid_int():
					seeds.append(int(part.strip_edges()))
	for seed in seeds:
		await _capture_village_seed(int(seed))
	await _capture_playground_ui(7)
	get_tree().quit(0)


func _capture_village_seed(seed: int) -> void:
	var main := await _boot_generated(seed)
	var world: Node3D = main.get_node("World")
	var sky: SkySun = world.get_sky_sun()
	sky.set_fog_model(HeroFog.FogModel.WORLD_AROUND_HERO)
	sky.set_fog_anchor(world.call("_hero_fog_anchor_world"))
	for _f in range(16):
		await get_tree().process_frame
	var shots := _shot_specs(world)
	var extra := Camera3D.new()
	world.add_child(extra)
	for s in shots:
		if s.get("seed_only", -1) >= 0 and s["seed_only"] != seed:
			continue
		var cam: Camera3D
		if s.get("use_camsun", false):
			cam = world.get_node("CameraRig/CamSun")
		else:
			cam = extra
			cam.global_transform = s["xf"]
		cam.make_current()
		for _f in range(28):
			await get_tree().process_frame
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		var path := "%s/seed%d_%s.png" % [_OUT, seed, s["name"]]
		get_viewport().get_texture().get_image().save_png(path)
		print("[hills-rework] ", path)
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
	var g := centre
	var off := ForestPlaygroundCamera.backdrop_origin()
	var top_pos := Vector3(g.x, 95.0, g.y)
	var shade_pos := edge_out + Vector3(0.0, 0.0, 0.0)
	shade_pos.y = 4.2
	var shade_look := Vector3(g.x + dir_out.x * 90.0, 8.0, g.y + dir_out.y * 90.0)
	var sil_pos := Vector3(g.x + side_dir.x * allowed, 3.8, g.y + side_dir.y * allowed)
	var sil_look := Vector3(g.x + side_dir.x * 130.0, 6.0, g.y + side_dir.y * 130.0)
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
		{
			"name": "camtop", "seed_only": 7,
			"xf": Transform3D(Basis.looking_at(Vector3(g.x, 0.0, g.y) - top_pos, Vector3.UP), top_pos),
		},
		{
			"name": "camshade", "seed_only": 7,
			"xf": Transform3D(Basis.looking_at(shade_look - shade_pos, Vector3.UP), shade_pos),
		},
		{
			"name": "camsilhouette", "seed_only": 7,
			"xf": Transform3D(Basis.looking_at(sil_look - sil_pos, Vector3.UP), sil_pos),
		},
	]


func _capture_playground_ui(seed: int) -> void:
	var ps := load(_PLAYGROUND) as PackedScene
	var pg := ps.instantiate()
	pg.set("script_driven", true)
	add_child(pg)
	for _i in range(35):
		await get_tree().process_frame
	var path := "%s/playground_ui_seed%d.png" % [_OUT, seed]
	pg.call("_capture_png", path)
	pg.queue_free()
	for _i in range(6):
		await get_tree().process_frame


func _boot_generated(seed: int) -> Node:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(28):
		await get_tree().process_frame
	main.call("apply_village_mode_live", GameModes.GENERATED, seed)
	for _i in range(24):
		await get_tree().process_frame
	return main
