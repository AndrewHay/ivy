class_name KnobPanel
extends PanelContainer

signal knob_changed(name: String, value: Variant)
signal variant_changed(variant: int)
signal preset_selected(name: String)
signal reset_requested
signal copy_requested

const _OverlayStyle = preload("res://src/ui/overlay_style.gd")
const GrassWindKnobSpec = preload("res://src/playground/grass_wind_knob_spec.gd")
const PlaygroundCheckboxStyle = preload("res://src/playground/playground_checkbox_style.gd")

var _params: Resource
var _spec: Array[Dictionary] = []
var _row_nodes: Dictionary = {}
var _variant: int = 0
var _variant_help: Label
var _defaults: Resource
var _group_headers: Dictionary = {}


func build_from_spec(
		spec: Array[Dictionary],
		params: Resource,
		presets: Dictionary) -> void:
	_spec = spec
	_params = params
	_defaults = GrassWindParams.new()
	_row_nodes.clear()
	_group_headers.clear()
	_variant = params.get("variant")
	for c in get_children():
		c.queue_free()
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	vbox.add_child(_make_variant_row())
	_variant_help = _make_help_label("VariantHelp")
	vbox.add_child(_variant_help)
	vbox.add_child(_make_preset_row(presets))
	vbox.add_child(_make_help_label("PresetHelp", GrassWindKnobSpec.PRESET_HELP))
	_refresh_variant_help()
	var scroll := ScrollContainer.new()
	scroll.name = "KnobScroll"
	scroll.custom_minimum_size = Vector2(320, 420)
	vbox.add_child(scroll)
	var knob_vbox := VBoxContainer.new()
	knob_vbox.name = "KnobVBox"
	knob_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(knob_vbox)
	_build_knob_rows(knob_vbox)
	_refresh_group_headers()
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	var reset_btn := Button.new()
	reset_btn.text = "Reset to production"
	_OverlayStyle.style_button(reset_btn)
	reset_btn.pressed.connect(func(): reset_requested.emit())
	btn_row.add_child(reset_btn)
	var copy_btn := Button.new()
	copy_btn.text = "Copy settings"
	_OverlayStyle.style_button(copy_btn)
	copy_btn.pressed.connect(func(): copy_requested.emit())
	btn_row.add_child(copy_btn)
	vbox.add_child(btn_row)
	_apply_panel_style()
	sync_preset_dropdown()


func set_variant(v: int) -> void:
	_variant = v
	for row in _row_nodes.values():
		_refresh_row_visibility(row)
	_refresh_group_headers()
	var btn: OptionButton = get_node("Margin/VBox/VariantRow/Variant")
	if btn.selected != v:
		btn.select(v)
	_refresh_variant_help()
	sync_preset_dropdown()


func refresh_values() -> void:
	for name in _row_nodes.keys():
		var row: Dictionary = _row_nodes[name]
		var spec: Dictionary = row["spec"]
		# *_no_signal: re-pushing a stepped/rounded slider value back into the params would
		# silently nudge them off their real value (e.g. direction 16.699° -> 17°).
		if spec["type"] == "float":
			var slider: HSlider = row["slider"]
			slider.set_value_no_signal(_params.get(name))
			row["label"].text = _format_value(name, _params.get(name))
		else:
			(row["check"] as CheckBox).set_pressed_no_signal(_params.get(name))
	sync_preset_dropdown()


func sync_preset_dropdown() -> void:
	if _params == null:
		return
	var opt: OptionButton = get_node_or_null("Margin/VBox/PresetRow/Preset") as OptionButton
	if opt == null:
		return
	var target := GrassWindParams.detect_preset_name(_params as GrassWindParams)
	for i in range(opt.item_count):
		if opt.get_item_text(i) == target:
			if opt.selected != i:
				opt.select(i)
			return


func _refresh_variant_help() -> void:
	if _variant_help != null:
		_variant_help.text = "%s\n\n%s" % [
			GrassWindKnobSpec.VARIANT_HELP, GrassWindKnobSpec.VARIANT_DESCRIPTIONS[_variant]]


