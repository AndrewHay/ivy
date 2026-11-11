## ivy-jnee: before (hero-shifted depth) vs after (world fog) evidence.
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")
const WorldFogParams = preload("res://src/world/world_fog_params.gd")
const ForestPlaygroundScene = preload("res://scenes/playground/forest_playground.tscn")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/vlr/fog_v2/v3"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)

	for seed in [7, 1]:
		await _capture_seed_pair(outdir, seed)
	_print_haze_table()
	await _playground_ui_shot(outdir.path_join("playground_fog_controls.png"))
	await _main_runtime_camsun(outdir.path_join("main_runtime_camsun_seed7.png"), 7)
	get_tree().quit(0)


func _main_runtime_camsun(path: String, seed: int) -> void:
	var main := await _boot_generated(seed)
	var world: Node3D = main.get_node("World")
	world.get_sky_sun().set_fog_model(HeroFog.FogModel.WORLD_AROUND_HERO)
	for _f in range(30):
		await get_tree().process_frame
	(world.get_node("CameraRig/CamSun") as Camera3D).make_current()
	for _f in range(20):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(path)
	print("[fog-v2] main-runtime ", path)
	main.queue_free()


func _capture_seed_pair(outdir: String, seed: int) -> void:
	for tag_model in [
		["before", HeroFog.FogModel.HERO_SHIFTED_DEPTH],
		["after", HeroFog.FogModel.WORLD_AROUND_HERO]]:
		var tag: String = tag_model[0]
		var model: HeroFog.FogModel = tag_model[1]
		var main := await _boot_generated(seed)
		var world: Node3D = main.get_node("World")
		var sky: SkySun = world.get_sky_sun()
		sky.set_fog_model(model)
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
			var path := outdir.path_join("%s_seed%d_%s.png" % [tag, seed, s["name"]])
			get_viewport().get_texture().get_image().save_png(path)
			print("[fog-v2] ", path)
		main.queue_free()
		for _i in range(8):
			await get_tree().process_frame


func _shot_specs(world: Node3D) -> Array:
	var pivot: Vector3 = world.get_orbit_pivot()
	var hero := Vector2(pivot.x, pivot.z) + VillageLayout.HERO_DOOR_STOOP
	var anchor := world.call("_hero_fog_anchor_world") as Vector3
	var bounds: Dictionary = world.get_village_lawn_camera_bounds()
	var centre: Vector2 = bounds.get("centre_xz", Vector2(hero.x, hero.y))
	var lawn_r: float = bounds.get("radius", 56.0)
	var margin: float = bounds.get("margin", 2.0)
	var allowed := maxf(lawn_r - margin, 2.0)
	var toward_hero := (Vector2(hero.x, hero.y) - centre)
	var dir_in := toward_hero.normalized() if toward_hero.length() > 0.1 else Vector2(0.0, -1.0)
	var dir_out := -dir_in
	var edge_in := CameraBounds.clamp_free_camera_eye(
		Vector3(centre.x + dir_in.x * allowed, 5.0, centre.y + dir_in.y * allowed),
		centre, lawn_r, margin)
	var edge_out := CameraBounds.clamp_free_camera_eye(
		Vector3(centre.x + dir_out.x * allowed, 5.0, centre.y + dir_out.y * allowed),
		centre, lawn_r, margin)
	var look_village := Vector3(hero.x, 1.2, hero.y)
	var look_out := Vector3(
		edge_out.x + dir_out.x * 150.0, 1.5, edge_out.z + dir_out.y * 150.0)
	var side_dir := Vector2(-dir_in.y, dir_in.x).normalized()
	var mid_eye := CameraBounds.clamp_free_camera_eye(
		Vector3(hero.x + side_dir.x * 30.0, 7.0, hero.y + side_dir.y * 30.0),
		centre, lawn_r, margin)
	return [
		{"name": "camsun", "use_camsun": true},
		{
			"name": "edge_inward",
			"xf": Transform3D(Basis.looking_at(look_village - edge_in, Vector3.UP), edge_in),
		},
		{
			"name": "edge_outward",
			"xf": Transform3D(Basis.looking_at(look_out - edge_out, Vector3.UP), edge_out),
		},
		{
			"name": "mid_side_village",
			"xf": Transform3D(
				Basis.looking_at(look_village - mid_eye, Vector3.UP), mid_eye),
		},
	]


func _print_haze_table() -> void:
	var anchor := Vector3(-7.0, 1.0, -15.0)
	var params: WorldFogParams = WorldFogParams.production()
	var hero_pt := anchor
	var village_pt := anchor + Vector3(12.0, 0.0, 8.0)
	var lawn_pt := anchor + Vector3(0.0, 0.0, 54.0)
	var camsun := Vector3(-7.0, 2.0, 8.0) * 1.35 + Vector3(-7.0, -0.44, 0.0)
	var edge := anchor + Vector3(52.0, 5.0, 0.0)
	var edge_opp := anchor + Vector3(-52.0, 5.0, 0.0)
	print("=== haze%% table (analytic WORLD model, seed-agnostic) ===")
	for label in ["hero", "village", "lawn_edge"]:
		var pt := hero_pt if label == "hero" else (village_pt if label == "village" else lawn_pt)
		for cam_name in ["A CamSun", "B edge", "C opp edge"]:
			var cam := camsun if cam_name.begins_with("A") else (edge if cam_name.begins_with("B") else edge_opp)
			var h := HeroFog.haze_along_view_ray(cam, pt, anchor, params) * 100.0
			print("%s @ %s: %.1f%%" % [label, cam_name, h])


func _playground_ui_shot(path: String) -> void:
	var ps: PackedScene = ForestPlaygroundScene
	var pg := ps.instantiate()
	add_child(pg)
	pg.set("script_driven", true)
	pg.set("force_show_ui", true)
	for _i in range(45):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	get_viewport().get_texture().get_image().save_png(path)
	print("[fog-v2] ", path)
	pg.queue_free()


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
