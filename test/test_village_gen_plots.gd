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


# ── Terrain site rejection (ivy-82zn.14.16, SD-VILLAGE-TERRAIN-19, AR-LF-LAYOUT) ──

func _cand(name: String, x: float, score: float) -> Dictionary:
	var spec := {"name": name, "centre": Vector2(x, -20.0), "bays": 3, "yaw_deg": 0, "door": "front:1"}
	return {"spec": spec, "template": name, "score": score, "path_id": 1, "s": x,
		"stoop": Vector2(x, -15.0), "door_connection_end": Vector2(x, -15.0)}


func test_select_runs_terrain_site_fn_last_and_skips_rejected_sites() -> void:
	## c2 overlaps c1 (wall gap): rejected before the terrain fn; c3 is rejected by the terrain fn;
	## accepted picks carry the measured ring width on their spec.
	var calls: Array[String] = []
	var fn := func(cand: Dictionary, _picked: Array) -> Dictionary:
		calls.append(String(cand["template"]))
		if String(cand["template"]) == "C3":
			return {"ok": false, "reason": "ring", "s_deg": 3.0, "w": 9.0, "target": 0.0}
		return {"ok": true, "reason": "", "s_deg": 2.0, "w": 4.5, "target": 1.25}
	var cands: Array = [_cand("C1", 0.0, 10.0), _cand("C2", 0.5, 9.0), _cand("C3", 30.0, 8.0), _cand("C4", 60.0, 7.0)]
	var picked: Array = _PlotSampler.select(cands, 3, 1, {"min_gap_wall_m": 4.0, "max_corner_m": 0.0,
		"terrain_site_fn": fn})
	var names: Array[String] = []
	for e: Dictionary in picked:
		names.append(String(e["template"]))
	assert_eq(names, ["C1", "C4"] as Array[String], "terrain-rejected C3 skipped, next site taken")
	assert_eq(calls, ["C1", "C3", "C4"] as Array[String], "fn runs after the wall-gap check (never for C2)")
	assert_almost_eq(float((picked[0]["spec"] as Dictionary)["ring_w"]), 4.5, 1e-6, "spec.ring_w stored")
	assert_almost_eq(float((picked[0]["_pad"] as Dictionary)["target"]), 1.25, 1e-6, "pad target kept for replay")


func test_select_with_null_terrain_fn_is_unchanged() -> void:
	var cands: Array = [_cand("C1", 0.0, 10.0), _cand("C2", 0.5, 9.0), _cand("C3", 30.0, 8.0)]
	var a: Array = _PlotSampler.select(cands, 3, 1, {"min_gap_wall_m": 4.0, "max_corner_m": 0.0})
	var b: Array = _PlotSampler.select(cands, 3, 1, {"min_gap_wall_m": 4.0, "max_corner_m": 0.0,
		"terrain_site_fn": null})
	assert_eq(a.size(), b.size(), "same count")
	for i in range(a.size()):
		assert_eq(a[i]["template"], b[i]["template"], "same pick %d" % i)
		assert_false((b[i]["spec"] as Dictionary).has("ring_w"), "flat variant writes no ring_w")


func test_append_to_selection_applies_the_terrain_fn() -> void:
	var fn := func(cand: Dictionary, picked: Array) -> Dictionary:
		assert_eq(picked.size(), 1, "the existing pick is passed for neighbour replay")
		return {"ok": String(cand["template"]) != "C3", "reason": "slope", "s_deg": 11.0, "w": 3.0, "target": 0.0}
	var existing: Array = _PlotSampler.select([_cand("C1", 0.0, 10.0)], 1, 1, {"max_corner_m": 0.0})
	var out: Array = _PlotSampler.append_to_selection([_cand("C3", 30.0, 8.0), _cand("C4", 60.0, 7.0)],
		existing, 2, 1, {"max_corner_m": 0.0, "terrain_site_fn": fn})
	assert_eq(out.size(), 2, "one appended")
	assert_eq(String(out[1]["template"]), "C4", "C3 rejected by terrain")