func _make_help_label(node_name: String, text: String = "") -> Label:
	var lbl := Label.new()
	lbl.name = node_name
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(330, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.72, 0.80, 0.86, 1.0))
	return lbl


## Tooltips only show on controls that take mouse input; Labels ignore it by default.
func _set_tip(node: Control, text: String) -> void:
	node.tooltip_text = text
	node.mouse_filter = Control.MOUSE_FILTER_STOP


func _knob_tooltip(spec: Dictionary) -> String:
	var default_value: Variant = _defaults.get(spec["name"])
	var parts: PackedStringArray = [spec["label"], "", spec.get("tip", "")]
	parts.append("")
	if spec["type"] == "float":
		parts.append("Default: %s   Range: %s – %s" % [
			String.num(default_value, 3), String.num(spec["min"], 3), String.num(spec["max"], 3)])
	else:
		parts.append("Default: %s" % ("on" if default_value else "off"))
	var variants: Array = spec["variants"]
	if variants.size() >= GrassWindKnobSpec.VARIANT_LABELS.size():
		parts.append("Used by: every variant")
	else:
		parts.append("Used by: variant %s only" % ", ".join(PackedStringArray(
			variants.map(func(v): return str(v)))))
	return "\n".join(parts)


func _apply_panel_style() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.08, 0.10, 0.88)
	box.set_corner_radius_all(8)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", box)


func _make_slider_with_track(spec: Dictionary) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(80, 20)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track_bg := ColorRect.new()
	track_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	track_bg.offset_top = 6
	track_bg.offset_bottom = -6
	track_bg.color = Color(0.62, 0.66, 0.72, 1.0)
	root.add_child(track_bg)
	var slider := HSlider.new()
	slider.set_anchors_preset(Control.PRESET_FULL_RECT)
	slider.min_value = spec["min"]
	slider.max_value = spec["max"]
	slider.step = spec["step"]
	_style_slider(slider)
	root.add_child(slider)
	return {"root": root, "slider": slider}


func _style_slider(slider: HSlider) -> void:
	slider.custom_minimum_size.y = 18
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	track.set_content_margin_all(0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.32, 0.78, 0.48, 1.0)
	fill.set_corner_radius_all(2)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	grabber.border_color = Color(0.15, 0.18, 0.22, 1.0)
	grabber.set_border_width_all(1)
	grabber.set_corner_radius_all(5)
	grabber.set_content_margin_all(3)
	grabber.expand_margin_top = 5
	grabber.expand_margin_bottom = 5
	grabber.expand_margin_left = 4
	grabber.expand_margin_right = 4
	var theme := ThemeDB.get_default_theme().duplicate()
	for type_name in ["Slider", "HSlider"]:
		theme.set_stylebox("slider", type_name, track)
		theme.set_stylebox("grabber_area", type_name, fill)
		theme.set_stylebox("grabber_area_highlight", type_name, fill)
		theme.set_stylebox("grabber", type_name, grabber)
	slider.theme = theme


func _make_variant_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "VariantRow"
	var lbl := Label.new()
	lbl.text = "Variant"
	lbl.custom_minimum_size = Vector2(72, 0)
	_set_tip(lbl, GrassWindKnobSpec.VARIANT_HELP)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.name = "Variant"
	opt.tooltip_text = GrassWindKnobSpec.VARIANT_HELP
	for i in range(GrassWindKnobSpec.VARIANT_LABELS.size()):
		opt.add_item(GrassWindKnobSpec.VARIANT_LABELS[i], i)
		opt.set_item_tooltip(i, GrassWindKnobSpec.VARIANT_DESCRIPTIONS[i])
	opt.select(_variant)
	opt.item_selected.connect(func(idx: int):
		_variant = idx
		for r in _row_nodes.values():
			_refresh_row_visibility(r)
		_refresh_group_headers()
		_refresh_variant_help()
		variant_changed.emit(idx)
		sync_preset_dropdown())
	row.add_child(opt)
	return row


