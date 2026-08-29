class_name DevOverlay
extends PanelContainer

## W-013 / AR-UI-2 — reflection-driven IvyParams tuning + AS-3 readouts.

const _SKIP_PARAMS := ["resource_local_to_scene", "resource_name", "script", "dev_build"]
const _Tooltips = preload("res://src/ui/dev_overlay_tooltips.gd")

var _sim: Node = null
var _params: IvyParams = null
var _as3_label: Label = null
var _scroll: ScrollContainer = null


func setup(sim: Node, params: IvyParams) -> void:
	_sim = sim
	_params = params
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.94)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -360
	offset_top = 8
	offset_right = -8
	offset_bottom = 640
	_build_ui()


func toggle_visible() -> void:
	visible = not visible


func refresh(clock: SimClock) -> void:
	if _as3_label == null or _sim == null or clock == null:
		return
	var solar: Solar = _sim.get("solar") as Solar
	if solar == null or _params == null:
		return
	var day_int := int(floor(clock.game_day))
	var noon_day := float(day_int) + (12.0 - _params.start_hour) / 24.0
	var midnight_day := float(day_int) + (24.0 - _params.start_hour) / 24.0
	var gate_noon := solar.diel_gate(noon_day)
	var gate_midnight := solar.diel_gate(midnight_day)
	var g_now := solar.diel_gate(clock.game_day)
	_as3_label.text = (
		"AS-3  ĝ(now)=%.3f  noon=%.3f  midnight=%.3f  ratio=%.3f"
		% [g_now, gate_noon, gate_midnight, gate_midnight / maxf(gate_noon, 1e-6)]
	)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	add_child(root)

	var title := Label.new()
	title.text = "Dev tuning (W-013)"
	root.add_child(title)

	_as3_label = Label.new()
	_as3_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_as3_label)

	var hint := Label.new()
	hint.text = "F: field viz (D_L → C → off)   ` : hide panel"
	root.add_child(hint)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(320, 520)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)
	_build_param_rows(list)


func _build_param_rows(parent: Control) -> void:
	var inert_set: Dictionary = {}
	for name in IvyParams.OVERLAY_INERT:
		inert_set[name] = true

	for prop in _params.get_property_list():
		var usage: int = prop["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name: String = prop["name"]
		if name in _SKIP_PARAMS:
			continue
		var inert := inert_set.has(name)
		var tip := _Tooltips.for_param(name, inert)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.tooltip_text = tip
		parent.add_child(row)

		var label := Label.new()
		label.text = name
		if inert:
			label.text += " (inert)"
			label.modulate = Color(0.65, 0.65, 0.65)
		label.custom_minimum_size.x = 150
		label.tooltip_text = tip
		row.add_child(label)

		var editor := _make_editor(name, prop["type"], inert, tip)
		if editor != null:
			row.add_child(editor)


func _make_editor(name: String, prop_type: int, inert: bool, tip: String) -> Control:
	match prop_type:
		TYPE_FLOAT:
			var spin := SpinBox.new()
			spin.min_value = -1e6
			spin.max_value = 1e6
			spin.step = 0.001
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.value = float(_params.get(name))
			spin.editable = not inert
			spin.tooltip_text = tip
			if not inert:
				spin.value_changed.connect(func(v: float) -> void: _params.set(name, v))
			return spin
		TYPE_INT:
			var spin := SpinBox.new()
			spin.min_value = -1_000_000
			spin.max_value = 1_000_000
			spin.step = 1
			spin.rounded = true
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.value = int(_params.get(name))
			spin.editable = not inert
			spin.tooltip_text = tip
			if not inert:
				spin.value_changed.connect(func(v: float) -> void: _params.set(name, int(v)))
			return spin
		TYPE_BOOL:
			var check := CheckButton.new()
			check.button_pressed = bool(_params.get(name))
			check.disabled = inert
			check.tooltip_text = tip
			if not inert:
				check.toggled.connect(func(v: bool) -> void: _params.set(name, v))
			return check
		TYPE_COLOR:
			var picker := ColorPickerButton.new()
			picker.color = _params.get(name)
			picker.disabled = inert
			picker.tooltip_text = tip
			if not inert:
				picker.color_changed.connect(func(c: Color) -> void: _params.set(name, c))
			return picker
		_:
			return null
