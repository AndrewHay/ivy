extends GutTest

## ivy-b1e.7 / SD-MESH-19.4.1 (ruled in ivy-b1e.23): gate (c) inside probe and closure must stay
## falsifiable. Synthetic box proxies, an analytic stand-in for the baked SDF (audit_sdf needs only
## `mesh_aabb` and `signed_distance`), no bake.
##
##   F1 closed 1 m cube, exact signed field             -> PASS, closure 0
##   F2 same cube, |phi| (unsigned everywhere)           -> FAIL: every counted inside probe not
##                                                          negative, labelled `sdf`
##   F3 cube + closed outward 0.05 m slab over air       -> PASS with the exact field AND with the
##                                                          field unsigned inside the slab: tau < 0.10
##   F4 cube + closed 0.15 m slab over air, unsigned     -> FAIL by the mid-thickness probe
##      inside the slab only
##   F5 cube with one face's triangles reversed          -> FAIL (c) closure
##   F6 cube + open single-sided sheet 0.15 m above it,  -> FAIL (c) inside, labelled `open`, not
##      signed field of the cube only                       exempted as thin

const Audit = preload("res://tools/growth_surface_audit.gd")


class AnalyticSdf:
	extends RefCounted
	var mesh_aabb: AABB
	var _fn: Callable

	func _init(bounds: AABB, fn: Callable) -> void:
		mesh_aabb = bounds
		_fn = fn

	func signed_distance(p: Vector3) -> float:
		return float(_fn.call(p))


## Triangles of an axis-aligned box, wound clockwise seen from outside (Godot front faces).
static func _box_faces(box: AABB, reverse_top := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	var lo := box.position
	var hi := box.end
	for axis in 3:
		var t1 := (axis + 1) % 3
		var t2 := (axis + 2) % 3
		for side in 2:
			var corners: Array[Vector3] = []
			for ij in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var p := Vector3.ZERO
				p[axis] = hi[axis] if side == 1 else lo[axis]
				p[t1] = hi[t1] if ij[0] == 1 else lo[t1]
				p[t2] = hi[t2] if ij[1] == 1 else lo[t2]
				corners.append(p)
			var flip := (side == 1) != (reverse_top and axis == 1 and side == 1)
			if flip:
				out.append_array([corners[0], corners[3], corners[2], corners[0], corners[2], corners[1]])
			else:
				out.append_array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]])
	return out


## An open, single-sided horizontal quad at height y, facing up.
static func _sheet_up(lo: Vector2, hi: Vector2, y: float) -> PackedVector3Array:
	var a := Vector3(lo.x, y, lo.y)
	var b := Vector3(hi.x, y, lo.y)
	var c := Vector3(hi.x, y, hi.y)
	var d := Vector3(lo.x, y, hi.y)
	# Same winding as _box_faces' top face, so its front faces up.
	return PackedVector3Array([a, b, c, a, c, d])


static func _box_sdf(p: Vector3, box: AABB) -> float:
	var q := (p - box.get_center()).abs() - box.size * 0.5
	var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
	return outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


static func _union(boxes: Array) -> Callable:
	return func(p: Vector3) -> float:
		var d := INF
		for b in boxes:
			d = minf(d, _box_sdf(p, b))
		return d


var _nodes: Array[Node] = []


func _audit(face_sets: Array, sdf) -> Dictionary:
	var proxy := StaticBody3D.new()
	proxy.collision_layer = Audit.PROXY_MASK
	proxy.collision_mask = 0
	add_child(proxy)
	for faces in face_sets:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var col := CollisionShape3D.new()
		col.shape = shape
		proxy.add_child(col)
	var two_sided: StaticBody3D = Audit.make_two_sided_proxy(self, proxy)
	_nodes = [proxy, two_sided]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var audit = Audit.new()
	audit.setup(proxy.get_world_3d().direct_space_state, [], sdf)
	audit.set_two_sided_proxy(two_sided)
	var report: Dictionary = audit.audit_sdf()
	gut.p("closure faults %d, inside n %d, not negative %d, labels %s, fails %s" % [
		report["closure_faults"], report["inside_n"], report["inside_not_negative"], report["labels"], report["fails"]])
	for node in _nodes:
		remove_child(node)
		node.free()
	_nodes = []
	await get_tree().physics_frame
	return report


