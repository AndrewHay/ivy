extends Node

const _SCENE := "res://scenes/playground/forest_playground.tscn"
const _OUT_ROOT := "/Users/andrewhay/github/ivy/.tmp/vlr/forest/v2"
const _SEEDS: Array[int] = [1, 7, 12]
const _CAMERAS: Array = ["camsun", "wide"]


func _ready() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	DirAccess.make_dir_recursive_absolute(_OUT_ROOT)
	var w := get_window()
	if w != null and w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame
	await _capture_set("before", 0, "")
	for row in [
		["deep_wedge", 1, "Deep wedge"],
		["arc_ring", 2, "Arc ring behind hero"],
		["flank_gap", 3, "Wedge + CamSun gap flanks"],
		["camsun_backstop", 4, "Behind-hero for CamSun"],
	]:
		await _capture_set("after_%s" % row[0], row[1], row[2])
	await _capture_ui_production()
	await _capture_ui_variant4()
	print("[forest-vlr] done")
	get_tree().quit(0)


func _capture_set(prefix: String, variant: int, preset: String) -> void:
	for seed in _SEEDS:
		for cam in _CAMERAS:
			var fname := "%s_seed%d_%s.png" % [prefix, seed, cam]
			await _one_shot(seed, variant, preset, cam, _OUT_ROOT.path_join(fname))


func _capture_ui_production() -> void:
	await _one_shot(7, 0, "", "camsun", _OUT_ROOT.path_join("playground_ui_production_seed7.png"), true)


func _capture_ui_variant4() -> void:
	await _one_shot(7, 4, "Behind-hero for CamSun", "camsun",
		_OUT_ROOT.path_join("playground_ui_camsun_backstop_seed7.png"), true)


func _one_shot(
		seed: int, variant: int, preset: String, cam: String, out_path: String,
		show_ui: bool = false) -> void:
	var ps := load(_SCENE) as PackedScene
	var root: Node3D = ps.instantiate()
	root.set("script_driven", not show_ui)
	root.set("capture_seed", seed)
	root.set("capture_variant", variant)
	root.set("capture_preset", preset)
	add_child(root)
	for _i in range(20):
		await get_tree().process_frame
	root.call("_apply_camera_preset", cam)
	var cam_node := root.get_node("Camera3D") as Camera3D
	if cam_node != null:
		cam_node.make_current()
	for _i in range(6):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[forest-vlr] saved ", out_path)
	root.queue_free()
	await get_tree().process_frame
