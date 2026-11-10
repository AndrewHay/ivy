extends GutTest

const WandererBrain = preload("res://src/presentation/wanderer/wanderer_brain.gd")
const WandererRouteGraph = preload("res://src/presentation/wanderer/wanderer_route_graph.gd")
const WandererContent = preload("res://src/presentation/wanderer/wanderer_content.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")

const _DT := 1.0 / 30.0


func _synthetic_graph() -> WandererRouteGraph:
	var houses: Array[Dictionary] = [
		{"name": "A", "door": Vector2(-10, 0), "normal": Vector2(1, 0)},
		{"name": "B", "door": Vector2(10, 0), "normal": Vector2(-1, 0)},
	]
	var paths: Array = [
		[Vector2(-12, 0), Vector2(-9.5, 0), Vector2(0, 0), Vector2(9.5, 0), Vector2(12, 0)],
	]
	var g := WandererRouteGraph.from_raw(houses, paths, WandererParams.production())
	assert_false(g.is_disabled(), "synthetic graph must have both houses reachable")
	return g


func _content_full() -> WandererContent:
	return WandererContent.from_arrays(
		PackedStringArray(["short", "a longer stroll quote"]),
		PackedFloat32Array([1.333, 0.75]),
	)


func _brain(seed: int = 99, speed: float = 1.0) -> WandererBrain:
	var p := WandererParams.production()
	p.walk_speed_mps = speed
	var b := WandererBrain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	b.setup(p, _synthetic_graph(), _content_full(), rng)
	b.start()
	return b


func _advance_to_state(b: WandererBrain, want: int, max_s: float = 120.0) -> bool:
	var t := 0.0
	while t < max_s:
		if b.state == want:
			return true
		b.tick(_DT)
		t += _DT
	return b.state == want


func _duration_in_current_state(b: WandererBrain, state: int, dt: float = _DT) -> float:
	assert_eq(b.state, state)
	var t := 0.0
	while b.state == state and t < 60.0:
		b.tick(dt)
		t += dt
	assert_ne(b.state, state)
	return t


func _yaw_probe_pi() -> WandererBrain:
	var p := WandererParams.production()
	var houses: Array[Dictionary] = [
		{"name": "A", "door": Vector2(-2, 0), "normal": Vector2(1, 0)},
		{"name": "B", "door": Vector2(2, 0), "normal": Vector2(0.0, 1.0)},
	]
	var paths: Array = [[Vector2(-2, 0), Vector2(2, 0)]]
	var g := WandererRouteGraph.from_raw(houses, paths, p)
	var b := WandererBrain.new()
	b.setup(p, g, WandererContent.new(), RandomNumberGenerator.new())
	b.target_house = 1
	b.yaw = 0.0
	b.state = WandererBrain.State.DOOR_PAUSE
	b.state_t = 0.0
	return b


func test_disabled_when_single_house() -> void:
	var p := WandererParams.production()
	var houses: Array[Dictionary] = [
		{"name": "A", "door": Vector2(5, 0), "normal": Vector2(0, 1)},
	]
	var paths: Array = [[Vector2(0, 0), Vector2(10, 0)]]
	var g := WandererRouteGraph.from_raw(houses, paths, p)
	var b := WandererBrain.new()
	b.setup(p, g, WandererContent.new(), RandomNumberGenerator.new())
	b.start()
	assert_eq(b.state, WandererBrain.State.DISABLED)


func test_timeline_dt_invariance() -> void:
	var b1 := _brain()
	var b2 := _brain()
	var events1: Array = []
	var events2: Array = []
	var t1 := 0.0
	while t1 < 25.0:
		b1.tick(1.0 / 30.0)
		t1 += 1.0 / 30.0
		for e in b1.drain_events():
			if e.get("type") == "state":
				events1.append(e)
	var t2 := 0.0
	while t2 < 25.0:
		b2.tick(1.0)
		t2 += 1.0
		for e in b2.drain_events():
			if e.get("type") == "state":
				events2.append(e)
	assert_eq(events1.size(), events2.size())


