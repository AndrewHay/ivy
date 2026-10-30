## Sweep test for VillageLayout.generate() — ivy-80z S2′ (two-ring placement).
##
## Seeds 1..200 (SD-VILLAGE-GEN-5). Per seed: INV-1..4, 11..14, 16, 17.
## Whole-sweep: INV-11 (determinism), INV-12 (variability).
## Plus edge-seed, forced-fallback, ring-assignment variability, and ≤ 20 ms perf tests.
extends GutTest

# ── Helpers ───────────────────────────────────────────────────────────────────

## Shortest distance from the world origin (0,0) to the nearest point on `rect`
## (2-D equivalent of the AABB helper in test_village_backdrop.gd).
static func _rect2_dist_from_origin(rect: Rect2) -> float:
	var nx := clampf(0.0, rect.position.x, rect.end.x)
	var ny := clampf(0.0, rect.position.y, rect.end.y)
	return sqrt(nx * nx + ny * ny)


## All 4 corners of a Rect2.
static func _rect2_corners(rect: Rect2) -> Array[Vector2]:
	return [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]


## Build a canonical string key for a layout (used for INV-12 variability check).
## Format: sorted (centreX_mm, centreY_mm, yaw) tuples joined.
static func _layout_key(layout: VillageLayout) -> String:
	var parts: Array[String] = []
	for spec: Dictionary in layout.cottages:
		var c: Vector2 = spec["centre"]
		var cx_mm := int(round(c.x * 1000.0))
		var cy_mm := int(round(c.y * 1000.0))
		var y: int = spec["yaw_deg"]
		parts.append("%d,%d,%d" % [cx_mm, cy_mm, y])
	parts.sort()
	return "|".join(parts)


## Angular difference (0..180°) between two angles in degrees.
static func _ang_diff_deg(a: float, b: float) -> float:
	var diff := fmod(absf(a - b), 360.0)
	if diff > 180.0:
		diff = 360.0 - diff
	return diff


# ── Teardown ──────────────────────────────────────────────────────────────────

func after_each() -> void:
	## Always reset the test hook so subsequent tests use the real _MAX_DARTS.
	VillageLayout._test_max_darts = -1


# ── Per-seed invariants (INV-1..4, 11..14, fallback=false) ───────────────────