# ── Centre spacing and reach (ivy-82zn.14.18, SD-VILLAGE-TERRAIN-21, AR-LF-LAYOUT WP3) ──

func _cand_at(name: String, c: Vector2, score: float) -> Dictionary:
	var spec := {"name": name, "centre": c, "bays": 3, "yaw_deg": 0, "door": "front:1"}
	return {"spec": spec, "template": name, "score": score, "path_id": 1, "s": c.x,
		"stoop": c + Vector2(0.0, 5.0), "door_connection_end": c + Vector2(0.0, 5.0)}


func _names(picked: Array) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in picked:
		out.append(String(e["template"]))
	return out


func test_select_rejects_centre_pairs_closer_than_min_centre_sep() -> void:
	## C2 is 15 m from C1: wall gap (~11 m) passes the 4 m floor but the 22 m centre rule rejects it;
	## C3 at 22.5 m is kept.
	var g := Vector2(0.0, -18.0)
	var cands: Array = [_cand_at("C1", g + Vector2(0.0, -20.0), 10.0),
		_cand_at("C2", g + Vector2(15.0, -20.0), 9.0), _cand_at("C3", g + Vector2(-22.5, -20.0), 8.0)]
	var p := {"min_gap_wall_m": 4.0, "max_corner_m": 0.0, "hamlet_g": g, "min_centre_sep_m": 22.0}
	assert_eq(_names(_PlotSampler.select(cands, 3, 1, p)), ["C1", "C3"] as Array[String], "C2 under 22 m skipped")
	p.erase("min_centre_sep_m")
	assert_eq(_PlotSampler.select(cands, 3, 1, p).size(), 3, "no min_centre_sep_m key: unchanged (wall gap only)")


func test_select_rejects_centres_beyond_centre_r_max() -> void:
	var g := Vector2(0.0, -18.0)
	var cands: Array = [_cand_at("NEAR", g + Vector2(0.0, -45.9), 10.0), _cand_at("FAR", g + Vector2(46.2, 0.0), 9.0)]
	var p := {"min_gap_wall_m": 4.0, "max_corner_m": 0.0, "hamlet_g": g, "centre_r_max_m": 46.0}
	assert_eq(_names(_PlotSampler.select(cands, 2, 1, p)), ["NEAR"] as Array[String], "centre r 46.2 > 46 skipped")


func test_append_to_selection_applies_centre_sep_and_reach() -> void:
	var g := Vector2(0.0, -18.0)
	var p := {"min_gap_wall_m": 4.0, "max_corner_m": 0.0, "hamlet_g": g,
		"min_centre_sep_m": 22.0, "centre_r_max_m": 46.0}
	var existing: Array = _PlotSampler.select([_cand_at("C1", g + Vector2(0.0, -20.0), 10.0)], 1, 1, p)
	var more: Array = [_cand_at("CLOSE", g + Vector2(18.0, -20.0), 9.0),
		_cand_at("OUT", g + Vector2(0.0, 47.0), 8.5), _cand_at("OK", g + Vector2(0.0, 20.0), 8.0)]
	var out: Array = _PlotSampler.append_to_selection(more, existing, 3, 1, p)
	assert_eq(_names(out), ["C1", "OK"] as Array[String], "too close and too far both skipped")


