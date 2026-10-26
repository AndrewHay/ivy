class_name Hud
extends Control

## SD-AGENCY player controls: anchors, pause + three speeds, date/time, time-lapse flag.

## Player asked to leave this building and pick another. Main owns the teardown.
signal change_building_requested
signal debug_snapshot_requested

const SeedAnchorsScript = preload("res://src/world/seed_anchors.gd")
const _HelpPanel = preload("res://src/ui/help_panel.gd")
const _SunCompass = preload("res://src/ui/sun_compass.gd")
## Gap between the compass and the window edge.
const _COMPASS_MARGIN := 12.0
const _CAMERA_HINT := "Click surface to move origin · scroll zoom · Tab mouse-look · WASD/arrows rotate · R reset · ? help"

var _world: Node = null
var _sim: Node = null
var _params: IvyParams = null
var _anchor_buttons: Array[Button] = []
var _speed_buttons: Dictionary = {}
var _date_label: Label = null
var _timelapse_label: Label = null
var _night_growth_label: Label = null
var _scenario_seed_count: int = 0
var _free_plant_mode: bool = false
var _anchor_row: HBoxContainer = null
var _clear_button: Button = null
var _plant_hint: Label = null
var _plant_debug: Label = null
var _sim_status: Label = null
var _planting_tool: PlantingTool = null
var _help_panel: PanelContainer = null
var _sun_compass: Control = null
var _session_log: RefCounted = null
var _snapshot_button: Button = null
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_timer: Timer = null


func set_planting_tool(tool: PlantingTool) -> void:
	_planting_tool = tool


func plant_hint_text() -> String:
	return _plant_hint.text if _plant_hint != null else ""


func is_plant_hint_visible() -> bool:
	return _plant_hint != null and _plant_hint.visible


func finish_planting_mode() -> void:
	_planting_tool = null
	if _plant_hint != null:
		_plant_hint.visible = false
	if _plant_debug != null:
		_plant_debug.visible = false
	if _anchor_row != null:
		for child in _anchor_row.get_children():
			if child is Label:
				(child as Label).text = _CAMERA_HINT


func setup(
	world: Node,
	sim: Node,
	params: IvyParams,
	free_plant_mode: bool = false,
	session_log: RefCounted = null
) -> void:
	_world = world
	_sim = sim
	_params = params
	_free_plant_mode = free_plant_mode
	_session_log = session_log
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if free_plant_mode:
		_build_help()
		_build_sun_compass()
	_refresh_anchor_buttons()


func get_sun_compass() -> Control:
	return _sun_compass


## Bottom-left corner. Placed by hand for the same reason as the help popup: this Control is
## full-rect under a CanvasLayer, so anchor presets on its children would resolve to nothing.
func _build_sun_compass() -> void:
	_sun_compass = _SunCompass.new()
	add_child(_sun_compass)
	_place_sun_compass()
	get_viewport().size_changed.connect(_place_sun_compass)


func _place_sun_compass() -> void:
	if _sun_compass == null:
		return
	var viewport := get_viewport_rect().size
	_sun_compass.position = Vector2(
		_COMPASS_MARGIN, viewport.y - _sun_compass.size.y - _COMPASS_MARGIN
	).floor()


func toggle_help() -> void:
	if _help_panel == null:
		return
	_help_panel.visible = not _help_panel.visible
	if _help_panel.visible:
		_center_help()


func close_help() -> void:
	if _help_panel != null:
		_help_panel.visible = false


func set_snapshot_enabled(enabled: bool) -> void:
	if _snapshot_button != null:
		_snapshot_button.disabled = not enabled


func show_snapshot_toast(dir_path: String) -> void:
	if _toast_label == null or _toast_panel == null:
		push_warning("Hud: snapshot toast UI missing (dev_build off?)")
		return
	_toast_label.text = "Screenshot saved\n%s" % dir_path
	_toast_panel.visible = true
	_toast_panel.move_to_front()
	_position_snapshot_toast()
	if _toast_timer != null:
		_toast_timer.start()


func _position_snapshot_toast() -> void:
	if _toast_panel == null:
		return
	var margin := 16.0
	var vp := get_viewport_rect().size
	_toast_panel.size = _toast_panel.get_combined_minimum_size()
	_toast_panel.position = Vector2(
		vp.x - _toast_panel.size.x - margin,
		margin
	)


func is_help_open() -> bool:
	return _help_panel != null and _help_panel.visible


func get_help_panel() -> PanelContainer:
	return _help_panel


## The popup sits over everything else in the HUD. It is positioned by hand because a
## full-rect Control under a CanvasLayer is not sized by anchors alone here, so a
## CenterContainer would collapse into the top-left corner. Only the panel takes clicks.
func _build_help() -> void:
	_help_panel = _HelpPanel.new()
	_help_panel.build(_params != null and _params.dev_build)
	add_child(_help_panel)
	get_viewport().size_changed.connect(_center_help)


