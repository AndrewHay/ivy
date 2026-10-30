extends Node3D

const _StructureScenario = preload("res://src/world/structure_scenario.gd")
const _Hud = preload("res://src/ui/hud.gd")
const _DevOverlay = preload("res://src/ui/dev_overlay.gd")
const _FieldViz = preload("res://src/ui/field_viz.gd")
const _BuildingPicker = preload("res://src/ui/building_picker.gd")
const GameModes = preload("res://src/world/game_modes.gd")
const _PlantingTool = preload("res://src/ui/planting_tool.gd")

const _LoadingOverlay = preload("res://src/ui/loading_overlay.gd")
const _DebugSessionLog = preload("res://src/debug/debug_session_log.gd")
const _SnapshotCapture = preload("res://src/debug/snapshot_capture.gd")
const _SnapshotRecipe = preload("res://src/debug/snapshot_recipe.gd")
const _SnapshotReplay = preload("res://src/debug/snapshot_replay.gd")
const _SnapshotAnnotationOverlay = preload("res://src/ui/snapshot_annotation_overlay.gd")

@export var params: IvyParams
@export var mesh_scenario: Resource

## Set by `tools/run_ui_script.gd` before the scene enters the tree. A scripted run
## drives ticks explicitly, so the clock must not also free-run on the frame delta.
var script_driven: bool = false

@onready var _world: Node3D = $World
@onready var _sim: Node = $Sim
@onready var _plant_render: Node3D = $PlantRender
@onready var _debug_camera: DebugCamera = $World/DebugCamera
@onready var _ui: CanvasLayer = $UI

var _hud: Control
var _dev_overlay: PanelContainer
var _field_viz: Node3D
var _planting_tool: Node3D
var _free_plant_mode: bool = false
var _loading_overlay: LoadingOverlay = null
var _session_log: RefCounted = null
var _snapshot_save_busy: bool = false
## Bumped when leaving for the picker so an in-flight interactive env build can abort.
var _bootstrap_generation: int = 0
var _snapshot_annotation_overlay: Control = null

## Village mode/seed (AR-VG-WIRE S4). Persists across return_to_picker.
var _village_mode: String = GameModes.CLASSIC
var _village_seed: int = 0
## Held while the picker is open so set_village_seed() can update the display (S5).
var _picker_ref: Control = null


func _enter_tree() -> void:
	if mesh_scenario == null:
		return
	var world := get_node_or_null("World")
	if world == null:
		return
	world.mesh_scenario = mesh_scenario


func _ready() -> void:
	if params == null:
		params = load("res://src/params/ivy_params_default.tres") as IvyParams
	if script_driven:
		await _bootstrap_simulation(true)
		return
	_show_building_picker()


func _show_building_picker() -> void:
	var picker := _BuildingPicker.new() as Control
	picker.name = "BuildingPicker"
	# Restore persisted mode so the toggle survives return_to_picker (AR-VG-WIRE).
	if picker.has_method("init_village_mode"):
		picker.call("init_village_mode", _village_mode)
	picker.building_selected.connect(_on_building_selected)
	if picker.has_signal("village_mode_changed"):
		picker.connect("village_mode_changed", _on_village_mode_changed)
	_picker_ref = picker
	_ui.add_child(picker)
	# Sync persisted seed display after _ready has built the label nodes.
	if _village_mode == GameModes.GENERATED and picker.has_method("set_village_seed"):
		picker.call("set_village_seed", _village_seed)


## Receives the picker toggle signal (AR-VG-WIRE S5).
## Rolls a fresh seed for GENERATED; zeroes seed for CLASSIC.
## Then calls back into the picker to update its display.
func _on_village_mode_changed(mode_id: String) -> void:
	_village_mode = mode_id
	if mode_id == GameModes.GENERATED:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_village_seed = rng.randi() & 0x7FFFFFFF
	else:
		_village_seed = 0
	if _picker_ref != null and is_instance_valid(_picker_ref) and _picker_ref.has_method("set_village_seed"):
		_picker_ref.call("set_village_seed", _village_seed)


