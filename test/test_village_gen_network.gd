## Unit tests: VillagePathNetwork (v3 path-first generator modules).
extends GutTest

const _PathNetwork = preload("res://src/world/village_gen/path_network.gd")


func test_point_at_straight_arc_length_tangent_normal() -> void:
	var net := _PathNetwork.new()
	var poly := PackedVector2Array([Vector2.ZERO, Vector2(10.0, 0.0)])
	net.add_path(poly, "primary")
	var mid: Dictionary = net.point_at(0, 5.0)
	assert_almost_eq((mid["point"] as Vector2).x, 5.0, 0.001)
	assert_almost_eq((mid["point"] as Vector2).y, 0.0, 0.001)
	var t: Vector2 = mid["tangent"] as Vector2
	var n: Vector2 = mid["normal"] as Vector2
	assert_true(absf(t.y) < 0.01 and t.x > 0.0)
	assert_true(absf(t.dot(n)) < 0.01)


func test_nearest_point_finds_projection_and_s() -> void:
	var net := _PathNetwork.new()
	var poly := PackedVector2Array([Vector2(0.0, 0.0), Vector2(4.0, 0.0)])
	net.add_path(poly, "primary")
	var r: Dictionary = net.nearest_point(Vector2(2.0, 1.0))
	assert_eq(r["path_id"], 0)
	assert_almost_eq(r["s"] as float, 2.0, 0.05)


func test_crosses_unintended_true_without_allowed() -> void:
	var net := _PathNetwork.new()
	net.add_path(PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0)]), "a")
	assert_true(net.crosses_unintended(
		PackedVector2Array([Vector2(5.0, -3.0), Vector2(5.0, 3.0)]),
		[] as Array[Vector2],
		0.3,
		[]))


func test_crosses_unintended_false_at_allowed_junction() -> void:
	var net := _PathNetwork.new()
	var j := Vector2(5.0, 0.0)
	net.add_path(PackedVector2Array([Vector2(0.0, 0.0), j]), "a")
	net.add_path(PackedVector2Array([j, Vector2(5.0, 5.0)]), "b")
	assert_false(net.crosses_unintended(
		PackedVector2Array([Vector2(5.0, -3.0), Vector2(5.0, 3.0)]),
		[j] as Array[Vector2],
		0.3,
		[1]))


func test_crosses_unintended_two_paths_vertical_horizontal() -> void:
	var net := _PathNetwork.new()
	var ha := PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0)])
	var vb := PackedVector2Array([Vector2(5.0, -5.0), Vector2(5.0, 5.0)])
	assert_true(net.crosses_unintended_two_paths(ha, vb, [] as Array[Vector2], 0.3))


func test_crosses_unintended_why_false_explains_miss() -> void:
	var net := _PathNetwork.new()
	net.add_path(PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0)]), "a")
	var why: Dictionary = net.crosses_unintended_why_false(
		PackedVector2Array([Vector2(5.0, -3.0), Vector2(5.0, 3.0)]),
		0,
		[] as Array[Vector2],
		0.3,
		[])
	assert_eq(str(why.get("reason", "")), "geometric_hit")


func test_v3_allowed_points_is_junction_only() -> void:
	var net := _PathNetwork.new()
	var j := net.add_junction(Vector2(2.0, 0.0))
	net.add_path(PackedVector2Array([Vector2(0.0, 0.0), Vector2(2.0, 0.0)]), "p", -1, j)
	var pts: Array[Vector2] = net.v3_allowed_points()
	assert_eq(pts.size(), 1)
	assert_almost_eq(pts[0].x, 2.0, 1e-4)


func test_min_distance_trimmed_ignores_near_ends() -> void:
	var net := _PathNetwork.new()
	net.add_path(PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0)]), "p")
	## Query segment near path end but trim ends so distance is large
	var d: float = net.min_distance_to_paths(
		PackedVector2Array([Vector2(9.8, 2.0), Vector2(9.9, 2.0)]),
		[],
		1.0)
	assert_gt(d, 1.5)