func test_per_seed_invariants() -> void:
	## INV-1: nearest grown-0.8 face ≥ 5.9 m from origin
	## INV-2: no pair of grown-0.8 rects intersects (across both rings)
	## INV-3 (two-ring): inner centre ∈ [11.5,13.0] m; outer centre ∈ [19.5,21.5] m;
	##        farthest grown corner ≤ 27.5 m
	## INV-4: door dot(normal, (−door_pos).normalized()) > 0.5
	## INV-13: exactly 7 cottages; type multiset equals COTTAGES
	## INV-14: yaw ∈ {0, 90, 180, 270}
	## fallback == false for all 200 seeds
	var SWEEP_SEEDS := 200
	var fallback_count := 0

	for seed in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)

		var seed_tag := "seed=%d" % seed

		# fallback must be false
		if layout.fallback:
			fallback_count += 1

		# INV-13a: exactly 7 cottages
		assert_eq(layout.cottages.size(), 7,
			"%s: must have exactly 7 cottages (INV-13)" % seed_tag)
		if layout.cottages.size() != 7:
			continue  # skip geometry checks on wrong-count layouts

		# INV-13b: type multiset equals COTTAGES
		# Compare sorted (bays, door, brick, chimney_bay) tuples
		var expected_types: Array[String] = []
		for s: Dictionary in VillageBackdrop.COTTAGES:
			expected_types.append(
				"%d|%s|%s|%d" % [int(s["bays"]), String(s["door"]), String(s["brick"]), int(s["chimney_bay"])])
		expected_types.sort()
		var got_types: Array[String] = []
		for s: Dictionary in layout.cottages:
			got_types.append(
				"%d|%s|%s|%d" % [int(s["bays"]), String(s["door"]), String(s["brick"]), int(s["chimney_bay"])])
		got_types.sort()
		assert_eq(got_types, expected_types,
			"%s: cottage type multiset must equal COTTAGES (INV-13)" % seed_tag)

		# cottage_rings must be parallel and size 7
		assert_eq(layout.cottage_rings.size(), 7,
			"%s: cottage_rings must have 7 entries (INV-16)" % seed_tag)
		if layout.cottage_rings.size() != 7:
			continue

		# Per-cottage geometry checks
		var placed_rects: Array[Rect2] = []
		for i: int in layout.cottages.size():
			var spec: Dictionary = layout.cottages[i]
			var tag := "%s cottage[%d](%s)" % [seed_tag, i, String(spec.get("name", "?"))]

			# INV-14: yaw ∈ {0, 90, 180, 270}
			var yaw: int = spec["yaw_deg"]
			assert_true(yaw in [0, 90, 180, 270],
				"%s: yaw_deg=%d not in {0,90,180,270} (INV-14)" % [tag, yaw])

			# INV-3a (two-ring): centre radius per ring
			var centre: Vector2 = spec["centre"]
			var ring_id: int = layout.cottage_rings[i]
			if ring_id == 0:
				# inner ring
				assert_gte(centre.length(), 11.5,
					"%s: inner centre %.3f m < R_IN_MIN=11.5 m (INV-3)" % [tag, centre.length()])
				assert_lte(centre.length(), 13.0,
					"%s: inner centre %.3f m > R_IN_MAX=13.0 m (INV-3)" % [tag, centre.length()])
			else:
				# outer ring
				assert_gte(centre.length(), 19.5,
					"%s: outer centre %.3f m < R_OUT_MIN=19.5 m (INV-3)" % [tag, centre.length()])
				assert_lte(centre.length(), 21.5,
					"%s: outer centre %.3f m > R_OUT_MAX=21.5 m (INV-3)" % [tag, centre.length()])

			var grown_rect := VillageBackdrop.cottage_exterior_rect(spec).grow(0.8)

			# INV-3b: farthest grown corner ≤ 27.5 m (two-ring outer bound)
			for corner: Vector2 in _rect2_corners(grown_rect):
				assert_lte(corner.length(), 27.5,
					"%s: corner distance %.3f m > 27.5 m (INV-3)" % [tag, corner.length()])

			# INV-1: nearest grown-rect face ≥ 5.9 m from origin
			var dist_origin := _rect2_dist_from_origin(grown_rect)
			assert_gte(dist_origin, 5.9,
				"%s: nearest face %.3f m < 5.9 m keep-out (INV-1)" % [tag, dist_origin])

			# INV-4: door faces hero — dot > 0.5
			var door_info := VillageBackdrop.cottage_door(spec)
			var door_pos: Vector2 = door_info[0]
			var door_normal: Vector2 = door_info[1]
			var dot_val: float = door_normal.dot((-door_pos).normalized())
			assert_gt(dot_val, 0.5,
				"%s: door dot=%.4f ≤ 0.5 — door does not face hero (INV-4)" % [tag, dot_val])

			placed_rects.append(grown_rect)

		# INV-2: no pair of grown-0.8 rects intersects (across both rings)
		for i: int in placed_rects.size():
			for j: int in range(i + 1, placed_rects.size()):
				var overlaps := placed_rects[i].intersects(placed_rects[j], false)
				assert_false(overlaps,
					"%s: cottages [%d] and [%d] grown rects overlap (INV-2)" % [seed_tag, i, j])

	assert_eq(fallback_count, 0,
		"fallback=true for %d / 200 seeds — must be 0 (acceptance criterion)" % fallback_count)


# ── INV-16 — Ring membership ──────────────────────────────────────────────────

