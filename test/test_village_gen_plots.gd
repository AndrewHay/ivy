## Unit tests: VillagePlotSampler (v3 candidate plots + selection).
extends GutTest

const _PathNetwork = preload("res://src/world/village_gen/path_network.gd")
const _PlotSampler = preload("res://src/world/village_gen/plot_sampler.gd")
const _VValidate = preload("res://src/world/village_gen/village_validate.gd")


func _straight_horiz_network():
	var net = _PathNetwork.new()
	net.add_path(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(40.0, 0.0),
	]), "primary")
	return net


func test_rect_buffer_flags_segment_through_rect_mid() -> void:
	## Regression: corner-only distance misses a segment cutting through the rect interior.
	var strip := Rect2(Vector2(-0.5, -12.0), Vector2(1.0, 24.0))
	var path := PackedVector2Array([Vector2(-25.0, 0.0), Vector2(25.0, 0.0)])
	## All four corners are ≥10 m from the infinite horizontal line y=0, but the segment pierces the rect.
	var d: float = _PlotSampler.rect_poly_min_clearance(strip, path)
	assert_lt(d, 0.01, "segment through interior must give ~0 clearance")
	assert_true(_PlotSampler._rect_too_close_to_poly(strip, path, 0.52))


func test_candidates_centre_offset_and_door_faces_path() -> void:
	var net = _straight_horiz_network()
	var kit: Array = [{
		"name": "T0",
		"bays": 3,
		"door": "front:1",
		"yaw_deg": 0,
	}]
	var blocked := func(_p: Vector2) -> bool:
		return false
	var cands: Array = _PlotSampler.candidates(
		net, [0], kit, 4242,
		{"is_blocked": blocked, "obstacle_rects": [] as Array, "pond_center": Vector2(200.0, 200.0),
		"pond_clear_r": 1.0, "g": Vector2(0.0, -18.0), "max_corner_m": 120.0})
	assert_gt(cands.size(), 0)
	var first: Dictionary = cands[0]
	var rect: Rect2 = first["rect"] as Rect2
	var stoop: Vector2 = first["stoop"] as Vector2
	var endp: Vector2 = first["door_connection_end"] as Vector2
	var spec: Dictionary = first["spec"] as Dictionary
	var door_n: Vector2 = VillageBackdrop.cottage_door(spec)[1] as Vector2
	var toward: Vector2 = (endp - stoop).normalized()
	assert_gte(door_n.dot(toward), 0.7)
	assert_true(rect.get_center().y > 1.0 or rect.get_center().y < -1.0)


func test_candidate_rejects_pond_corner() -> void:
	var net = _straight_horiz_network()
	var kit: Array = [{"name": "TP", "bays": 2, "door": "front:0"}]
	var noop_block := func(_p: Vector2) -> bool:
		return false
	var c0: int = _PlotSampler.candidates(
		net, [0], kit, 100,
		{"is_blocked": noop_block, "obstacle_rects": [] as Array, "pond_center": Vector2(20.0, 5.0),
			"pond_clear_r": 30.0, "g": Vector2(0.0, -18.0), "max_corner_m": 200.0}).size()
	var blocked2 := func(_p: Vector2) -> bool:
		return false
	var c1: int = _PlotSampler.candidates(
		net, [0], kit, 100,
		{"is_blocked": blocked2, "obstacle_rects": [] as Array, "pond_center": Vector2(200.0, 0.0),
			"pond_clear_r": 0.01, "g": Vector2(0.0, -18.0), "max_corner_m": 200.0}).size()
	assert_gt(c1, c0)