func test_centre_sep_runs_before_the_terrain_fn() -> void:
	## The terrain fn is the costly check; spacing / reach rejections must never reach it.
	var g := Vector2(0.0, -18.0)
	var calls: Array[String] = []
	var fn := func(cand: Dictionary, _picked: Array) -> Dictionary:
		calls.append(String(cand["template"]))
		return {"ok": true, "reason": "", "s_deg": 1.0, "w": 3.0, "target": 0.0}
	var cands: Array = [_cand_at("C1", g + Vector2(0.0, -20.0), 10.0),
		_cand_at("C2", g + Vector2(10.0, -20.0), 9.0), _cand_at("FAR", g + Vector2(0.0, 50.0), 8.0)]
	_PlotSampler.select(cands, 3, 1, {"min_gap_wall_m": 4.0, "max_corner_m": 0.0, "hamlet_g": g,
		"min_centre_sep_m": 22.0, "centre_r_max_m": 46.0, "terrain_site_fn": fn})
	assert_eq(calls, ["C1"] as Array[String], "terrain fn only for the accepted candidate")


func _site(u_fn: Callable, hero := {}) -> VillageSiteTerrain:
	return VillageSiteTerrain.from_fn(u_fn, VillageTerrainParams.production(), hero)


func test_site_terrain_rejects_a_steep_site() -> void:
	var k := tan(deg_to_rad(12.0))
	var st := _site(func(xz: Vector2) -> float: return k * xz.x)
	var r := st.evaluate(_cand("S", 0.0, 1.0), [])
	assert_false(bool(r["ok"]), "12° site rejected")
	assert_eq(String(r["reason"]), "slope", "reason slope")
	assert_almost_eq(float(r["s_deg"]), 12.0, 0.2, "plane slope measured")
	assert_eq(int(st.stats["rejected_slope"]), 1, "counted")


func test_site_terrain_rejects_a_level_core_whose_ring_peaks_over_22() -> void:
	## SD-22 WP2 test: the core is level (site slope passes) but the land outside rises at 42°, so no
	## ring ≤ 9 m meets 22°.
	var c := _cand("S", 0.0, 1.0)
	var core := VillageBackdrop.cottage_exterior_rect(c["spec"]).grow(VillageTerrainParams.production().pad_margin_m)
	var st := _site(func(xz: Vector2) -> float:
		return 0.9 * maxf(0.0, VillageTerrain.rect_sdf(xz, core) - 1.0))
	var r := st.evaluate(c, [])
	assert_lte(float(r["s_deg"]), 1.0, "core is level")
	assert_false(bool(r["ok"]), "ring fails")
	assert_eq(String(r["reason"]), "ring", "reason ring")
	assert_eq(int(st.stats["rejected_ring"]), 1, "counted")


func test_site_terrain_accepts_a_gentle_site_with_a_measured_ring() -> void:
	var k := tan(deg_to_rad(5.0))
	var st := _site(func(xz: Vector2) -> float: return k * xz.x + 2.0)
	var c := _cand("S", 0.0, 1.0)
	var r := st.evaluate(c, [])
	var p := VillageTerrainParams.production()
	assert_true(bool(r["ok"]), "5° site accepted")
	assert_between(float(r["w"]), p.pad_ring_min_m, p.pad_ring_max_m, "w in the pad clamp")
	assert_almost_eq(float(r["target"]), 2.0 + k * (c["spec"]["centre"] as Vector2).x, 0.05, "target = core mean")
	assert_lte(float(r["peak_deg"]), p.ring_max_slope_deg, "peak at w*")


func test_site_terrain_replays_selected_neighbours() -> void:
	## A selected pad 3 m higher, 2 m away: the candidate's ring cannot meet even 25° once the
	## neighbour is replayed; alone it is flat and passes.
	var st := _site(func(_xz: Vector2) -> float: return 0.0)
	var c := _cand("S", 0.0, 1.0)
	var alone := st.evaluate(c, [])
	assert_true(bool(alone["ok"]), "isolated flat site passes")
	var core := VillageBackdrop.cottage_exterior_rect(c["spec"]).grow(VillageTerrainParams.production().pad_margin_m)
	var n_rect := Rect2(core.end + Vector2(2.0, -core.size.y), core.size)
	var nb := {"_pad": {"rect": n_rect, "target": 3.0, "w": 3.0}}
	var with_nb := st.evaluate(c.duplicate(true), [nb])
	assert_false(bool(with_nb["ok"]), "rejected with the neighbour replayed")
	assert_eq(String(with_nb["reason"]), "ring", "reason ring")