func test_door_inside_exit_showing_durations() -> void:
	var prod := WandererParams.production()
	var b := _brain(7, 6.0)
	assert_true(_advance_to_state(b, WandererBrain.State.DOOR_PAUSE, 30.0))
	var door_t := _duration_in_current_state(b, WandererBrain.State.DOOR_PAUSE)
	assert_almost_eq(door_t, prod.door_pause_s, _DT + 1e-4)
	var inside_t := _duration_in_current_state(b, WandererBrain.State.INSIDE)
	assert_almost_eq(inside_t, prod.inside_s, _DT + 1e-4)
	var exit_t := _duration_in_current_state(b, WandererBrain.State.EXIT_PAUSE)
	assert_almost_eq(exit_t, prod.exit_pause_s, _DT + 1e-4)
	_duration_in_current_state(b, WandererBrain.State.EXIT_WALK)
	_duration_in_current_state(b, WandererBrain.State.SAYING)
	var show_t := _duration_in_current_state(b, WandererBrain.State.SHOWING)
	assert_almost_eq(show_t, prod.image_s, _DT + 1e-4)


func test_saying_duration_matches_bubble_formula() -> void:
	var b := _brain(11, 6.0)
	assert_true(_advance_to_state(b, WandererBrain.State.SAYING, 40.0))
	var expected := WandererParams.production().bubble_duration(b.bubble_text)
	var saying_t := _duration_in_current_state(b, WandererBrain.State.SAYING)
	assert_almost_eq(saying_t, expected, _DT + 1e-4)


func test_quote_after_twenty_walking_seconds_only() -> void:
	var b := _brain(42, 1.0)
	var dt := _DT
	var walked := 0.0
	var quoted := false
	var elapsed := 0.0
	while walked < 80.0 and elapsed < 300.0:
		elapsed += dt
		var st := b.state
		b.tick(dt)
		if st == WandererBrain.State.WALKING:
			walked += dt
		for e in b.drain_events():
			if e.get("type") == "bubble" and e.get("kind") == "quote":
				quoted = true
				var prod := WandererParams.production()
				assert_gte(walked, prod.quote_interval_s - dt * 2.0)
				assert_gte(walked, prod.quote_min_walk_s)
		if quoted:
			break
		if b.state == WandererBrain.State.INSIDE:
			var clock := b.quote_clock
			for _j in 30:
				b.tick(dt)
				assert_eq(b.quote_clock, clock)
	assert_true(quoted, "quote should fire after 20s walking")


func test_skip_saying_without_quotes() -> void:
	var p := WandererParams.production()
	var c := WandererContent.from_arrays(PackedStringArray(), PackedFloat32Array([1.0]))
	var b := WandererBrain.new()
	b.setup(p, _synthetic_graph(), c, RandomNumberGenerator.new())
	b.start()
	assert_true(_advance_to_state(b, WandererBrain.State.EXIT_PAUSE, 60.0))
	_duration_in_current_state(b, WandererBrain.State.EXIT_PAUSE)
	_duration_in_current_state(b, WandererBrain.State.EXIT_WALK)
	assert_eq(b.state, WandererBrain.State.SHOWING)


func test_exit_walk_state_enum() -> void:
	assert_eq(WandererBrain.State.EXIT_WALK, 7)
	assert_eq(WandererBrain.state_name(7), "EXIT_WALK")


func test_skip_showing_without_images() -> void:
	var p := WandererParams.production()
	var c := WandererContent.from_arrays(PackedStringArray(["only words"]), PackedFloat32Array())
	var b := WandererBrain.new()
	b.setup(p, _synthetic_graph(), c, RandomNumberGenerator.new())
	b.start()
	assert_true(_advance_to_state(b, WandererBrain.State.SAYING, 60.0))
	_duration_in_current_state(b, WandererBrain.State.SAYING)
	assert_eq(b.state, WandererBrain.State.WALKING)


func test_figure_hidden_only_inside() -> void:
	var b := _brain(5, 5.0)
	var seen_inside := false
	var t := 0.0
	while t < 50.0:
		if b.state == WandererBrain.State.INSIDE:
			seen_inside = true
			assert_false(b.figure_visible)
		elif b.state != WandererBrain.State.DISABLED:
			assert_true(b.figure_visible)
		b.tick(_DT)
		t += _DT
	assert_true(seen_inside)


func test_target_never_equals_last_house() -> void:
	var b := _brain(88, 4.0)
	for _i in 200:
		var tgt := b.target_house
		var last := b.last_house
		if last >= 0 and tgt >= 0:
			assert_ne(tgt, last)
		b.tick(_DT)
		if b.state == WandererBrain.State.DISABLED:
			break


func test_twelve_cycle_soak() -> void:
	var b := _brain(12001, 1.2)
	var t := 0.0
	while b.cycles_completed < 12 and t < 900.0:
		b.tick(1.0)
		t += 1.0
	assert_eq(b.cycles_completed, 12)