func test_f1_closed_cube_with_exact_field_passes() -> void:
	var cube := AABB(Vector3(200.0, 0.0, 0.0), Vector3.ONE)
	var r: Dictionary = await _audit([_box_faces(cube)], AnalyticSdf.new(cube, _union([cube])))
	assert_eq(r["closure_faults"], 0)
	assert_gte(r["inside_n"], Audit.SDF_INSIDE_MIN_SAMPLES)
	assert_true(r["pass"], "%s" % [r["fails"]])


func test_f2_unsigned_field_fails_and_is_labelled_sdf() -> void:
	var cube := AABB(Vector3(210.0, 0.0, 0.0), Vector3.ONE)
	var exact := _union([cube])
	var unsigned := func(p: Vector3) -> float: return absf(float(exact.call(p)))
	var r: Dictionary = await _audit([_box_faces(cube)], AnalyticSdf.new(cube, unsigned))
	assert_false(r["pass"])
	assert_gt(r["inside_n"], 0)
	assert_eq(r["inside_not_negative"], r["inside_n"], "every counted inside probe reads not negative")
	assert_eq(int(r["labels"].get("sdf", 0)), r["inside_not_negative"])


func test_f3_thin_closed_slab_over_air_gets_no_inside_probe() -> void:
	var cube := AABB(Vector3(220.0, 0.0, 0.0), Vector3.ONE)
	var slab := AABB(Vector3(220.0, 0.999, 0.0), Vector3(1.6, 0.05, 1.0))  # overlaps the cube 1 mm
	var bounds := cube.merge(slab)
	var exact := _union([cube, slab])
	var r: Dictionary = await _audit([_box_faces(cube), _box_faces(slab)], AnalyticSdf.new(bounds, exact))
	assert_true(r["pass"], "exact field: %s" % [r["fails"]])
	var cube_only := _union([cube])
	var unsigned_slab := func(p: Vector3) -> float:
		if slab.has_point(p) and not cube.has_point(p):
			return absf(float(exact.call(p)))
		return float(exact.call(p))
	var r2: Dictionary = await _audit([_box_faces(cube), _box_faces(slab)], AnalyticSdf.new(bounds, unsigned_slab))
	assert_true(r2["pass"], "a slab under 0.10 m is not probed: %s" % [r2["fails"]])
	assert_gt(r2["inside_thin"], 0, "the slab's faces were seen and skipped as thin")
	assert_true(cube_only.is_valid())


func test_f4_unsigned_slab_of_0_15_m_fails_by_the_mid_thickness_probe() -> void:
	var cube := AABB(Vector3(240.0, 0.0, 0.0), Vector3.ONE)
	var slab := AABB(Vector3(240.0, 0.999, 0.0), Vector3(1.6, 0.15, 1.0))
	var bounds := cube.merge(slab)
	var exact := _union([cube, slab])
	var unsigned_slab := func(p: Vector3) -> float:
		if slab.has_point(p) and not cube.has_point(p):
			return absf(float(exact.call(p)))
		return float(exact.call(p))
	var r: Dictionary = await _audit([_box_faces(cube), _box_faces(slab)], AnalyticSdf.new(bounds, unsigned_slab))
	assert_false(r["pass"])
	assert_gt(r["inside_mid"], 0, "0.15 m thick: probed at mid-thickness")
	assert_gt(r["inside_not_negative"], 0)


func test_f5_reversed_face_fails_closure() -> void:
	var cube := AABB(Vector3(260.0, 0.0, 0.0), Vector3.ONE)
	var r: Dictionary = await _audit([_box_faces(cube, true)], AnalyticSdf.new(cube, _union([cube])))
	assert_gt(r["closure_faults"], 0)
	assert_false(r["pass"])
	assert_true(r["fails"].any(func(f): return String(f).contains("closure")), "%s" % [r["fails"]])


func test_f6_open_sheet_over_air_fails_inside_labelled_open() -> void:
	var cube := AABB(Vector3(280.0, 0.0, 0.0), Vector3.ONE)
	var sheet := _sheet_up(Vector2(280.0, 0.0), Vector2(281.0, 1.0), 1.15)
	var bounds := cube.merge(AABB(Vector3(280.0, 1.15, 0.0), Vector3(1.0, 0.001, 1.0)))
	var r: Dictionary = await _audit([_box_faces(cube), sheet], AnalyticSdf.new(bounds, _union([cube])))
	assert_false(r["pass"])
	assert_gt(r["inside_not_negative"], 0)
	assert_gt(int(r["labels"].get("open", 0)), 0, "labelled open: %s" % [r["labels"]])
	assert_eq(int(r["labels"].get("sdf", 0)), 0)
