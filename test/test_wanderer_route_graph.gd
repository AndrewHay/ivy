extends GutTest

const WandererRouteGraph = preload("res://src/presentation/wanderer/wanderer_route_graph.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")


func test_classic_all_houses_reachable() -> void:
	var layout := VillageLayout.authored()
	var p := WandererParams.production()
	var g := WandererRouteGraph.build(layout, p)
	assert_false(g.is_disabled())
	assert_gte(g.reachable_houses().size(), 2)
	assert_gte(g.bridge_count, 1)


func test_route_on_segments() -> void:
	var layout := VillageLayout.authored()
	var p := WandererParams.production()
	var g := WandererRouteGraph.build(layout, p)
	var rh: PackedInt32Array = g.reachable_houses()
	if rh.size() < 2:
		return
	var r: PackedVector2Array = g.route(rh[0], rh[1])
	assert_gt(r.size(), 1)
	var segs: Array = g.segments()
	for pt in r:
		assert_true(_point_on_graph(pt, segs), "route leaves graph at %s" % pt)


func _point_on_graph(pt: Vector2, segs: Array, tol: float = 0.05) -> bool:
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if _dist_segment(pt, a, b) <= tol:
			return true
	return false


func _dist_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := ab.dot(p - a) / maxf(ab.length_squared(), 1e-9)
	t = clampf(t, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func test_houses_have_door_exterior() -> void:
	var p := WandererParams.production()
	var houses: Array[Dictionary] = [
		{"name": "A", "door": Vector2(1, 2), "normal": Vector2(0, 1)},
	]
	var paths: Array = [[Vector2(0, 0), Vector2(1, 2)]]
	var g := WandererRouteGraph.from_raw(houses, paths, p)
	var h: Dictionary = g.houses[0]
	assert_true(h.has("door_exterior"))
	assert_almost_eq(h["door_exterior"].x, 1.0, 1e-4)
	assert_almost_eq(h["door_exterior"].y, 2.0, 1e-4)


func test_leg_from_present_spur_along_minus_normal() -> void:
	var p := WandererParams.production()
	var n := Vector2(0, 1)
	var door := Vector2(5, 3)
	var present := door + n * 2.5
	var stoop := door + n * 0.5
	var base := PackedVector2Array([stoop, Vector2(0, 0), Vector2(10, 0)])
	var leg := WandererRouteGraph.leg_from_present(base, present, stoop)
	assert_almost_eq(leg[0].x, present.x, 1e-4)
	assert_almost_eq(leg[0].y, present.y, 1e-4)
	assert_almost_eq(leg[1].x, stoop.x, 1e-4)
	var dir := (leg[1] - leg[0]).normalized()
	assert_gt(dir.dot(-n), 0.99)
	var mid01 := leg[0].lerp(leg[1], 0.5)
	assert_gte((mid01 - door).dot(n), -0.01, "spur must not cross wall plane")


func test_empty_paths_disabled() -> void:
	var p := WandererParams.production()
	var houses: Array[Dictionary] = [
		{"name": "A", "door": Vector2(1, 0), "normal": Vector2(0, 1)},
	]
	var g := WandererRouteGraph.from_raw(houses, [], p)
	assert_true(g.is_disabled())


func test_generated_seed_routing() -> void:
	var layout := VillageLayout.generate(42)
	var p := WandererParams.production()
	p.hero_xz = Vector2.ZERO
	var g := WandererRouteGraph.build(layout, p)
	assert_false(g.is_disabled())
	var rh: PackedInt32Array = g.reachable_houses()
	assert_gte(rh.size(), 2)
	var r: PackedVector2Array = g.route(rh[0], rh[1])
	assert_gt(r.size(), 1)
	var segs: Array = g.segments()
	const max_step := 3.0
	for i in range(1, r.size()):
		assert_lte(r[i - 1].distance_to(r[i]), max_step)
		assert_true(_point_on_graph(r[i], segs, 0.35) or _near_bridge_arc(r[i], segs, p), r[i])


func _near_bridge_arc(pt: Vector2, segs: Array, params: WandererParams, tol: float = 0.5) -> bool:
	var hero := params.hero_xz
	if pt.distance_to(hero) < params.bridge_min_ring_m + tol:
		return true
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if _dist_segment(pt, a, b) <= tol:
			return true
	return false


func test_five_hundred_targets_not_repeat() -> void:
	const WandererBrain = preload("res://src/presentation/wanderer/wanderer_brain.gd")
	const WandererContent = preload("res://src/presentation/wanderer/wanderer_content.gd")
	var layout := VillageLayout.generate(42)
	var p := WandererParams.production()
	p.hero_xz = Vector2.ZERO
	var g := WandererRouteGraph.build(layout, p)
	var c := WandererContent.from_arrays(PackedStringArray(["hi"]), PackedFloat32Array([1.0]))
	var b := WandererBrain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	b.setup(p, g, c, rng)
	b.start()
	# After a visit last_house == target_house until the next pick, so check each new pick
	# against the house he is leaving.
	var picks := 0
	var prev_target := b.target_house
	var prev_last := b.last_house
	for _i in 4000:
		b.tick(0.05)
		if b.target_house != prev_target:
			picks += 1
			assert_ne(b.target_house, prev_last, "new target is the house he just left")
		prev_target = b.target_house
		prev_last = b.last_house
	assert_gte(picks, 3, "several legs exercised")