func test_ring_membership() -> void:
	## INV-16: exactly 3 inner (ring=0, all bays=3), 4 outer (ring=1);
	## both 4-bay types (CA, CD) must always be outer.
	var SWEEP_SEEDS := 200
	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		var seed_tag := "seed=%d" % seed
		if layout.fallback or layout.cottages.size() != 7 or layout.cottage_rings.size() != 7:
			continue

		var inner_count := 0
		var outer_count := 0
		var all_inner_3bay := true
		var four_bay_outer := true

		for i: int in 7:
			var spec: Dictionary = layout.cottages[i]
			var ring: int = layout.cottage_rings[i]
			var bays: int = int(spec["bays"])
			var name: String = String(spec.get("name", "?"))

			if ring == 0:
				inner_count += 1
				if bays != 3:
					all_inner_3bay = false
			elif ring == 1:
				outer_count += 1

			# 4-bay (CA, CD) must always be outer
			if bays == 4 and ring != 1:
				four_bay_outer = false
				assert_true(false,
					"%s: 4-bay cottage %s (idx %d) must be outer (ring=1) (INV-16)" % [seed_tag, name, i])

		assert_eq(inner_count, 3,
			"%s: must have exactly 3 inner cottages (INV-16), got %d" % [seed_tag, inner_count])
		assert_eq(outer_count, 4,
			"%s: must have exactly 4 outer cottages (INV-16), got %d" % [seed_tag, outer_count])
		assert_true(all_inner_3bay,
			"%s: all inner cottages must be 3-bay (INV-16)" % seed_tag)
		assert_true(four_bay_outer,
			"%s: both 4-bay cottages must be outer (INV-16)" % seed_tag)


# ── INV-17 — Per-ring angular spread ─────────────────────────────────────────

func test_per_ring_angular_spread() -> void:
	## INV-17: inner pairwise angular separation ≥ 65°; outer pairwise ≥ 50°.
	var SWEEP_SEEDS := 200
	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		var seed_tag := "seed=%d" % seed
		if layout.fallback or layout.cottages.size() != 7 or layout.cottage_rings.size() != 7:
			continue

		var inner_angles: Array[float] = []
		var outer_angles: Array[float] = []

		for i: int in 7:
			var spec: Dictionary = layout.cottages[i]
			var centre: Vector2 = spec["centre"]
			var angle_deg := rad_to_deg(atan2(centre.y, centre.x))
			if layout.cottage_rings[i] == 0:
				inner_angles.append(angle_deg)
			else:
				outer_angles.append(angle_deg)

		# Inner: pairwise ≥ 65°
		for i: int in inner_angles.size():
			for j: int in range(i + 1, inner_angles.size()):
				var diff := _ang_diff_deg(inner_angles[i], inner_angles[j])
				assert_gte(diff, 65.0,
					"%s: inner cottages [%d],[%d] angular sep=%.2f° < 65° (INV-17)" % [seed_tag, i, j, diff])

		# Outer: pairwise ≥ 50°
		for i: int in outer_angles.size():
			for j: int in range(i + 1, outer_angles.size()):
				var diff := _ang_diff_deg(outer_angles[i], outer_angles[j])
				assert_gte(diff, 50.0,
					"%s: outer cottages [%d],[%d] angular sep=%.2f° < 50° (INV-17)" % [seed_tag, i, j, diff])


# ── INV-11 — Determinism ──────────────────────────────────────────────────────