func test_start_end_junction_ids_match_add_path() -> void:
	var net := _PathNetwork.new()
	var j0: int = net.add_junction(Vector2(1.0, 2.0))
	var j1: int = net.add_junction(Vector2(9.0, 2.0))
	net.add_path(PackedVector2Array([Vector2(1.0, 2.0), Vector2(9.0, 2.0)]), "primary", j0, j1)
	assert_eq(net.start_junction_id(0), j0)
	assert_eq(net.end_junction_id(0), j1)


func test_edges_node_numbering_documented() -> void:
	## J=0 free endpoints: path0 nodes 0 and 1
	var net := _PathNetwork.new()
	net.add_path(PackedVector2Array([Vector2(0.0, 0.0), Vector2(5.0, 0.0)]), "primary")
	var e: Array[Vector2i] = net.edges()
	assert_eq(e.size(), 1)
	assert_eq(e[0], Vector2i(0, 1))
	## Add junction at (5,0), second path from junction to (8,8): nodes 0=junc, 1=free tip
	var net2 := _PathNetwork.new()
	var jid: int = net2.add_junction(Vector2(5.0, 0.0), [])
	net2.add_path(PackedVector2Array([Vector2(0.0, 0.0), Vector2(5.0, 0.0)]), "a", -1, jid)
	net2.add_path(PackedVector2Array([Vector2(5.0, 0.0), Vector2(8.0, 8.0)]), "b", jid, -1)
	var e2: Array[Vector2i] = net2.edges()
	assert_true(e2.has(Vector2i(0, 1)) or e2.has(Vector2i(1, 2)))


func test_connectivity_through_junction() -> void:
	var net := _PathNetwork.new()
	var j: int = net.add_junction(Vector2(5.0, 0.0), [])
	net.add_path(PackedVector2Array([Vector2(0.0, 0.0), Vector2(5.0, 0.0)]), "a", -1, j)
	net.add_path(PackedVector2Array([Vector2(5.0, 0.0), Vector2(10.0, 0.0)]), "b", j, -1)
	assert_true(net.connected(Vector2(0.4, 0.0), Vector2(9.6, 0.0), 1.0))


func test_connectivity_ok_required_points() -> void:
	var net := _PathNetwork.new()
	var j: int = net.add_junction(Vector2(5.0, 0.0), [])
	net.add_path(PackedVector2Array([Vector2(0.0, 0.0), Vector2(5.0, 0.0)]), "p", -1, j)
	net.add_path(PackedVector2Array([Vector2(5.0, 0.0), Vector2(12.0, 0.0)]), "p", j, -1)
	assert_true(net.connectivity_ok([Vector2(11.5, 0.0)], Vector2(0.2, 0.1), 0.8))
	assert_false(net.connectivity_ok([Vector2(50.0, 50.0)], Vector2(0.2, 0.1), 0.8))


func test_to_layout_paths_and_kinds() -> void:
	var net := _PathNetwork.new()
	net.add_path(PackedVector2Array([Vector2(1.0, 2.0), Vector2(3.0, 4.0)]), "hero")
	var la: Array = net.to_layout_paths()
	assert_eq(la.size(), 1)
	var arr: Array = la[0]
	assert_almost_eq((arr[1] as Vector2).y, 4.0, 0.001)
	assert_eq(net.kinds_array(), ["hero"])


func test_truncate_paths_restores_parent_polyline() -> void:
	var net := _PathNetwork.new()
	var j0: int = net.add_junction(Vector2(0.0, 0.0), [])
	var j1: int = net.add_junction(Vector2(10.0, 0.0), [])
	var orig := PackedVector2Array([Vector2(0.0, 0.0), Vector2(5.0, 0.0), Vector2(10.0, 0.0)])
	net.add_path(orig, "primary", j0, j1)
	var before: int = net.path_count()
	var _jid: int = net.split_path_at_point(0, Vector2(5.0, 0.0), 0.5)
	assert_eq(net.path_count(), before + 1)
	net.truncate_paths(before)
	net.set_path_polyline(0, orig)
	net.set_end_junction(0, j1)
	assert_eq(net.path_count(), before)
	assert_almost_eq(net.length(0), 10.0, 0.01)
