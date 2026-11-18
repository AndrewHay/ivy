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


func test_point_in_outline_vertex_ray_inside_bbox_ivy_5anf() -> void:
	## Review 2 F3: every case must sit INSIDE the bbox so the crossing rule (not the bbox
	## early-out) decides. Diamond: the ray y=0 passes exactly through the vertices (2,0) / (-2,0).
	var diamond := PackedVector2Array([Vector2(0, -2), Vector2(2, 0), Vector2(0, 2), Vector2(-2, 0)])
	assert_true(VillagePondShape.point_in_outline(Vector2(0, 0), diamond),
		"diamond centre: ray passes through vertex (2,0), inside")
	assert_true(VillagePondShape.point_in_outline(Vector2(-1.5, 0), diamond),
		"near the left vertex on the vertex row: inside")
	assert_false(VillagePondShape.point_in_outline(Vector2(1.5, 1.5), diamond),
		"in bbox, outside the diamond")
	## Concave 'W' top: the ray y=2 passes through the reflex vertex (2,2) and the tip (4,4) is above.
	## (0,0) (4,0) (4,4) (2,2) (0,4): points on y=2 left of the notch are inside; right of x=2 at
	## y=3 is inside the right lobe; (2,3) sits in the notch (outside) but inside the bbox.
	var concave := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(2, 2), Vector2(0, 4)])
	assert_true(VillagePondShape.point_in_outline(Vector2(1, 2), concave),
		"ray through reflex vertex (2,2): inside")
	assert_true(VillagePondShape.point_in_outline(Vector2(3, 2), concave),
		"right of the reflex vertex on its row: inside")
	assert_false(VillagePondShape.point_in_outline(Vector2(2, 3), concave),
		"in the notch above the reflex vertex: outside")
	assert_true(VillagePondShape.point_in_outline(Vector2(3.5, 3), concave), "right lobe: inside")
	## Ray through a horizontal edge's endpoints (square bottom edge at y=0 shifted inside bbox):
	var notch := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(2, 1),
		Vector2(2, 0), Vector2(3, 0), Vector2(3, 3), Vector2(0, 3)])
	assert_true(VillagePondShape.point_in_outline(Vector2(0.5, 1), notch),
		"ray along the notch's horizontal edge y=1: inside")
	assert_false(VillagePondShape.point_in_outline(Vector2(1.5, 0.5), notch),
		"inside the notch (in bbox): outside")


func test_pond_shape_has_no_godot_point_in_polygon_calls_ivy_5anf() -> void:
	## Review 2 F3: the migration must be complete — one point-in-polygon rule for every pond query.
	var src := FileAccess.get_file_as_string("res://src/world/village_pond_shape.gd")
	assert_false(src.is_empty(), "source readable")
	var calls := src.count("Geometry2D.is_point_in_polygon(")
	assert_eq(calls, 0, "village_pond_shape.gd still calls Geometry2D.is_point_in_polygon %d time(s)" % calls)


func test_all_pond_shape_queries_use_vertex_robust_test_ivy_5anf() -> void:
	## Review 2 F3: the grass / bank / scatter queries still used Geometry2D.is_point_in_polygon.
	## They must agree with point_in_outline on the same outlines everywhere, including the ivy-5anf
	## repro points far outside the seed-7 generated pond.
	var shape := VillagePondShape.at(Vector2(-18.12696, -26.29458))
	shape._ensure_grass_shoreline_rays()
	var probes: Array[Vector2] = [Vector2(-25.5273, -30.37608), Vector2(-29.49546, -48.8884)]
	var c := shape.center_xz()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(600):
		probes.append(c + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0)))
	## Points on the outlines' own vertex rows (horizontal rays through vertices).
	var bank := shape._bank_outer_outline_local()
	for i in range(0, bank.size(), 7):
		probes.append(Vector2(c.x - 0.37, bank[i].y))
		probes.append(Vector2(c.x + 0.41, bank[i].y))
	var mism := 0
	for p: Vector2 in probes:
		if shape._is_in_water_grass_exclusion(p) != VillagePondShape.point_in_outline(p, shape._grass_water_exclusion_fast):
			mism += 1
		if shape._is_on_bank_outer_grass(p) != VillagePondShape.point_in_outline(p, shape._grass_bank_outer_fast):
			mism += 1
		if shape._blocks_scatter_at(p) != VillagePondShape.point_in_outline(p, shape._scatter_exclusion_outline_local()):
			mism += 1
		var on_bank := VillagePondShape.point_in_outline(p, bank) and not shape._is_in_water(p, 0.04)
		if (shape._bank_shoreline_along(p) >= 0.0) != on_bank:
			mism += 1
		if (shape._bank_shoreline_along_grass(p) >= 0.0) != on_bank:
			mism += 1
	assert_eq(mism, 0, "grass/bank/scatter queries disagree with point_in_outline at %d probe(s)" % mism)
	for p: Vector2 in [Vector2(-25.5273, -30.37608), Vector2(-29.49546, -48.8884)]:
		assert_false(shape._blocks_scatter_at(p), "ivy-5anf repro point blocks scatter: %s" % p)
		assert_false(shape._is_in_water_grass_exclusion(p), "ivy-5anf repro point in grass exclusion: %s" % p)
		assert_false(shape._is_on_bank_outer_grass(p), "ivy-5anf repro point on grass bank: %s" % p)
		assert_eq(shape._bank_shoreline_along(p), -1.0, "ivy-5anf repro point on bank: %s" % p)
		assert_eq(shape._bank_shoreline_along_grass(p), -1.0, "ivy-5anf repro point on grass bank: %s" % p)


func test_bank_ring_wraps_water() -> void:
	var water := VillagePondShape.water_render_outline_xz()
	var bank := VillagePondShape.bank_outer_outline_xz()
	assert_eq(water.size(), bank.size())
	var center := VillageScatterPositions.pond_center_xz()
	for i in range(water.size()):
		var rw := water[i].distance_to(center)
		var rb := bank[i].distance_to(center)
		assert_gt(rb, rw)