func test_site_terrain_replays_the_plaza_before_pads() -> void:
	## SD-19 step 2 (restated): the plaza plane is replayed under the candidate. A plaza 3 m higher,
	## 2 m away, makes the flat candidate's ring fail.
	var p := VillageTerrainParams.production()
	var st := _site(func(_xz: Vector2) -> float: return 0.0)
	var c := _cand("S", 0.0, 1.0)
	var core := st.pad_core(c["spec"])
	var rect := Rect2(core.end + Vector2(2.0, -core.size.y), Vector2(18.0, 18.0))
	st.plaza = {"kind": "plaza", "rect": rect, "a": 0.0, "b": 0.0, "c": 3.0, "w": 5.0,
		"bound_c": rect.get_center(), "bound_r": rect.size.length() * 0.5 + 5.0}
	var r := st.evaluate(c, [])
	assert_false(bool(r["ok"]), "plaza replayed: ring fails")
	assert_eq(String(r["reason"]), "ring", "reason ring")
	assert_eq(p.ring_max_slope_deg, 22.0, "production ring max")


func test_site_terrain_replays_the_pond_and_keys_the_memo_on_it() -> void:
	## The pond basin (deepened here) is replayed under the candidate; moving the pond away gives a
	## fresh evaluation (memo key includes the pond centre).
	var p := VillageTerrainParams.production()
	p.pond_depth_m = -3.0
	var st := VillageSiteTerrain.from_fn(func(_xz: Vector2) -> float: return 0.0, p, {})
	var c := _cand("S", 0.0, 1.0)
	var core := st.pad_core(c["spec"])
	st.set_pond(Vector2(core.end.x + 1.0 + VillagePondSite.BANK_OUTER_M, core.get_center().y))
	var near := st.evaluate(c, [])
	assert_false(bool(near["ok"]), "deep pond basin next to the pad: ring fails")
	st.set_pond(Vector2(500.0, 500.0))
	var far := st.evaluate(c, [])
	assert_true(bool(far["ok"]), "pond moved away: re-evaluated and passes")


## SD-VILLAGE-TERRAIN-28 §3 (seed 13 geometry): a plaza on a slope and a pond whose blend overlaps the
## plaza ring just off its SW corner. The plaza plane is tilt-capped (6°) and the pond basin is cut in,
## so the overlap nodes read steeper than the 22° ring limit.
func _pond_plaza_site(k_deg: float) -> VillageSiteTerrain:
	var p := VillageTerrainParams.production()
	var k := tan(deg_to_rad(k_deg))
	var fn := func(xz: Vector2) -> float: return -k * xz.x
	var st := VillageSiteTerrain.from_fn(fn, p, {})
	var rect := VillageLayout.plaza_rect_at(VillageLayout.VILLAGE_GREEN_G, VillageLayout.PLAZA_SIDE_L)
	st.plaza = VillageTerrainField.plaza_site(fn, rect, p, p.plaza_ring_m)
	return st


func test_pond_plaza_ring_ok_rejects_a_pond_off_the_plaza_corner() -> void:
	var st := _pond_plaza_site(16.0)
	var rect: Rect2 = st.plaza["rect"]
	## Pond core edge 2.5 m into the plaza ring off the SW corner (x min, z max).
	var r_c: float = VillagePondSite.MEAN_WATER_RADIUS_M * float(st.params.pond_floor_scale)
	var corner := Vector2(rect.position.x, rect.end.y)
	var c: Vector2 = corner + Vector2(-1.0, 1.0).normalized() * (2.5 + r_c)
	var r: Dictionary = st.pond_plaza_ring_ok(c)
	gut.p("pond off the SW corner: ok %s peak %.1f° over %d nodes" % [r["ok"], r["peak_deg"], r["nodes"]])
	assert_gt(int(r["nodes"]), 0, "the overlap is measured")
	assert_false(bool(r["ok"]), "pond blend over the plaza ring is rejected (> 22°)")
	assert_gt(float(r["peak_deg"]), st.params.ring_max_slope_deg, "peak recorded")


