extends Node

## Fast macro capture for ivy-t5w: one stem, few leaves, tight camera ~1.5 m at local noon.
## Avoids the 15+ min mid-archetype wall run; frames a single leaf blade for shader QA.
##
## Non-headless only (--headless produces no image on macOS).
##
## Usage:
##   Godot res://tools/capture_leaf_lookdev.tscn -- \
##     --out=res://.tmp/leaf-lookdev/leaf_after_closeup.png
##
## Optional: --day=30 --leaf_index=0 --dist=1.5

const _MAIN_SCENE := "res://src/main/main.tscn"
const _BuildingCatalog = preload("res://src/world/building_catalog.gd")
const _Conv = preload("res://src/core/conv.gd")
const _DEFAULT_OUT := "res://.tmp/leaf-lookdev/leaf_after_closeup.png"
## SimClock.Speed.NORMAL: 24 h × 15 growth steps/h (SD-TIME-2).
const _TICKS_PER_DAY := 360
const _PRESENT_TIMEOUT_MS := 4000
const _DEFAULT_DIST := 1.5
const _MACRO_FOV := 38.0


func _ready() -> void:
	var args := _parse_args()
	var out_rel: String = args.get("out", _DEFAULT_OUT)
	var day: int = int(args.get("day", 30))
	var dist: float = float(args.get("dist", _DEFAULT_DIST))
	var leaf_index: int = int(args.get("leaf_index", -1))

	var out_path := ProjectSettings.globalize_path(out_rel)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())

	var main := await _spawn_main()
	var params: IvyParams = main.get("params") as IvyParams
	params.branch_rate = 0.0
	params.tip_cap_soft = 2
	params.tip_cap_hard = 4

	await _select_building(main, "test_wall")
	if not await _wait_for_free_plant(main, 600000):
		printerr("[leaf-lookdev] wall load timed out")
		get_tree().quit(1)
		return

	_hide_chrome(main)

	var sim: Node = main.get_node("Sim")
	var clock: SimClock = sim.get_clock()
	clock.set_speed(SimClock.Speed.PAUSE)

	sim.plant_at(Vector3(0.0, 0.02, 0.01), _Conv.SOUTH)
	if main.has_method("_on_plant_success"):
		main.call("_on_plant_success")
	clock.set_speed(SimClock.Speed.PAUSE)
	await _settle(5)

	var t0 := Time.get_ticks_msec()
	sim.advance_ticks(_TICKS_PER_DAY * day + 6)
	var elapsed_ms := Time.get_ticks_msec() - t0
	await _settle(10)

	var plant: PlantData = sim.get("plant") as PlantData
	var n_leaves := plant.leaf_count()
	print("[leaf-lookdev] day=%d elapsed_ms=%d leaves=%d segs=%d length=%.2f"
		% [day, elapsed_ms, n_leaves, plant.segment_count(), plant.total_length])
	if n_leaves <= 0:
		printerr("[leaf-lookdev] no leaves — increase --day")
		get_tree().quit(1)
		return

	var idx := leaf_index if leaf_index >= 0 else _pick_hero_leaf(plant)
	await _capture_leaf_macro(main, plant, idx, dist, out_path)

	main.queue_free()
	print("[leaf-lookdev] done")
	get_tree().quit(0)


func _pick_hero_leaf(plant: PlantData) -> int:
	## Prefer a mature leaf high on the stem (larger basis, higher on wall).
	var best := 0
	var best_score := -1.0
	for i in range(plant.leaf_count()):
		var base := i * 12
		var bx := Vector3(plant.leaf_xform[base], plant.leaf_xform[base + 1], plant.leaf_xform[base + 2])
		var by := Vector3(plant.leaf_xform[base + 4], plant.leaf_xform[base + 5], plant.leaf_xform[base + 6])
		var oy := plant.leaf_xform[base + 7]
		var score := bx.length() * by.length() + oy * 0.01
		if score > best_score:
			best_score = score
			best = i
	return best


func _leaf_frame(plant: PlantData, idx: int) -> Dictionary:
	var base := idx * 12
	var bx := Vector3(plant.leaf_xform[base], plant.leaf_xform[base + 1], plant.leaf_xform[base + 2])
	var by := Vector3(plant.leaf_xform[base + 4], plant.leaf_xform[base + 5], plant.leaf_xform[base + 6])
	var bz := Vector3(plant.leaf_xform[base + 8], plant.leaf_xform[base + 9], plant.leaf_xform[base + 10])
	var origin := Vector3(plant.leaf_xform[base + 3], plant.leaf_xform[base + 7], plant.leaf_xform[base + 11])
	var center := origin + bx * 0.2 + by * 0.45
	var normal := bz.normalized()
	if normal.length_squared() < 0.01:
		normal = Vector3(0.0, 0.0, 1.0)
	return {"center": center, "normal": normal, "bx": bx, "by": by}


func _capture_leaf_macro(main: Node, plant: PlantData, idx: int, dist: float, path: String) -> void:
	var frame := _leaf_frame(plant, idx)
	var center: Vector3 = frame["center"]
	var normal: Vector3 = frame["normal"]
	var bx: Vector3 = frame["bx"]
	## Slight lateral offset so the blade shows thickness (not straight-on decal).
	var lateral := bx.normalized() if bx.length_squared() > 1e-6 else Vector3.RIGHT
	var eye := center + normal * dist + lateral * 0.12 + Vector3(0.0, 0.08, 0.0)

	var cam := Camera3D.new()
	cam.name = "LeafMacroCam"
	cam.fov = _MACRO_FOV
	cam.near = 0.02
	(main.get_node("World") as Node3D).add_child(cam)
	cam.global_position = eye
	cam.look_at(center, Vector3.UP)
	cam.current = true

	await _settle(4)
	if not await _present_fresh_frame():
		printerr("[leaf-lookdev] no frame for ", path)
		cam.queue_free()
		return
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("[leaf-lookdev] save_png failed ", err, " ", path)
	else:
		print("[leaf-lookdev] saved ", path, " leaf_index=", idx, " size=", img.get_size())
	cam.queue_free()


func _hide_chrome(main: Node) -> void:
	var ui: CanvasLayer = main.get_node_or_null("UI") as CanvasLayer
	if ui != null:
		ui.visible = false
	var dev := main.get_node_or_null("DevUI")
	if dev != null:
		dev.visible = false


func _spawn_main() -> Node:
	var ps := load(_MAIN_SCENE) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", false)
	add_child(main)
	_keep_window_presenting()
	await _settle(35)
	return main


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
	await _settle(3)


func _dismiss_picker(ui: CanvasLayer) -> void:
	var picker := ui.get_node_or_null("BuildingPicker")
	if picker != null:
		picker.queue_free()


func _find_buttons(root: Node) -> Array:
	var out: Array = []
	if root is Button:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_buttons(c))
	return out


func _building_id_for_label(label: String) -> String:
	for entry in _BuildingCatalog.all():
		if entry.label == label:
			return entry.id
	return ""


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


func _keep_window_presenting() -> void:
	var w := get_window()
	if w == null:
		return
	if w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
