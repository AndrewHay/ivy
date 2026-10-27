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


func test_blade_tuft_roots_near_origin() -> void:
	var mesh := _tuft_mesh()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	for i in range(verts.size()):
		if uvs[i].y >= 0.99:
			var xz := Vector2(verts[i].x, verts[i].z)
			assert_lte(xz.length(), 0.05 + 0.036, "Root XZ within 0.05 m (+ blade half-width slack)")