func _make_preset_row(presets: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "PresetRow"
	var lbl := Label.new()
	lbl.text = "Preset"
	lbl.custom_minimum_size = Vector2(72, 0)
	_set_tip(lbl, GrassWindKnobSpec.PRESET_HELP)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.name = "Preset"
	opt.tooltip_text = GrassWindKnobSpec.PRESET_HELP
	var tips := GrassWindParams.preset_tips()
	for n in GrassWindParams.ordered_preset_names():
		opt.add_item(n)
		opt.set_item_tooltip(opt.item_count - 1, tips.get(n, ""))
	# Informational only: shown when the knobs match no preset, never pickable.
	opt.add_item(GrassWindParams.CUSTOM_PRESET)
	var custom_idx := opt.item_count - 1
	opt.set_item_disabled(custom_idx, true)
	opt.set_item_tooltip(custom_idx, "Your slider values do not match any preset.")
	opt.item_selected.connect(func(_idx: int):
		preset_selected.emit(opt.get_item_text(opt.selected)))
	row.add_child(opt)
	return row


func _build_knob_rows(parent: VBoxContainer) -> void:
	var last_group := ""
	for spec in _spec:
		if spec["group"] != last_group:
			last_group = spec["group"]
			var gl := Label.new()
			gl.text = "Group %s" % last_group
			gl.add_theme_font_size_override("font_size", 16)
			parent.add_child(gl)
			_group_headers[last_group] = gl
		var row := _make_knob_row(spec)
		parent.add_child(row["container"])
		_row_nodes[spec["name"]] = row
		_refresh_row_visibility(row)


func _make_knob_row(spec: Dictionary) -> Dictionary:
	var container := HBoxContainer.new()
	container.name = "Knob_%s" % spec["name"]
	var tip := _knob_tooltip(spec)
	var name_lbl := Label.new()
	name_lbl.text = spec["label"]
	name_lbl.custom_minimum_size = Vector2(150, 0)
	_set_tip(name_lbl, tip)
	container.add_child(name_lbl)
	var out := {"spec": spec, "container": container}
	if spec["type"] == "float":
		var slider_wrap := _make_slider_with_track(spec)
		var slider: HSlider = slider_wrap["slider"]
		slider.value = _params.get(spec["name"])
		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(52, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.text = _format_value(spec["name"], slider.value)
		slider.value_changed.connect(func(v: float):
			val_lbl.text = _format_value(spec["name"], v)
			knob_changed.emit(spec["name"], v)
			sync_preset_dropdown())
		var root: Control = slider_wrap["root"]
		_set_tip(root, tip)
		for child in root.get_children():
			_set_tip(child as Control, tip)
		_set_tip(val_lbl, tip)
		container.add_child(root)
		container.add_child(val_lbl)
		out["slider"] = slider
		out["label"] = val_lbl
	else:
		var check := CheckBox.new()
		PlaygroundCheckboxStyle.apply(check)
		check.button_pressed = _params.get(spec["name"])
		check.toggled.connect(func(on: bool):
			knob_changed.emit(spec["name"], on)
			sync_preset_dropdown())
		_set_tip(check, tip)
		container.add_child(check)
		out["check"] = check
	return out


## Hide a group header when none of its knobs apply to the current variant.
func _refresh_group_headers() -> void:
	for group in _group_headers.keys():
		var any_visible := false
		for row in _row_nodes.values():
			if row["spec"]["group"] == group and row["container"].visible:
				any_visible = true
				break
		(_group_headers[group] as Label).visible = any_visible


func _refresh_row_visibility(row: Dictionary) -> void:
	var spec: Dictionary = row["spec"]
	var show: bool = _variant in spec["variants"]
	row["container"].visible = show


func _format_value(name: String, v: float) -> String:
	if name.ends_with("_deg"):
		return "%.1f" % v
	if name.contains("density"):
		return "%.0f" % v
	return "%.3f" % v
