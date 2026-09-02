class_name Hud
extends Control

## SD-AGENCY player controls: anchors, pause + three speeds, date/time, time-lapse flag.

const SeedAnchorsScript = preload("res://src/world/seed_anchors.gd")

var _world: Node = null
var _sim: Node = null
var _params: IvyParams = null
var _anchor_buttons: Array[Button] = []
var _speed_buttons: Dictionary = {}
var _date_label: Label = null
var _timelapse_label: Label = null
var _scenario_seed_count: int = 0
var _free_plant_mode: bool = false
var _anchor_row: HBoxContainer = null
var _clear_button: Button = null
var _plant_debug: Label = null
var _sim_status: Label = null
var _planting_tool: PlantingTool = null


func set_planting_tool(tool: PlantingTool) -> void:
	_planting_tool = tool


func finish_planting_mode() -> void:
	_planting_tool = null
	if _plant_debug != null:
		_plant_debug.visible = false
	if _anchor_row != null:
		for child in _anchor_row.get_children():
			if child is Label:
				(child as Label).text = "Left-drag to orbit · scroll to zoom"


func setup(world: Node, sim: Node, params: IvyParams, free_plant_mode: bool = false) -> void:
	_world = world
	_sim = sim
	_params = params
	_free_plant_mode = free_plant_mode
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_anchor_buttons()


func refresh(clock: SimClock, sky_sun: SkySun) -> void:
	if _date_label != null and clock != null and _params != null:
		var display_day := clock.display_game_day()
		var hour := display_day * 24.0 + _params.start_hour
		var day_num := int(floor(display_day)) + 1
		var hour_i := int(floor(fposmod(hour, 24.0)))
		var minute_i := int(floor(fposmod(hour * 60.0, 60.0)))
		_date_label.text = "Day %d  %02d:%02d" % [day_num, hour_i, minute_i]
	if _plant_debug != null and _planting_tool != null:
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


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

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
	if _free_plant_mode:
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
		SimClock.Speed.WATCH:
			return "watch"
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
		var hint := _make_passthrough_label("Left-click glow to plant · right-drag to orbit camera")
		_anchor_row.add_child(hint)
		_clear_button = _make_button("Clear ivy")
		_clear_button.pressed.connect(_on_clear_pressed)
		_anchor_row.add_child(_clear_button)
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
		["Pause", SimClock.Speed.PAUSE],
		["Watch", SimClock.Speed.WATCH],
		["Fast", SimClock.Speed.FAST],
		["Grow", SimClock.Speed.GROW],
	]:
		var btn := _make_button(spec[0])
		btn.pressed.connect(_on_speed_pressed.bind(spec[1]))
		row.add_child(btn)
		_speed_buttons[spec[1]] = btn


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
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
	_world.set_seed_index(compass)
	_sim.set_seed_index(compass)
	_sim.reseed()
	_refresh_anchor_buttons()


func _on_scenario_seed_pressed(index: int) -> void:
	if _world == null or _sim == null:
		return
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