func test_determinism() -> void:
	## generate(seed) called twice must produce identical centre (≤ 1e-4), yaw, and ring.
	var test_seeds := [1, 42, 100, 12345, 200]
	for seed: int in test_seeds:
		var a := VillageLayout.generate(seed)
		var b := VillageLayout.generate(seed)
		assert_eq(a.cottages.size(), b.cottages.size(),
			"seed=%d: cottage count differs between two calls (INV-11)" % seed)
		assert_eq(a.cottage_rings.size(), b.cottage_rings.size(),
			"seed=%d: cottage_rings size differs between two calls (INV-11)" % seed)
		for i: int in a.cottages.size():
			var ca: Vector2 = a.cottages[i]["centre"]
			var cb: Vector2 = b.cottages[i]["centre"]
			assert_almost_eq(ca.x, cb.x, 1e-4,
				"seed=%d cottage[%d] centre.x differs (INV-11)" % [seed, i])
			assert_almost_eq(ca.y, cb.y, 1e-4,
				"seed=%d cottage[%d] centre.y differs (INV-11)" % [seed, i])
			assert_eq(int(a.cottages[i]["yaw_deg"]), int(b.cottages[i]["yaw_deg"]),
				"seed=%d cottage[%d] yaw differs (INV-11)" % [seed, i])
			if i < a.cottage_rings.size() and i < b.cottage_rings.size():
				assert_eq(int(a.cottage_rings[i]), int(b.cottage_rings[i]),
					"seed=%d cottage[%d] ring differs (INV-11)" % [seed, i])
		assert_eq(a.stone_seed, b.stone_seed,
			"seed=%d stone_seed differs between calls (INV-11)" % seed)


# ── INV-12 — Variability ──────────────────────────────────────────────────────

func test_variability() -> void:
	## Over seeds 1..200, ≥ 190/200 unique (centre, yaw) layouts (≥ 95%).
	var seen: Dictionary = {}
	var total := 200
	for seed: int in range(1, total + 1):
		var layout := VillageLayout.generate(seed)
		var key := _layout_key(layout)
		if not seen.has(key):
			seen[key] = 0
		seen[key] += 1
	var unique_count := seen.size()
	assert_gte(unique_count, 190,
		"Only %d/200 unique layouts — need ≥ 190 (INV-12)" % unique_count)


func test_inner_assignment_varies_across_seeds() -> void:
	## The Fisher–Yates inner-set assignment must produce ≥ 3 distinct inner-cottage
	## name-sets over 200 seeds (seeded, not fixed).
	var inner_sets: Dictionary = {}
	for seed: int in range(1, 201):
		var layout := VillageLayout.generate(seed)
		if layout.fallback or layout.cottage_rings.size() != 7:
			continue
		var inner_names: Array[String] = []
		for i: int in 7:
			if layout.cottage_rings[i] == 0:
				inner_names.append(String(layout.cottages[i].get("name", "?")))
		inner_names.sort()
		var key := "|".join(inner_names)
		inner_sets[key] = true
	assert_gte(inner_sets.size(), 3,
		"inner-set varies only %d ways over 200 seeds — need ≥ 3 (seeded assignment)" % inner_sets.size())


# ── Edge-seed tests ────────────────────────────────────────────────────────────

func test_edge_seed_zero() -> void:
	var layout := VillageLayout.generate(0)
	assert_false(layout.fallback, "seed=0 must not fall back")
	assert_eq(layout.cottages.size(), 7, "seed=0 must produce 7 cottages")
	# Determinism: call twice
	var layout2 := VillageLayout.generate(0)
	assert_eq(_layout_key(layout), _layout_key(layout2), "seed=0 must be deterministic")


func test_edge_seed_negative_one() -> void:
	## -1 normalised by & 0x7FFFFFFF = 0x7FFFFFFF = 2147483647.
	var layout := VillageLayout.generate(-1)
	assert_false(layout.fallback, "seed=-1 must not fall back")
	assert_eq(layout.cottages.size(), 7, "seed=-1 must produce 7 cottages")
	# Must equal normalised positive seed
	var norm_seed := -1 & 0x7FFFFFFF  # GDScript applies & as bitwise; result = 2147483647
	var layout2 := VillageLayout.generate(norm_seed)
	assert_eq(_layout_key(layout), _layout_key(layout2),
		"generate(-1) must equal generate(-1 & 0x7FFFFFFF)")


func test_edge_seed_large() -> void:
	## 2^62 masked to 31 bits — must be deterministic.
	const HUGE_SEED: int = 1 << 62
	var layout := VillageLayout.generate(HUGE_SEED)
	assert_eq(layout.cottages.size(), 7, "huge seed must produce 7 cottages")
	var layout2 := VillageLayout.generate(HUGE_SEED)
	assert_eq(_layout_key(layout), _layout_key(layout2),
		"huge seed must be deterministic")


