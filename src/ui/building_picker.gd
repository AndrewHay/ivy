class_name BuildingPicker
extends Control

signal building_selected(building_id: String)

const BuildingCatalog = preload("res://src/world/building_catalog.gd")
const _OverlayStyle = preload("res://src/ui/overlay_style.gd")


func _ready() -> void:
	# _ready runs once we are already in the tree, where set_anchors_preset alone leaves the
	# offsets untouched and the control zero-sized (menu stuck top-left, no backdrop). The
	# *_and_offsets_ form sets both, so it works whenever it is called.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.05, 0.07, 0.09, 0.92)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 14)
	center.add_child(panel)

	var title := Label.new()
	title.text = "Choose a building"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Then click the glowing cursor to plant ivy at the base."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(subtitle)

	for entry in BuildingCatalog.all():
		var btn := Button.new()
		btn.text = entry.label
		btn.custom_minimum_size = Vector2(280, 48)
		_OverlayStyle.style_button(btn)
		btn.pressed.connect(_on_entry_pressed.bind(entry.id))
		panel.add_child(btn)


func _on_entry_pressed(building_id: String) -> void:
	building_selected.emit(building_id)
	queue_free()
