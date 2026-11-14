extends GutTest

## ivy-b1e.2 — the growth-surface audit (SG-9 a-c) must be falsifiable.
##
## A bounding-box proxy over a ribbed hero wall (what `cottage_sim_shell_from_hero` builds for the
## cottage's straight walls) has to FAIL the gap gate (a) and the concavity gate (b); a proxy that
## carries the ribs has to PASS both.

const Audit = preload("res://tools/growth_surface_audit.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")

## Slab 0.30 m thick with its outer face at x = 0 (facing -X); ribs stand proud of it.
const SLAB_SIZE := Vector3(0.30, 2.0, 2.0)
const RIB_PROUD := 0.10
const RIB_WIDTH := 0.10
const RIB_Z: Array[float] = [0.2, 0.65, 1.1, 1.55]  # 0.45 m spacing
const SAMPLES := 400


func _hero_boxes(offset: Vector3) -> Array[AABB]:
	var out: Array[AABB] = [AABB(offset, SLAB_SIZE)]
	for z in RIB_Z:
		out.append(AABB(offset + Vector3(-RIB_PROUD, 0.0, z), Vector3(RIB_PROUD, SLAB_SIZE.y, RIB_WIDTH)))
	return out


## Triangles of an axis-aligned box, wound clockwise seen from outside (Godot front faces).
static func _box_faces(box: AABB) -> PackedVector3Array:
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
			if side == 1:
				out.append_array([corners[0], corners[3], corners[2], corners[0], corners[2], corners[1]])
			else:
				out.append_array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]])
	return out


static func _box_sdf(p: Vector3, box: AABB) -> float:
	var q := (p - box.get_center()).abs() - box.size * 0.5
	var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
	return outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


## Exact (outside) signed distance to a union of boxes, sampled at cell centres like the baker.
static func _analytic_sdf(boxes: Array[AABB]) -> MeshSdf:
	var sdf := MeshSdf.new()
	sdf.h = 0.05
	sdf.band = 0.55
	var bounds := boxes[0]
	for box in boxes:
		bounds = bounds.merge(box)
	sdf.mesh_aabb = bounds
	var lo := bounds.position - Vector3.ONE * sdf.band
	var hi := bounds.end + Vector3.ONE * sdf.band
	sdf.origin = (lo / sdf.h).floor() * sdf.h
	sdf.dims = Vector3i(
		int((hi.x - sdf.origin.x) / sdf.h) + 1,
		int((hi.y - sdf.origin.y) / sdf.h) + 1,
		int((hi.z - sdf.origin.z) / sdf.h) + 1
	)
	var data := PackedFloat32Array()
	data.resize(sdf.dims.x * sdf.dims.y * sdf.dims.z)
	var i := 0
	for iz in sdf.dims.z:
		for iy in sdf.dims.y:
			for ix in sdf.dims.x:
				var p := sdf.origin + (Vector3(ix, iy, iz) + Vector3(0.5, 0.5, 0.5)) * sdf.h
				var d := INF
				for box in boxes:
					d = minf(d, _box_sdf(p, box))
				data[i] = clampf(d, -sdf.band, sdf.band)
				i += 1
	sdf._data = data
	return sdf


func _run_case(offset: Vector3, proxy_boxes: Array[AABB]) -> Dictionary:
	var pieces: Array = []
	var hero_boxes := _hero_boxes(offset)
	for i in hero_boxes.size():
		pieces.append({
			"name": "t_hero_Wall_Ribbed_part_%d" % i,
			"faces": _box_faces(hero_boxes[i]),
			"transform": Transform3D.IDENTITY,
		})
	var proxy := StaticBody3D.new()
	proxy.collision_layer = Audit.PROXY_MASK
	proxy.collision_mask = 0
	add_child(proxy)
	for box in proxy_boxes:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_box_faces(box))
		var col := CollisionShape3D.new()
		col.shape = shape
		proxy.add_child(col)
	var hero_body: StaticBody3D = Audit.make_hero_body(self, pieces)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var audit = Audit.new()
	audit.setup(proxy.get_world_3d().direct_space_state, pieces, _analytic_sdf(proxy_boxes))
	var report: Dictionary = audit.run({"samples": SAMPLES, "seed": 7})
	gut.p(Audit.format_report("ribbed test wall", report))
	remove_child(hero_body)
	hero_body.free()
	remove_child(proxy)
	proxy.free()
	await get_tree().physics_frame
	return report


