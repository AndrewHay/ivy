## v3: fog demo with live Environment readback (ivy-89a6).
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
	var outdir := "/Users/andrewhay/github/ivy/.tmp/vlr/fog_forest/v3"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)
	await _capture_demo_pairs(outdir, 7, 80.0, "80m")
	await _capture_demo_pairs(outdir, 7, 60.0, "60m")
	get_tree().quit(0)


func _capture_demo_pairs(outdir: String, seed: int, dist: float, tag: String) -> void:
	var main := await _boot_generated(seed)
	var world: Node3D = main.get_node("World")
	var sky: SkySun = world.get_sky_sun()
	var pivot: Vector3 = world.get_orbit_pivot()
	var hero := Vector2(pivot.x, pivot.z) + VillageLayout.HERO_DOOR_STOOP
	var anchor: Vector3 = world.call("_hero_fog_anchor_world") as Vector3
	var cam := Camera3D.new()
	world.add_child(cam)
	var dir := Vector2(0.92, 0.38).normalized()
	var eye := Vector3(hero.x + dir.x * dist, pivot.y + 5.0, hero.y + dir.y * dist)
	if world.has_method("get_village_lawn_camera_bounds"):
		var b: Dictionary = world.get_village_lawn_camera_bounds()
		if not b.is_empty():
			eye = CameraBounds.clamp_free_camera_eye(
				eye, b["centre_xz"], b["radius"], b["margin"])
	cam.global_transform = Transform3D(
		Basis.looking_at(Vector3(hero.x, 1.2, hero.y) - eye, Vector3.UP), eye)
	cam.fov = 75.0
	cam.make_current()
	sky.set_fog_anchor(anchor)
	for _i in range(6):
		await get_tree().process_frame
	var cam_dist := cam.global_position.distance_to(anchor)
	for mode in [HeroFog.CentreMode.CAMERA, HeroFog.CentreMode.HERO]:
		var label := "Camera-centred" if mode == HeroFog.CentreMode.CAMERA else "Hero-centred"
		sky.set_fog_centre_mode(mode)
		for _f in range(24):
			sky.sync_depth_fog_from_active_camera()
			await get_tree().process_frame
		if RenderingServer.has_method("force_draw"):
			RenderingServer.force_draw(false)
		var st := sky.read_fog_environment_state()
		var path := outdir.path_join(
			"fog_demo_seed%d_%s_%s.png" % [seed, tag, label.replace(" ", "_")])
		get_viewport().get_texture().get_image().save_png(path)
		print(
			"[fog-v3] %s mode=%s dist=%.1f cam_to_hero=%.1f env enabled=%s begin=%.2f end=%.2f mode_enum=%s sky_affect=%.2f"
			% [path, label, dist, cam_dist, st.get("fog_enabled"), st.get("fog_depth_begin"),
			st.get("fog_depth_end"), st.get("fog_mode"), st.get("fog_sky_affect")])
	main.queue_free()
	for _i in range(8):
		await get_tree().process_frame


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
