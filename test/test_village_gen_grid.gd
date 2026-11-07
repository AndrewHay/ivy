## Unit tests for VillageOccupancyGrid (v3 path-first stage 1).
extends GutTest

const OccupancyGridScr := preload("res://src/world/village_gen/occupancy_grid.gd")


func test_block_rect_and_is_free() -> void:
	var g = OccupancyGridScr.new(Rect2(-10, -10, 40, 40), 1.0)
	g.block_rect(Rect2(0, 0, 6, 6), 1.0)
	assert_false(g.is_free(Vector2(3, 3)), "inside grown rect should be blocked")
	assert_true(g.is_free(Vector2(-5, -5)), "far corner should stay free")


func test_clearance_near_wall() -> void:
	var g = OccupancyGridScr.new(Rect2(0, 0, 32, 32), 1.0)
	g.block_rect(Rect2(10, 10, 8, 8), 0.0)
	## Cell (9, 13) centre ~(9.5, 13.5) — adjacent north of blocked region
	var p := Vector2(9.5, 13.5)
	var c: float = g.clearance(p)
	assert_gt(c, 0.4, "clearance adjacent to block should be ~1 cell edge")
	assert_lt(c, 1.6, "clearance should not jump far for one step away from block")


func test_clearance_gradient_points_to_more_space() -> void:
	var g = OccupancyGridScr.new(Rect2(0, 0, 40, 40), 1.0)
	g.block_rect(Rect2(10, 10, 10, 10), 0.0)
	var p := Vector2(9.6, 15.0)
	var grad: Vector2 = g.clearance_gradient(p)
	assert_gt(grad.dot(Vector2(-1, 0)), 0.7, "gradient should favor -X (away from block)")


func test_astar_routes_around_wall() -> void:
	var g = OccupancyGridScr.new(Rect2(0, 0, 40, 40), 1.0)
	## Full-height wall except gap at y=5 row not needed — leave bottom corridor
	g.block_rect(Rect2(18, 0, 4, 26), 0.0)
	var a := Vector2(8, 8)
	var b := Vector2(32, 8)
	var path: PackedVector2Array = g.astar(a, b)
	assert_gt(path.size(), 2, "path should bend around obstacle")
	for pt in path:
		var pv: Vector2 = pt
		assert_true(g.is_free(pv), "path must stay in free cells")


func test_astar_empty_when_sealed() -> void:
	var g = OccupancyGridScr.new(Rect2(0, 0, 40, 40), 1.0)
	g.block_rect(Rect2(18, 0, 4, 40), 0.0)
	var path: PackedVector2Array = g.astar(Vector2(10, 20), Vector2(30, 20))
	assert_eq(path.size(), 0, "no route through solid wall")


func test_grid_performance_120_astar_and_clearance() -> void:
	var g = OccupancyGridScr.new(Rect2(0, 0, 120, 120), 1.0)
	g.block_rect(Rect2(50, 10, 20, 100), 0.0)
	## Warm up script/cache timing noise (first clearance can skew high in editor/headless)
	for _w in range(3):
		g.clearance(Vector2(10.5, 10.5))
	var t0 := Time.get_ticks_usec()
	var _c: float = g.clearance(Vector2(10.5, 10.5))
	var t1 := Time.get_ticks_usec()
	var path: PackedVector2Array = g.astar(Vector2(5.5, 60.5), Vector2(115.5, 60.5))
	var t2 := Time.get_ticks_usec()
	assert_gt(path.size(), 2)
	assert_lt((t1 - t0) * 1e-3, 10.0, "clearance build should be < 10 ms")
	assert_lt((t2 - t1) * 1e-3, 10.0, "A* should be < 10 ms")


func test_copy_is_independent() -> void:
	var g = OccupancyGridScr.new(Rect2(0, 0, 10, 10), 1.0)
	g.block_rect(Rect2(2, 2, 2, 2), 0.0)
	var h = g.copy()
	var p_probe := Vector2(6.5, 6.5)
	assert_true(g.is_free(p_probe) and h.is_free(p_probe))
	h.block_rect(Rect2(5, 5, 2, 2), 0.0)
	assert_true(g.is_free(p_probe), "mutating copy must not affect original")
	assert_false(h.is_free(p_probe), "copy should carry new block")
