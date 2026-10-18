extends Node

## Non-headless capture tool for the overhang (eave-wall) fixture (ivy-9us).
##
## Plants 5 seeds at x in {-4,-2,0,2,4}, y=0.05, z=0.01, grows to day 100.25
## (local noon), then captures:
##   profile.png       — +X looking -X (wall face / soffit / eave lip side view)
##   straight_on.png   — +Z looking -Z (lateral fan-out elevation)
##
## Non-headless only (--headless produces no image on macOS).
##
## Usage:
##   Godot res://tools/capture_eave_wall.tscn -- --day=100 --label=eave_wall
##
## Output: res://.tmp/eave_wall/  (globalised before save)

const _MAIN_SCENE := "res://src/main/main.tscn"
const _OUTDIR := "res://.tmp/eave_wall/"
const _TICKS_PER_DAY := 24
const _PRESENT_TIMEOUT_MS := 4000

const _SEED_XS: Array = [-4.0, -2.0, 0.0, 2.0, 4.0]
const _SEED_Y := 0.05
const _SEED_Z := 0.01


func _ready() -> void:
	var args := _parse_args()
	var label: String = args.get("label", "eave_wall")
	var day: int = int(args.get("day", 100))
	var outdir := ProjectSettings.globalize_path(_OUTDIR)
	DirAccess.make_dir_recursive_absolute(outdir)

	var main := await _spawn_main()

	## Select the overhang building
	await _select_building(main, "overhang")
	if not await _wait_for_free_plant(main, 600000):
		printerr("[eave-wall] overhang load timed out")
		get_tree().quit(1)
		return

	## C-1: Pause the real-time clock before planting/advancing so only our
	## explicit advance_ticks call drives simulation time. _on_plant_success
	## sets GROW; re-pause immediately after.
	var sim: Node = main.get_node("Sim")
	var clock: SimClock = sim.get_clock()
	clock.set_speed(SimClock.Speed.PAUSE)

	var params: IvyParams = main.get("params") as IvyParams
	for x in _SEED_XS:
		sim.plant_at(Vector3(x, _SEED_Y, _SEED_Z), Vector3(0, 0, 1))
	if main.has_method("_on_plant_success"):
		main.call("_on_plant_success")
	## Re-pause: _on_plant_success sets Speed.GROW; keep clock paused for both captures.
	clock.set_speed(SimClock.Speed.PAUSE)
	await _settle(5)

	## Advance to day N.25 (local noon)
	var ticks: int = _TICKS_PER_DAY * day + 6
	var t0 := Time.get_ticks_msec()
	sim.advance_ticks(ticks)
	var elapsed_ms := Time.get_ticks_msec() - t0
	await _settle(10)

	var plant: PlantData = sim.get("plant") as PlantData
	var tips = sim.get("tips")
	print("[eave-wall] day=%d elapsed_ms=%d total_length=%.3f segs=%d tips_live=%d" % [
		day, elapsed_ms, plant.total_length, plant.segment_count(), tips.live_count()])

	## PROFILE shot: +X looking -X, framing wall face / soffit / lip
	## eye=(11,3.0,0.5), look_at=(0,3.0,0.5), fov=45
	await _capture(
		main,
		outdir.path_join("%s_profile.png" % label),
		Vector3(11.0, 3.0, 0.5), Vector3(0.0, 3.0, 0.5), 45.0
	)

	## EAVE close-up: below and in front of the lip, looking up at soffit + lip
	await _capture(
		main,
		outdir.path_join("%s_eave_closeup.png" % label),
		Vector3(-1.0, 4.2, 2.4), Vector3(-1.0, 4.9, 0.4), 60.0
	)

	## EAVE edge-on: along the lip from the west end, low, to see droop past the lip
	await _capture(
		main,
		outdir.path_join("%s_eave_edge.png" % label),
		Vector3(-9.5, 4.6, 2.2), Vector3(-3.0, 5.0, 0.6), 40.0
	)

	## STRAIGHT-ON shot: +Z looking -Z (lateral fan-out elevation)
	## Frame the 16x5 m wall face + 0.3 m slab plus a small margin.
	await _capture_straight_on(main, outdir.path_join("%s_straight_on.png" % label))

	main.queue_free()
	print("[eave-wall] done — outputs in %s" % outdir)
	get_tree().quit(0)


func _capture(main: Node, path: String, eye: Vector3, target: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	(main.get_node("World") as Node3D).add_child(cam)
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.current = true
	await _settle(4)
	if not await _present_fresh_frame():
		printerr("[eave-wall] no frame for ", path)
		cam.queue_free()
		return
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("[eave-wall] save_png failed ", err, " ", path)
	else:
		print("[eave-wall] saved ", path, " size=", img.get_size())
	cam.queue_free()


func _capture_straight_on(main: Node, path: String) -> void:
	## Data-driven framing for a 16×5.3 m wall face (wall + slab) from +Z.
	## 16:9 viewport; 40% margin.
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	(main.get_node("World") as Node3D).add_child(cam)
	var half_w := 8.0   # wall_length / 2
	var half_h := 2.65  # (wall_height + slab_thickness) / 2 = 5.3 / 2
	var aim_y  := half_h  # centre of the combined shape
	var vfov_half := deg_to_rad(cam.fov * 0.5)
	var hfov_half := atan(tan(vfov_half) * 16.0 / 9.0)
	var dist_w := half_w / tan(hfov_half)
	var dist_h := half_h / tan(vfov_half)
	var dist := maxf(dist_w, dist_h) * 1.4
	cam.global_position = Vector3(0.0, aim_y, dist)
	cam.look_at(Vector3(0.0, aim_y, 0.0), Vector3.UP)
	cam.current = true
	await _settle(4)
	if not await _present_fresh_frame():
		printerr("[eave-wall] no frame for ", path)
		cam.queue_free()
		return
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("[eave-wall] save_png failed ", err, " ", path)
	else:
		print("[eave-wall] saved ", path, " size=", img.get_size())
	cam.queue_free()


func _spawn_main() -> Node:
	var ps := load(_MAIN_SCENE) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", false)
	add_child(main)
	_keep_window_presenting()
	await _settle(35)
	return main


func _select_building(main: Node, building_id: String) -> void:
	const _BuildingCatalog = preload("res://src/world/building_catalog.gd")
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
		var ui2: CanvasLayer = main.get_node_or_null("UI") as CanvasLayer
		if ui2 != null:
			var picker2 := ui2.get_node_or_null("BuildingPicker")
			if picker2 != null:
				picker2.queue_free()
	await _settle(3)


func _find_buttons(root: Node) -> Array:
	var out: Array = []
	if root is Button:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_buttons(c))
	return out


func _building_id_for_label(label_text: String) -> String:
	const _BuildingCatalog = preload("res://src/world/building_catalog.gd")
	for entry in _BuildingCatalog.all():
		if entry.label == label_text:
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
