extends Node

## ivy-3hg QA harness — full player flow for procedural Test wall acceptance.
## Run: Godot res://tools/qa_wall_acceptance.tscn

const _MAIN_SCENE := "res://src/main/main.tscn"
const _BuildingCatalog = preload("res://src/world/building_catalog.gd")
const _Conv = preload("res://src/core/conv.gd")
const _OUTDIR := "res://.tmp/ui_scripts/qa_3hg_wall/"
const _PRESENT_TIMEOUT_MS := 4000
const _TICKS_PER_DAY := 24
const _GROWTH_DAYS := 30


func _ready() -> void:
	var outdir := ProjectSettings.globalize_path(_OUTDIR)
	DirAccess.make_dir_recursive_absolute(outdir)
	print("[qa-wall] outdir=", outdir)

	var failures: PackedStringArray = []
	failures += await _run_wall_flow(outdir)
	failures += await _run_cylinder_regression(outdir)

	if failures.is_empty():
		print("[qa-wall] PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("[qa-wall] FAIL: ", f)
		get_tree().quit(1)


func _run_wall_flow(outdir: String) -> PackedStringArray:
	var main := await _spawn_main()
	var failures: PackedStringArray = []

	if not _picker_has_wall_option(main):
		failures.append("picker missing 'Test wall' button")
		await _capture(outdir.path_join("picker.png"))
		main.queue_free()
		return failures

	await _capture(outdir.path_join("picker.png"))
	print("[qa-wall] picker shows Test wall")

	await _select_building(main, "wall")
	# 100 m wall light-field bake can exceed 5 min on first run (review ivy-3hg.13).
	var load_ok := await _wait_for_free_plant(main, 600000)
	if not load_ok:
		failures.append("wall load timed out or free-plant session failed")
		await _capture(outdir.path_join("wall_load_timeout.png"))
		main.queue_free()
		return failures

	await _capture(outdir.path_join("wall_sun.png"))
	print("[qa-wall] wall loaded")

	var sim: Node = main.get_node("Sim")
	var world: Node = main.get_node("World")
	if not sim.has_method("plant_at"):
		failures.append("Sim has no plant_at")
	else:
		sim.plant_at(Vector3(0.0, 0.02, 0.01), _Conv.SOUTH)
		if main.has_method("_on_plant_success"):
			main.call("_on_plant_success")
		await _settle(5)
		await _capture(outdir.path_join("wall_planted.png"))
		print("[qa-wall] planted at wall midpoint")

		if sim.has_method("advance_ticks"):
			sim.advance_ticks(_TICKS_PER_DAY * _GROWTH_DAYS)
			sim.advance_ticks(int(round(0.25 * _TICKS_PER_DAY)))
			await _settle(5)
			await _capture(outdir.path_join("wall_growth_d30.png"))
			var plant: PlantData = sim.get("plant") as PlantData
			if plant == null or plant.total_length <= 0.0:
				failures.append("no stem growth after 30 days on wall")
			else:
				print("[qa-wall] growth total_len=%.3f" % plant.total_length)

	main.queue_free()
	await _settle(10)
	return failures


func _run_cylinder_regression(outdir: String) -> PackedStringArray:
	var main := await _spawn_main()
	var failures: PackedStringArray = []
	await _select_building(main, "cylinder")
	var load_ok := await _wait_for_free_plant(main, 120000)
	if not load_ok:
		failures.append("cylinder regression load timed out")
	else:
		await _capture(outdir.path_join("cylinder_regression.png"))
		print("[qa-wall] cylinder regression capture done")
	main.queue_free()
	return failures


func _spawn_main() -> Node:
	var ps := load(_MAIN_SCENE) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", false)
	add_child(main)
	_keep_window_presenting()
	await _settle(35)
	return main


func _picker_has_wall_option(main: Node) -> bool:
	var ui: CanvasLayer = main.get_node("UI") as CanvasLayer
	if ui == null:
		return false
	for child in ui.get_children():
		if child.name != "BuildingPicker":
			continue
		for btn in _find_buttons(child):
			if (btn as Button).text == "Test wall":
				return true
	return false


func _find_buttons(root: Node) -> Array:
	var out: Array = []
	if root is Button:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_buttons(c))
	return out


func _select_building(main: Node, building_id: String) -> void:
	var ui: CanvasLayer = main.get_node("UI") as CanvasLayer
	var picker := ui.get_node_or_null("BuildingPicker")
	if picker != null:
		for btn in _find_buttons(picker):
			var entry_id := _building_id_for_label((btn as Button).text)
			if entry_id == building_id:
				(btn as Button).emit_signal("pressed")
				await _settle(5)
				return
	if main.has_method("_on_building_selected"):
		main.call("_on_building_selected", building_id)
		_dismiss_picker(ui)
	else:
		push_error("[qa-wall] Main has no _on_building_selected")
	await _settle(3)


func _building_id_for_label(label: String) -> String:
	for entry in _BuildingCatalog.all():
		if entry.label == label:
			return entry.id
	return ""


func _dismiss_picker(ui: CanvasLayer) -> void:
	var picker := ui.get_node_or_null("BuildingPicker")
	if picker != null:
		picker.queue_free()


func _wait_for_free_plant(main: Node, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var ui: CanvasLayer = main.get_node_or_null("UI") as CanvasLayer
		var has_picker := ui != null and ui.get_node_or_null("BuildingPicker") != null
		var overlay := ui.get_node_or_null("LoadingOverlay") if ui != null else null
		var tool := main.get_node_or_null("World/PlantingTool")
		var hud := ui.get_node_or_null("Hud") if ui != null else null
		if not has_picker and overlay == null and tool != null and hud != null:
			await _settle(15)
			return true
		await get_tree().process_frame
	return false


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _present_fresh_frame() -> bool:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
		return true
	var drawn := [false]
	var on_draw := func() -> void: drawn[0] = true
	RenderingServer.frame_post_draw.connect(on_draw, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + _PRESENT_TIMEOUT_MS
	while not drawn[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if RenderingServer.frame_post_draw.is_connected(on_draw):
		RenderingServer.frame_post_draw.disconnect(on_draw)
	return drawn[0]


func _capture(path: String) -> void:
	if not await _present_fresh_frame():
		printerr("[qa-wall] capture refused (no frame): ", path)
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		printerr("[qa-wall] no viewport image for ", path)
		return
	var err := img.save_png(path)
	if err != OK:
		printerr("[qa-wall] save_png failed ", err, " ", path)
		return
	print("[qa-wall] saved ", path, " size=", img.get_size())


func _keep_window_presenting() -> void:
	var w := get_window()
	if w == null:
		return
	if w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()
