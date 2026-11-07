## Unit tests for VillagePathGrower (v3 path-first stage 1).
extends GutTest

const PathGrowerScr := preload("res://src/world/village_gen/path_grower.gd")
const OccupancyGridScr := preload("res://src/world/village_gen/occupancy_grid.gd")


func _default_params(seed: int) -> PathGrowerScr.GrowParams:
	var p := PathGrowerScr.GrowParams.new()
	p.seed = seed
	return p


func _heading_change_deg(poly: PackedVector2Array, i: int) -> float:
	if i < 1 or i >= poly.size():
		return 0.0
	var v0: Vector2 = poly[i] - poly[i - 1]
	var v1: Vector2 = poly[i + 1] - poly[i]
	if v0.length_squared() < 1e-12 or v1.length_squared() < 1e-12:
		return 0.0
	return absf(rad_to_deg(PathGrowerScr._wrap_pi(v1.angle() - v0.angle())))


func _lateral_signs(poly: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if poly.size() < 3:
		return out
	var a := poly[0]
	var b := poly[poly.size() - 1]
	var ab := b - a
	for i in range(1, poly.size() - 1):
		var cr := (poly[i] - a).cross(ab)
		var s := 0
		if cr > 0.02:
			s = 1
		elif cr < -0.02:
			s = -1
		if s != 0:
			out.append(s)
	return out


func test_grow_free_deterministic_same_seed() -> void:
	var p: PathGrowerScr.GrowParams = _default_params(4242)
	var a: PackedVector2Array = PathGrowerScr.grow_free(Vector2.ZERO, 0.0, 20.0, p, null, null)
	var b: PackedVector2Array = PathGrowerScr.grow_free(Vector2.ZERO, 0.0, 20.0, p, null, null)
	assert_eq(a.size(), b.size())
	for i in range(a.size()):
		assert_almost_eq(a[i].x, b[i].x, 1e-5)
		assert_almost_eq(a[i].y, b[i].y, 1e-5)


func test_grow_free_differs_across_seeds() -> void:
	var p1: PathGrowerScr.GrowParams = _default_params(1)
	var p2: PathGrowerScr.GrowParams = _default_params(2)
	var a: PackedVector2Array = PathGrowerScr.grow_free(Vector2.ZERO, 0.3, 15.0, p1, null, null)
	var b: PackedVector2Array = PathGrowerScr.grow_free(Vector2.ZERO, 0.3, 15.0, p2, null, null)
	var diff := false
	var n := mini(a.size(), b.size())
	for i in range(n):
		if a[i].distance_to(b[i]) > 0.05:
			diff = true
			break
	assert_true(diff, "different seeds should produce different noise")


func test_resample_no_duplicate_consecutive_vertices() -> void:
	## Short first edge then long edge used to emit a sample almost identical to vertex 2 (V5 kink).
	var poly := PackedVector2Array([Vector2.ZERO, Vector2(0.3, 0.0), Vector2(2.0, 0.0)])
	var r: PackedVector2Array = PathGrowerScr.resample(poly, 0.3)
	for i: int in range(r.size() - 1):
		assert_gt(r[i].distance_to(r[i + 1]), 2e-4, "consecutive points should not duplicate")


func test_heading_step_and_per_metre_caps() -> void:
	var p: PathGrowerScr.GrowParams = _default_params(77)
	var poly: PackedVector2Array = PathGrowerScr.grow_free(Vector2(1, 1), 0.4, 30.0, p, null, null)
	for i in range(1, poly.size() - 1):
		assert_lte(_heading_change_deg(poly, i), p.max_turn_deg + 1e-3, "per-step turn cap")
	assert_lte(PathGrowerScr.max_heading_change_per_m(poly), 25.0 + 1e-3)


func test_free_growth_shape_stats() -> void:
	var pass_n := 0
	for seed in range(1, 11):
		var p: PathGrowerScr.GrowParams = _default_params(seed)
		var poly: PackedVector2Array = PathGrowerScr.grow_free(Vector2.ZERO, 0.0, 25.0, p, null, null)
		var ratio: float = PathGrowerScr.len_over_chord(poly)
		assert_gte(ratio, 1.03 - 1e-3)
		assert_lte(ratio, 1.3 + 1e-3)
		if PathGrowerScr.max_lateral_deviation(poly) >= 0.8 - 1e-3:
			pass_n += 1
		var signs := _lateral_signs(poly)
		if signs.size() >= 4:
			var pat := true
			for j in range(signs.size() - 1):
				if signs[j] != signs[j + 1]:
					pat = false
					break
			assert_false(pat, "lateral sign pattern should not be single-block flip-only for all")
	assert_gte(pass_n, 8, "≥8/10 seeds with sufficient lateral wiggle")


func test_obstacle_steering_avoids_rect() -> void:
	var g = OccupancyGridScr.new(Rect2(-20, -5, 80, 40), 1.0)
	g.block_rect(Rect2(15, -4, 8, 8), 0.0)
	var p: PathGrowerScr.GrowParams = _default_params(9001)
	var poly: PackedVector2Array = PathGrowerScr.grow_free(Vector2(0, 0), 0.0, 35.0, p, g, null)
	var min_cl := INF
	for pt in poly:
		min_cl = minf(min_cl, g.clearance(pt))
	assert_gte(min_cl, 0.4)


func test_pursuit_stays_free_and_reaches_guide_end() -> void:
	var g = OccupancyGridScr.new(Rect2(0, 0, 50, 30), 1.0)
	g.block_rect(Rect2(20, 5, 6, 20), 0.0)
	var guide: PackedVector2Array = g.astar(Vector2(5, 15), Vector2(45, 15))
	assert_gt(guide.size(), 2)
	var p: PathGrowerScr.GrowParams = _default_params(240424)
	var poly: PackedVector2Array = PathGrowerScr.grow_pursuit(Vector2(5, 15), guide, p, g)
	assert_almost_eq(poly[poly.size() - 1].x, guide[guide.size() - 1].x, 0.2)
	assert_almost_eq(poly[poly.size() - 1].y, guide[guide.size() - 1].y, 0.2)
	for pt in poly:
		assert_true(g.is_free(pt))


func test_best_of_picks_lower_cost() -> void:
	var g = OccupancyGridScr.new(Rect2(0, 0, 60, 60), 1.0)
	var a := PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(40, 5)])
	var b := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(40, 5)])
	var pick: PackedVector2Array = PathGrowerScr.best_of([a, b], g, [])
	assert_eq(pick.size(), b.size())
	assert_almost_eq(pick[2].x, 40.0, 1e-4)


func test_shape_cost_weights() -> void:
	var g = OccupancyGridScr.new(Rect2(0, 0, 10, 10), 1.0)
	var long := PackedVector2Array([Vector2(0, 0), Vector2(30, 0.01)])
	var short := PackedVector2Array([Vector2(0, 0), Vector2(5, 0)])
	var c_long: float = PathGrowerScr.shape_cost(long, g, [], {"w1": 1.0, "w2": 0.0, "w3": 0.0, "w4": 0.0, "w5": 0.0})
	var c_short: float = PathGrowerScr.shape_cost(short, g, [], {"w1": 1.0, "w2": 0.0, "w3": 0.0, "w4": 0.0, "w5": 0.0})
	assert_gt(c_long, c_short)
