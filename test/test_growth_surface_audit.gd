extends GutTest

## ivy-b1e.2 / ivy-b1e.12 — the growth-surface audit (SG-9 a-c) must be falsifiable, and its
## gates are the ratified ones (IMPLEMENTATION.md SD-MESH-19.4).
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


func _run_case(offset: Vector3, proxy_boxes: Array[AABB], hero_override: Array[AABB] = []) -> Dictionary:
	var pieces: Array = []
	var hero_boxes := _hero_boxes(offset) if hero_override.is_empty() else hero_override
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
	var a: Dictionary = report["a"]["walls"]
	var b: Dictionary = report["b"]
	assert_eq(a["n"], SAMPLES, "enough ivy-reachable hero samples")
	assert_false(a["pass"], "(a) must fail: the wall between the ribs is 0.10 m behind the box face")
	assert_false(report["a"]["pass"])
	assert_almost_eq(a["p95_abs"], RIB_PROUD, 0.01)
	assert_gt(a["float_share"], 0.2, "the recessed wall floats, it does not clip")
	assert_almost_eq(a["clip_share"], 0.0, 0.001)
	assert_false(report["a"]["roof"]["present"], "no tiled roof field on the test wall")
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
	var a: Dictionary = report["a"]["walls"]
	var b: Dictionary = report["b"]
	assert_eq(a["n"], SAMPLES)
	assert_true(a["pass"], "(a) %s" % [a["fails"]])
	assert_true(report["a"]["pass"])
	assert_lte(a["p95_abs"], Audit.GAP_W_P95_MAX)
	assert_lte(a["p99_abs"], Audit.GAP_W_P99_MAX)
	assert_gte(b["listed"], 3, "the recesses between ribs are found on the hero")
	assert_true(b["pass"], "(b) every hero recess is in the proxy: %d missing" % b["unrepresented"])
	# An exact box SDF read trilinearly peaks near 0.015 m at sharp edges: inside the 0.025 m cap.
	assert_true(report["c"]["pass"], "(c) %s" % [report["c"]["fails"]])


## Slab of SLAB_SIZE with its outer face at x = 0 (facing -X) and a slot SLOT_WIDTH wide and
## SLOT_DEPTH deep cut into that face, SLOT_EDGE_GAP from the slab's +Z end: like slot S1 on the
## relief article (SD-MESH-19.5), which sits 0.26 m from the article's end.
const SLOT_Z0 := 1.70
const SLOT_WIDTH := 0.04
const SLOT_DEPTH := 0.10
const SLOT_Y := Vector2(0.5, 1.5)


func _slotted_slab(offset: Vector3) -> Array[AABB]:
	var front := SLOT_DEPTH
	var z1 := SLOT_Z0 + SLOT_WIDTH
	return [
		AABB(offset + Vector3(front, 0.0, 0.0), SLAB_SIZE - Vector3(front, 0.0, 0.0)),
		AABB(offset, Vector3(front, SLAB_SIZE.y, SLOT_Z0)),
		AABB(offset + Vector3(0.0, 0.0, z1), Vector3(front, SLAB_SIZE.y, SLAB_SIZE.z - z1)),
		AABB(offset + Vector3(0.0, 0.0, SLOT_Z0), Vector3(front, SLOT_Y.x, SLOT_WIDTH)),
		AABB(offset + Vector3(0.0, SLOT_Y.y, SLOT_Z0), Vector3(front, SLAB_SIZE.y - SLOT_Y.y, SLOT_WIDTH)),
	]


## SD-MESH-19.2: a slot narrower than 0.10 m is closed in the growth surface and never listed.
## A proxy that bridges it flush must pass (a) and (b), and (b) must list nothing around it: the
## depth-map pass used to report the strip between the slot and the slab's end as a missing proud
## feature (AR-MESH-20.11; the article's "(1.58, 1.54)" and the cottage shutter boards).
func test_slot_under_ten_centimetres_closed_by_the_proxy_is_not_a_feature() -> void:
	var offset := Vector3(80.0, 0.0, 0.0)
	var proxy: Array[AABB] = [AABB(offset, SLAB_SIZE)]
	var report: Dictionary = await _run_case(offset, proxy, _slotted_slab(offset))
	var a: Dictionary = report["a"]["walls"]
	var b: Dictionary = report["b"]
	assert_gt(a["in_slot"], 0, "hero samples inside the slot are classified not reachable")
	assert_true(a["pass"], "(a) %s" % [a["fails"]])
	assert_true(b["pass"], "(b) a closed narrow slot leaves nothing missing: %d missing" % b["unrepresented"])
	for cv in b["concavities"]:
		var c: Array = cv["centre"]
		var near_slot := absf(float(c[0]) - offset.x) < 0.2 and float(c[2]) - offset.z > SLOT_Z0 - 0.5
		assert_false(near_slot and String(cv["view"]).begins_with("west"),
			"(b) lists a %s feature beside the slot at %s" % [cv["kind"], c])


