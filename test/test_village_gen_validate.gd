## Unit tests: VillageLayoutValidate (v3 invariants V1–V6).
extends GutTest

const _Validate = preload("res://src/world/village_gen/village_validate.gd")
const _PathNetwork = preload("res://src/world/village_gen/path_network.gd")
const _Layout = preload("res://src/world/village_layout.gd")


func test_v3_seed4_primary_door_touch_not_violation() -> void:
	var layout: VillageLayout = VillageLayout.generate(4)
	assert_false(layout.fallback, "seed 4 must generate")
	var j_vec: Array[Vector2] = []
	for jv: Variant in layout.junction_points:
		j_vec.append(jv as Vector2)
	var v3: Array = _Validate.v3_crossings(layout.paths, j_vec, 0.3)
	assert_eq(v3.size(), 0, "primary/door junction touch is allowed: %s" % str(v3))


func test_door_facing_dot_matches_stoop_to_end() -> void:
	var spec := {"name": "t", "centre": Vector2(10.0, -25.0), "bays": 2, "yaw_deg": 0, "door": "front:0"}
	var stoop: Vector2 = VillageBackdrop.cottage_door(spec)[0] as Vector2
	var door_n: Vector2 = VillageBackdrop.cottage_door(spec)[1] as Vector2
	var endp: Vector2 = stoop + Vector2(0.0, -4.0)
	var dotv: float = _Validate.door_facing_dot(spec, stoop, endp)
	var expected: float = door_n.dot((endp - stoop).normalized())
	assert_almost_eq(dotv, expected, 0.001)


func test_v1_corner_beyond_max_from_g() -> void:
	var g := Vector2(0.0, -18.0)
	var max_m := 54.0
	var viol: Array = _Validate.v1_cottages(
		[{"name": "far", "centre": Vector2(52.0, -50.0), "bays": 3, "yaw_deg": 0, "door": "front:1"}],
		Rect2(), Rect2(), Vector2(200.0, 200.0), 0.0, g, max_m, 4.0)
	assert_gt(viol.size(), 0)
	assert_true(str(viol[0]).contains("corner beyond max"))


func test_seed_120_exterior_corners_within_54m() -> void:
	var layout: VillageLayout = VillageLayout.generate(120)
	assert_false(layout.fallback)
	var g := layout.hamlet_centre_xz
	var max_m := VillageLayout.HAMLET_MAX_CORNER_FROM_G
	for spec: Dictionary in layout.cottages:
		var rect: Rect2 = VillageBackdrop.cottage_exterior_rect(spec)
		for c: Vector2 in [
			rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]:
			assert_lte(c.distance_to(g), max_m + 1e-4, "seed 120 corner from G")


func test_v1_flags_overlap_and_v1_passes_when_separated() -> void:
	var g := Vector2(0.0, -18.0)
	var bad: Array = [
		{"name": "a", "centre": Vector2(10.0, -20.0), "bays": 3, "yaw_deg": 0, "door": "front:1"},
		{"name": "b", "centre": Vector2(11.0, -20.0), "bays": 3, "yaw_deg": 0, "door": "front:1"},
	]
	var v_bad: Array = _Validate.v1_cottages(
		bad, Rect2(), Rect2(), Vector2(200.0, 200.0), 0.0, g, 54.0, 4.0)
	assert_gt(v_bad.size(), 0)
	var good: Array = [
		{"name": "a", "centre": Vector2(10.0, -20.0), "bays": 3, "yaw_deg": 0, "door": "front:1"},
		{"name": "b", "centre": Vector2(30.0, -35.0), "bays": 3, "yaw_deg": 0, "door": "front:1"},
	]
	var v_ok: Array = _Validate.v1_cottages(
		good, Rect2(), Rect2(), Vector2(200.0, 200.0), 0.0, g, 54.0, 4.0)
	assert_eq(v_ok.size(), 0)


