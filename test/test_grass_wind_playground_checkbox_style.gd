extends GutTest

const KnobPanel = preload("res://src/playground/knob_panel.gd")
const KnobSpec = preload("res://src/playground/grass_wind_knob_spec.gd")
const GrassWindParams = preload("res://src/playground/grass_wind_params.gd")
const PlaygroundCheckboxStyle = preload("res://src/playground/playground_checkbox_style.gd")

const PANEL_BG := Color(0.06, 0.08, 0.10, 1.0)
const BOOL_KNOBS := ["gust_envelope_on", "freeze_direction", "droop_on"]


func _panel(params: GrassWindParams = null) -> KnobPanel:
	var p := params if params != null else GrassWindParams.new()
	var panel := KnobPanel.new()
	panel.build_from_spec(KnobSpec.all_knobs(), p, GrassWindParams.presets())
	add_child_autofree(panel)
	return panel


func _checkbox_in_row(panel: KnobPanel, knob_name: String) -> CheckBox:
	var row: Node = panel.get_node("Margin/VBox/KnobScroll/KnobVBox/Knob_%s" % knob_name)
	for c in row.get_children():
		if c is CheckBox:
			return c as CheckBox
	return null


func test_helper_icons_are_distinct_and_opaque() -> void:
	var unchecked := PlaygroundCheckboxStyle.make_unchecked_image()
	var checked := PlaygroundCheckboxStyle.make_checked_image()
	assert_not_null(unchecked)
	assert_not_null(checked)
	assert_gt(PlaygroundCheckboxStyle.max_opaque_pixels(unchecked), 8,
		"unchecked icon should have visible pixels")
	assert_gt(PlaygroundCheckboxStyle.max_opaque_pixels(checked), 8,
		"checked icon should have visible pixels")
	assert_false(PlaygroundCheckboxStyle.images_visually_same(unchecked, checked),
		"checked and unchecked should differ")


func test_unchecked_icon_contrasts_panel_background() -> void:
	var img := PlaygroundCheckboxStyle.make_unchecked_image()
	var panel_lum := PlaygroundCheckboxStyle.relative_luminance(PANEL_BG)
	var peak_lum := PlaygroundCheckboxStyle.peak_opaque_luminance(img)
	var contrast := absf(peak_lum - panel_lum)
	assert_gte(contrast, 0.22,
		"unchecked box should stand out on panel bg (peak lum %.3f vs bg %.3f)" % [peak_lum, panel_lum])


func test_knob_panel_bool_rows_use_styled_checkbox_icons() -> void:
	var panel := _panel()
	for knob_name in BOOL_KNOBS:
		var check := _checkbox_in_row(panel, knob_name)
		assert_not_null(check, "bool knob row %s has CheckBox" % knob_name)
		assert_not_null(check.get_theme_icon("unchecked"),
			"%s should override unchecked icon" % knob_name)
		assert_not_null(check.get_theme_icon("checked"),
			"%s should override checked icon" % knob_name)
		var u_tex: Texture2D = check.get_theme_icon("unchecked")
		var c_tex: Texture2D = check.get_theme_icon("checked")
		assert_ne(u_tex.get_image(), c_tex.get_image(),
			"%s checked/unchecked textures should differ" % knob_name)