func test_pond_plaza_ring_ok_passes_without_overlap() -> void:
	var st := _pond_plaza_site(16.0)
	var r: Dictionary = st.pond_plaza_ring_ok(Vector2(60.0, 40.0))
	assert_true(bool(r["ok"]), "no overlap: pass")
	assert_eq(int(r["nodes"]), 0, "nothing measured")
	var flat := _pond_plaza_site(0.0)
	var rect: Rect2 = flat.plaza["rect"]
	var r_c: float = VillagePondSite.MEAN_WATER_RADIUS_M * float(flat.params.pond_floor_scale)
	var c: Vector2 = Vector2(rect.position.x, rect.end.y) + Vector2(-1.0, 1.0).normalized() * (2.5 + r_c)
	var r2: Dictionary = flat.pond_plaza_ring_ok(c)
	assert_gt(int(r2["nodes"]), 0, "overlap measured on flat ground")
	assert_true(bool(r2["ok"]), "flat ground: the shallow basin stays under 22° (%.1f°)" % r2["peak_deg"])


func test_pond_hero_ring_ok_rejects_a_pond_in_the_hero_ring() -> void:
	## Extension of SD-28 §3 to the hero ring (handoff 3; seed 7 repro: resolve_after_paths moved the
	## pond into the hero ring, field 27.5°). Field order plaza < pond < hero; the hero ring nodes the
	## pond blend reaches must stay <= 22°.
	var p := VillageTerrainParams.production()
	var k := tan(deg_to_rad(16.0))
	var fn := func(xz: Vector2) -> float: return -k * xz.x
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var st := VillageSiteTerrain.from_fn(fn, p, {"centre": h0, "r_c": p.hero_flat_r_m, "target": 0.0, "w": 9.5})
	var r_c: float = VillagePondSite.MEAN_WATER_RADIUS_M * p.pond_floor_scale
	var near: Dictionary = st.pond_hero_ring_ok(h0 + Vector2(-(p.hero_flat_r_m + 2.0 + r_c), 0.0))
	gut.p("pond in the hero ring: ok %s peak %.1f° over %d nodes" % [near["ok"], near["peak_deg"], near["nodes"]])
	assert_gt(int(near["nodes"]), 0, "overlap measured")
	assert_false(bool(near["ok"]), "rejected")
	var far: Dictionary = st.pond_hero_ring_ok(h0 + Vector2(0.0, -60.0))
	assert_true(bool(far["ok"]), "no overlap: pass")
	assert_eq(int(far["nodes"]), 0, "nothing measured")


func test_site_terrain_memoises_per_candidate() -> void:
	var calls := [0]
	var st := _site(func(xz: Vector2) -> float:
		calls[0] += 1
		return 0.02 * xz.x)
	var c := _cand("S", 0.0, 1.0)
	var a := st.evaluate(c, [])
	var n0: int = calls[0]
	var b := st.evaluate(c, [])
	assert_eq(calls[0], n0, "second evaluation of the same candidate samples nothing")
	assert_eq(a, b, "same result")
	assert_eq(int(st.stats["evaluated"]), 1, "evaluated once")


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

	# Project-relative so the test works in any checkout / worktree and on Linux.
	var path_str := ProjectSettings.globalize_path("res://.tmp/village-gen-v3/s2/plots_debug.png")
	DirAccess.make_dir_recursive_absolute(path_str.get_base_dir())
	assert_eq(img.save_png(path_str), OK, "save_png must succeed: %s" % path_str)
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