func _center_help() -> void:
	if _help_panel == null or not _help_panel.visible:
		return
	_help_panel.size = _help_panel.get_combined_minimum_size()
	_help_panel.position = ((get_viewport_rect().size - _help_panel.size) * 0.5).floor()


## `camera_yaw` turns the sun compass so its top is the way the camera is looking.
func refresh(clock: SimClock, sky_sun: SkySun, camera_yaw: float = 0.0) -> void:
	if _sun_compass != null and sky_sun != null and sky_sun.solar != null and clock != null:
		_sun_compass.set_sun(
			sky_sun.solar.render_direction(clock.display_game_day(), clock.seconds_per_game_day()),
			camera_yaw
		)
	if _date_label != null and clock != null and _params != null:
		var display_day := clock.display_game_day()
		var hour := display_day * 24.0 + _params.start_hour
		var day_num := int(floor(display_day)) + 1
		var hour_i := int(floor(fposmod(hour, 24.0)))
		var minute_i := int(floor(fposmod(hour * 60.0, 60.0)))
		_date_label.text = "Day %d  %02d:%02d" % [day_num, hour_i, minute_i]
	if _planting_tool != null:
		if _plant_hint != null:
			_plant_hint.text = _planting_tool.player_hint_text()
		if _plant_debug != null:
			_plant_debug.text = _planting_tool.debug_status()
	if _sim_status != null and _sim != null and clock != null:
		var tips_n := 0
		var segs := 0
		if _sim.get("tips") != null:
			tips_n = (_sim.tips as TipManager).tips.size()
		if _sim.get("plant") != null:
			segs = (_sim.plant as PlantData).segment_count()
		_sim_status.text = "tips=%d  segments=%d  speed=%s" % [
			tips_n, segs, _speed_label(clock.speed)
		]
	if _timelapse_label != null and sky_sun != null and clock != null:
		var show := sky_sun.is_time_lapse(clock.seconds_per_game_day())
		_timelapse_label.visible = show
	if _night_growth_label != null and sky_sun != null and sky_sun.solar != null and clock != null:
		var night := sky_sun.solar.is_geometric_night(clock.display_game_day())
		_night_growth_label.visible = night and clock.speed != SimClock.Speed.PAUSE


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	if _params != null and _params.dev_build:
		_build_snapshot_toast()
		get_viewport().size_changed.connect(_position_snapshot_toast)

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)

	_build_anchor_row(root)
	_build_speed_row(root)
	_date_label = _make_passthrough_label("Day 1  06:00")
	root.add_child(_date_label)
	_timelapse_label = _make_passthrough_label("time-lapse — average daylight")
	_timelapse_label.visible = false
	root.add_child(_timelapse_label)
	_night_growth_label = _make_passthrough_label("night — too little light to grow")
	_night_growth_label.add_theme_font_size_override("font_size", 11)
	_night_growth_label.visible = false
	root.add_child(_night_growth_label)
	if _free_plant_mode:
		# What the player needs while aiming: plain language, always shown.
		_plant_hint = _make_passthrough_label("")
		_plant_hint.add_theme_font_size_override("font_size", 18)
		root.add_child(_plant_hint)
		# Raycast details (tips=…, hover=…) are for developers only.
		if _params != null and _params.dev_build:
			_plant_debug = _make_passthrough_label("")
			_plant_debug.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_plant_debug.add_theme_font_size_override("font_size", 12)
			root.add_child(_plant_debug)
		_sim_status = _make_passthrough_label("tips=0  segments=0  speed=pause")
		_sim_status.add_theme_font_size_override("font_size", 12)
		root.add_child(_sim_status)


func _make_passthrough_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _speed_label(speed: SimClock.Speed) -> String:
	match speed:
		SimClock.Speed.PAUSE:
			return "pause"
		SimClock.Speed.NORMAL:
			return "normal"
		SimClock.Speed.FAST:
			return "fast"
		SimClock.Speed.GROW:
			return "grow"
		_:
			return "?"


