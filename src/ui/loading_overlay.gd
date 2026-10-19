class_name LoadingOverlay
extends Control

## Full-screen loading panel with status text and a progress bar (M6 bootstrap).

const _OverlayStyle = preload("res://src/ui/overlay_style.gd")

## Emitted by the failure screen's button; the owner decides where "back" goes.
signal back_requested

var _label: Label
var _bar: ProgressBar
var _panel: VBoxContainer
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
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 16)
	_panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(_panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 22)
	_panel.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(420, 28)
	_bar.show_percentage = true
	_bar.value = 0.0
	_panel.add_child(_bar)


## Turn the loading screen into an error screen with a way out, so a failed build is not a
## dead end that only quitting the game can escape.
func show_failure(message: String) -> void:
	_label.text = message
	_bar.visible = false
	var back := Button.new()
	back.text = "Back to buildings"
	back.custom_minimum_size = Vector2(0, 44)
	back.focus_mode = Control.FOCUS_NONE
	_OverlayStyle.style_button(back)
	back.pressed.connect(back_requested.emit)
	_panel.add_child(back)


func set_progress(message: String, ratio: float) -> void:
	_label.text = message
	_ratio = clampf(ratio, 0.0, 1.0)
	_bar.value = _ratio * 100.0


func get_ratio() -> float:
	return _ratio
