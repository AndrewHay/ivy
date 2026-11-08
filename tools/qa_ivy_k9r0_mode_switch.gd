## ivy-k9r0 QA: village mode switch via BuildingPicker toggle (real UI path).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _BuildingCatalog = preload("res://src/world/building_catalog.gd")
const _PRESENT_TIMEOUT_MS := 8000
const _BOOTSTRAP_TIMEOUT_MS := 120000


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("[qa-k9r0-mode] refuses headless")
		get_tree().quit(2)
		return
	var outdir := "/Users/andrewhay/github/ivy/.tmp/qa_k9r0/mode_switch"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			outdir = String(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(outdir)

	var failures := await _flow_classic_generated_classic(outdir)
	if failures.is_empty():
		print("[qa-k9r0-mode] PASS")
		get_tree().quit(0)
	else:
		for e in failures:
			printerr("[qa-k9r0-mode] FAIL: ", e)
		get_tree().quit(1)


func _flow_classic_generated_classic(outdir: String) -> PackedStringArray:
	var failures: PackedStringArray = []
	var main := await _spawn_main_interactive()
	if main == null:
		return PackedStringArray(["failed to spawn main"])

	if not await _await_picker(main, 30000):
		failures.append("initial picker never appeared")
		main.queue_free()
		return failures

	# Classic -> Village cottage
	failures += await _ensure_classic_on_picker(main)
	failures += await _load_cottage_and_capture(
		main, outdir.path_join("s05_classic_after_picker_load.png"), "classic_initial")

	# Picker again via HUD (real player path)
	if not await _click_change_building(main):
		failures.append("Change building not found after classic session")
	else:
		if not await _await_picker(main, 30000):
			failures.append("picker missing after Change building (classic)")
		else:
			failures += await _ensure_generated_seed(main, 1)
			failures += await _load_cottage_and_capture(
				main, outdir.path_join("s05_generated_after_picker_load.png"), "generated_seed1")

	if not await _click_change_building(main):
		failures.append("Change building not found after generated session")
	else:
		if not await _await_picker(main, 30000):
			failures.append("picker missing after Change building (generated)")
		else:
			failures += await _ensure_classic_on_picker(main)
			failures += await _load_cottage_and_capture(
				main, outdir.path_join("s05_classic_after_switch_back.png"), "classic_switch_back")

	main.queue_free()
	await _settle(10)
	return failures


func _load_cottage_and_capture(main: Node, png_path: String, label: String) -> PackedStringArray:
	var failures: PackedStringArray = []
	await _select_village_cottage(main)
	var t0 := Time.get_ticks_msec()
	if not await _wait_for_bootstrap(main, _BOOTSTRAP_TIMEOUT_MS):
		failures.append("%s load timed out" % label)
		return failures
	var wall := Time.get_ticks_msec() - t0
	print("[qa-k9r0-mode] %s wall_ms=%d" % [label, wall])
	await _capture(png_path)
	return failures


func _ensure_classic_on_picker(main: Node) -> PackedStringArray:
	var failures: PackedStringArray = []
	var picker := _get_picker(main)
	if picker == null:
		failures.append("no picker for classic ensure")
		return failures
	var toggle := _find_toggle(picker)
	if toggle == null:
		failures.append("VillageModeToggle missing (classic)")
		return failures
	if toggle.button_pressed:
		toggle.button_pressed = false
		toggle.emit_signal("toggled", false)
		await _settle(15)
	return failures


func _ensure_generated_seed(main: Node, seed: int) -> PackedStringArray:
	var failures: PackedStringArray = []
	var picker := _get_picker(main)
	if picker == null:
		failures.append("no picker for generated ensure")
		return failures
	var toggle := _find_toggle(picker)
	if toggle == null:
		failures.append("VillageModeToggle missing (generated)")
		return failures
	if not toggle.button_pressed:
		toggle.button_pressed = true
		toggle.emit_signal("toggled", true)
		await _settle(15)
	var seed_field := _find_named(picker, "VillageSeedField") as LineEdit
	if seed_field == null:
		failures.append("VillageSeedField missing")
		return failures
	seed_field.text = str(seed)
	seed_field.emit_signal("text_submitted", str(seed))
	await _settle(15)
	return failures


func _await_picker(main: Node, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _get_picker(main) != null:
			await _settle(10)
			return true
		await get_tree().process_frame
	return false


func _get_picker(main: Node) -> Control:
	var ui: CanvasLayer = main.get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return null
	var picker := ui.get_node_or_null("BuildingPicker")
	if picker == null or not is_instance_valid(picker):
		return null
	return picker as Control


func _click_change_building(main: Node) -> bool:
	var ui: CanvasLayer = main.get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return false
	for btn in _find_buttons(ui):
		if (btn as Button).text == "Change building":
			(btn as Button).emit_signal("pressed")
			await _settle(30)
			return true
	return false


func _spawn_main_interactive() -> Node:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", false)
	add_child(main)
	_keep_window_presenting()
	await _settle(60)
	return main


func _select_village_cottage(main: Node) -> void:
	var picker := _get_picker(main)
	if picker == null:
		if main.has_method("_on_building_selected"):
			main.call("_on_building_selected", "ivy")
		await _settle(5)
		return
	for btn in _find_buttons(picker):
		if (btn as Button).text == "Village cottage":
			(btn as Button).emit_signal("pressed")
			await _settle(5)
			return
	main.call("_on_building_selected", "ivy")
	await _settle(5)


func _wait_for_bootstrap(main: Node, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var ui: CanvasLayer = main.get_node_or_null("UI")
		var has_picker := ui != null and _get_picker(main) != null
		var overlay := ui.get_node_or_null("LoadingOverlay") if ui != null else null
		var world: Node = main.get_node_or_null("World")
		var backdrop := world.get_node_or_null("VillageBackdrop") if world != null else null
		if not has_picker and overlay == null and backdrop != null:
			await _settle(120)
			return true
		await get_tree().process_frame
	return false


func _find_buttons(root: Node) -> Array:
	var out: Array = []
	if root is Button:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_buttons(c))
	return out


func _find_toggle(picker: Node) -> CheckButton:
	return _find_named(picker, "VillageModeToggle") as CheckButton


func _find_named(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for c in root.get_children():
		var hit := _find_named(c, node_name)
		if hit != null:
			return hit
	return null


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _keep_window_presenting() -> void:
	var w := get_window()
	if w != null and w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()


func _capture(path: String) -> void:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	else:
		var drawn := [false]
		var on_draw := func() -> void: drawn[0] = true
		RenderingServer.frame_post_draw.connect(on_draw, CONNECT_ONE_SHOT)
		var deadline := Time.get_ticks_msec() + _PRESENT_TIMEOUT_MS
		while not drawn[0] and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("[qa-k9r0-mode] saved ", path)
