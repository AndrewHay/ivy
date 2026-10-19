class_name OverlayStyle
extends RefCounted

## Look for buttons that sit on the near-black full-screen overlays (building picker, failure
## screen). The default theme's dark-grey buttons vanish against that backdrop, so these get an
## explicit lighter fill, a border, and a brighter hover.


static func style_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _box(Color(0.24, 0.30, 0.34)))
	btn.add_theme_stylebox_override("hover", _box(Color(0.33, 0.42, 0.47)))
	btn.add_theme_stylebox_override("pressed", _box(Color(0.20, 0.26, 0.30)))
	btn.add_theme_stylebox_override("focus", _box(Color(0.24, 0.30, 0.34)))
	btn.add_theme_color_override("font_color", Color(0.95, 0.97, 0.98))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)


static func _box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color(0.65, 0.85, 0.6, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	return box
