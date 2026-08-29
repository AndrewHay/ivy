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


func setup(world: Node, sim: Node, params: IvyParams) -> void:
	_world = world
	_sim = sim
	_params = params
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_anchor_buttons()


func refresh(clock: SimClock, sky_sun: SkySun) -> void:
	if _date_label != null and clock != null and _params != null:
		var hour := clock.game_day * 24.0 + _params.start_hour
		var day_num := int(floor(clock.game_day)) + 1
		var hour_i := int(floor(fposmod(hour, 24.0)))
		var minute_i := int(floor(fposmod(hour * 60.0, 60.0)))
		_date_label.text = "Day %d  %02d:%02d" % [day_num, hour_i, minute_i]
	if _timelapse_label != null and sky_sun != null and clock != null:
		var show := sky_sun.is_time_lapse(clock.seconds_per_game_day())
		_timelapse_label.visible = show


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(root)

	_build_anchor_row(root)
	_build_speed_row(root)
	_date_label = Label.new()
	_date_label.text = "Day 1  06:00"
	root.add_child(_date_label)
	_timelapse_label = Label.new()
	_timelapse_label.text = "time-lapse — average daylight"
	_timelapse_label.visible = false
	root.add_child(_timelapse_label)


func _build_anchor_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var scenario = _world.get_mesh_scenario() if _world.has_method("get_mesh_scenario") else null
	if scenario != null:
		_scenario_seed_count = scenario.seed_positions.size()
		for i in _scenario_seed_count:
			var btn := _make_button("Seed %d" % i)
			btn.pressed.connect(_on_scenario_seed_pressed.bind(i))
			row.add_child(btn)
			_anchor_buttons.append(btn)
	else:
		for compass in 4:
			var label := SeedAnchorsScript.compass_label(compass)
			var btn := _make_button(label)
			btn.pressed.connect(_on_compass_pressed.bind(compass))
			row.add_child(btn)
			_anchor_buttons.append(btn)


func _build_speed_row(parent: Control) -> void:
	var row := HBoxContainer.new()
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
	if _world == null:
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
