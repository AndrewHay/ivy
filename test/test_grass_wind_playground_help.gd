extends GutTest

## Variant vs preset semantics, the "Custom" preset state, and per-knob tooltips.

const KnobPanel = preload("res://src/playground/knob_panel.gd")
const KnobSpec = preload("res://src/playground/grass_wind_knob_spec.gd")


func _panel(params: GrassWindParams) -> KnobPanel:
	var panel := KnobPanel.new()
	panel.build_from_spec(KnobSpec.all_knobs(), params, GrassWindParams.presets())
	add_child_autofree(panel)
	return panel


func _preset_text(panel: KnobPanel) -> String:
	var opt: OptionButton = panel.get_node("Margin/VBox/PresetRow/Preset")
	return opt.get_item_text(opt.selected)


# ── Preset semantics ─────────────────────────────────────────────────────────

func test_presets_do_not_stack() -> void:
	var p := GrassWindParams.new()
	p.apply_preset("Blustery")
	assert_almost_eq(p.gust_period_sec, 10.0, 1e-6)
	p.apply_preset("Gentle breeze")
	assert_almost_eq(p.wind_strength, 0.5, 1e-6)
	assert_almost_eq(p.gust_period_sec, 28.0, 1e-6, "Blustery leftovers cleared")
	assert_almost_eq(p.lean_gust_gain, 0.45, 1e-6, "Blustery leftovers cleared")
	assert_eq(GrassWindParams.detect_preset_name(p), "Gentle breeze")


func test_preset_without_variant_keeps_current_variant() -> void:
	var p := GrassWindParams.new()
	p.variant = 3
	p.apply_preset("Gentle breeze")
	assert_eq(p.variant, 3)
	assert_eq(GrassWindParams.detect_preset_name(p), "Gentle breeze")


func test_preset_with_variant_switches_variant() -> void:
	var p := GrassWindParams.new()
	p.apply_preset("Rolling gust")
	assert_eq(p.variant, 4)


func test_production_preset_returns_to_variant_zero() -> void:
	var p := GrassWindParams.new()
	p.apply_preset("Springy meadow")
	p.apply_preset("Production")
	assert_eq(p.variant, 0)
	assert_eq(GrassWindParams.detect_preset_name(p), "Production")


func test_presets_leave_stage_settings_alone() -> void:
	var p := GrassWindParams.new()
	p.lawn_size_m = 30.0
	p.blade_density_per_m2 = 99.0
	p.apply_preset("Blustery")
	assert_almost_eq(p.lawn_size_m, 30.0, 1e-6)
	assert_almost_eq(p.blade_density_per_m2, 99.0, 1e-6)


func test_tweaked_knobs_detect_as_custom() -> void:
	var p := GrassWindParams.new()
	p.apply_preset("Blustery")
	p.wind_strength = 1.234
	assert_eq(GrassWindParams.detect_preset_name(p), GrassWindParams.CUSTOM_PRESET)


func test_every_preset_has_a_tooltip() -> void:
	var tips := GrassWindParams.preset_tips()
	for n in GrassWindParams.presets().keys():
		assert_true(tips.has(n) and not String(tips[n]).is_empty(), "tip for preset %s" % n)


# ── Panel behaviour ──────────────────────────────────────────────────────────

func test_dropdown_shows_custom_after_slider_tweak_and_is_not_pickable() -> void:
	var params := GrassWindParams.new()
	var panel := _panel(params)
	# The playground scene does this: the panel emits, the scene writes the params.
	panel.knob_changed.connect(func(n: String, v: Variant): params.set(n, v))
	assert_eq(_preset_text(panel), "Production")
	var slider: HSlider = panel.get_node(
		"Margin/VBox/KnobScroll/KnobVBox/Knob_wind_strength").find_children("*", "HSlider", true, false)[0]
	slider.value = 2.0
	assert_eq(_preset_text(panel), "Custom")
	var opt: OptionButton = panel.get_node("Margin/VBox/PresetRow/Preset")
	assert_true(opt.is_item_disabled(opt.item_count - 1), "Custom cannot be chosen by hand")