func test_yaw_180_turn_rate_at_sixty_fps() -> void:
	var b := _yaw_probe_pi()
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < 2.0 and absf(wrapf(PI - b.yaw, -PI, PI)) > 0.03:
		b.tick(dt)
		t += dt
	var expected := PI / deg_to_rad(WandererParams.production().turn_rate_deg_s)
	assert_almost_eq(t, expected, dt + 0.02)


func test_yaw_frame_rate_independent() -> void:
	var _run := func(dt: float, steps: int) -> float:
		var b := _yaw_probe_pi()
		for _i in steps:
			b.tick(dt)
		return b.yaw
	var y_a: float = _run.call(1.0 / 30.0, 20)
	var y_b: float = _run.call(1.0 / 120.0, 80)
	assert_almost_eq(y_a, y_b, 0.025)


func test_paused_dt_zero_freezes() -> void:
	var b := _brain()
	var p0 := b.pos
	b.tick(0.0)
	b.tick(0.0)
	assert_eq(b.pos, p0)


func test_exit_walk_travels_2_2_m_along_normal() -> void:
	var b := _brain(3, 1.0)
	assert_true(_advance_to_state(b, WandererBrain.State.EXIT_WALK, 60.0))
	var p0 := b.pos
	var n: Vector2 = _synthetic_graph().houses[b.last_house]["normal"]
	var t := 0.0
	while b.state == WandererBrain.State.EXIT_WALK and t < 10.0:
		b.tick(_DT)
		t += _DT
	var along := (b.pos - p0).dot(n)
	assert_almost_eq(along, 2.2, 0.08)
	assert_almost_eq(b.yaw, atan2(n.x, n.y), 0.15)


func test_quote_clock_frozen_during_exit_walk() -> void:
	var b := _brain(5, 1.0)
	assert_true(_advance_to_state(b, WandererBrain.State.EXIT_WALK, 60.0))
	var clk := b.quote_clock
	var t := 0.0
	while b.state == WandererBrain.State.EXIT_WALK and t < 8.0:
		b.tick(_DT)
		t += _DT
		assert_eq(b.quote_clock, clk)


func test_no_exit_walk_without_images() -> void:
	var p := WandererParams.production()
	var c := WandererContent.from_arrays(PackedStringArray(["words"]), PackedFloat32Array())
	var b := WandererBrain.new()
	b.setup(p, _synthetic_graph(), c, RandomNumberGenerator.new())
	b.start()
	var t := 0.0
	while t < 80.0:
		if b.state == WandererBrain.State.EXIT_WALK:
			assert_true(false, "EXIT_WALK must not run without images")
		b.tick(_DT)
		t += _DT


func test_present_pos_and_showing_placement() -> void:
	var b := _brain(9, 2.0)
	assert_true(_advance_to_state(b, WandererBrain.State.SHOWING, 90.0))
	var n: Vector2 = _synthetic_graph().houses[b.last_house]["normal"]
	var door: Vector2 = _synthetic_graph().houses[b.last_house]["door_exterior"]
	var expect := door + n * WandererParams.production().present_standoff()
	assert_almost_eq(b.present_pos.x, expect.x, 1e-3)
	assert_almost_eq(b.present_pos.y, expect.y, 1e-3)
	var P: Vector2 = b.image_placement["figure_xz"]
	assert_almost_eq(b.pos.x, P.x, 1e-3)
	assert_almost_eq(b.pos.y, P.y, 1e-3)


func test_next_leg_starts_at_present_pos() -> void:
	var b := _brain(8, 3.0)
	assert_true(_advance_to_state(b, WandererBrain.State.SHOWING, 90.0))
	_duration_in_current_state(b, WandererBrain.State.SHOWING)
	assert_eq(b._route[0], b.present_pos)


func test_turn_gate_holds_until_aligned() -> void:
	var p := WandererParams.production()
	var n := Vector2(0, 1)
	var houses: Array[Dictionary] = [
		{"name": "A", "door": Vector2(0, 0), "normal": n, "door_exterior": Vector2(0, 0), "stoop": Vector2(0, 0.5), "door_spot": Vector2(0, 0.3)},
		{"name": "B", "door": Vector2(8, 0), "normal": Vector2(-1, 0), "door_exterior": Vector2(8, 0), "stoop": Vector2(7.5, 0), "door_spot": Vector2(7.7, 0)},
	]
	var paths: Array = [[Vector2(0, 2.5), Vector2(0, 5), Vector2(8, 5), Vector2(8, 0.3)]]
	var g := WandererRouteGraph.from_raw(houses, paths, p)
	var b := WandererBrain.new()
	b.setup(p, g, _content_full(), RandomNumberGenerator.new())
	b.last_house = 0
	b.present_pos = Vector2(0, 2.5)
	b.target_house = 1
	b._route = WandererRouteGraph.leg_from_present(g.route(0, 1), b.present_pos, houses[0]["stoop"])
	b._build_route_cum()
	b.route_progress_m = 0.0
	b._leg_gate_open = false
	b._stepped_out = true
	b.yaw = PI
	b.state = WandererBrain.State.WALKING
	b.figure_visible = true
	var p0 := b.pos
	var t := 0.0
	while t < 1.5 and not b._leg_gate_open:
		b.tick(_DT)
		t += _DT
		assert_almost_eq(b.pos.x, p0.x, 0.05)
		assert_almost_eq(b.pos.y, p0.y, 0.05)


