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
	var two_sided: StaticBody3D = Audit.make_two_sided_proxy(self, proxy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var audit = Audit.new()
	audit.setup(proxy.get_world_3d().direct_space_state, pieces, _analytic_sdf(proxy_boxes))
	audit.set_two_sided_proxy(two_sided)
	var report: Dictionary = audit.run({"samples": SAMPLES, "seed": 7})
	gut.p(Audit.format_report("ribbed test wall", report))
	remove_child(hero_body)
	hero_body.free()
	remove_child(two_sided)
	two_sided.free()
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


## ivy-b1e.27 (review ivy-b1e.26 B1): a visible hero wall with the proxy floating 0.06 m off it must
## fail (a) even when its 0.25 m viewpoint lies inside a proxy solid whose nearest way out (the SDF
## gradient) crosses hero skin. Here the wall is recessed 0.06 m between two hero shelves 0.20 m
## apart; the proxy bridges the recess flush with the wall (the bounding-box error) and its box
## over the shelves (flush with their outsides) swallows the viewpoint. That box's nearest faces
## are above and below, through a shelf, but the line of sight runs straight out of its front into
## open air. ivy-8mqi's rule dropped every such sample unjudged and unreported, and (a) passed.
func test_floating_proxy_over_a_visible_wall_fails_when_the_nearest_way_out_crosses_hero_skin() -> void:
	var offset := Vector3(200.0, 0.0, 0.0)
	var recess := 0.06
	var hero: Array[AABB] = [
		AABB(offset, Vector3(SLAB_SIZE.x, 0.88, SLAB_SIZE.z)),  # wall below the shelves
		AABB(offset + Vector3(0.0, 1.12, 0.0), Vector3(SLAB_SIZE.x, SLAB_SIZE.y - 1.12, SLAB_SIZE.z)),  # above
		AABB(offset + Vector3(recess, 0.88, 0.0), Vector3(SLAB_SIZE.x - recess, 0.24, SLAB_SIZE.z)),  # recessed band
		AABB(offset + Vector3(-0.50, 0.88, 0.0), Vector3(0.50 + recess, 0.02, SLAB_SIZE.z)),  # lower shelf
		AABB(offset + Vector3(-0.50, 1.10, 0.0), Vector3(0.50 + recess, 0.02, SLAB_SIZE.z)),  # upper shelf
		AABB(offset + Vector3(-0.50, 0.88, -0.02), Vector3(0.50 + recess, 0.24, 0.02)),  # end cheeks
		AABB(offset + Vector3(-0.50, 0.88, SLAB_SIZE.z), Vector3(0.50 + recess, 0.24, 0.02)),
	]
	var proxy: Array[AABB] = [
		AABB(offset, SLAB_SIZE),  # flush with the wall face: bridges the recess
		AABB(offset + Vector3(-0.50, 0.88, -0.02), Vector3(0.50, 0.24, SLAB_SIZE.z + 0.04)),  # over the shelves
	]
	var report: Dictionary = await _run_case(offset, proxy, hero)
	var a: Dictionary = report["a"]["walls"]
	var band_samples := 0
	for st in report["a"]["worst_nodes"]:
		if st["name"] == "t_hero_Wall_Ribbed_part_2":
			band_samples = int(st["n"])
			assert_almost_eq(float(st["max_abs"]), recess, 0.005, "the recessed band floats 0.06 m")
	assert_gt(band_samples, 0, "the recessed band between the shelves is judged")
	assert_false(a["pass"], "(a) must fail: the band is 0.06 m behind the proxy")
	assert_gte(float(a["max_abs"]), 0.055)


## SD-MESH-19.4.2 fixtures U and J (ivy-b1e.29 ruling, items 4 and 6). A hero shell (x 0.10-0.80,
## y 0.20-0.602, z 0.20-1.80 from `o`) with a closed cavity inside it (x 0.30-0.65, y 0.40-0.60,
## z 0.40-1.60) under a 2 mm top skin. A 1.5 mm crack runs through that skin along z at x = 0.40.
## Every skin is under 0.25 m thick, so no viewpoint starts inside hero material. The proxy is the
## solid shell box: what ivy needs. The cavity's back face (x = 0.65, facing -x) has its 0.25 m
## viewpoint at x = 0.40, inside the proxy; the nearest way out (the SDF gradient, straight up)
## threads the crack, the line of sight (-x) crosses the front wall. The back face floats 0.15 m
## behind the proxy's back face. With `side_opening` (fixture J) the z- side wall has a
## 0.30 x 0.20 m opening (x 0.45-0.75, the cavity's full height), in line with the level escape
## direction -z from the back face.
const CRACK_X := 0.40
const CRACK_WIDTH := 0.0015
const SKIN := 0.002


func _cavity_proxy(o: Vector3) -> Array[AABB]:
	return [AABB(o + Vector3(0.10, 0.20, 0.20), Vector3(0.70, 0.40 + SKIN, 1.60))]


func _cavity_hero(o: Vector3, side_opening: bool) -> Array[AABB]:
	var top := 0.60
	var c0 := CRACK_X - CRACK_WIDTH * 0.5
	var c1 := CRACK_X + CRACK_WIDTH * 0.5
	var boxes: Array[AABB] = [
		AABB(o + Vector3(0.10, 0.20, 0.20), Vector3(0.70, 0.20, 1.60)),  # bottom
		AABB(o + Vector3(0.10, 0.40, 0.20), Vector3(0.20, 0.20, 1.60)),  # front wall
		AABB(o + Vector3(0.30, 0.40, 1.60), Vector3(0.35, 0.20, 0.20)),  # side wall z+
		AABB(o + Vector3(0.10, top, 0.20), Vector3(c0 - 0.10, SKIN, 1.60)),  # top skin, front of the crack
		AABB(o + Vector3(c1, top, 0.20), Vector3(0.80 - c1, SKIN, 1.60)),  # top skin, behind it
		AABB(o + Vector3(c0, top, 0.20), Vector3(CRACK_WIDTH, SKIN, 0.20)),  # crack ends
		AABB(o + Vector3(c0, top, 1.60), Vector3(CRACK_WIDTH, SKIN, 0.20)),
	]
	if side_opening:
		boxes.append_array([
			AABB(o + Vector3(0.65, 0.40, 0.40), Vector3(0.15, 0.20, 1.40)),  # back wall beside the cavity
			AABB(o + Vector3(0.75, 0.40, 0.20), Vector3(0.05, 0.20, 0.20)),  # back wall beside the opening
			AABB(o + Vector3(0.30, 0.40, 0.20), Vector3(0.15, 0.20, 0.20)),  # side wall z- beside it
		])
	else:
		boxes.append_array([
			AABB(o + Vector3(0.65, 0.40, 0.20), Vector3(0.15, 0.20, 1.60)),  # back wall
			AABB(o + Vector3(0.30, 0.40, 0.20), Vector3(0.35, 0.20, 0.20)),  # side wall z-
		])
	return boxes


## Fixture U: the cavity is shut in. Its faces are reached from open air only through the 1.5 mm
## crack, so they are not judged: every exemption is listed with its opening (< 0.005 m) and 0
## clear escapes, and (a) passes. Red against the 0.01 m / 4-direction slot test, which steps over
## the 2 mm skin on most viewpoints and judges the back face at +0.15 m.
func test_shut_in_cavity_seen_only_through_a_crack_is_not_judged() -> void:
	var offset := Vector3(220.0, 0.5, 0.0)
	var report: Dictionary = await _run_case(offset, _cavity_proxy(offset), _cavity_hero(offset, false))
	var a: Dictionary = report["a"]["walls"]
	assert_true(a["pass"], "(a) the shut-in cavity is not judged: %s" % [a["fails"]])
	assert_lte(float(a["max_abs"]), Audit.GAP_W_ABS_MAX)
	var exemptions: Array = a.get("exemptions", [])
	assert_gt(exemptions.size(), 0, "the cavity's faces are listed as narrow-opening exemptions")
	assert_eq(int(a.get("exempt_exit_slot", -1)) + int(a.get("exempt_in_slot", -1)), exemptions.size(),
		"every exemption is listed")
	assert_eq(int(a.get("judged_by_escape", -1)), 0, "no way out of the cavity is clear")
	var back_face := 0
	for e in exemptions:
		assert_lt(float(e["width"]), 0.005, "exempt through the crack, not something wider: %s" % [e])
		assert_eq(int(e["clear_escapes"]), 0)
		assert_eq((e["width_position"] as Array).size(), 3, "the opening's position is recorded")
		assert_true(String(e["path"]) in ["viewpoint", "gradient", "sight"])
		if absf(float(e["position"][0]) - offset.x - 0.65) < 0.001:
			back_face += 1
			assert_gt(float(e["g"]), 0.0, "the would-be gap is kept: the back face floats")
			assert_almost_eq(float(e["width_position"][0]) - offset.x, CRACK_X, 0.001,
				"the narrowest point is the crack")
	assert_gt(back_face, 0, "back-face samples are among the exemptions")
	var summary: Dictionary = a.get("exemption_summary", {})
	assert_eq(int(summary.get("count", -1)), exemptions.size())
	assert_gt(int(summary.get("over_line", -1)), 0, "exemptions with would-be |g| > 0.03 m are counted")
	assert_gt(absf(float((summary.get("worst", {}) as Dictionary).get("g", 0.0))), 0.06,
		"the worst would-be gap is the floating back face, printed beside the verdict")
	var text := Audit.format_report("fixture U", report)
	assert_string_contains(text, "narrow-opening exemptions")


## Fixture J: the same cavity with a 0.30 x 0.20 m opening in its side wall. The back face's level
## escape -z leaves through it, so the back face is judged after all (judged_by_escape > 0) and (a)
## fails on its float, though its tried ways out still thread only the crack.
func test_cavity_with_a_clear_way_out_is_judged_and_fails() -> void:
	var offset := Vector3(240.0, 0.5, 0.0)
	var report: Dictionary = await _run_case(offset, _cavity_proxy(offset), _cavity_hero(offset, true))
	var a: Dictionary = report["a"]["walls"]
	assert_gt(int(a.get("judged_by_escape", 0)), 0, "candidates with a clear escape are judged")
	assert_false(a["pass"], "(a) fails: the back face floats behind the proxy")
	assert_gt(float(a["max_abs"]), Audit.GAP_W_ABS_MAX)
	for e in a.get("exemptions", []):
		assert_eq(int(e["clear_escapes"]), 0, "an exemption never has a clear escape")


## SD-MESH-19.4.2 item 2, the resolution contract: every opening up to 0.098 m wide and at least
## 0.001 m long along the path is flagged, at any orientation about the path and any position along
## it; one 0.10 m or wider never is. Slits between two 1 mm plates across a path along +x, at widths
## 0.0014-0.102 m, rotated 0-45 degrees about the path (the 8 test directions are 22.5 degrees
## apart, so 11.25 and 33.75 are the worst cases), shifted across one 0.01 m step in 0.25 mm
## increments, with the path through the slit's middle and off it.
func test_opening_test_meets_the_resolution_contract() -> void:
	var widths: Array[float] = [0.0014, 0.05, 0.098, 0.100, 0.102]
	var angles: Array[float] = [0.0, 11.25, 22.5, 33.75, 45.0]
	var pieces: Array = []
	var centres := {}
	for iw in widths.size():
		for ia in angles.size():
			var w: float = widths[iw]
			var centre := Vector3(1.0 + ia, 1.0, 1.0 + iw)
			var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(angles[ia])), centre)
			centres[[iw, ia]] = xf
			for half in [AABB(Vector3(0.0, -0.2, w * 0.5), Vector3(0.001, 0.4, 0.2)),
					AABB(Vector3(0.0, -0.2, -w * 0.5 - 0.2), Vector3(0.001, 0.4, 0.2))]:
				pieces.append({"name": "t_hero_Wall_slit_%d_%d" % [iw, ia], "faces": _box_faces(half),
					"transform": xf})
	# The opening test reads hero only; a token proxy keeps setup() and its SDF small.
	var audit = await _audit_for_pieces(pieces, [AABB(Vector3(0.0, -5.0, 0.0), Vector3(0.1, 0.1, 0.1))])
	var misses: Array = []
	for key in centres:
		var w: float = widths[key[0]]
		var xf: Transform3D = centres[key]
		var across: Vector3 = xf.basis * Vector3.BACK
		for off in [0.0, 0.3 * w]:
			for k in 41:
				var shift := 0.00025 * k
				var origin: Vector3 = xf.origin + across * off - Vector3.RIGHT * (0.005 + shift)
				var found: Dictionary = audit._narrowest_opening(origin, Vector3.RIGHT, 0.0, 0.02)
				var flagged := not found.is_empty()
				if flagged != (w < 0.099):
					misses.append("w %.4f at %.2f deg, off %.4f, shift %.5f: %s" % [w, angles[key[1]], off, shift,
						"flagged" if flagged else "missed"])
				elif flagged:
					assert_between(float(found["width"]), w - 1e-5, w * 1.0205,
						"width reads within the 22.5 degree overstatement")
					var at: Vector3 = found["position"]
					assert_between(at.x - xf.origin.x, -1e-5, 0.001 + 1e-5, "measured inside the slit")
	assert_eq(misses.size(), 0, "resolution contract broken in %d cases: %s" % [misses.size(), misses.slice(0, 8)])
	_free_case()
	await get_tree().physics_frame