func _build_anchor_row(parent: Control) -> void:
	_anchor_row = HBoxContainer.new()
	_anchor_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_row.add_theme_constant_override("separation", 6)
	parent.add_child(_anchor_row)
	if _free_plant_mode:
		# Buttons first so they stay at a fixed spot; the hint text is the part that changes.
		_clear_button = _make_button("Clear ivy")
		_clear_button.pressed.connect(_on_clear_pressed)
		_anchor_row.add_child(_clear_button)
		var change_button := _make_button("Change building")
		change_button.pressed.connect(change_building_requested.emit)
		_anchor_row.add_child(change_button)
		var help_button := _make_button("?")
		help_button.tooltip_text = "Keyboard commands (? or F1)"
		help_button.pressed.connect(toggle_help)
		_anchor_row.add_child(help_button)
		var hint := _make_passthrough_label(
			"Left-click glow to plant · Tab mouse-look orbit · scroll zoom · WASD/arrows rotate · R reset · ? help")
		_anchor_row.add_child(hint)
		return
	var scenario = _world.get_mesh_scenario() if _world.has_method("get_mesh_scenario") else null
	if scenario != null:
		_scenario_seed_count = scenario.seed_positions.size()
		for i in _scenario_seed_count:
			var btn := _make_button("Seed %d" % i)
			btn.pressed.connect(_on_scenario_seed_pressed.bind(i))
			_anchor_row.add_child(btn)
			_anchor_buttons.append(btn)
	else:
		for compass in 4:
			var label := SeedAnchorsScript.compass_label(compass)
			var btn := _make_button(label)
			btn.pressed.connect(_on_compass_pressed.bind(compass))
			_anchor_row.add_child(btn)
			_anchor_buttons.append(btn)


func _build_speed_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	for spec in [
		["Pause (Space)", SimClock.Speed.PAUSE],
		["Normal (1)", SimClock.Speed.NORMAL],
		["Fast (2)", SimClock.Speed.FAST],
		["Grow (3)", SimClock.Speed.GROW],
	]:
		var btn := _make_button(spec[0])
		btn.pressed.connect(_on_speed_pressed.bind(spec[1]))
		row.add_child(btn)
		_speed_buttons[spec[1]] = btn
	if _params != null and _params.dev_build:
		_snapshot_button = _make_button("Snap (F9)")
		_snapshot_button.tooltip_text = "Save debug snapshot (F9). Shift+F9 skips annotation."
		_snapshot_button.pressed.connect(func() -> void: debug_snapshot_requested.emit())
		row.add_child(_snapshot_button)


func _build_snapshot_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.top_level = true
	_toast_panel.z_index = 4096
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.1, 0.92)
	style.border_color = Color(0.65, 0.85, 0.6, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_toast_panel.add_theme_stylebox_override("panel", style)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	_toast_panel.add_child(pad)
	_toast_label = Label.new()
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size = Vector2(280, 0)
	_toast_label.add_theme_font_size_override("font_size", 15)
	_toast_label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.9))
	pad.add_child(_toast_label)
	add_child(_toast_panel)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 6.0
	_toast_timer.timeout.connect(func() -> void:
		if _toast_panel != null:
			_toast_panel.visible = false
	)
	add_child(_toast_timer)


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	# A focused button swallows Space (ui_accept), which would re-press it instead of
	# reaching the pause hotkey; arrow keys would also move focus instead of panning.
	btn.focus_mode = Control.FOCUS_NONE
	return btn


func _refresh_anchor_buttons() -> void:
	if _free_plant_mode or _world == null:
		return
	var scenario = _world.get_mesh_scenario() if _world.has_method("get_mesh_scenario") else null
	if scenario != null:
		for i in _anchor_buttons.size():
			_anchor_buttons[i].disabled = false
		return
	var anchors_obj = _world.get_seed_anchors() if _world.has_method("get_seed_anchors") else null
	if anchors_obj == null:
		return
	var anchors: Array = anchors_obj.get_anchors()
	for i in mini(_anchor_buttons.size(), anchors.size()):
		_anchor_buttons[i].disabled = not anchors[i].available


func _on_clear_pressed() -> void:
	if _session_log != null:
		_session_log.clear()
	if _sim != null and _sim.has_method("clear_plants"):
		_sim.clear_plants()


func _on_compass_pressed(compass: int) -> void:
	if _world == null or _sim == null:
		return
	var anchors_obj = _world.get_seed_anchors() if _world.has_method("get_seed_anchors") else null
	if anchors_obj != null:
		var anchors: Array = anchors_obj.get_anchors()
		if compass < anchors.size() and not anchors[compass].available:
			return
	if _session_log != null:
		_session_log.clear()
	_world.set_seed_index(compass)
	_sim.set_seed_index(compass)
	_sim.reseed()
	_refresh_anchor_buttons()


func _on_scenario_seed_pressed(index: int) -> void:
	if _world == null or _sim == null:
		return
	if _session_log != null:
		_session_log.clear()
	_world.set_seed_index(index)
	_sim.set_seed_index(index)
	_sim.reseed()
	_refresh_anchor_buttons()


func _on_speed_pressed(speed: SimClock.Speed) -> void:
	if _sim == null or not _sim.has_method("get_clock"):
		return
	var clock: SimClock = _sim.get_clock()
	if clock == null:
		return
	clock.set_speed(speed)
