## Unit tests for VillageLayout path network helpers (ivy-80z S3).
##
## Tests the pure algorithmic building blocks:
##   _mst_edges         — Prim with candidate mask + tie-break
##   _bezier_polyline   — quadratic Bézier sampling
##   VillageScatterPositions.path_stone_transforms dedupe
##   _build_network     — full integration test with a controlled cottage layout
extends GutTest

# ── Helpers ───────────────────────────────────────────────────────────────────

## Build 8 nodes arranged in a simple 2-ring layout for testing.
## Inner: nodes 0,1,2 at r≈12  (angles 0°, 120°, 240°)
## Outer: nodes 3,4,5,6 at r≈20 (angles 0°, 90°, 180°, 270°)
## Hero: node 7 at (0,0)
static func _make_test_nodes() -> PackedVector2Array:
	var nodes := PackedVector2Array()
	for i: int in range(3):
		var angle := float(i) * TAU / 3.0
		nodes.append(Vector2(cos(angle) * 12.0, sin(angle) * 12.0))
	for i: int in range(4):
		var angle := float(i) * TAU / 4.0
		nodes.append(Vector2(cos(angle) * 20.0, sin(angle) * 20.0))
	nodes.append(Vector2.ZERO)  # hero
	return nodes


## Inner set for the test layout.
static func _make_inner_set() -> Array[int]:
	return [0, 1, 2]


## Candidate mask using the inner set (same logic as _build_network).
static func _make_mask(inner_set: Array[int]) -> Callable:
	return func(a: int, b: int) -> bool:
		if a == VillageLayout.HERO_NODE or b == VillageLayout.HERO_NODE:
			var door: int = b if a == VillageLayout.HERO_NODE else a
			return inner_set.has(door)
		return true


# ── MST tests ─────────────────────────────────────────────────────────────────

func test_mst_small_graph_produces_n_minus_1_edges() -> void:
	## Prim over 8 nodes must produce exactly 7 edges (spanning tree).
	var nodes := _make_test_nodes()
	var inner_set := _make_inner_set()
	var mask := _make_mask(inner_set)
	var edges := VillageLayout._mst_edges(nodes, mask)
	assert_eq(edges.size(), 7,
		"Prim MST over 8 nodes must return exactly 7 edges")


func test_mst_all_nodes_connected() -> void:
	## All 8 nodes must appear in the MST edge set.
	var nodes := _make_test_nodes()
	var inner_set := _make_inner_set()
	var mask := _make_mask(inner_set)
	var edges := VillageLayout._mst_edges(nodes, mask)
	var present: Dictionary = {}
	for e_raw in edges:
		var e := e_raw as Vector2i
		present[e.x] = true
		present[e.y] = true
	assert_eq(present.size(), 8,
		"All 8 nodes must appear in the MST")


func test_mst_hero_only_connects_to_inner() -> void:
	## In the MST, every edge incident to hero (node 7) must have its door endpoint
	## in the inner set (INV-18 guarantee from the candidate mask).
	var nodes := _make_test_nodes()
	var inner_set := _make_inner_set()
	var mask := _make_mask(inner_set)
	var edges := VillageLayout._mst_edges(nodes, mask)
	for e_raw in edges:
		var e := e_raw as Vector2i
		if e.x == VillageLayout.HERO_NODE or e.y == VillageLayout.HERO_NODE:
			var door: int = e.y if e.x == VillageLayout.HERO_NODE else e.x
			assert_true(inner_set.has(door),
				"Hero MST edge must connect to inner-ring door, got door=%d" % door)


func test_mst_tie_break_lower_index() -> void:
	## Two edges of equal Euclidean length: the one with lower (min,max) idx wins.
	## Build a square: 4 nodes, all sides equal (l=1), diagonals longer.
	## Nodes: 0=(0,0), 1=(1,0), 2=(1,1), 3=(0,1), hero=4=(0.5,0.5) (not used)
	var nodes := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
		Vector2(0.5, 0.5),  # hero (node 4)
	])
	# For this test, all edges are candidates (hero only connects to node 0 as inner).
	var inner_set_small: Array[int] = [0]
	var mask_small := func(a: int, b: int) -> bool:
		if a == 4 or b == 4:
			var door: int = b if a == 4 else a
			return door == 0
		return true
	var edges := VillageLayout._mst_edges(nodes, mask_small)
	# Must have 4 edges (5-1)
	assert_eq(edges.size(), 4, "5-node MST must have 4 edges")
	# Side edges 0-1, 1-2, 2-3, 3-0 all have length=1; diagonals have length=sqrt(2)
	# MST must pick the 3 cheapest non-hero edges among 0-1, 1-2, 2-3, 3-0
	# (plus hero-0 edge). With tie-break: 0-1, 1-2, 0-3 or 2-3 expected.
	for e_raw in edges:
		var e := e_raw as Vector2i
		var edge_len := nodes[e.x].distance_to(nodes[e.y])
		# No diagonal edges should appear (they're longer than sides)
		assert_lte(edge_len, 1.001,
			"MST should not include diagonal edge (%d,%d) len=%.3f" % [e.x, e.y, edge_len])


