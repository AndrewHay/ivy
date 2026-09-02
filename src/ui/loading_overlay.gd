class_name LoadingOverlay
extends Control

## Full-screen loading panel with status text and a progress bar (M6 bootstrap).

var _label: Label
var _bar: ProgressBar
var _ratio: float = 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.05, 0.07, 0.09, 0.94)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 16)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 22)
	panel.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(420, 28)
	_bar.show_percentage = true
	_bar.value = 0.0
	panel.add_child(_bar)


func set_progress(message: String, ratio: float) -> void:
	_label.text = message
	_ratio = clampf(ratio, 0.0, 1.0)
	_bar.value = _ratio * 100.0


func get_ratio() -> float:
	return _ratio