func test_bounding_box_proxy_over_ribbed_hero_fails_gap_and_concavity() -> void:
	var offset := Vector3(40.0, 0.0, 0.0)
	var bounding_box := AABB(offset + Vector3(-RIB_PROUD, 0.0, 0.0), SLAB_SIZE + Vector3(RIB_PROUD, 0.0, 0.0))
	var report: Dictionary = await _run_case(offset, [bounding_box])
	var a: Dictionary = report["a"]
	var b: Dictionary = report["b"]
	assert_eq(a["n"], SAMPLES, "enough ivy-reachable hero samples")
	assert_false(a["pass"], "(a) must fail: the wall between the ribs is 0.10 m behind the box face")
	assert_almost_eq(a["p95_abs"], RIB_PROUD, 0.01)
	assert_gt(a["float_share"], 0.2, "the recessed wall floats, it does not clip")
	assert_almost_eq(a["clip_share"], 0.0, 0.001)
	assert_false(b["pass"], "(b) must fail: the recesses between ribs are absent from the box")
	assert_gte(b["unrepresented"], 3)
	for cv in b["concavities"]:
		if String(cv["view"]).begins_with("west"):
			assert_almost_eq(cv["hero_depth"], RIB_PROUD, 0.01)
			assert_almost_eq(cv["proxy_depth"], 0.0, 0.01)
			assert_false(cv["represented"])
	assert_false(report["pass"])
	# The box itself is a sound solid: its analytic SDF agrees with its collision faces.
	assert_lt(report["c"]["face_median"], 0.005)
	assert_eq(report["c"]["inside_not_negative"], 0)


func test_proxy_that_carries_the_ribs_passes_gap_and_concavity() -> void:
	var offset := Vector3(60.0, 0.0, 0.0)
	var report: Dictionary = await _run_case(offset, _hero_boxes(offset))
	var a: Dictionary = report["a"]
	var b: Dictionary = report["b"]
	assert_eq(a["n"], SAMPLES)
	assert_true(a["pass"], "(a) p95|g| %.4f max|g| %.4f" % [a["p95_abs"], a["max_abs"]])
	assert_gte(b["listed"], 3, "the recesses between ribs are found on the hero")
	assert_true(b["pass"], "(b) every hero recess is in the proxy: %d missing" % b["unrepresented"])


func test_classify_keeps_the_sd_open_27_exclusions_and_names_cottage_pieces() -> void:
	assert_true(Audit.classify("ivy_hero_Seal_ivy_ground_wide_win_W_0_glass") in Audit.UNREACHABLE_CATEGORIES)
	assert_true(Audit.classify("tower_hero_Corner_ExteriorWide_Brick_0") in Audit.UNREACHABLE_CATEGORIES)
	assert_true(Audit.classify("tower_hero_Door_2_Round_S_1") in Audit.UNREACHABLE_CATEGORIES)
	assert_eq(Audit.classify("ivy_hero_Wall_Plaster_Straight_left_1"), "wall_straight")
	assert_eq(Audit.classify("ivy_hero_Wall_Plaster_Window_Wide_Flat_left_0"), "wall_window_bay")
	assert_eq(Audit.classify("ivy_hero_WindowShutters_Wide_Flat_Closed_left_0"), "shutter")
	assert_eq(Audit.classify("ivy_hero_Roof_Front_Brick4_-1"), "gable")
	assert_false(Audit.classify("ivy_hero_Roof_RoundTiles_4x6") in Audit.UNREACHABLE_CATEGORIES)
