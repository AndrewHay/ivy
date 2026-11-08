## SD-GRASS-2 blade tuft mesh (VillageGrassMesh.blade_tuft_mesh).
extends GutTest


func _tuft_mesh() -> ArrayMesh:
	return VillageGrassMesh.blade_tuft_mesh()


func test_blade_tuft_deterministic() -> void:
	var a := _tuft_mesh()
	var b := _tuft_mesh()
	var arr_a := a.surface_get_arrays(0)
	var arr_b := b.surface_get_arrays(0)
	assert_eq(arr_a[Mesh.ARRAY_VERTEX], arr_b[Mesh.ARRAY_VERTEX], "Vertex positions match")
	assert_eq(arr_a[Mesh.ARRAY_TEX_UV], arr_b[Mesh.ARRAY_TEX_UV], "UVs match")
	assert_eq(arr_a[Mesh.ARRAY_COLOR], arr_b[Mesh.ARRAY_COLOR], "Colors match")


func test_blade_tuft_thirty_five_triangles() -> void:
	var mesh := _tuft_mesh()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size() % 3, 0, "Triangle list")
	assert_eq(verts.size() / 3, 35, "7 blades × 5 tris")


func test_blade_tuft_uv_conventions() -> void:
	var mesh := _tuft_mesh()
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tip_uv := Vector2(0.5, 0.0)
	var found_tip := false
	for i in range(verts.size()):
		if verts[i].y > 0.14 and uvs[i].is_equal_approx(tip_uv):
			found_tip = true
			break
	assert_true(found_tip, "At least one tip vertex at UV (0.5, 0)")
	for uv in uvs:
		assert_gte(uv.x, 0.0, "UV.x lower bound")
		assert_lte(uv.x, 1.0, "UV.x upper bound")
		assert_gte(uv.y, 0.0, "UV.y lower bound")
		assert_lte(uv.y, 1.0, "UV.y upper bound")


func test_blade_tuft_color_hash_per_blade() -> void:
	var mesh := _tuft_mesh()
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var seen: Dictionary = {}
	for c in colors:
		var key := snappedf(c.r, 0.0001)
		seen[key] = true
	assert_gte(seen.size(), 5, "Distinct per-blade hashes in COLOR.r")


func test_grass_camera_dissolve_constants() -> void:
	assert_eq(VillageScatterPositions.GRASS_CAMERA_DISSOLVE_START_M, 14.0)
	assert_eq(
		VillageScatterPositions.GRASS_CAMERA_DISSOLVE_END_GENERATED_M,
		VillageScatterPositions.GRASS_CAMERA_DISSOLVE_END_DEFAULT_M)
	var vis := VillageScatterPositions.grass_chunk_visibility_end_m(
		VillageScatterPositions.GRASS_CAMERA_DISSOLVE_END_GENERATED_M)
	assert_almost_eq(vis, 30.0 + VillageScatterPositions.GRASS_BLADE_CHUNK_HALF_DIAGONAL_M, 0.02)


func test_grass_blade_shader_per_camera_dissolve() -> void:
	var f := FileAccess.open("res://src/render/shaders/grass_blade.gdshader", FileAccess.READ)
	assert_not_null(f)
	var text := f.get_as_text()
	f.close()
	assert_true(text.contains("dissolve_start"), "Shader must expose dissolve_start")
	assert_true(text.contains("dissolve_end"), "Shader must expose dissolve_end")
	assert_true(text.contains("dissolve_active"), "Shader dissolve_active for classic no-op")
	assert_true(text.contains("v_hash") or text.contains("COLOR.r"), "Stable per-blade hash for dissolve")
	assert_false(_vertex_body_has_early_return(text), "vertex() must not early-return (breaks varyings)")


func _vertex_body_has_early_return(shader_text: String) -> bool:
	var start := shader_text.find("void vertex()")
	assert_gt(start, -1, "vertex()")
	var body_start := shader_text.find("{", start)
	var body_end := shader_text.find("}", body_start)
	var body := shader_text.substr(body_start, body_end - body_start + 1)
	return body.contains("return;")


func test_grass_blade_classic_shader_fragment_parity() -> void:
	var dissolve := _read_shader("res://src/render/shaders/grass_blade.gdshader")
	var classic := _read_shader("res://src/render/shaders/grass_blade_classic.gdshader")
	var frag_d := _extract_shader_function_body(dissolve, "fragment")
	var frag_c := _extract_shader_function_body(classic, "fragment")
	frag_d = frag_d.replace(
		"\tif (dissolve_active > 0.5 && v_hash > v_keep) {\n\t\tdiscard;\n\t}\n", "")
	assert_eq(frag_d, frag_c, "fragment() must match classic after dissolve discard removed")


func test_grass_blade_classic_shader_vertex_parity() -> void:
	var dissolve := _read_shader("res://src/render/shaders/grass_blade.gdshader")
	var classic := _read_shader("res://src/render/shaders/grass_blade_classic.gdshader")
	var vert_d := _strip_dissolve_vertex_block(
		_extract_shader_function_body(dissolve, "vertex"))
	var vert_c := _extract_shader_function_body(classic, "vertex")
	assert_eq(vert_d, vert_c, "vertex() must match classic after dissolve block removed")


func _read_shader(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, path)
	var text := f.get_as_text()
	f.close()
	return text


func _extract_shader_function_body(text: String, func_name: String) -> String:
	var needle := "void %s()" % func_name
	var start := text.find(needle)
	assert_gt(start, -1, "Missing %s" % func_name)
	var body_start := text.find("{", start)
	var depth := 0
	for i in range(body_start, text.length()):
		var ch := text[i]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				return text.substr(body_start, i - body_start + 1)
	push_error("Unbalanced braces in %s" % func_name)
	return ""


func _strip_dissolve_vertex_block(vertex_body: String) -> String:
	var marker := "\tv_keep = 1.0;"
	var cut := vertex_body.find(marker)
	assert_gt(cut, -1, "Generated vertex() must set v_keep before dissolve")
	return vertex_body.substr(0, cut).strip_edges() + "\n}"


func test_grass_blade_shader_albedo_srgb_to_linear() -> void:
	var f := FileAccess.open("res://src/render/shaders/grass_blade.gdshader", FileAccess.READ)
	assert_not_null(f, "grass_blade.gdshader must exist")
	var text := f.get_as_text()
	f.close()
	assert_true(
		text.contains("srgb_to_linear") or text.contains("pow("),
		"Blade albedo colours must be converted sRGB→linear for ALBEDO")


func test_blade_tuft_roots_near_origin() -> void:
	var mesh := _tuft_mesh()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	for i in range(verts.size()):
		if uvs[i].y >= 0.99:
			var xz := Vector2(verts[i].x, verts[i].z)
			assert_lte(xz.length(), 0.05 + 0.036, "Root XZ within 0.05 m (+ blade half-width slack)")

