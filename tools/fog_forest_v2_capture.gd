## v2 evidence: seeds 7/1/12 CamSun + wide + fog contrast (ivy-89a6).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/vlr/fog_forest/v2"
	var tag := "before"
	var fog_hero := true
	var unbounded_lawn := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
		if arg.begins_with("--tag="):
			tag = String(arg.get_slice("=", 1))
		if arg == "--fog-camera":
			fog_hero = false
		if arg == "--diagnostic-unbounded-lawn":
			unbounded_lawn = true
	DirAccess.make_dir_recursive_absolute(outdir)

	for seed in [7, 1, 12]:
		await _shot_seed(outdir, tag, seed, fog_hero)
	await _shot_wide(outdir, tag, 7, fog_hero, unbounded_lawn)
	await _shot_fog_contrast(outdir, tag, 7, fog_hero, unbounded_lawn)
	get_tree().quit(0)


func _shot_seed(outdir: String, tag: String, seed: int, fog_hero: bool) -> void:
	var main := await _boot_generated(seed)
	var world: Node3D = main.get_node("World")
	_set_fog_mode(world, fog_hero)
	var rig: Node3D = world.get_node("CameraRig")
	var cam_sun: Camera3D = rig.get_node("CamSun")
	cam_sun.make_current()
	for _f in range(18):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var path := outdir.path_join("%s_game_seed%d_camsun.png" % [tag, seed])
	get_viewport().get_texture().get_image().save_png(path)
	print("[fog-v2] ", path)
	main.queue_free()
	for _i in range(8):
		await get_tree().process_frame


func _shot_wide(
		outdir: String, tag: String, seed: int, fog_hero: bool, unbounded: bool) -> void:
	var main := await _boot_generated(seed)
	var world: Node3D = main.get_node("World")
	_set_fog_mode(world, fog_hero)
	var pivot: Vector3 = world.get_orbit_pivot()
	var g := Vector2(pivot.x, pivot.z) + VillageLayout.HERO_DOOR_STOOP
	var cam := Camera3D.new()
	world.add_child(cam)
	var eye := Vector3(g.x + 55.0, 38.0, g.y + 48.0)
	if not unbounded and world.has_method("get_village_lawn_camera_bounds"):
		var b: Dictionary = world.get_village_lawn_camera_bounds()
		if not b.is_empty():
			eye = CameraBounds.clamp_free_camera_eye(
				eye, b["centre_xz"], b["radius"], b["margin"])
			eye.y = minf(eye.y, 45.0)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(g.x, 1.0, g.y) - eye, Vector3.UP), eye)
	cam.fov = 75.0
	cam.make_current()
	for _f in range(18):
		await get_tree().process_frame
	var path := outdir.path_join("%s_game_seed%d_wide.png" % [tag, seed])
	get_viewport().get_texture().get_image().save_png(path)
	print("[fog-v2] ", path)
	main.queue_free()
	for _i in range(8):
		await get_tree().process_frame


func _shot_fog_contrast(
		outdir: String, tag: String, seed: int, default_hero: bool, unbounded: bool) -> void:
	var main := await _boot_generated(seed)
	var world: Node3D = main.get_node("World")
	var pivot: Vector3 = world.get_orbit_pivot()
	var hero := Vector2(pivot.x, pivot.z) + VillageLayout.HERO_DOOR_STOOP
	var anchor := Vector3(hero.x, pivot.y + 1.0, hero.y)
	var layout: VillageLayout = (
		world.get_node("VillageBackdrop") as VillageBackdrop).get_layout()
	var fb := layout.fog_begin
	var fe := layout.fog_end
	var cam := Camera3D.new()
	world.add_child(cam)
	var dir := Vector2(0.92, 0.38).normalized()
	var dist := 80.0
	var eye := Vector3(hero.x + dir.x * dist, pivot.y + 5.0, hero.y + dir.y * dist)
	if not unbounded and world.has_method("get_village_lawn_camera_bounds"):
		var b: Dictionary = world.get_village_lawn_camera_bounds()
		if not b.is_empty():
			eye = CameraBounds.clamp_free_camera_eye(
				eye, b["centre_xz"], b["radius"], b["margin"])
	cam.global_transform = Transform3D(
		Basis.looking_at(Vector3(hero.x, 1.2, hero.y) - eye, Vector3.UP), eye)
	cam.fov = 75.0
	for mode_name in ["camera", "hero"]:
		_set_fog_mode(world, mode_name == "hero")
		cam.make_current()
		for _f in range(20):
			await get_tree().process_frame
		var haze_pt := Vector3(hero.x, 1.0, hero.y)
		var hero_amt := HeroFog.fog_amount_at_world_point(
			cam.global_position, haze_pt, anchor, fb, fe,
			HeroFog.CentreMode.HERO if mode_name == "hero" else HeroFog.CentreMode.CAMERA)
		var path := outdir.path_join(
			"%s_fog_demo_seed%d_%s_haze%.0f.png" % [tag, seed, mode_name, hero_amt * 100.0])
		get_viewport().get_texture().get_image().save_png(path)
		print("[fog-v2] %s haze@hero=%.1f%%" % [path, hero_amt * 100.0])
	main.queue_free()


func _boot_generated(seed: int) -> Node:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(30):
		await get_tree().process_frame
	main.call("apply_village_mode_live", GameModes.GENERATED, seed)
	for _i in range(22):
		await get_tree().process_frame
	return main


func _set_fog_mode(world: Node3D, hero: bool) -> void:
	var sky: SkySun = world.get_sky_sun()
	sky.set_fog_centre_mode(
		HeroFog.CentreMode.HERO if hero else HeroFog.CentreMode.CAMERA)
	sky.set_fog_anchor(world.call("_hero_fog_anchor_world"))
