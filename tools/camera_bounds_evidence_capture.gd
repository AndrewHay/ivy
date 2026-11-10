## ivy-7h1f: lawn-disc camera bounds evidence + fog-on CamSun (seeds 7/1).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")
const DebugCamera = preload("res://src/world/debug_camera.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/vlr/camera_bounds"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)

	var before_src := (
		"/Users/andrewhay/github/ivy/.tmp/vlr/fog_forest/v2/before_game_seed7_wide.png")
	if FileAccess.file_exists(before_src):
		var img := Image.load_from_file(before_src)
		img.save_png(outdir.path_join("before_wide_pullback_flat_plane.png"))
		print("[camera-bounds] linked before wide from v2")

	var main := await _boot_generated(7)
	var world: Node3D = main.get_node("World")
	var bounds: Dictionary = world.get_village_lawn_camera_bounds()
	var centre: Vector2 = bounds["centre_xz"]
	var lawn_r: float = bounds["radius"]
	var margin: float = bounds["margin"]
	var dc: DebugCamera = world.get_node("DebugCamera") as DebugCamera
	dc.script_driven = false
	dc.make_current()
	for _i in range(300):
		dc._zoom_by_notches(-1.0)
	dc._enforce_lawn_orbit_bounds()
	dc._apply_orbit_view()
	await _save(world, outdir, "after_debug_max_zoom_inward", dc)

	dc._yaw += PI
	dc._apply_orbit_view()
	await _save(world, outdir, "after_debug_max_zoom_outward", dc)

	var edge_cam := Camera3D.new()
	world.add_child(edge_cam)
	var allowed := maxf(lawn_r - margin, 2.0)
	var dir_out := Vector2(0.35, 0.94).normalized()
	var eye_out := CameraBounds.clamp_free_camera_eye(
		Vector3(centre.x + dir_out.x * allowed, 5.5, centre.y + dir_out.y * allowed),
		centre, lawn_r, margin)
	var look_village := Vector3(centre.x, 1.2, centre.y)
	edge_cam.global_transform = Transform3D(
		Basis.looking_at(look_village - eye_out, Vector3.UP), eye_out)
	await _save(world, outdir, "after_edge_look_inward_village", edge_cam)
	var look_out := eye_out + Vector3(dir_out.x, 0.0, dir_out.y) * 30.0
	edge_cam.global_transform = Transform3D(
		Basis.looking_at(look_out - eye_out, Vector3.UP), eye_out)
	await _save(world, outdir, "after_edge_look_outward_plane", edge_cam)

	var rig: Node3D = world.get_node("CameraRig")
	(rig.get_node("CamSun") as Camera3D).make_current()
	for _f in range(16):
		await get_tree().process_frame
	await _save_viewport(world, outdir, "after_seed7_camsun")
	rig.call("select", 2)
	for _f in range(16):
		await get_tree().process_frame
	await _save_viewport(world, outdir, "after_seed7_top")

	var sky: SkySun = world.get_sky_sun()
	sky.set_fog_centre_mode(HeroFog.CentreMode.HERO)
	sky.set_fog_anchor(world.call("_hero_fog_anchor_world"))
	(rig.get_node("CamSun") as Camera3D).make_current()
	for _f in range(20):
		await get_tree().process_frame
	await _save_viewport(world, outdir, "after_seed7_camsun_fog_forest")

	main.queue_free()
	for _i in range(10):
		await get_tree().process_frame

	for seed in [7, 1]:
		await _fog_on_camsun(outdir, seed)

	get_tree().quit(0)


func _fog_on_camsun(outdir: String, seed: int) -> void:
	var main := await _boot_generated(seed)
	var world: Node3D = main.get_node("World")
	var rig: Node3D = world.get_node("CameraRig")
	(rig.get_node("CamSun") as Camera3D).make_current()
	for _f in range(18):
		await get_tree().process_frame
	await _save_viewport(world, outdir, "fog_on_game_seed%d_camsun" % seed)
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


func _save(_world: Node, outdir: String, name: String, cam: Camera3D) -> void:
	cam.make_current()
	for _f in range(14):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var path := outdir.path_join("%s.png" % name)
	get_viewport().get_texture().get_image().save_png(path)
	print("[camera-bounds] ", path)


func _save_viewport(_world: Node, outdir: String, name: String) -> void:
	for _f in range(4):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var path := outdir.path_join("%s.png" % name)
	get_viewport().get_texture().get_image().save_png(path)
	print("[camera-bounds] ", path)
