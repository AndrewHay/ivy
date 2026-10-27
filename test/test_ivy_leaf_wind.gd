extends GutTest

const PlantRender = preload("res://src/render/plant_render.gd")


func _read_shader(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, path)
	var text := f.get_as_text()
	f.close()
	return text


func test_plant_render_does_not_push_per_material_wind() -> void:
	var text := FileAccess.get_file_as_string("res://src/render/plant_render.gd")
	assert_false(text.contains("func push_wind"), "PlantRender must not push per-material wind uniforms")
	assert_false(text.contains("wind_direction_xz"), "No leaf wind uniform pushes on CPU")


func test_leaf_shader_includes_wind_gust_not_foliage() -> void:
	var text := _read_shader("res://src/render/shaders/leaf.gdshader")
	assert_true(text.contains("wind_gust.gdshaderinc"), "leaf.gdshader must include wind_gust")
	assert_false(text.contains("foliage_wind"), "leaf.gdshader must not include foliage_wind")
	assert_true(
		text.contains("ivy_leaf_wind_offset_model"),
		"leaf vertex must call ivy_leaf_wind_offset_model")


func test_leaf_wind_flutter_phase_uses_integer_multiple_only() -> void:
	for path in [
		"res://src/render/shaders/leaf.gdshader",
		"res://src/render/shaders/wind_gust.gdshaderinc",
	]:
		var text := _read_shader(path)
		var re := RegEx.new()
		re.compile("ivy_wind_flutter_phase\\s*\\*\\s*([0-9]+(?:\\.[0-9]+)?)")
		var m := re.search(text)
		while m != null:
			var factor := m.get_string(1)
			assert_true(
				factor == "2.0" or factor == "2",
				"Non-integer flutter phase scale %s in %s" % [factor, path])
			m = re.search(text, m.get_end())
	assert_false(
		FileAccess.file_exists("res://src/render/shaders/foliage_wind.gdshaderinc"),
		"foliage_wind.gdshaderinc should be removed when unused")


func test_wind_gust_declares_ivy_leaf_helper() -> void:
	var text := _read_shader("res://src/render/shaders/wind_gust.gdshaderinc")
	assert_true(
		text.contains("ivy_leaf_wind_offset_model"),
		"wind_gust.gdshaderinc must declare ivy_leaf_wind_offset_model")
	assert_true(
		text.contains("ivy_wind_tip_displace_model"),
		"grass helper must remain in wind_gust include")


func test_main_does_not_push_leaf_or_foliage_wind() -> void:
	var text := FileAccess.get_file_as_string("res://src/main/main.gd")
	assert_false(text.contains("push_wind"), "main.gd must not call push_wind")
	assert_false(text.contains("push_foliage_wind"), "main.gd must not call push_foliage_wind")


func test_plant_render_still_configures() -> void:
	var pr := PlantRender.new()
	assert_false(pr.is_configured())