func test_dropdown_follows_variant_change() -> void:
	var params := GrassWindParams.new()
	var panel := _panel(params)
	params.variant = 2
	panel.set_variant(2)
	assert_eq(_preset_text(panel), "Custom", "production knobs on variant 2 is not a preset")
	params.variant = 0
	panel.set_variant(0)
	assert_eq(_preset_text(panel), "Production")


func test_refresh_values_does_not_nudge_params_through_rounded_sliders() -> void:
	var params := GrassWindParams.new()
	var panel := _panel(params)
	params.apply_preset("Blustery")
	panel.refresh_values()
	params.apply_preset("Production")
	panel.refresh_values()
	assert_almost_eq(params.direction_deg, 16.6992412467622, 1e-9,
		"slider step 1.0 must not round the real production direction")
	assert_eq(_preset_text(panel), "Production")


func test_variant_help_text_follows_variant() -> void:
	var params := GrassWindParams.new()
	var panel := _panel(params)
	var help: Label = panel.get_node("Margin/VBox/VariantHelp")
	assert_true(help.text.contains(KnobSpec.VARIANT_DESCRIPTIONS[0]))
	panel.set_variant(4)
	assert_true(help.text.contains(KnobSpec.VARIANT_DESCRIPTIONS[4]))
	assert_true(help.text.contains("WHICH ALGORITHM"))
	assert_true(panel.get_node("Margin/VBox/PresetHelp").text.contains("BUNDLE"))


func test_group_header_hidden_when_no_knobs_apply() -> void:
	var params := GrassWindParams.new()
	params.variant = 4
	var panel := _panel(params)
	var vbox := panel.get_node("Margin/VBox/KnobScroll/KnobVBox")
	var headers := {}
	for c in vbox.get_children():
		if c is Label and (c as Label).text.begins_with("Group "):
			headers[(c as Label).text] = c
	assert_false(headers["Group B"].visible, "variant 4 uses no Group B knobs")
	assert_true(headers["Group D"].visible)
	panel.set_variant(0)
	assert_true(headers["Group B"].visible, "variant 0 uses Group B")


# ── Tooltips ─────────────────────────────────────────────────────────────────

func test_every_knob_spec_has_a_real_tip() -> void:
	for spec in KnobSpec.all_knobs():
		assert_gt(String(spec["tip"]).length(), 30, "tip for %s" % spec["name"])


func test_every_knob_row_shows_tooltip_with_default_and_usage() -> void:
	var panel := _panel(GrassWindParams.new())
	for spec in KnobSpec.all_knobs():
		var row: Node = panel.get_node("Margin/VBox/KnobScroll/KnobVBox/Knob_%s" % spec["name"])
		var label: Label = row.get_child(0)
		assert_eq(label.mouse_filter, Control.MOUSE_FILTER_STOP, "label can receive hover")
		assert_true(label.tooltip_text.contains("Default:"), "default in tip for %s" % spec["name"])
		assert_true(label.tooltip_text.contains("Used by:"), "usage in tip for %s" % spec["name"])
		assert_true(label.tooltip_text.contains(spec["tip"]))
		for c in row.find_children("*", "Control", true, false):
			if c is HSlider or c is CheckBox:
				assert_eq((c as Control).tooltip_text, label.tooltip_text, "%s control tip" % spec["name"])


func test_variant_and_preset_dropdown_items_have_tooltips() -> void:
	var panel := _panel(GrassWindParams.new())
	var variant: OptionButton = panel.get_node("Margin/VBox/VariantRow/Variant")
	for i in range(variant.item_count):
		assert_false(variant.get_item_tooltip(i).is_empty())
	var preset: OptionButton = panel.get_node("Margin/VBox/PresetRow/Preset")
	for i in range(preset.item_count):
		assert_false(preset.get_item_tooltip(i).is_empty())