## SD-MESH-19.4.2 clause 2a (ivy-b1e.31): a slit of width w between two hero plates of thickness T
## (sheet in local x 0..T, slit across local z), crossed by a path at alpha from the sheet normal and
## rotated by gamma about the path. Every path through it that touches no hero is flagged when
## w <= 0.098 and w <= 2T, reading a width within w..1.0205w; a slit 0.10 m or wider never is. The
## perpendicular chords alone slide past the short plate sides on a steep path (the ivy-8mqi
## shutter blind spot); the chord along the plate side's own normal catches it.
func test_opening_test_catches_oblique_passage_through_thin_sheets() -> void:
	# [w, T, wide]
	var cases := [[0.04, 0.02, false], [0.06, 0.03, false], [0.098, 0.049, false], [0.0015, 0.002, false],
		[0.10, 0.03, true], [0.102, 0.002, true]]
	var alphas: Array[float] = [15.0, 30.0, 45.0, 60.0]
	var gammas: Array[float] = [0.0, 5.625, 11.25]
	var pieces: Array = []
	var entries: Array = []
	var i := 0
	for c in cases:
		for alpha in alphas:
			for gamma in gammas:
				var base := Vector3(1.0 + i, 1.0, 1.0)
				var a := deg_to_rad(alpha)
				var d := Vector3(cos(a), 0.0, sin(a))
				var xf := Transform3D(Basis(d, deg_to_rad(gamma)), base)
				var w: float = c[0]
				var t: float = c[1]
				for half in [AABB(Vector3(0.0, -0.2, w * 0.5), Vector3(t, 0.4, 0.3)),
						AABB(Vector3(0.0, -0.2, -w * 0.5 - 0.3), Vector3(t, 0.4, 0.3))]:
					pieces.append({"name": "t_hero_Wall_obl_%d" % i, "faces": _box_faces(half), "transform": xf})
				entries.append([base, w, t, alpha, gamma, c[2]])
				i += 1
	var audit = await _audit_for_pieces(pieces, [AABB(Vector3(0.0, -5.0, 0.0), Vector3(0.1, 0.1, 0.1))])
	var misses: Array = []
	var by_case := {}
	var checked := 0
	for e in entries:
		var base: Vector3 = e[0]
		var w: float = e[1]
		var t: float = e[2]
		var a := deg_to_rad(float(e[3]))
		var wide: bool = e[5]
		var d := Vector3(cos(a), 0.0, sin(a))
		# Entry points along the slit mouth whose straight path clears both plates.
		var span := w - t * tan(a)
		if span <= 0.002:
			continue
		var rot := Basis(d, deg_to_rad(float(e[4])))
		var dir: Vector3 = rot * d
		var length := 0.10 + t / cos(a)
		for k in 11:
			var z_in := -w * 0.5 + 0.0005 + (span - 0.001) * k / 10.0
			var origin: Vector3 = base + rot * (Vector3(0.0, 0.0, z_in) - d * 0.05)
			var label := "w %.4f T %.3f alpha %.0f gamma %.3f k %d" % [w, t, e[3], e[4], k]
			assert_true(audit._cast(origin, origin + dir * length, Audit.HERO_MASK).is_empty(),
				"%s: the path clears both plates" % label)
			checked += 1
			var found: Dictionary = audit._narrowest_opening(origin, dir, 0.0, length)
			var kind := ""
			if wide and not found.is_empty():
				kind = "flagged wide"
				misses.append("%s: flagged a wide slit at %.5f" % [label, float(found["width"])])
			elif not wide and found.is_empty():
				kind = "missed"
				misses.append("%s: missed" % label)
			elif not wide and float(found["width"]) > w * 1.0205:
				kind = "read wide"
				misses.append("%s: read %.5f" % [label, float(found["width"])])
			if kind != "":
				var bucket := "w %.4f alpha %.0f %s" % [w, e[3], kind]
				by_case[bucket] = int(by_case.get(bucket, 0)) + 1
	gut.p("oblique passage: %d paths checked, %d misses; by case %s" % [checked, misses.size(), by_case])
	assert_gt(checked, 0)
	assert_eq(misses.size(), 0, "oblique passage contract broken in %d cases: %s" % [misses.size(), misses.slice(0, 12)])
	_free_case()
	await get_tree().physics_frame


var _case_nodes: Array[Node] = []


## An audit set up over hero `pieces` (with their own transforms) and `proxy_boxes`.
func _audit_for_pieces(pieces: Array, proxy_boxes: Array[AABB]):
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
