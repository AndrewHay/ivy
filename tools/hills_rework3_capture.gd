## ivy-xid2 round 3 evidence captures.
extends "res://tools/hills_rework2_capture.gd"

const _OUT3 := "/Users/andrewhay/github/ivy/.tmp/hills/rework3"
const _REWORK2 := "/Users/andrewhay/github/ivy/.tmp/hills/rework2"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hills_rework3_capture: headless produces no PNG on macOS")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_OUT3)
	var seeds: Array[int] = [1, 7, 12]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds.clear()
			for part in String(arg.get_slice("=", 1)).split(","):
				if part.strip_edges().is_valid_int():
					seeds.append(int(part.strip_edges()))
	for seed in seeds:
		await _capture_village_seed(int(seed))
	await _capture_playground_shots(7)
	_log_luminance_compare_custom(_OUT3, _REWORK2)
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
		var path := "%s/seed%d_%s.png" % [_OUT3, seed, s["name"]]
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		if s["name"] == "edge_outward":
			var stats := _upper_third_luminance_stats(img)
			print("[hills-rework3] edge_outward seed=%d lum_mean=%.4f lum_std=%.4f" % [
				seed, stats["mean"], stats["std"]])
		print("[hills-rework3] ", path)
	main.queue_free()
	for _i in range(8):
		await get_tree().process_frame


func _capture_playground_shots(seed: int) -> void:
	for spec in [
		{"camera": "camsun", "name": "playground_camsun"},
		{"camera": "edge_outward", "name": "playground_edge_outward"},
	]:
		var ps := load("res://scenes/playground/hills_playground.tscn") as PackedScene
		var pg := ps.instantiate()
		pg.set("script_driven", true)
		pg.get("_params").layout_seed = seed
		add_child(pg)
		for _i in range(45):
			await get_tree().process_frame
		pg.call("_apply_camera_preset", spec["camera"])
		pg.call("_apply_playground_fog")
		if pg.has_node("Camera3D"):
			(pg.get_node("Camera3D") as Camera3D).make_current()
		for _f in range(28):
			await get_tree().process_frame
		var path := "%s/%s_seed%d.png" % [_OUT3, spec["name"], seed]
		pg.call("_capture_png", path)
		pg.queue_free()
		for _i in range(6):
			await get_tree().process_frame


func _log_luminance_compare_custom(out_dir: String, before_dir: String) -> void:
	for seed in [1, 7, 12]:
		for label in ["rework3", "before"]:
			var base := out_dir if label == "rework3" else before_dir
			var p := "%s/seed%d_edge_outward.png" % [base, seed]
			if not FileAccess.file_exists(p):
				continue
			var img := Image.load_from_file(p)
			if img == null:
				continue
			var s := _upper_third_luminance_stats(img)
			print("[hills-lum] %s seed%d edge_outward mean=%.4f std=%.4f" % [
				label, seed, s["mean"], s["std"]])