## The slot fix must not hide real relief: the same slab with a recess 0.16 m wide (just over the
## 0.15 m floor, like M1) next to the end is still listed and, against a flat proxy, missing.
func test_recess_wider_than_the_floor_is_still_listed_and_missing_from_a_flat_proxy() -> void:
	var offset := Vector3(100.0, 0.0, 0.0)
	var wide := 0.16
	var z1 := SLOT_Z0 + wide
	var hero: Array[AABB] = [
		AABB(offset + Vector3(SLOT_DEPTH, 0.0, 0.0), SLAB_SIZE - Vector3(SLOT_DEPTH, 0.0, 0.0)),
		AABB(offset, Vector3(SLOT_DEPTH, SLAB_SIZE.y, SLOT_Z0)),
		AABB(offset + Vector3(0.0, 0.0, z1), Vector3(SLOT_DEPTH, SLAB_SIZE.y, SLAB_SIZE.z - z1)),
		AABB(offset + Vector3(0.0, 0.0, SLOT_Z0), Vector3(SLOT_DEPTH, SLOT_Y.x, wide)),
		AABB(offset + Vector3(0.0, SLOT_Y.y, SLOT_Z0), Vector3(SLOT_DEPTH, SLAB_SIZE.y - SLOT_Y.y, wide)),
	]
	var proxy: Array[AABB] = [AABB(offset, SLAB_SIZE)]
	var report: Dictionary = await _run_case(offset, proxy, hero)
	var b: Dictionary = report["b"]
	assert_false(b["pass"], "(b) a 0.16 m recess bridged by the proxy is missing")
	var found := false
	for cv in b["concavities"]:
		var c: Array = cv["centre"]
		if cv["kind"] == "recess" and String(cv["view"]).begins_with("west") \
				and absf(float(c[2]) - offset.z - (SLOT_Z0 + wide * 0.5)) < 0.05:
			found = true
			assert_almost_eq(float(cv["hero_depth"]), SLOT_DEPTH, 0.01)
			assert_false(cv["represented"])
	assert_true(found, "the 0.16 m recess is listed")


## A recess deeper than half a thin structure's thickness is still found: the relief article's
## niche N1 is 0.20 m deep in a 0.45 m wall (SD-MESH-19.5), and the depth maps used to stop at the
## structure's mid-plane, so (b) never listed it.
func test_deep_recess_in_a_thin_slab_is_listed() -> void:
	var offset := Vector3(120.0, 0.0, 0.0)
	var deep := 0.20
	var z0 := 0.70
	var z1 := 1.30
	var y0 := 0.60
	var y1 := 1.50
	var hero: Array[AABB] = [
		AABB(offset + Vector3(deep, 0.0, 0.0), SLAB_SIZE - Vector3(deep, 0.0, 0.0)),
		AABB(offset, Vector3(deep, SLAB_SIZE.y, z0)),
		AABB(offset + Vector3(0.0, 0.0, z1), Vector3(deep, SLAB_SIZE.y, SLAB_SIZE.z - z1)),
		AABB(offset + Vector3(0.0, 0.0, z0), Vector3(deep, y0, z1 - z0)),
		AABB(offset + Vector3(0.0, y1, z0), Vector3(deep, SLAB_SIZE.y - y1, z1 - z0)),
	]
	var flat: Array[AABB] = [AABB(offset, SLAB_SIZE)]
	var report: Dictionary = await _run_case(offset, flat, hero)
	var found := false
	for cv in report["b"]["concavities"]:
		var c: Array = cv["centre"]
		if cv["kind"] == "recess" and String(cv["view"]).begins_with("west") \
				and absf(float(c[2]) - offset.z - 1.0) < 0.05 and absf(float(c[1]) - 1.05) < 0.05:
			found = true
			assert_almost_eq(float(cv["hero_depth"]), deep, 0.01)
			assert_false(cv["represented"], "the flat proxy does not carry it")
	assert_true(found, "(b) lists the 0.20 m recess in a 0.30 m slab")
	assert_false(report["b"]["pass"])
	# The same recess carried by the proxy is listed and represented.
	var carried: Dictionary = await _run_case(offset + Vector3(0.0, 0.0, 10.0),
			_shift(hero, Vector3(0.0, 0.0, 10.0)), _shift(hero, Vector3(0.0, 0.0, 10.0)))
	assert_true(carried["b"]["pass"], "(b) %d missing" % carried["b"]["unrepresented"])
	var listed := false
	for cv in carried["b"]["concavities"]:
		if cv["kind"] == "recess" and absf(float(cv["hero_depth"]) - deep) < 0.01:
			listed = true
	assert_true(listed)