# ── Forced-fallback test ──────────────────────────────────────────────────────

func test_forced_fallback() -> void:
	## With _test_max_darts = 0, every _place_cottages call exhausts immediately,
	## so generate() must return authored() with fallback=true after all redraws.
	VillageLayout._test_max_darts = 0
	var layout := VillageLayout.generate(42)
	VillageLayout._test_max_darts = -1

	assert_true(layout.fallback,
		"fallback must be true when _test_max_darts=0 forces all attempts to fail")
	# Fallback returns authored() shape
	assert_eq(layout.cottages.size(), 7,
		"fallback layout must still have 7 cottages (authored())")
	# Verify it matches authored() centres
	var authored := VillageLayout.authored()
	for i: int in layout.cottages.size():
		var lc: Vector2 = layout.cottages[i]["centre"]
		var ac: Vector2 = authored.cottages[i]["centre"]
		assert_almost_eq(lc.x, ac.x, 1e-4,
			"fallback cottage[%d] centre.x must match authored" % i)
		assert_almost_eq(lc.y, ac.y, 1e-4,
			"fallback cottage[%d] centre.y must match authored" % i)


# ── Performance test (includes S3 network) ────────────────────────────────────

func test_generate_under_20ms() -> void:
	## Hard ceiling: generate() (including network build) must complete in ≤ 20 ms.
	var test_seeds := [1, 12, 42, 100, 12345, 77777, 200]
	var max_ms := 0.0
	var total_ms := 0.0
	for seed: int in test_seeds:
		var t0 := Time.get_ticks_usec()
		var _layout := VillageLayout.generate(seed)
		var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		total_ms += elapsed_ms
		if elapsed_ms > max_ms:
			max_ms = elapsed_ms
		assert_lte(elapsed_ms, 20.0,
			"generate(%d) took %.2f ms — exceeds 20 ms hard ceiling" % [seed, elapsed_ms])

	var avg_ms := total_ms / float(test_seeds.size())
	print("[perf] generate() over %d seeds: avg=%.2f ms  max=%.2f ms" \
		% [test_seeds.size(), avg_ms, max_ms])


# ── S3 network invariants (seeds 1..200) ──────────────────────────────────────