func test_v2_path_inside_cottage_except_door_tail() -> void:
	var c := {"name": "c", "centre": Vector2(20.0, -22.0), "bays": 3, "yaw_deg": 0, "door": "front:1"}
	var stoop := VillageBackdrop.cottage_door(c)[0] as Vector2 + (
		VillageBackdrop.cottage_door(c)[1] as Vector2) * 0.5
	var path_good: Array = [
		stoop,
		stoop + (Vector2(20.0, -10.0) - stoop).normalized() * 0.3,
		Vector2(20.0, -10.0),
	]
	var paths: Array = [path_good]
	var kinds: Array = ["door"]
	var door_stoops: Array = [stoop]
	var viol: Array = _Validate.v2_paths_vs_cottages(
		paths, kinds, [c], door_stoops, Vector2(100.0, 100.0), 0.0)
	assert_eq(viol.size(), 0)

	var path_bad: Array = [Vector2(20.0, -22.0), Vector2(25.0, -22.0)]
	var viol2: Array = _Validate.v2_paths_vs_cottages(
		[path_bad], ["primary"], [c], [Vector2.ZERO], Vector2(100.0, 100.0), 0.0)
	assert_gt(viol2.size(), 0)


func test_v2_door_paths_index_stoops_by_door_order() -> void:
	## Regression: must not use door_stoops[path_index] — door paths may not be the first paths.
	var c := {"name": "c", "centre": Vector2(20.0, -22.0), "bays": 3, "yaw_deg": 0, "door": "front:1"}
	var dr := VillageBackdrop.cottage_door(c)
	var stoop: Vector2 = dr[0] as Vector2 + (dr[1] as Vector2) * 0.45
	var conn := Vector2(20.0, -10.0)
	var door_path: Array = [
		stoop,
		stoop + (conn - stoop).normalized() * 0.28,
		conn,
	]
	var primary_other: Array = [Vector2(5.0, -5.0), Vector2(6.0, -5.0)]
	var paths: Array = [primary_other, door_path]
	var kinds: Array = ["primary", "door"]
	var door_stoops: Array = [stoop]
	var viol: Array = _Validate.v2_paths_vs_cottages(
		paths, kinds, [c], door_stoops, Vector2(100.0, 100.0), 0.0)
	assert_eq(viol.size(), 0)


func test_door_connector_crosses_v3_detects_plaza_cross() -> void:
	var net := _PathNetwork.new()
	var j0 := net.add_junction(Vector2(0.0, 0.0))
	var j1 := net.add_junction(Vector2(10.0, 0.0))
	net.add_path(PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0)]), "plaza", j0, j1)
	var st := Vector2(5.0, -3.0)
	var en := Vector2(5.0, 3.0)
	assert_true(_Validate.door_connector_crosses_v3(net, st, en, 0, 0.3))


func test_v3_first_crossing_debug_finds_xy_cross() -> void:
	var paths: Array = [
		[Vector2(0.0, 0.0), Vector2(10.0, 0.0)] as Array,
		[Vector2(5.0, -5.0), Vector2(5.0, 5.0)] as Array,
	]
	var kinds: Array = ["primary", "primary"]
	var dbg: Dictionary = _Validate.v3_first_crossing_debug(paths, kinds, [] as Array[Vector2], 0.3)
	assert_eq(dbg.get("path_i", -1), 0)
	assert_eq(dbg.get("path_j", -1), 1)
	var loc: Vector2 = dbg.get("location", Vector2.ZERO) as Vector2
	assert_almost_eq(loc.x, 5.0, 0.02)
	assert_almost_eq(loc.y, 0.0, 0.02)


func test_v3_crossings_detected() -> void:
	var paths: Array = [
		[Vector2(0.0, 0.0), Vector2(10.0, 0.0)] as Array,
		[Vector2(5.0, -5.0), Vector2(5.0, 5.0)] as Array,
	]
	var viol: Array = _Validate.v3_crossings(paths, [] as Array[Vector2], 0.3)
	assert_gt(viol.size(), 0)

	var paths_ok: Array = [
		[Vector2(0.0, 0.0), Vector2(5.0, 0.0)] as Array,
		[Vector2(5.0, 0.0), Vector2(5.0, 5.0)] as Array,
	]
	var viol2: Array = _Validate.v3_crossings(
		paths_ok, [Vector2(5.0, 0.0)] as Array[Vector2], 0.3)
	assert_eq(viol2.size(), 0)