## ivy-8mqi: a window pane 0.20 m behind closed shutter boards is seen from outside only through
## the 0.04 m gaps between the boards. SD-MESH-19.2 closes gaps under 0.10 m, so the growth surface
## is a flat envelope over the boards and the pane is not ivy-reachable: gate (a) must not count it.
func test_surface_seen_only_through_gaps_between_closed_shutter_boards_is_not_judged() -> void:
	var offset := Vector3(140.0, 0.0, 0.0)
	var deep := 0.20
	var z0 := 0.40
	var z1 := 1.60
	var y0 := 0.50
	var y1 := 1.50
	var hero: Array[AABB] = [
		AABB(offset + Vector3(deep, 0.0, 0.0), SLAB_SIZE - Vector3(deep, 0.0, 0.0)),
		AABB(offset, Vector3(deep, SLAB_SIZE.y, z0)),
		AABB(offset + Vector3(0.0, 0.0, z1), Vector3(deep, SLAB_SIZE.y, SLAB_SIZE.z - z1)),
		AABB(offset + Vector3(0.0, 0.0, z0), Vector3(deep, y0, z1 - z0)),
		AABB(offset + Vector3(0.0, y1, z0), Vector3(deep, SLAB_SIZE.y - y1, z1 - z0)),
	]
	# Seven boards 0.12 m wide and 0.03 m thick, flush with the wall face, 0.04 m apart.
	for i in 7:
		hero.append(AABB(offset + Vector3(0.0, y0, z0 + 0.04 + 0.16 * i), Vector3(0.03, y1 - y0, 0.12)))
	var envelope: Array[AABB] = [AABB(offset, SLAB_SIZE)]
	var report: Dictionary = await _run_case(offset, envelope, hero)
	var a: Dictionary = report["a"]["walls"]
	assert_lt(float(a["max_abs"]), Audit.GAP_W_ABS_MAX,
		"(a) the pane behind the boards (0.20 m under the envelope) is not a wall sample")
	assert_true(a["pass"], "(a) %s" % [a["fails"]])


## ivy-8mqi, second case: a hero face whose 0.25 m viewpoint lands inside a growth-surface solid
## is exterior only if the way on out of that solid reaches open air above the ground. Here the
## face looks down into a floor solid, so it is not exterior; the same face looking sideways
## through a wall solid into open air still is (a proxy standing far in front of the hero must
## keep failing).
func test_viewpoint_inside_a_proxy_solid_is_exterior_only_if_it_leads_out_above_ground() -> void:
	var offset := Vector3(160.0, 0.0, 0.0)
	var floor_solid: Array[AABB] = [AABB(offset, Vector3(2.0, 0.20, 2.0))]
	var sheet: Array[AABB] = [AABB(offset + Vector3(0.8, 0.32, 0.8), Vector3(0.4, 0.02, 0.4))]
	var audit = await _audit_for(floor_solid, sheet)
	var under: Vector3 = offset + Vector3(1.0, 0.32, 1.0)
	assert_eq(audit._exterior_normal(under, Vector3.DOWN), Vector3.ZERO,
		"a face looking down into the floor solid is not exterior")
	_free_case()
	await get_tree().physics_frame
	var wall_offset := Vector3(180.0, 0.0, 0.0)
	var wall_solid: Array[AABB] = [AABB(wall_offset, SLAB_SIZE)]
	var behind: Array[AABB] = [AABB(wall_offset + Vector3(0.35, 0.8, 0.8), Vector3(0.02, 0.4, 0.4))]
	audit = await _audit_for(wall_solid, behind)
	var face: Vector3 = wall_offset + Vector3(0.35, 1.0, 1.0)
	assert_eq(audit._exterior_normal(face, Vector3.LEFT), Vector3.LEFT,
		"a face buried behind a wall solid, with open air beyond it, is still judged")
	_free_case()
	await get_tree().physics_frame


var _case_nodes: Array[Node] = []


## An audit set up over `proxy_boxes` and `hero_boxes`, for calling its helpers directly.
func _audit_for(proxy_boxes: Array[AABB], hero_boxes: Array[AABB]):
	var pieces: Array = []
	for i in hero_boxes.size():
		pieces.append({"name": "t_hero_Wall_part_%d" % i, "faces": _box_faces(hero_boxes[i]),
			"transform": Transform3D.IDENTITY})
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
	_case_nodes = [proxy, hero_body]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var audit = Audit.new()
	audit.setup(proxy.get_world_3d().direct_space_state, pieces, _analytic_sdf(proxy_boxes))
	return audit