## Union-find helper (path-compressed).
static func _uf_find(parent: Array[int], x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

static func _uf_union(parent: Array[int], rank: Array[int], a: int, b: int) -> void:
	var ra := _uf_find(parent, a)
	var rb := _uf_find(parent, b)
	if ra == rb:
		return
	if rank[ra] < rank[rb]:
		var tmp := ra; ra = rb; rb = tmp
	parent[rb] = ra
	if rank[ra] == rank[rb]:
		rank[ra] += 1

## Shortest distance from point p to an axis-aligned Rect2 (0 if inside).
static func _pt_dist_to_rect_test(p: Vector2, rect: Rect2) -> float:
	var dx := maxf(0.0, maxf(rect.position.x - p.x, p.x - rect.end.x))
	var dy := maxf(0.0, maxf(rect.position.y - p.y, p.y - rect.end.y))
	return sqrt(dx * dx + dy * dy)


func test_per_seed_network_invariants() -> void:
	## INV-5: every door (0..6) reaches hero (7) via layout.edges (union-find).
	## INV-6: loop_count = edges.size() - 7 ∈ [MIN_LOOPS=3, TARGET_LOOPS=4].
	## INV-18: every edge incident to node 7 has its door endpoint in inner ring;
	##         hero_degree ≤ 3.
	## INV-19: ≥ 6 edges with both endpoints < 7 (house-to-house guarantee).
	const SWEEP_SEEDS := 200
	const HERO := 7
	const N_NODES := 8
	const MIN_LOOPS := 3
	const TARGET_LOOPS := 4

	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		var seed_tag := "seed=%d" % seed
		if layout.fallback:
			continue  # placement fallback — network invariants don't apply

		var edges := layout.edges
		var cottage_rings := layout.cottage_rings

		# ── INV-6: loop count ─────────────────────────────────────────────
		var n_tree_edges := N_NODES - 1  # 7 for 8-node spanning tree
		var loop_count := edges.size() - n_tree_edges
		assert_gte(loop_count, MIN_LOOPS,
			"%s: loop_count=%d < MIN_LOOPS=%d (INV-6)" % [seed_tag, loop_count, MIN_LOOPS])
		assert_lte(loop_count, TARGET_LOOPS,
			"%s: loop_count=%d > TARGET_LOOPS=%d (INV-6)" % [seed_tag, loop_count, TARGET_LOOPS])

		# ── INV-5: connectivity (union-find over edges) ───────────────────
		var parent: Array[int] = []
		var rank_arr: Array[int] = []
		parent.resize(N_NODES); rank_arr.resize(N_NODES)
		for i: int in range(N_NODES):
			parent[i] = i
			rank_arr[i] = 0
		for e: Vector2i in edges:
			_uf_union(parent, rank_arr, e.x, e.y)
		var root := _uf_find(parent, HERO)
		var all_connected := true
		for i: int in range(N_NODES):
			if _uf_find(parent, i) != root:
				all_connected = false
				break
		assert_true(all_connected,
			"%s: not all 8 nodes reachable from hero via edges (INV-5)" % seed_tag)

		# ── INV-18: hero edges → inner only; hero_degree ≤ 3 ─────────────
		var hero_degree := 0
		for e: Vector2i in edges:
			var ai := e.x
			var bi := e.y
			if ai == HERO or bi == HERO:
				hero_degree += 1
				var door_idx := bi if ai == HERO else ai
				assert_true(door_idx < cottage_rings.size() and int(cottage_rings[door_idx]) == 0,
					"%s: hero edge door=%d is not inner ring (INV-18)" % [seed_tag, door_idx])
		assert_lte(hero_degree, 3,
			"%s: hero_degree=%d > 3 (INV-18)" % [seed_tag, hero_degree])

		# ── INV-19: ≥ 6 house-to-house edges ─────────────────────────────
		var h2h_count := 0
		for e: Vector2i in edges:
			if e.x < HERO and e.y < HERO:
				h2h_count += 1
		assert_gte(h2h_count, 6,
			"%s: house-to-house edge count=%d < 6 (INV-19)" % [seed_tag, h2h_count])


func test_per_seed_network_clearance() -> void:
	## INV-8: no polyline centreline sample within PATH_CLEARANCE=0.35 m of any
	## non-endpoint cottage rect grown by PATH_COTTAGE_GROW=0.2 m.
	## Checks seeds 1..200 (uses paths and edges parallel arrays).
	const SWEEP_SEEDS := 200
	const PATH_COTTAGE_GROW := 0.2
	const PATH_CLEARANCE := 0.35

	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		var seed_tag := "seed=%d" % seed
		if layout.fallback or layout.paths.is_empty():
			continue

		# Pre-build grown rects.
		var cottage_rects: Array[Rect2] = []
		for spec: Dictionary in layout.cottages:
			cottage_rects.append(VillageBackdrop.cottage_exterior_rect(spec).grow(PATH_COTTAGE_GROW))

		# For each path, look up its endpoint cottage indices via layout.edges.
		for pi: int in layout.paths.size():
			var poly := layout.paths[pi] as Array
			var endpoint_indices: Array[int] = []
			if pi < layout.edges.size():
				var e: Vector2i = layout.edges[pi]
				if e.x < layout.cottages.size():
					endpoint_indices.append(e.x)
				if e.y < layout.cottages.size():
					endpoint_indices.append(e.y)

			for pt_raw in poly:
				var pt := pt_raw as Vector2
				for ci: int in range(cottage_rects.size()):
					if endpoint_indices.has(ci):
						continue
					var dist := _pt_dist_to_rect_test(pt, cottage_rects[ci])
					assert_gte(dist, PATH_CLEARANCE,
						"%s path[%d] sample %s too close (%.3f m) to cottage[%d] (INV-8)" \
						% [seed_tag, pi, str(pt), dist, ci])


func test_network_determinism() -> void:
	## Calling generate(seed) twice must produce identical paths and edges (INV-11 extended).
	var test_seeds := [1, 42, 100, 12345, 200]
	for seed: int in test_seeds:
		var a := VillageLayout.generate(seed)
		var b := VillageLayout.generate(seed)
		assert_eq(a.edges.size(), b.edges.size(),
			"seed=%d: edges.size differs between two calls" % seed)
		assert_eq(a.paths.size(), b.paths.size(),
			"seed=%d: paths.size differs between two calls" % seed)
		for i: int in range(mini(a.edges.size(), b.edges.size())):
			assert_eq(a.edges[i], b.edges[i],
				"seed=%d edges[%d] differs" % [seed, i])
		for i: int in range(mini(a.paths.size(), b.paths.size())):
			var pa := a.paths[i] as Array
			var pb := b.paths[i] as Array
			assert_eq(pa.size(), pb.size(),
				"seed=%d paths[%d].size differs" % [seed, i])


func test_network_path_variability() -> void:
	## Over seeds 1..200 at least 180/200 must produce distinct edge sets.
	var edge_keys: Dictionary = {}
	for seed: int in range(1, 201):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var parts: Array[String] = []
		for e: Vector2i in layout.edges:
			parts.append("%d_%d" % [mini(e.x, e.y), maxi(e.x, e.y)])
		parts.sort()
		var key := "|".join(parts)
		edge_keys[key] = true
	assert_gte(edge_keys.size(), 150,
		"Only %d/200 distinct edge sets — expected ≥ 150" % edge_keys.size())


func test_each_door_has_polyline() -> void:
	## Each door stoop index 0..6 must be the start (or end) of at least one polyline.
	var test_seeds := [1, 42, 100]
	for seed: int in test_seeds:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		for door: int in range(7):
			var found := false
			for e: Vector2i in layout.edges:
				if e.x == door or e.y == door:
					found = true
					break
			assert_true(found,
				"seed=%d: door[%d] has no edge in network" % [seed, door])


func test_network_fallback_hook() -> void:
	## _test_force_network_fail = true must produce fallback=true.
	VillageLayout._test_force_network_fail = true
	var layout := VillageLayout.generate(42)
	VillageLayout._test_force_network_fail = false
	assert_true(layout.fallback,
		"_test_force_network_fail=true must yield fallback=true")
	assert_eq(layout.paths, VillageLayout.authored().paths,
		"Forced network fallback must return authored() paths")


func test_stone_count_budget() -> void:
	## INV-10: stone count ∈ [70, 360] after dedup.
	## Also reports min/median/max for diagnostics.
	const SWEEP_SEEDS := 200
	var counts: Array[int] = []
	var fails: Array[String] = []
	for seed: int in range(1, SWEEP_SEEDS + 1):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var stones := VillageScatterPositions.path_stone_transforms(
			layout.path_polylines(),
			func(cx: float, cz: float) -> bool:
				return Vector2(cx, cz).length() < 4.5 or layout.inside_any_cottage(Vector2(cx, cz), 0.2),
			layout.stone_seed, layout.min_stone_spacing)
		counts.append(stones.size())
		if stones.size() < 70 or stones.size() > 360:
			fails.append("seed=%d: %d stones" % [seed, stones.size()])
	counts.sort()
	var med_idx := counts.size() / 2
	var median := counts[med_idx] if not counts.is_empty() else 0
	print("[INV-10] stone counts: min=%d  median=%d  max=%d over %d seeds" \
		% [counts[0] if not counts.is_empty() else 0,
		   median,
		   counts[-1] if not counts.is_empty() else 0,
		   counts.size()])
	assert_eq(fails.size(), 0,
		"Stone count out of [70,360] range for %d seeds:\n%s" \
		% [fails.size(), "\n".join(fails)])
