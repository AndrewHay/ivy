extends GutTest

const PlaygroundScene = preload("res://scenes/playground/grass_wind_playground.tscn")
const KnobPanel = preload("res://src/playground/knob_panel.gd")


func test_lawn_grid_mesh_has_line_segments() -> void:
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	var grid := root.get_node_or_null("Lawn/Grid") as MeshInstance3D
	assert_not_null(grid.mesh)
	var arrays := (grid.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_gt(verts.size(), 8, "1 m grid should emit multiple line vertices")


func test_scene_loads_headless_with_lawn() -> void:
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	var lawn := root.get_node_or_null("Lawn/GrassMultiMesh") as MultiMeshInstance3D
	assert_not_null(lawn, "Lawn MultiMeshInstance3D exists")
	assert_gt(lawn.multimesh.instance_count, 0, "Lawn has blade tufts")


func test_preset_dropdown_shows_production_at_defaults() -> void:
	var panel := KnobPanel.new()
	var params := preload("res://src/playground/grass_wind_params.gd").new()
	panel.build_from_spec(
		preload("res://src/playground/grass_wind_knob_spec.gd").all_knobs(),
		params,
		preload("res://src/playground/grass_wind_params.gd").presets())
	add_child_autofree(panel)
	var preset_btn: OptionButton = panel.get_node("Margin/VBox/PresetRow/Preset")
	assert_eq(
		preset_btn.get_item_text(preset_btn.selected),
		"Production",
		"Default params should show Production preset, not alphabetical first")


func test_preset_dropdown_shows_production_after_reset() -> void:
	var panel := KnobPanel.new()
	var params := preload("res://src/playground/grass_wind_params.gd").new()
	panel.build_from_spec(
		preload("res://src/playground/grass_wind_knob_spec.gd").all_knobs(),
		params,
		preload("res://src/playground/grass_wind_params.gd").presets())
	add_child_autofree(panel)
	params.apply_preset("Blustery")
	panel.refresh_values()
	params.reset_to_production()
	panel.set_variant(0)
	panel.refresh_values()
	var preset_btn: OptionButton = panel.get_node("Margin/VBox/PresetRow/Preset")
	assert_eq(preset_btn.get_item_text(preset_btn.selected), "Production")


func test_knob_panel_variant_selector_includes_production() -> void:
	var panel := KnobPanel.new()
	panel.build_from_spec(
		preload("res://src/playground/grass_wind_knob_spec.gd").all_knobs(),
		preload("res://src/playground/grass_wind_params.gd").new(),
		preload("res://src/playground/grass_wind_params.gd").presets())
	add_child_autofree(panel)
	var variant_btn: OptionButton = panel.get_node("Margin/VBox/VariantRow/Variant")
	assert_gte(variant_btn.item_count, 3)
	var labels: PackedStringArray = []
	for i in range(variant_btn.item_count):
		labels.append(variant_btn.get_item_text(i))
	assert_true(labels[0].contains("0"), "First variant is production")
	assert_gt(panel.get_node("Margin/VBox/KnobScroll/KnobVBox").get_child_count(), 8)