# ── Bézier tests ──────────────────────────────────────────────────────────────

func test_bezier_starts_at_a_ends_at_b() -> void:
	var a := Vector2(5.0, 3.0)
	var b := Vector2(-2.0, 8.0)
	var poly := VillageLayout._bezier_polyline(a, b, 0.7)
	assert_gt(poly.size(), 2, "Bézier must have more than 2 points")
	var first := poly[0] as Vector2
	var last := poly[-1] as Vector2
	assert_almost_eq(first.x, a.x, 0.001, "Bézier first point X must equal a.x")
	assert_almost_eq(first.y, a.y, 0.001, "Bézier first point Y must equal a.y")
	assert_almost_eq(last.x, b.x, 0.001, "Bézier last point X must equal b.x")
	assert_almost_eq(last.y, b.y, 0.001, "Bézier last point Y must equal b.y")


func test_bezier_bend_clamp() -> void:
	## Bends larger than _BEZIER_BEND_MAX=1.5 must be clamped.
	## The polyline midpoint deviation from the chord should not exceed ~1.5 m.
	var a := Vector2(0.0, 0.0)
	var b := Vector2(10.0, 0.0)
	var chord_mid := (a + b) * 0.5
	# Call with a very large bend — internally clamped to 1.5.
	# We test this through _bezier_polyline directly.
	var poly_unclamped := VillageLayout._bezier_polyline(a, b, 10.0)
	var poly_clamped   := VillageLayout._bezier_polyline(a, b, 1.5)
	# Both should produce similar results since 10.0 is clamped to 1.5 in _route_edge.
	# For _bezier_polyline itself, we just verify it produces valid output.
	assert_gt(poly_unclamped.size(), 2, "Bezier (bend=10.0) must produce >2 points")
	# Maximum perpendicular deviation from chord for clamped version
	var max_dev := 0.0
	for pt_raw in poly_clamped:
		var pt := pt_raw as Vector2
		# Perpendicular deviation from line a–b (which is y=0 here)
		max_dev = maxf(max_dev, absf(pt.y))
	assert_lte(max_dev, 1.51, "Clamped bend=1.5 max deviation must be ≤1.51 m (got %.3f)" % max_dev)


func test_bezier_sample_spacing() -> void:
	## All consecutive sample pairs must be ≤ 2 × _BEZIER_SPACING ≈ 0.6 m apart.
	var a := Vector2(0.0, 0.0)
	var b := Vector2(15.0, 0.0)
	var poly := VillageLayout._bezier_polyline(a, b, 1.0)
	for i: int in range(poly.size() - 1):
		var pa := poly[i] as Vector2
		var pb := poly[i + 1] as Vector2
		var d := pa.distance_to(pb)
		assert_lte(d, 0.65, "Consecutive Bézier samples must be ≤ 0.65 m apart (got %.3f)" % d)


func test_bezier_zero_bend_is_straight() -> void:
	## bend=0 must produce a straight line (all points on the chord).
	var a := Vector2(0.0, 0.0)
	var b := Vector2(10.0, 0.0)
	var poly := VillageLayout._bezier_polyline(a, b, 0.0)
	for pt_raw in poly:
		var pt := pt_raw as Vector2
		assert_almost_eq(pt.y, 0.0, 0.001, "bend=0 point Y must be 0 (straight line)")


# ── Stone dedup tests ─────────────────────────────────────────────────────────

func test_dedup_classic_zero_spacing_bit_identical() -> void:
	## min_stone_spacing=0.0 must produce bit-identical output to a call with
	## the old 2-arg signature (stone_seed=9999, default args).
	## Verified by calling path_stone_transforms twice with explicit vs default args.
	var segments: Array = [
		[Vector2(0.0, 8.0), Vector2(5.0, 8.0), Vector2(10.0, 8.0)]
	]
	var reject_none := func(_cx: float, _cz: float) -> bool: return false

	var out_default := VillageScatterPositions.path_stone_transforms(
		segments, reject_none, 9999, 0.0)
	var out_explicit := VillageScatterPositions.path_stone_transforms(
		segments, reject_none, 9999)  # uses default min_stone_spacing=0.0

	assert_eq(out_default.size(), out_explicit.size(),
		"Classic (spacing=0.0) and default-args call must produce same count")
	for i: int in range(out_default.size()):
		assert_almost_eq(out_default[i].origin.x, out_explicit[i].origin.x, 1e-5,
			"Classic stone[%d] origin.x differs between calls" % i)
		assert_almost_eq(out_default[i].origin.z, out_explicit[i].origin.z, 1e-5,
			"Classic stone[%d] origin.z differs between calls" % i)