func _on_building_selected(building_id: String) -> void:
	_picker_ref = null  # picker will queue_free itself
	var standalone := BuildingCatalog.standalone_scene_for(building_id)
	if not standalone.is_empty():
		get_tree().change_scene_to_file(standalone)
		return
	_bootstrap_generation += 1
	_session_log = null
	_loading_overlay = _LoadingOverlay.new()
	_loading_overlay.name = "LoadingOverlay"
	_ui.add_child(_loading_overlay)
	_set_loading_progress("Loading building…", 0.02)
	await _load_building(building_id)
	_set_loading_progress("Preparing simulation…", 0.05)
	var ok := await _start_free_plant_session()
	_dismiss_loading()
	if not ok:
		_show_build_failure()


## The building or its environment failed to build. Say so, and offer a way back instead of
## leaving the player on a dead-end screen.
func _show_build_failure() -> void:
	_loading_overlay = _LoadingOverlay.new()
	_loading_overlay.name = "LoadingOverlay"
	_ui.add_child(_loading_overlay)
	_loading_overlay.show_failure(
		"Environment build failed.\nCheck the Godot Output panel for errors.")
	_loading_overlay.back_requested.connect(_on_build_failure_back)


func _on_build_failure_back() -> void:
	_discard(_loading_overlay)
	_loading_overlay = null
	# Nothing of the failed session is up (no HUD, no tool), but the debug camera may have
	# been seeded; hand the view back to the authored camera and offer the picker again.
	_debug_camera.suspend()
	var authored := _world.get_node_or_null("CameraRig/CamSun") as Camera3D
	if authored != null:
		authored.make_current()
	_show_building_picker()


func _dismiss_loading() -> void:
	if _loading_overlay != null:
		_loading_overlay.queue_free()
		_loading_overlay = null


func _set_loading_progress(message: String, ratio: float) -> void:
	if _loading_overlay != null:
		_loading_overlay.set_progress(message, ratio)


func _load_building(building_id: String) -> void:
	if mesh_scenario != null and _world.mesh_scenario == null:
		_world.mesh_scenario = mesh_scenario
	# Push village mode/seed to World before load_building triggers rebuild_backdrop (AR-VG-WIRE).
	if _world.has_method("set_village_mode"):
		_world.call("set_village_mode", _village_mode, _village_seed)
	_world.load_building(building_id)
	await get_tree().physics_frame
	await get_tree().process_frame


## QA/dev hook: set village mode + seed and immediately rebuild the backdrop without
## reloading the building. Used by run_ui_script.gd VILLAGE_MODE verb and tools (AR-VG-WIRE).
func apply_village_mode_live(mode_id: String, seed: int) -> void:
	_village_mode = mode_id
	_village_seed = seed
	if _world.has_method("set_village_mode"):
		_world.call("set_village_mode", _village_mode, _village_seed)
	if _world.has_method("rebuild_backdrop"):
		_world.call("rebuild_backdrop")