func test_candidates_reject_exterior_corner_beyond_max_from_g() -> void:
	var net = _straight_horiz_network()
	var kit: Array = [{"name": "T", "bays": 3, "door": "front:1"}]
	var g := Vector2(0.0, -18.0)
	var blocked := func(_p: Vector2) -> bool:
		return false
	var cands: Array = _PlotSampler.candidates(
		net, [0], kit, 9001,
		{"is_blocked": blocked, "obstacle_rects": [] as Array, "pond_center": Vector2(200.0, 200.0),
		"pond_clear_r": 0.0, "g": g, "max_corner_m": 12.0, "junction_clear_m": 0.0})
	assert_eq(cands.size(), 0, "plots within 12 m corner cap from G should be rejected")


func test_select_rejects_tight_pair_cb_ce_like_specs() -> void:
	## Regression: greedy must not accept two cottages whose exterior rects are < 4 m apart (axis rule).
	var a: Dictionary = {"name": "CB", "centre": Vector2(22.52263, -10.5301), "bays": 3, "yaw_deg": 180, "door": "front:1"}
	var b: Dictionary = {"name": "CE", "centre": Vector2(23.74407, -6.339616), "bays": 3, "yaw_deg": 180, "door": "front:1"}
	var ra: Rect2 = VillageBackdrop.cottage_exterior_rect(a)
	var rb: Rect2 = VillageBackdrop.cottage_exterior_rect(b)
	assert_true(_VValidate.wall_gap_too_small(ra, rb, 4.0))
	var cands: Array = [
		{"spec": a, "template": "CB", "score": 10.0, "path_id": 1, "s": 0.0, "stoop": Vector2.ZERO, "door_connection_end": Vector2.ZERO},
		{"spec": b, "template": "CE", "score": 9.0, "path_id": 1, "s": 5.0, "stoop": Vector2.ZERO, "door_connection_end": Vector2.ZERO},
	]
	var picked: Array = _PlotSampler.select(cands, 2, 1, {"min_gap_wall_m": 4.0})
	assert_true(picked.size() <= 1)


func test_select_respects_min_gap_and_determinism() -> void:
	var net = _straight_horiz_network()
	var kit: Array = [
		{"name": "A", "bays": 3, "door": "front:1"},
		{"name": "B", "bays": 3, "door": "front:1"},
	]
	var blocked := func(_p: Vector2) -> bool:
		return false
	var cands: Array = _PlotSampler.candidates(
		net, [0], kit, 999,
		{"is_blocked": blocked, "obstacle_rects": [] as Array, "pond_center": Vector2(200.0, 200.0),
		"pond_clear_r": 0.0, "g": Vector2(0.0, -18.0), "max_corner_m": 120.0})
	## Two picks: greedy set stays separated under V1 edge-distance (wide templates + N>2 can fail).
	var a: Array = _PlotSampler.select(cands, 2, 555, {"min_gap_wall_m": 4.0})
	var b: Array = _PlotSampler.select(cands, 2, 555, {"min_gap_wall_m": 4.0})
	assert_eq(a.size(), b.size())
	for i: int in a.size():
		assert_eq(a[i]["template"], b[i]["template"])
	## pairwise gaps
	for i: int in a.size():
		for j: int in range(i + 1, a.size()):
			var ra: Rect2 = a[i]["rect"] as Rect2
			var rb: Rect2 = a[j]["rect"] as Rect2
			assert_false(_VValidate.wall_gap_too_small(ra, rb, 4.0))


func test_better_facing_wins_before_select() -> void:
	## Artificial kit templates: same geom, scoring difference from door slot only happens via yaw;
	## we compare two candidates with different score field on same path.
	var net = _straight_horiz_network()
	var kit: Array = [{"name": "X", "bays": 3, "door": "front:1"}]
	var blocked := func(_p: Vector2) -> bool:
		return false
	var cands: Array = _PlotSampler.candidates(
		net, [0], kit, 1,
		{"is_blocked": blocked, "obstacle_rects": [] as Array, "pond_center": Vector2(300.0, 300.0),
		"pond_clear_r": 0.0, "g": Vector2(0.0, -18.0), "max_corner_m": 200.0})
	assert_gt(cands.size(), 2)
	cands.sort_custom(func(x: Variant, y: Variant) -> bool:
		return (x as Dictionary).get("score", -INF) > (y as Dictionary).get("score", -INF))
	assert_gt(cands[0]["score"], cands[cands.size() - 1]["score"])