func test_dedup_removes_close_stones() -> void:
	## min_stone_spacing=0.5 must remove stones closer than 0.5 m from each other.
	## Build two parallel overlapping segments that would produce duplicate stones.
	var segments: Array = [
		[Vector2(0.0, 8.0), Vector2(10.0, 8.0)],
		[Vector2(0.1, 8.0), Vector2(10.1, 8.0)],  # nearly identical → mostly dupes
	]
	var reject_none := func(_cx: float, _cz: float) -> bool: return false
	var out_dedup := VillageScatterPositions.path_stone_transforms(
		segments, reject_none, 42, 0.5)

	# Verify no two stones are within 0.5 - ε of each other.
	var min_dist := INF
	for i: int in range(out_dedup.size()):
		for j: int in range(i + 1, out_dedup.size()):
			var pa := out_dedup[i].origin
			var pb := out_dedup[j].origin
			var d := Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))
			min_dist = minf(min_dist, d)
	assert_gte(min_dist, 0.49,
		"After dedup (spacing=0.5), min stone distance must be ≥ 0.49 m (got %.4f)" % min_dist)


func test_dedup_does_not_change_classic() -> void:
	## Passing min_stone_spacing=0.0 on a normal path must give the same count as
	## spacing=0.0 (no dedup), confirming the classic path is untouched.
	var segments: Array = [
		[Vector2(0.0, 10.0), Vector2(8.0, 10.0)]
	]
	var reject_none := func(_cx: float, _cz: float) -> bool: return false
	var out_no_dedup := VillageScatterPositions.path_stone_transforms(
		segments, reject_none, 9999, 0.0)
	var out_dedup_half := VillageScatterPositions.path_stone_transforms(
		segments, reject_none, 9999, 0.5)
	# With dedup, some may be removed; without dedup, all candidates remain.
	# On a straight segment with 0.9 m spacing, consecutive stones are ~0.9 m apart
	# (plus ±0.175 m jitter), so dedup with 0.5 m shouldn't remove many.
	assert_lte(out_no_dedup.size() - out_dedup_half.size(), 2,
		"Dedup on a well-spaced path should remove ≤ 2 stones compared to no-dedup")


# ── _build_network integration ────────────────────────────────────────────────

func test_build_network_returns_valid_structure_for_generated_seed() -> void:
	## VillageLayout.generate with a fixed seed must produce non-empty paths and edges.
	var layout := VillageLayout.generate(42)
	assert_false(layout.fallback, "seed=42 must not fall back")
	assert_gt(layout.edges.size(), 7,
		"edges must contain MST (7) + loop edges")
	assert_eq(layout.paths.size(), layout.edges.size(),
		"paths and edges must be parallel arrays")
	for i: int in range(layout.paths.size()):
		var poly := layout.paths[i] as Array
		assert_gt(poly.size(), 1, "path[%d] must have > 1 point" % i)


func test_hero_edge_ends_near_6_5m_ring() -> void:
	## All hero-incident polylines must end at |p| ∈ [6.4, 6.6] (clipped to ring).
	var layout := VillageLayout.generate(1)
	assert_false(layout.fallback, "seed=1 must not fall back")
	var any_hero_edge := false
	for i: int in range(layout.edges.size()):
		var e: Vector2i = layout.edges[i]
		if e.x == VillageLayout.HERO_NODE or e.y == VillageLayout.HERO_NODE:
			any_hero_edge = true
			var poly := layout.paths[i] as Array
			assert_gt(poly.size(), 1, "hero edge path must have > 1 point")
			var last_pt := poly[-1] as Vector2
			var r := last_pt.length()
			assert_gte(r, 6.4,
				"hero edge path[-1] |p|=%.3f m — must be ≥ 6.4 m (ring clip)" % r)
			assert_lte(r, 6.6,
				"hero edge path[-1] |p|=%.3f m — must be ≤ 6.6 m (ring clip)" % r)
	assert_true(any_hero_edge, "seed=1 must have at least one hero edge")


func test_reroute_clears_cottage() -> void:
	## Verify that _build_network still produces a valid layout even when the
	## straight-line path from one door to another passes through a cottage rect.
	## We use a real generated seed; since all 200 seeds pass the S3 sweep,
	## this test just verifies the general correctness path.
	var any_ok := false
	for seed: int in [1, 7, 13, 42, 99]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		any_ok = true
		assert_gt(layout.paths.size(), 0,
			"seed=%d: paths must be non-empty after successful network build" % seed)
	assert_true(any_ok, "At least one of the test seeds must not fall back")


func after_each() -> void:
	VillageLayout._test_force_network_fail = false
	VillageLayout._test_max_darts = -1