func test_soak_event_queue_bounded() -> void:
	var b := _brain(12002, 1.2)
	var t := 0.0
	var max_ev := 0
	while b.cycles_completed < 12 and t < 900.0:
		b.tick(1.0)
		t += 1.0
		b.drain_events()
		max_ev = maxi(max_ev, b._events.size())
	assert_lte(max_ev, 8)


func _brain_images_only(n: int, seed: int) -> WandererBrain:
	var asp := PackedFloat32Array()
	for i in n:
		asp.append(1.333)
	var c := WandererContent.from_arrays(PackedStringArray(), asp)
	var b := WandererBrain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	b.setup(WandererParams.production(), _synthetic_graph(), c, rng)
	return b


func _collect_image_idxs(b: WandererBrain, count: int) -> Array:
	var out: Array = []
	var guard := 0
	while out.size() < count and guard < count + 8:
		guard += 1
		out.append(b._next_image_idx())
	return out


func test_shuffle_bag_exactly_once_per_pass_n5() -> void:
	var b := _brain_images_only(5, 12345)
	for _pass_i in 4:
		var seen := {}
		var seq := _collect_image_idxs(b, 5)
		assert_eq(seq.size(), 5)
		for idx in seq:
			assert_gte(idx, 0)
			assert_lt(idx, 5)
			assert_false(seen.has(idx), "duplicate in pass")
			seen[idx] = true


func test_shuffle_bag_no_back_to_back_n5() -> void:
	var b := _brain_images_only(5, 777)
	var prev := -1
	var guard := 0
	while guard < 30:
		guard += 1
		var idx: int = b._next_image_idx()
		if prev >= 0:
			assert_ne(idx, prev)
		prev = idx


func test_shuffle_bag_no_back_to_back_n2() -> void:
	var b := _brain_images_only(2, 42)
	var prev := -1
	for _i in 20:
		var idx: int = b._next_image_idx()
		if prev >= 0:
			assert_ne(idx, prev)
		prev = idx


func test_shuffle_bag_deterministic_and_differs_by_seed() -> void:
	var a := _collect_image_idxs(_brain_images_only(5, 100), 10)
	var a2 := _collect_image_idxs(_brain_images_only(5, 100), 10)
	var b := _collect_image_idxs(_brain_images_only(5, 200), 10)
	assert_eq(a, a2)
	assert_ne(a, b)


func test_shuffle_bag_n1_always_zero() -> void:
	var b := _brain_images_only(1, 99)
	for _i in 8:
		assert_eq(b._next_image_idx(), 0)


func test_shuffle_bag_rebuild_on_setup() -> void:
	var b := _brain_images_only(3, 11)
	var first := _collect_image_idxs(b, 3)
	var c := WandererContent.from_arrays(PackedStringArray(), PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	b.setup(WandererParams.production(), _synthetic_graph(), c, rng)
	var after := _collect_image_idxs(b, 5)
	assert_eq(after.size(), 5)
	for idx in after:
		assert_lt(idx, 5)


func test_zero_length_tangent_opens_turn_gate() -> void:
	var p := WandererParams.production()
	var b := WandererBrain.new()
	b.setup(p, _synthetic_graph(), WandererContent.new(), RandomNumberGenerator.new())
	b._route = PackedVector2Array([Vector2(1, 1), Vector2(1, 1.0001)])
	b._build_route_cum()
	b.route_progress_m = 0.0
	b._leg_gate_open = false
	b.yaw = 0.0
	b.state = WandererBrain.State.WALKING
	var t := 0.0
	while t < 2.0 and not b._leg_gate_open:
		b.tick(_DT)
		t += _DT
	assert_true(b._leg_gate_open, "turn gate must open even on degenerate tangent")