func _bootstrap_simulation(auto_seed: bool) -> bool:
	var t0 := Time.get_ticks_msec()
	if mesh_scenario != null and _world.mesh_scenario == null:
		_world.mesh_scenario = mesh_scenario
	# Push village mode before building loads so rebuild_backdrop uses the right mode.
	# In script_driven runs the mode is set via --village-mode flag; in interactive runs
	# it is already pushed by _load_building before _bootstrap_simulation is called.
	if _world.has_method("set_village_mode"):
		_world.call("set_village_mode", _village_mode, _village_seed)
	_world.ensure_mesh_scenario_loaded()
	# Collision shapes — ConcavePolygonShape3D trimeshes from StructureBody.build() on the
	# mesh path, the Tower/Wall trimeshes on the procedural path, and the WorldBoundaryShape3D
	# Ground plane present in all paths — are not queryable until the physics server commits
	# them. One physics_frame unconditionally covers all paths.
	#
	# ivy-hsu: the mesh-scenario path previously had this await; ivy-2ey: the procedural path
	# (mesh_scenario == null, script_driven=true via run_ui_script.gd) skipped it entirely
	# because the whole block was guarded by `if mesh_scenario != null`. Without the await the
	# light bake's horizon-escape raycasts ran against uncommitted geometry — near-ground cells
	# baked leak=1.0 (all rays escaped) instead of the correct ~0.917.
	#
	# ensure_mesh_scenario_loaded() is idempotent (_tower_built/_wall_built/_structure guards),
	# so calling it here is safe even when _load_building has already called it (interactive
	# picker path). The extra physics_frame on that path is a harmless single-frame wait.
	await get_tree().physics_frame
	await get_tree().process_frame
	var surface: SurfaceQuery = _world.get_surface_query(params)
	if surface == null:
		push_error("Main: surface query failed during bootstrap")
		return false
	if _free_plant_mode:
		var gen := _bootstrap_generation
		var alive := func() -> bool:
			return gen == _bootstrap_generation
		await _sim.setup_interactive(
			params,
			surface,
			get_tree(),
			_set_loading_progress,
			_world.get_mesh_scenario(),
			_world.get_seed_index(),
			_world.get_seed_anchors(),
			auto_seed,
			alive
		)
		if not alive.call():
			push_warning("Main: interactive bootstrap cancelled (returned to picker)")
			return false
	else:
		_sim.setup(
			params,
			surface,
			_world.get_mesh_scenario(),
			_world.get_seed_index(),
			_world.get_seed_anchors(),
			auto_seed
		)
	_plant_render.setup(params)
	_debug_camera.setup(_world.tower_spec, _world.get_debug_camera_zoom_bounds())
	_debug_camera.set_surface_query(surface)
	_world.get_sky_sun().setup(_sim.solar)
	if not script_driven and not _free_plant_mode:
		_sim.get_clock().set_speed(SimClock.Speed.GROW)
	print("[ivy] bootstrap %d ms (building=%s)" % [
		Time.get_ticks_msec() - t0,
		_world.uses_mesh_backend() if _world.has_method("uses_mesh_backend") else "?"
	])
	return true


func _start_free_plant_session() -> bool:
	_free_plant_mode = true
	var ok := await _bootstrap_simulation(false)
	_dismiss_loading()
	if not ok:
		return false
	# Stay paused while the player aims; growth starts on first plant.
	_sim.get_clock().set_speed(SimClock.Speed.PAUSE)
	_debug_camera.set_orbit_pivot(_world.get_orbit_pivot())
	_debug_camera.activate_for_planting()
	_hud = _Hud.new() as Control
	_hud.name = "Hud"
	_ui.add_child(_hud)
	_session_log = _DebugSessionLog.new()
	_hud.change_building_requested.connect(return_to_picker)
	_hud.debug_snapshot_requested.connect(_on_debug_snapshot_requested)
	_hud.setup(_world, _sim, params, true, _session_log)
	_refresh_snapshot_controls()
	if params.dev_build:
		_setup_dev_tools()
	_planting_tool = _PlantingTool.new()
	_planting_tool.name = "PlantingTool"
	_world.add_child(_planting_tool)
	_planting_tool.setup(_world, _sim, params, _debug_camera)
	(_planting_tool as PlantingTool).planted_at.connect(_on_planted_at)
	if _hud.has_method("set_planting_tool"):
		_hud.set_planting_tool(_planting_tool as PlantingTool)
	return true


func _on_planted_at(position: Vector3, normal: Vector3) -> void:
	if _session_log != null:
		_session_log.record_plant(_sim.get_clock().tick_index, position, normal)
	_sim.plant_at(position, normal)
	_on_plant_success()


func _on_plant_success() -> void:
	_finish_planting_session()
	var clock: SimClock = _sim.get_clock()
	clock.tick_index = 0
	clock._accumulator = 0.0
	clock._update_game_day()
	clock.set_speed(SimClock.Speed.GROW)
	print(
		"[ivy] planted tips=%d segments=%d (grow speed on)"
		% [_sim.tips.tips.size(), _sim.plant.segment_count()]
	)


