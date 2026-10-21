extends Node3D

const _StructureScenario = preload("res://src/world/structure_scenario.gd")
const _Hud = preload("res://src/ui/hud.gd")
const _DevOverlay = preload("res://src/ui/dev_overlay.gd")
const _FieldViz = preload("res://src/ui/field_viz.gd")
const _BuildingPicker = preload("res://src/ui/building_picker.gd")
const _PlantingTool = preload("res://src/ui/planting_tool.gd")

const _LoadingOverlay = preload("res://src/ui/loading_overlay.gd")

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
	picker.building_selected.connect(_on_building_selected)
	_ui.add_child(picker)


func _on_building_selected(building_id: String) -> void:
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
	_world.load_building(building_id)
	await get_tree().physics_frame
	await get_tree().process_frame


func _bootstrap_simulation(auto_seed: bool) -> bool:
	var t0 := Time.get_ticks_msec()
	if mesh_scenario != null and _world.mesh_scenario == null:
		_world.mesh_scenario = mesh_scenario
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
		await _sim.setup_interactive(
			params,
			surface,
			get_tree(),
			_set_loading_progress,
			_world.get_mesh_scenario(),
			_world.get_seed_index(),
			_world.get_seed_anchors(),
			auto_seed
		)
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
	_hud.change_building_requested.connect(return_to_picker)
	_hud.setup(_world, _sim, params, true)
	if params.dev_build:
		_setup_dev_tools()
	_planting_tool = _PlantingTool.new()
	_planting_tool.name = "PlantingTool"
	_world.add_child(_planting_tool)
	_planting_tool.setup(_world, _sim, params, _debug_camera)
	(_planting_tool as PlantingTool).planted.connect(_on_plant_success)
	if _hud.has_method("set_planting_tool"):
		_hud.set_planting_tool(_planting_tool as PlantingTool)
	return true


func _on_plant_success() -> void:
	_finish_planting_session()
	var clock: SimClock = _sim.get_clock()
	clock.tick_index = 0
	clock._update_game_day()
	clock.set_speed(SimClock.Speed.GROW)
	print(
		"[ivy] planted tips=%d segments=%d (grow speed on)"
		% [_sim.tips.tips.size(), _sim.plant.segment_count()]
	)


func _try_plant_input(event: InputEvent) -> bool:
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
	_dev_overlay.setup(_sim, params)
	_field_viz = _FieldViz.new() as Node3D
	_field_viz.name = "FieldViz"
	_world.add_child(_field_viz)
	_field_viz.setup(_sim)


func _unhandled_input(event: InputEvent) -> void:
	if _try_plant_input(event):
		return
	if not script_driven and (_handle_help_key(event) or _handle_time_hotkey(event)):
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


func _process(_delta: float) -> void:
	if not _sim.has_method("get_clock"):
		return
	var clock: SimClock = _sim.get_clock()
	if clock == null:
		return
	_world.get_sky_sun().update(clock.display_game_day(), clock.seconds_per_game_day())
	if _hud != null:
		_hud.refresh(clock, _world.get_sky_sun(), _debug_camera.get_yaw())
	if _dev_overlay != null and _dev_overlay.has_method("refresh"):
		_dev_overlay.refresh(clock)
