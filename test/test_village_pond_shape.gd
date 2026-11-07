extends GutTest


func before_each() -> void:
	VillagePondShape.clear_cache_for_tests()


func test_water_outline_is_noisy_not_a_circle() -> void:
	var poly := VillagePondShape.water_outline_xz()
	assert_gte(poly.size(), 120, "noisy edges + irregular seed produce a dense loop")
	var center := VillageScatterPositions.pond_center_xz()
	var radii: Array[float] = []
	for v in poly:
		radii.append(v.distance_to(center))
	radii.sort()
	var r_span := radii[-1] - radii[0]
	assert_gt(r_span, 0.52, "pond should be clearly non-circular (irregular seed + noise)")


func test_water_outline_deterministic() -> void:
	var a := VillagePondShape.water_outline_xz()
	VillagePondShape.clear_cache_for_tests()
	var b := VillagePondShape.water_outline_xz()
	assert_eq(a.size(), b.size())
	for i in range(a.size()):
		assert_almost_eq(a[i].x, b[i].x, 1e-5)
		assert_almost_eq(a[i].y, b[i].y, 1e-5)


func test_water_mesh_triangulates() -> void:
	var mesh := VillagePondShape.build_water_surface_mesh(0.01)
	assert_gte(mesh.get_surface_count(), 1)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_gte(verts.size(), 700, "render spline should land on the mesh boundary")
	assert_gt(indices.size(), 0)
	assert_eq(indices.size() % 3, 0)
	assert_gt(indices.size(), 1400, "concave pond must ear-clip, not fan-fallback")
	for idx in indices:
		assert_gte(idx, 0)
		assert_lt(idx, verts.size())


func test_render_outline_is_densified_spline() -> void:
	assert_gte(VillagePondShape.water_render_outline_xz().size(), 700)


func test_bank_ring_wraps_water() -> void:
	var water := VillagePondShape.water_render_outline_xz()
	var bank := VillagePondShape.bank_outer_outline_xz()
	assert_eq(water.size(), bank.size())
	var center := VillageScatterPositions.pond_center_xz()
	for i in range(water.size()):
		var rw := water[i].distance_to(center)
		var rb := bank[i].distance_to(center)
		assert_gt(rb, rw)