func test_plot_debug_png_written() -> void:
	## Optional sanity: draw paths + top candidate rects (headless Image).
	var net = _PathNetwork.new()
	var curved := PackedVector2Array()
	for i: int in 21:
		var t: float = float(i) / 20.0
		curved.append(Vector2(t * 30.0, sin(t * PI * 1.5) * 4.0))
	net.add_path(curved, "primary")
	var kit: Array = [{"name": "D", "bays": 3, "door": "front:1"}]
	var blocked := func(_p: Vector2) -> bool:
		return false
	var cands: Array = _PlotSampler.candidates(
		net, [0], kit, 77,
		{"is_blocked": blocked, "obstacle_rects": [] as Array, "pond_center": Vector2(500.0, 500.0),
		"pond_clear_r": 0.0, "g": Vector2(0.0, -18.0), "max_corner_m": 200.0})
	cands.sort_custom(func(x: Variant, y: Variant) -> bool:
		return (x as Dictionary).get("score", -INF) > (y as Dictionary).get("score", -INF))
	var top: Array = cands.slice(0, mini(30, cands.size()))
	var sel: Array = _PlotSampler.select(cands, mini(8, cands.size()), 123, {})

	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.14, 0.18, 1.0))
	var xf: float = 14.0
	var yf: float = 14.0
	var offs := Vector2(30.0, 220.0)

	for c: Dictionary in top:
		var r: Rect2 = c["rect"] as Rect2
		_draw_rect_px(img, r, xf, yf, offs, Color(0.2, 0.65, 0.35, 0.5))
	for c2: Dictionary in sel:
		var r2: Rect2 = c2["rect"] as Rect2
		_draw_rect_px(img, r2, xf, yf, offs, Color(0.95, 0.55, 0.15, 0.85))
		var st: Vector2 = c2["stoop"] as Vector2
		var en: Vector2 = c2["door_connection_end"] as Vector2
		var spt := Vector2(st.x * xf + offs.x, st.y * yf + offs.y)
		var ept := Vector2(en.x * xf + offs.x, en.y * yf + offs.y)
		_draw_line_px(img, spt, ept, Color(0.95, 0.85, 0.2, 1.0))

	var path_str := "/Users/andrewhay/github/ivy/.tmp/village-gen-v3/s2/plots_debug.png"
	img.save_png(path_str)
	assert_true(FileAccess.file_exists(path_str))


static func _draw_rect_px(img: Image, r: Rect2, xs: float, ys: float, o: Vector2, col: Color) -> void:
	var p0 := Vector2(r.position.x * xs + o.x, r.position.y * ys + o.y)
	var p1 := Vector2((r.position.x + r.size.x) * xs + o.x, r.position.y * ys + o.y)
	var p2 := Vector2((r.position.x + r.size.x) * xs + o.x, (r.position.y + r.size.y) * ys + o.y)
	var p3 := Vector2(r.position.x * xs + o.x, (r.position.y + r.size.y) * ys + o.y)
	_draw_line_px(img, p0, p1, col)
	_draw_line_px(img, p1, p2, col)
	_draw_line_px(img, p2, p3, col)
	_draw_line_px(img, p3, p0, col)


static func _draw_line_px(img: Image, pa: Vector2, pb: Vector2, col: Color) -> void:
	var steps: int = int(pa.distance_to(pb)) + 1
	for s: int in steps:
		var t: float = float(s) / float(maxi(1, steps - 1))
		var p: Vector2 = pa.lerp(pb, t)
		var x: int = clampi(int(p.x), 0, img.get_width() - 1)
		var y: int = clampi(int(p.y), 0, img.get_height() - 1)
		img.set_pixel(x, y, col)

