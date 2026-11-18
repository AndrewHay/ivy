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


func test_point_in_outline_is_vertex_robust_ivy_5anf() -> void:
	## ivy-5anf: Geometry2D.is_point_in_polygon on the 720-point outline reported these points (8.5 m
	## and 25 m from the seed-7 generated centre, outline max r 3.3 m) as in the water.
	var shape := VillagePondShape.at(Vector2(-18.12696, -26.29458))
	assert_false(shape._is_in_water(Vector2(-25.5273, -30.37608)), "8.5 m away: not in water")
	assert_false(shape._is_in_water(Vector2(-29.49546, -48.8884)), "25 m away: not in water")
	assert_true(shape._is_in_water(Vector2(-18.12696, -26.29458)), "centre is in water")
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)])
	assert_true(VillagePondShape.point_in_outline(Vector2(1, 1), poly), "inside square")
	assert_false(VillagePondShape.point_in_outline(Vector2(3, 1), poly), "outside square")
	assert_false(VillagePondShape.point_in_outline(Vector2(-1, 0), poly), "ray through a vertex: outside")


func test_bank_ring_wraps_water() -> void:
	var water := VillagePondShape.water_render_outline_xz()
	var bank := VillagePondShape.bank_outer_outline_xz()
	assert_eq(water.size(), bank.size())
	var center := VillageScatterPositions.pond_center_xz()
	for i in range(water.size()):
		var rw := water[i].distance_to(center)
		var rb := bank[i].distance_to(center)
		assert_gt(rb, rw)
