## rework5 evidence capture: CamSun, edge outward, east/west horizon, seam shot.
## Usage: godot tools/hills_rework5_capture.tscn -- --outdir=.tmp/hills/rework5
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hills_rework5_capture: headless produces no PNG on macOS")
		get_tree().quit(1)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/hills/rework5"
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
		print("[rework5-capture] ", path)
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

	# Primary hero-facing direction
	var toward_hero := (Vector2(hero.x, hero.y) - centre)
	var dir_in := toward_hero.normalized() if toward_hero.length() > 0.1 else Vector2(0.0, -1.0)
	var dir_out := -dir_in  # typically northward

	# North-lawn edge (outward)
	var edge_out := CameraBounds.clamp_free_camera_eye(
		Vector3(centre.x + dir_out.x * allowed, 5.0, centre.y + dir_out.y * allowed),
		centre, lawn_r, margin)
	var look_out := Vector3(
		edge_out.x + dir_out.x * 200.0, 2.0, edge_out.z + dir_out.y * 200.0)

	# East lawn edge (looking east)
	var east_dir := Vector2(1.0, 0.0)
	var edge_east := CameraBounds.clamp_free_camera_eye(
		Vector3(centre.x + east_dir.x * allowed, 5.0, centre.y + east_dir.y * allowed),
		centre, lawn_r, margin)
	var look_east := Vector3(
		edge_east.x + east_dir.x * 200.0, 2.0, edge_east.z + east_dir.y * 200.0)

	# West lawn edge (looking west)
	var west_dir := Vector2(-1.0, 0.0)
	var edge_west := CameraBounds.clamp_free_camera_eye(
		Vector3(centre.x + west_dir.x * allowed, 5.0, centre.y + west_dir.y * allowed),
		centre, lawn_r, margin)
	var look_west := Vector3(
		edge_west.x + west_dir.x * 200.0, 2.0, edge_west.z + west_dir.y * 200.0)

	# Seam shot: from just inside lawn looking at the hill-toe transition zone (~100m out)
	var seam_eye := Vector3(centre.x + dir_out.x * (allowed - 4.0), 1.2,
		centre.y + dir_out.y * (allowed - 4.0))
	var seam_look := Vector3(
		seam_eye.x + dir_out.x * 60.0, 0.8, seam_eye.z + dir_out.y * 60.0)

	# Top-down overview
	var top_eye := Vector3(centre.x, 320.0, centre.y)
	var top_look := Vector3(centre.x, 0.0, centre.y + 0.01)

	# Silhouette: low angle from south edge looking north
	var south_edge := Vector3(centre.x - dir_out.x * allowed, 3.0,
		centre.y - dir_out.y * allowed)
	var sil_look := Vector3(
		south_edge.x + dir_out.x * 300.0, 10.0, south_edge.z + dir_out.y * 300.0)

	return [
		{"name": "camsun", "use_camsun": true},
		{
			"name": "edge_outward",
			"xf": Transform3D(Basis.looking_at(look_out - edge_out, Vector3.UP), edge_out),
		},
		{
			"name": "east_horizon",
			"xf": Transform3D(Basis.looking_at(look_east - edge_east, Vector3.UP), edge_east),
		},
		{
			"name": "west_horizon",
			"xf": Transform3D(Basis.looking_at(look_west - edge_west, Vector3.UP), edge_west),
		},
		{
			"name": "seam",
			"xf": Transform3D(Basis.looking_at(seam_look - seam_eye, Vector3.UP), seam_eye),
		},
		{
			"name": "top",
			"xf": Transform3D(Basis.looking_at(top_look - top_eye, Vector3.UP), top_eye),
		},
		{
			"name": "silhouette",
			"xf": Transform3D(Basis.looking_at(sil_look - south_edge, Vector3.UP), south_edge),
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