func _try_plant_input(event: InputEvent) -> bool:
	if _snapshot_annotation_overlay != null:
		return false
	if _planting_tool == null:
		return false
	var tool := _planting_tool as PlantingTool
	if tool == null:
		return false
	if tool.try_plant(event):
		get_viewport().set_input_as_handled()
		return true
	return false


func _finish_planting_session() -> void:
	if _planting_tool != null:
		var tool := _planting_tool as PlantingTool
		if tool != null:
			tool.retire()
		_planting_tool.queue_free()
		_planting_tool = null
	if _hud != null and _hud.has_method("finish_planting_mode"):
		_hud.finish_planting_mode()
	_debug_camera.finish_planting()


## Leave the current building and show the picker again. Undoes everything
## `_start_free_plant_session` set up, so the next pick starts from a clean slate. The grown
## plant is discarded; there is no save/load (DESIGN.md non-goals).
func return_to_picker() -> void:
	if script_driven or _hud == null:
		return  # no interactive session to leave (also stops a double press)
	_bootstrap_generation += 1
	_finish_planting_session()  # tool + its camera/HUD hooks, if the player never planted
	_discard(_hud)
	_hud = null
	if _dev_overlay != null:
		_discard(_dev_overlay.get_parent())  # the DevUI CanvasLayer that owns it
		_dev_overlay = null
	if _field_viz != null:
		_discard(_field_viz)
		_field_viz = null
	# Stop ticking and wipe the drawn plant; clear_plants resets the renderer too, and
	# SimRoot would otherwise redraw the old plant on its next frame.
	var clock: SimClock = _sim.get_clock()
	if clock != null:
		clock.set_speed(SimClock.Speed.PAUSE)
	_sim.clear_plants()
	_session_log = null
	# The debug camera must not answer keys behind the picker; give the view back to the
	# authored camera (made current here so debug_camera.gd keeps its write-only-in-input rule).
	_debug_camera.suspend()
	var authored := _world.get_node_or_null("CameraRig/CamSun") as Camera3D
	if authored != null:
		authored.make_current()
	_show_building_picker()