func _free_case() -> void:
	for node in _case_nodes:
		remove_child(node)
		node.free()
	_case_nodes = []


static func _shift(boxes: Array[AABB], by: Vector3) -> Array[AABB]:
	var out: Array[AABB] = []
	for b in boxes:
		out.append(AABB(b.position + by, b.size))
	return out


## 1000 gaps: `near` of them at `near_value`, the rest at `far_value`.
func _gaps(near: int, near_value: float, far_value: float) -> Array:
	var out: Array = []
	for i in 1000:
		out.append(near_value if i < near else far_value)
	return out


func test_walls_gate_is_p95_p99_max_and_category_median() -> void:
	var ok := Audit.gap_stats(_gaps(985, 0.0, 0.02))
	assert_eq(Audit.judge_walls(ok, {}, 1000, 0), [], "1.5 pct at 0.02 m passes")
	var p95 := Audit.gap_stats(_gaps(900, 0.0, 0.02))
	assert_eq(Audit.judge_walls(p95, {}, 1000, 0).size(), 1, "10 pct at 0.02 m fails p95 only")
	var p99 := Audit.gap_stats(_gaps(980, 0.0, 0.04))
	assert_eq(Audit.judge_walls(p99, {}, 1000, 0).size(), 1, "2 pct at 0.04 m fails p99 only")
	var worst := Audit.gap_stats(_gaps(999, 0.0, -0.06))
	assert_eq(Audit.judge_walls(worst, {}, 1000, 0).size(), 1, "one sample at 0.06 m fails the worst case")
	assert_eq(Audit.judge_walls(ok, {}, 2000, 0).size(), 1, "too few samples fails")
	assert_eq(Audit.judge_walls(ok, {}, 1000, 1).size(), 1, "a sample with no proxy in reach fails")
	# A small category sitting wholly off the wall fails even when the pooled figures pass.
	var shutter := Audit.gap_stats(_gaps(1000, 0.02, 0.02).slice(0, 30))
	assert_eq(Audit.judge_walls(ok, {"shutter": shutter}, 1000, 0).size(), 1)
	assert_eq(Audit.judge_walls(ok, {"shutter": Audit.gap_stats([0.02, 0.02])}, 1000, 0), [],
		"a category under 30 samples is not gated")


func test_roof_gate_is_signed_and_separate() -> void:
	# Tiles riding 0.025 m proud at the median: the baseline cottage roof. Fails the proud side.
	assert_eq(Audit.judge_roof(Audit.gap_stats(_gaps(600, -0.025, 0.0)), 1000, 0).size(), 1)
	# Crest envelope: 4 pct proud by 0.02 m, troughs floating 0.04 m. Passes.
	var envelope := Audit.gap_stats(_gaps(40, -0.02, 0.04))
	assert_eq(Audit.judge_roof(envelope, 1000, 0), [])
	assert_eq(Audit.judge_roof(Audit.gap_stats(_gaps(900, 0.0, 0.08)), 1000, 0).size(), 1, "float p95 over 0.05 m")
	assert_eq(Audit.judge_roof(Audit.gap_stats(_gaps(999, 0.0, 0.12)), 1000, 0).size(), 1, "max over 0.10 m")
	assert_eq(Audit.surface_class("roof"), "R")
	for cat in ["wall_straight", "gable", "chimney", "shutter", "roof_cap", "other"]:
		assert_eq(Audit.surface_class(cat), "W")


func test_classify_keeps_the_sd_open_27_exclusions_and_names_cottage_pieces() -> void:
	assert_true(Audit.classify("ivy_hero_Seal_ivy_ground_wide_win_W_0_glass") in Audit.UNREACHABLE_CATEGORIES)
	assert_true(Audit.classify("tower_hero_Corner_ExteriorWide_Brick_0") in Audit.UNREACHABLE_CATEGORIES)
	assert_true(Audit.classify("tower_hero_Door_2_Round_S_1") in Audit.UNREACHABLE_CATEGORIES)
	assert_eq(Audit.classify("ivy_hero_Wall_Plaster_Straight_left_1"), "wall_straight")
	assert_eq(Audit.classify("ivy_hero_Wall_Plaster_Window_Wide_Flat_left_0"), "wall_window_bay")
	assert_eq(Audit.classify("ivy_hero_WindowShutters_Wide_Flat_Closed_left_0"), "shutter")
	assert_eq(Audit.classify("ivy_hero_Roof_Front_Brick4_-1"), "gable")
	assert_false(Audit.classify("ivy_hero_Roof_RoundTiles_4x6") in Audit.UNREACHABLE_CATEGORIES)