func test_quadrant_index_cardinal() -> void:
	var g := _Layout.VILLAGE_GREEN_G
	var _Sampler = preload("res://src/world/village_gen/plot_sampler.gd")
	assert_eq(_Sampler.quadrant_index(g + Vector2(-5.0, -5.0), g), 0)
	assert_eq(_Sampler.quadrant_index(g + Vector2(5.0, -5.0), g), 1)
	assert_eq(_Sampler.quadrant_index(g + Vector2(-5.0, 3.0), g), 2)
	assert_eq(_Sampler.quadrant_index(g + Vector2(6.0, 2.0), g), 3)


func test_v3_crossings_flags_t_without_junction_even_if_endpoints_align() -> void:
	## Regression: path endpoints alone must not mask a T joint — only junction coordinates are allowed.
	var paths: Array = [
		[Vector2(0.0, 0.0), Vector2(10.0, 0.0)] as Array,
		[Vector2(5.0, 0.0), Vector2(5.0, 5.0)] as Array,
	]
	var viol: Array = _Validate.v3_crossings(paths, [] as Array[Vector2], 0.3)
	assert_gt(viol.size(), 0)


func test_v4_connectivity() -> void:
	var paths: Array = [
		[Vector2(0.0, 0.0), Vector2(10.0, 0.0)] as Array,
		[Vector2(10.0, 0.0), Vector2(10.0, 8.0)] as Array,
	]
	var kinds: Array = ["primary", "primary"]
	var door_stoops: Array = [Vector2(10.0, 8.0)]
	var hero := Vector2(0.0, 0.1)
	var plaza := Vector2(0.0, 0.0)
	assert_eq(_Validate.v4_connectivity({"paths": paths, "kinds": kinds},
		door_stoops, hero, plaza, 0.8).size(), 0)

	var paths_bad: Array = [
		[Vector2(0.0, 0.0), Vector2(5.0, 0.0)] as Array,
		[Vector2(20.0, 0.0), Vector2(30.0, 0.0)] as Array,
	]
	assert_gt(_Validate.v4_connectivity({"paths": paths_bad, "kinds": ["primary", "primary"]},
		[Vector2(30.0, 0.0)], hero, plaza, 0.5).size(), 0)


func test_v5_shape_curvature_and_door_len() -> void:
	## Sliding-window 25°/m cap: ~40° every 0.25 m ⇒ ~160°/m >> 25.
	var sharp: Array = [] as Array
	var p := Vector2.ZERO
	var ang := 0.0
	for _i in range(8):
		sharp.append(p)
		ang += deg_to_rad(40.0)
		p += Vector2(cos(ang), sin(ang)) * 0.25
	sharp.append(p)
	var viol: Array = _Validate.v5_shape([sharp], ["primary"])
	assert_gt(viol.size(), 0)

	var door_long: Array = [
		Vector2.ZERO, Vector2(10.0, 0.0),
	] as Array
	var viol_d: Array = _Validate.v5_shape([door_long], ["door"])
	assert_gt(viol_d.size(), 0)


func test_v6_door_facing() -> void:
	var c := {"name": "c", "centre": Vector2(0.0, -10.0), "bays": 3, "yaw_deg": 0, "door": "front:1"}
	var door_n: Vector2 = VillageBackdrop.cottage_door(c)[1] as Vector2
	var st: Vector2 = VillageBackdrop.cottage_door(c)[0] as Vector2 + door_n * 0.5
	var en: Vector2 = st + door_n * 3.0
	var good: Array = [[st, en] as Array]
	assert_eq(_Validate.v6_doors_face_paths([c], good).size(), 0)

	var bad: Array = [[st, st - door_n * 3.0] as Array]
	assert_gt(_Validate.v6_doors_face_paths([c], bad).size(), 0)


func test_all_aggregator() -> void:
	var layout := {
		"cottages": [] as Array,
		"paths": [] as Array,
		"kinds": [] as Array,
		"door_stoops": [] as Array,
		"door_connections": [] as Array,
		"plaza_keep_clear": Rect2(),
		"hero_rect": Rect2(),
		"pond_center": Vector2(500.0, 500.0),
		"pond_clear_r": 0.0,
		"g": Vector2(0.0, -18.0),
		"junction_points": [] as Array,
		"hero_stoop": Vector2.ZERO,
		"plaza_root": Vector2.ZERO,
	}
	var res: Dictionary = _Validate.all(layout)
	assert_true(res.has("v1"))
	assert_true(res.has("v6"))