## Remove a node right now (so names are free for the next session) and free it.
func _discard(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


func _setup_dev_tools() -> void:
	var dev_layer := CanvasLayer.new()
	dev_layer.layer = 10
	dev_layer.name = "DevUI"
	add_child(dev_layer)
	_dev_overlay = _DevOverlay.new()
	_dev_overlay.name = "DevOverlay"
	dev_layer.add_child(_dev_overlay)
	_dev_overlay.setup(_sim, params, func(tick: int, name: String, value: Variant) -> void:
		if _session_log != null:
			_session_log.record_param(tick, name, value)
	)
	if _dev_overlay.has_method("set_village_info"):
		_dev_overlay.call("set_village_info", _village_mode, _village_seed)
	_field_viz = _FieldViz.new() as Node3D
	_field_viz.name = "FieldViz"
	_world.add_child(_field_viz)
	_field_viz.setup(_sim)


func _unhandled_input(event: InputEvent) -> void:
	if _snapshot_annotation_overlay != null:
		if event is InputEventKey and event.pressed and not event.echo:
			var key := event as InputEventKey
			if _snapshot_annotation_overlay.has_method("handle_key_event"):
				if _snapshot_annotation_overlay.call("handle_key_event", key):
					get_viewport().set_input_as_handled()
		return
	if _try_plant_input(event):
		return
	if not script_driven and (
		_handle_help_key(event)
		or _handle_time_hotkey(event)
		or _handle_snapshot_key(event)
	):
		return
	if script_driven or params == null or not params.dev_build:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F:
			if _field_viz != null and _field_viz.has_method("toggle"):
				_field_viz.toggle()
				get_viewport().set_input_as_handled()
		KEY_QUOTELEFT:
			if _dev_overlay != null and _dev_overlay.has_method("toggle_visible"):
				_dev_overlay.toggle_visible()
				get_viewport().set_input_as_handled()


## `?` or F1 toggles the keyboard-commands popup; Esc closes it. Works from the moment the
## HUD exists, including while the player is still aiming. `?` is Shift+/, which Godot reports
## as the slash keycode plus the character 63, so it is matched on the character.
func _handle_help_key(event: InputEvent) -> bool:
	if _hud == null or not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	if key.keycode == KEY_F1 or key.keycode == KEY_QUESTION or key.unicode == 63:
		_hud.toggle_help()
	elif key.keycode == KEY_ESCAPE and _hud.is_help_open():
		_hud.close_help()
	else:
		return false
	get_viewport().set_input_as_handled()
	return true


## Space toggles pause, 1/2/3 select Watch/Fast/Grow. Inactive until the player has planted:
## while aiming the clock is deliberately paused and there is no plant to run.
func _snapshot_available() -> bool:
	if script_driven or params == null or not params.dev_build or _hud == null:
		return false
	if _ui.get_node_or_null("BuildingPicker") != null:
		return false
	if _loading_overlay != null:
		return false
	if _snapshot_annotation_overlay != null:
		return false
	return true


func _refresh_snapshot_controls() -> void:
	if _hud != null and _hud.has_method("set_snapshot_enabled"):
		_hud.set_snapshot_enabled(_snapshot_available())


func _handle_snapshot_key(event: InputEvent) -> bool:
	if not _snapshot_available() or not event is InputEventKey:
		return false
	if _hud.is_help_open():
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_F9:
		return false
	_queue_snapshot_save(key.shift_pressed)
	get_viewport().set_input_as_handled()
	return true


func _on_debug_snapshot_requested() -> void:
	_queue_snapshot_save(false)


func _queue_snapshot_save(quick: bool) -> void:
	if _snapshot_save_busy or not _snapshot_available():
		return
	_snapshot_save_busy = true
	_co_snapshot_save(quick)


func _co_snapshot_save(quick: bool) -> void:
	await _save_debug_snapshot(quick)
	_snapshot_save_busy = false
	_snapshot_annotation_overlay = null
	_refresh_snapshot_controls()


## Script-driven replay entry (SNAPSHOT_LOAD / replay_snapshot tool).
func load_snapshot_recipe(recipe) -> Dictionary:
	# Apply village mode/seed before _load_building so World.set_village_mode is set first
	# (AR-VG-WIRE: _load_building calls set_village_mode → rebuild_backdrop on the mode).
	_village_mode = str(recipe.scene.get("village_mode", GameModes.CLASSIC))
	_village_seed = int(recipe.scene.get("village_seed", 0))
	await _load_building(str(recipe.scene.get("building_id", "cylinder")))
	_free_plant_mode = bool(recipe.scene.get("free_plant_mode", true))
	_world.set_seed_index(int(recipe.scene.get("seed_index", 0)))
	var ok := await _bootstrap_simulation(false)
	if not ok:
		return {"ok": false, "reason": "bootstrap failed"}
	_sim.set_seed_index(int(recipe.scene.get("seed_index", 0)))
	_SnapshotReplay.replay_to_tick(_sim, params, recipe)
	var verdict: Dictionary = _SnapshotReplay.verify_fingerprint(_sim, recipe)
	_SnapshotReplay.restore_camera(self, recipe)
	return {"ok": true, "verdict": verdict}


func load_snapshot_from_dir(spec: String) -> Dictionary:
	var dir := _SnapshotReplay.resolve_dir(spec)
	if dir.is_empty():
		return {"ok": false, "reason": "snapshot not found: %s" % spec}
	var recipe = _SnapshotRecipe.read_json(dir.path_join("snapshot.json"))
	if recipe == null:
		return {"ok": false, "reason": "invalid snapshot.json in %s" % dir}
	var result := await load_snapshot_recipe(recipe)
	result["dir"] = dir
	result["recipe"] = recipe
	return result


func _save_debug_snapshot(quick: bool) -> void:
	var clock: SimClock = _sim.get_clock()
	var prior_speed := clock.speed
	clock.set_speed(SimClock.Speed.PAUSE)
	var prior_sun_day := clock.display_game_day()
	_apply_snapshot_sun_noon(clock)
	for _i in range(3):
		await get_tree().process_frame
	var img: Image = _capture_viewport_image()
	_world.get_sky_sun().update(prior_sun_day, clock.seconds_per_game_day())
	if img == null:
		push_error("Main: snapshot failed — no viewport image")
		clock.set_speed(prior_speed)
		return
	var display_size := get_viewport().get_visible_rect().size
	var annotations: Array = []
	var note := ""
	var annotated_img: Image = null
	if not quick:
		var frozen := _SnapshotCapture.image_for_display(img, display_size)
		var result := await _run_snapshot_annotation_ui(frozen, display_size, img)
		if not result.get("cancelled", true):
			annotated_img = result.get("annotated_image") as Image
			annotations = result.get("annotations", [])
			note = str(result.get("note", ""))
		if result.get("cancelled", true):
			clock.set_speed(prior_speed)
			return
	print("[snapshot] writing files…")
	var recipe = _SnapshotCapture.build_recipe(self, _session_log, _free_plant_mode, note)
	recipe.annotations = _SnapshotCapture.enrich_annotations(self, _sim, annotations, display_size)
	var folder_name := _SnapshotCapture.make_folder_name(
		recipe.scene.get("building_id", "unknown"),
		float(recipe.time.get("game_day", 0.0))
	)
	var dir_path := _SnapshotCapture.write_snapshot(recipe, img, folder_name, annotated_img)
	clock.set_speed(prior_speed)
	await _notify_snapshot_saved(dir_path)


func _notify_snapshot_saved(dir_path: String) -> void:
	if dir_path.is_empty():
		push_error("Main: snapshot save failed (no output folder)")
		return
	var line := "[snapshot] saved %s" % dir_path
	print(line)
	print_rich("[color=#8fd49a]%s[/color]" % line)
	if _hud != null and _hud.has_method("show_snapshot_toast"):
		await get_tree().process_frame
		_hud.show_snapshot_toast(dir_path)
	DisplayServer.clipboard_set(dir_path)


func _close_snapshot_annotation_window(win: Window) -> void:
	if win == null or not is_instance_valid(win):
		return
	win.hide()
	win.queue_free()


func _focus_snapshot_window(win: Window, overlay: Control) -> void:
	call_deferred("_focus_snapshot_window_deferred", win, overlay)


func _focus_snapshot_window_deferred(win: Window, overlay: Control) -> void:
	if win != null and win.is_inside_tree():
		win.grab_focus()
	if overlay != null and overlay.is_inside_tree():
		overlay.grab_focus()


func _apply_snapshot_sun_noon(clock: SimClock) -> void:
	var solar := Solar.new(params)
	var day := clock.display_game_day()
	var hour := solar.hour_of_day(day)
	var delta_h := 12.0 - hour
	if delta_h > 12.0:
		delta_h -= 24.0
	elif delta_h < -12.0:
		delta_h += 24.0
	var noon_day := day + delta_h / 24.0
	_world.get_sky_sun().update(noon_day, clock.seconds_per_game_day())


func _capture_viewport_image() -> Image:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var tex := get_viewport().get_texture()
	if tex == null:
		return null
	return tex.get_image()


func _run_snapshot_annotation_ui(frozen: Image, display_size: Vector2, full_image: Image) -> Dictionary:
	var result := {
		"cancelled": true,
		"annotations": [],
		"note": "",
		"annotated_image": null,
	}
	if frozen == null:
		return result
	var win := Window.new()
	win.title = "Snapshot highlights"
	win.borderless = true
	win.unresizable = true
	win.wrap_controls = true
	win.exclusive = true
	win.size = Vector2i(maxi(1, int(display_size.x)), maxi(1, int(display_size.y)))
	add_child(win)
	var overlay := _SnapshotAnnotationOverlay.new()
	_snapshot_annotation_overlay = overlay
	win.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.setup(frozen, display_size)
	_refresh_snapshot_controls()
	win.popup_centered(win.size)
	_focus_snapshot_window(win, overlay)
	overlay.completed.connect(func(annotations: Array, note: String) -> void:
		var annotated: Image = null
		if is_instance_valid(overlay) and full_image != null:
			annotated = overlay.render_annotated_image(full_image)
		result["cancelled"] = false
		result["annotations"] = annotations
		result["note"] = note
		result["annotated_image"] = annotated
		_close_snapshot_annotation_window(win)
	, CONNECT_ONE_SHOT)
	overlay.cancelled.connect(func() -> void:
		result["cancelled"] = true
		result["annotations"] = []
		result["note"] = ""
		result["annotated_image"] = null
		_close_snapshot_annotation_window(win)
	, CONNECT_ONE_SHOT)
	while is_instance_valid(win) and win.is_inside_tree():
		await get_tree().process_frame
	_snapshot_annotation_overlay = null
	_refresh_snapshot_controls()
	return result


func _handle_time_hotkey(event: InputEvent) -> bool:
	if _hud == null or _planting_tool != null or _sim == null:
		return false
	if not event is InputEventKey or not event.pressed or event.echo:
		return false
	var clock: SimClock = _sim.get_clock()
	if clock == null:
		return false
	var keycode: Key = (event as InputEventKey).keycode
	if keycode == KEY_SPACE:
		clock.toggle_pause()
	else:
		var speed := SimClock.speed_for_hotkey(keycode)
		if speed < 0:
			return false
		clock.set_speed(speed as SimClock.Speed)
	get_viewport().set_input_as_handled()
	return true


func _tick_fauna(clock: SimClock, delta: float) -> void:
	if not FaunaIntegration.world_runtime_enabled():
		return
	var fauna: FaunaController = _world.get_fauna_controller()
	if fauna == null:
		return
	var sky: SkySun = _world.get_sky_sun()
	if sky.solar == null:
		return
	var game_day := clock.display_game_day()
	var spd := clock.seconds_per_game_day()
	var s: Vector3 = sky.solar.render_direction(game_day, spd)
	var ctx := FaunaPresentationContext.new()
	ctx.game_day = game_day
	ctx.local_solar_hour = sky.solar.hour_of_day(game_day)
	ctx.lit = SkySun.lit_for(s.y)
	ctx.render_blend = sky.solar.render_blend(spd)
	ctx.weather_activity_scale = 1.0
	ctx.wind = _world.get_ambient_wind()
	ctx.pivot_global_position = _world.get_orbit_pivot()
	var cam := get_viewport().get_camera_3d()
	ctx.camera_global_position = cam.global_position if cam != null else _debug_camera.global_position
	var backdrop := _world.get_node_or_null("VillageBackdrop")
	if backdrop != null and backdrop.visible:
		ctx.backdrop_global_transform = backdrop.global_transform
	ctx.paused = clock.speed == SimClock.Speed.PAUSE
	fauna.tick(ctx, delta)


func _process(delta: float) -> void:
	if not _sim.has_method("get_clock"):
		return
	var clock: SimClock = _sim.get_clock()
	if clock == null:
		return
	_world.get_sky_sun().update(clock.display_game_day(), clock.seconds_per_game_day())
	var wind: AmbientWind = _world.get_ambient_wind()
	if wind != null:
		wind.advance(clock.speed, delta)
		wind.push_shader_globals()
	_tick_fauna(clock, delta)
	if _hud != null:
		_hud.refresh(clock, _world.get_sky_sun(), _debug_camera.get_yaw(), wind)
	if _dev_overlay != null and _dev_overlay.has_method("refresh"):
		_dev_overlay.refresh(clock)
