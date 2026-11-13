## Village generator v3: path-first orchestration (DESIGN §3 stages 1–8).
class_name VillageGeneratorV3
extends RefCounted

const _Layout := preload("res://src/world/village_layout.gd")
const _GridScr := preload("res://src/world/village_gen/occupancy_grid.gd")
const _Grower := preload("res://src/world/village_gen/path_grower.gd")
const _NetworkScr := preload("res://src/world/village_gen/path_network.gd")
const _Sampler := preload("res://src/world/village_gen/plot_sampler.gd")
const _Validate := preload("res://src/world/village_gen/village_validate.gd")
const _PondPlace := preload("res://src/world/village_pond_placement.gd")
const _PondSite := preload("res://src/world/village_pond_site.gd")
const _Scatter := preload("res://src/world/village_scatter_positions.gd")
const _Backdrop := preload("res://src/world/village_backdrop.gd")

const _WORLD_EXTENT_M := 60.0
const _RETRY_SALT := 0xE2B7A13D
const _MAIN_SALT := 0x7F4C9A01
const _PATH_SALT := 0x51EE6007
const _POND_SALT := 0x2D88B021
const _CAP_BRANCH_S_STEP := 2.0
## Stage 7: resample step (DESIGN meander spacing).
const _STAGE7_RESAMPLE_M := 0.3
## Pin vertices within this distance of a network junction (smoothing must not move them).
const _STAGE7_JUNCTION_PIN_M := 0.35
## Match plot sampler path_buffer_m — block + hard-reject growth near picked cottages.
const _PICKED_COTTAGE_PATH_BUF_M := 0.52

## Last diagnostics for probes / tests (per finished `generate()` call).
static var last_diag: Dictionary = {}
## Filled during stage 7 resample/smooth (V3 on try vs committed geometry).
static var last_stage7_debug: Dictionary = {}


static func generate(seed: int) -> VillageLayout:
	var norm: int = seed & 0x7FFFFFFF
	last_diag = {}
	var t_all := Time.get_ticks_usec()
	var attempts_log: Array = []
	for attempt: int in range(4):
		var t_att := Time.get_ticks_usec()
		var attempt_seed := _attempt_seed(norm, attempt)
		var rec := _attempt_generate(norm, attempt_seed, attempt)
		var att_ms := float(Time.get_ticks_usec() - t_att) / 1000.0
		attempts_log.append({
			"attempt": attempt,
			"ok": bool(rec.get("ok", false)),
			"fail_reason": str(rec.get("fail_reason", "")),
			"stage_reached": str(rec.get("stage_reached", "")),
			"ms": att_ms,
		})
		rec["attempts"] = attempts_log.duplicate(true)
		rec["attempts_used"] = attempt + 1
		rec["total_ms"] = float(Time.get_ticks_usec() - t_all) / 1000.0
		last_diag = rec
		if rec.get("ok", false):
			return rec["layout"] as VillageLayout
		if attempt >= 3:
			break
	push_warning("VillageGeneratorV3: falling back to authored() after failed attempts")
	var fb := _Layout.authored()
	fb.fallback = true
	fb.is_generated = false
	last_diag["fallback_layout"] = true
	last_diag["attempts"] = attempts_log
	last_diag["attempts_used"] = attempts_log.size()
	return fb


static func _attempt_seed(norm: int, attempt: int) -> int:
	## DESIGN + user note: retries must mix base seed with attempt index.
	return _Layout._derive(norm ^ (attempt * 0x9E3779B1), _RETRY_SALT + attempt * 131)


static func _attempt_generate(norm: int, st: int, attempt_idx: int) -> Dictionary:
	var diag := {
		"ok": false,
		"attempt": attempt_idx,
		"seed_base": norm,
		"seed_attempt": st,
		"stage_reached": "",
		"fail_reason": "",
		"stage_ms": {},
		"v_counts": {},
		"v_samples": {},
		"counts_per_kind": {},
		"candidates_n": 0,
		"picked_n": 0,
		"join_snap_splits_failed": 0,
		"capacity_grow_failures": 0,
	}
	var t_stage := Time.get_ticks_usec()

	var g: Vector2 = _Layout.VILLAGE_GREEN_G
	var plaza_side: float = _Layout.PLAZA_SIDE_L
	var plaza_rect: Rect2 = _Layout.plaza_rect_at(g, plaza_side)
	var keep_clear: Rect2 = _Layout.plaza_keep_clear_rect(g, plaza_side)
	var cottage_keep: Rect2 = _Layout.plaza_cottage_keep_clear_rect(g, plaza_side)
	var hero_rect := Rect2(-5.5, -5.0, 11.0, 8.5)
	diag["hero_rect"] = hero_rect

	st = _reserve_stage1(norm, st, g, plaza_rect, keep_clear, cottage_keep, diag)
	diag["stage_ms"]["1_reserve"] = _ms_since(t_stage)
	t_stage = Time.get_ticks_usec()
	if diag.has("abort"):
		return diag

	var net: Variant = _NetworkScr.new()
	var pond_c: Vector2 = diag["pond_center"] as Vector2
	var plaza_jids: Array[int] = _build_plaza_paths(net, g, plaza_side)
	diag["plaza_jids"] = plaza_jids
	diag["plaza_path_id"] = 0

	st = _stage2_primaries_hero(norm, st, g, plaza_side, diag["grid"], net, pond_c, plaza_jids, diag)
	diag["stage_ms"]["2_network"] = _ms_since(t_stage)
	t_stage = Time.get_ticks_usec()
	if diag.has("abort"):
		return diag

	st = _stage3_secondaries(norm, st, g, diag["grid"], net, pond_c, diag)
	diag["stage_ms"]["3_branches"] = _ms_since(t_stage)
	t_stage = Time.get_ticks_usec()
	if diag.has("abort"):
		return diag
	var frontage_slots: int = _estimate_plot_frontage_slots(net, diag["is_blocked_cb"])
	diag["plot_frontage_slots"] = frontage_slots
	if frontage_slots < _Layout.GENERATED_HAMLET_COUNT:
		diag["abort"] = true
		diag["fail_reason"] = "insufficient_frontage_%d" % frontage_slots
		diag["stage_reached"] = "post_branches"
		return diag

	var kit_st := _Layout._derive(st, _MAIN_SALT ^ 0x33)
	var pond_clear_cottage: float = _PondSite.BANK_OUTER_M + float(diag.get("pond_cottage_clearance_m", _Layout.GENERATED_POND_COTTAGE_CLEARANCE_M))
	var samp_params := {
		"norm": norm,
		"g": g,
		"max_corner_m": _Layout.HAMLET_MAX_CORNER_FROM_G,
		"pond_center": pond_c,
		"pond_clear_r": pond_clear_cottage,
		"obstacle_rects": [keep_clear],
		## Same test as validate v1: exterior rect must not intersect hero AABB (corner-only obstacle_rect misses spans).
		"hero_avoid_rect": hero_rect,
		"is_blocked": diag["is_blocked_cb"],
		"plaza_path_id": diag.get("plaza_path_id", -1),
		"plaza_s_max": 24.0,
		"junction_clear_m": 0.0,
		## Slightly below 1.0 so curved own-path polylines don't self-reject every footprint (V2 still uses INV-8 clearance).
		"path_buffer_m": 0.52,
		"step_m": 2.0,
		"verge_min_m": 1.6,
		"verge_max_m": 3.6,
	}
	var pick_st := _Layout._derive(kit_st, _PATH_SALT)
	var sel_params := {
		"max_same_template": 8,
		"density_noise_scale": 0.03,
		"min_gap_wall_m": 4.0,
		"hamlet_g": g,
		"max_corner_m": _Layout.HAMLET_MAX_CORNER_FROM_G,
		"quadrant_cap_max": 4,
	}
	var st5 := _stage5_select_with_capacity(
		norm, kit_st, pick_st, st, g, pond_c, samp_params, sel_params, diag["grid"], net, diag)
	st = int(st5.get("st", st))
	diag["candidates_n"] = int(st5.get("candidates_n", 0))
	diag["picked_n"] = int(st5.get("picked_n", 0))
	diag["capacity_branches"] = int(st5.get("capacity_branches", 0))
	diag["capacity_grow_failures"] = int(st5.get("capacity_grow_failures", diag.get("capacity_grow_failures", 0)))
	diag["join_snap_splits_failed"] = int(st5.get("join_snap_splits_failed", diag.get("join_snap_splits_failed", 0)))
	var picked: Array = st5.get("picked", []) as Array
	var plot_ms: Dictionary = st5.get("stage_ms", {}) as Dictionary
	for k: Variant in plot_ms:
		diag["stage_ms"][str(k)] = plot_ms[k]
	diag["stage_ms"]["4_5_plots"] = _ms_since(t_stage)
	diag["quadrants"] = quadrant_counts_from_picked(picked, g)
	t_stage = Time.get_ticks_usec()
	if not bool(st5.get("ok", false)):
		diag["fail_reason"] = str(st5.get("fail_reason", "plot_select"))
		diag["stage_reached"] = "select_plots"
		diag["plot_select_detail"] = {
			"picked_n": int(st5.get("picked_n", 0)),
			"need": _Layout.GENERATED_HAMLET_COUNT,
			"candidates_n": int(st5.get("candidates_n", 0)),
			"capacity_branches": int(st5.get("capacity_branches", 0)),
			"capacity_grow_failures": int(st5.get("capacity_grow_failures", 0)),
			"join_snap_splits_failed": int(st5.get("join_snap_splits_failed", 0)),
			"join_allow_not_junction_count": int(diag.get("join_allow_not_junction_count", 0)),
		}
		return diag

	st = _stage6_doors(net, picked, diag)
	diag["stage_ms"]["6_doors"] = _ms_since(t_stage)
	t_stage = Time.get_ticks_usec()
	if diag.has("abort"):
		diag["fail_reason"] = diag.get("fail_reason", "door_stage")
		diag["stage_reached"] = "door_connections"
		return diag

	var pond_cr_v2: float = _PondSite.BANK_OUTER_M + float(diag.get("pond_cottage_clearance_m", _Layout.GENERATED_POND_COTTAGE_CLEARANCE_M))
	var t7 := Time.get_ticks_usec()
	if not _stage7_resample_and_smooth_guarded(net, picked, pond_c, pond_cr_v2):
		diag["stage_ms"]["7_resample_smooth"] = _ms_since(t7)
		diag["stage7_debug"] = last_stage7_debug.duplicate(true)
		diag["abort"] = true
		diag["fail_reason"] = "stage7_v3_no_bundle"
		diag["stage_reached"] = "resample_smooth"
		return diag
	diag["stage_ms"]["7_resample_smooth"] = _ms_since(t7)
	diag["stage7_debug"] = last_stage7_debug.duplicate(true)

	var t_build := Time.get_ticks_usec()
	var layout := _build_layout(norm, g, plaza_side, keep_clear, cottage_keep, net, picked, pond_c, diag)
	diag["stage_ms"]["7_layout_build"] = _ms_since(t_build)
	t_build = Time.get_ticks_usec()

	var val := _validate_full(layout, picked, net)
	diag["stage_ms"]["8_validate"] = _ms_since(t_build)
	diag["stage_ms"]["7_8_finalize"] = _ms_since(t_stage)
	diag["v_counts"] = val["counts"]
	diag["v_samples"] = val["samples"]
	if not val["ok"]:
		diag["fail_reason"] = val["reason"]
		diag["stage_reached"] = "validate"
		diag["layout_on_fail"] = layout
		var rs: String = str(val["reason"])
		if rs.begins_with("v3:"):
			var pair: Vector2i = _v3_path_pair_from_reason(rs)
			var j_arr: Array = layout.junction_points as Array
			var j_vec: Array[Vector2] = []
			for jv: Variant in j_arr:
				j_vec.append(jv as Vector2)
			var kinds_arr: Array = layout.path_kinds as Array
			diag["v3_cross_debug"] = _Validate.v3_first_crossing_debug(layout.paths, kinds_arr, j_vec, 0.3)
		if rs.begins_with("v5:"):
			var pidx: int = _v5_path_index_from_reason(rs)
			if pidx >= 0 and pidx < layout.paths.size():
				var kinds_arr2: Array = layout.path_kinds as Array
				diag["v5_path_debug"] = _Validate.v5_debug_path(layout.paths, kinds_arr2, pidx)
		return diag

	diag["ok"] = true
	diag["layout"] = layout
	diag["counts_per_kind"] = _kind_counts(layout.path_kinds)
	diag["stage_reached"] = "complete"
	return diag


static func _ms_since(t0_us: int) -> float:
	return float(Time.get_ticks_usec() - t0_us) / 1000.0


static func _kind_counts(kinds: Array) -> Dictionary:
	var d := {}
	for k: Variant in kinds:
		var ks := str(k)
		d[ks] = int(d.get(ks, 0)) + 1
	return d


static func _reserve_stage1(
		norm: int,
		st: int,
		g: Vector2,
		plaza_rect: Rect2,
		_keep_clear_unused: Rect2,
		cottage_keep: Rect2,
		diag: Dictionary,
) -> int:
	var t0 := Time.get_ticks_usec()
	var world := Rect2(g - Vector2(_WORLD_EXTENT_M, _WORLD_EXTENT_M), Vector2(_WORLD_EXTENT_M * 2.0, _WORLD_EXTENT_M * 2.0))
	var grid: Variant = _GridScr.new(world, 1.0)
	## Hero building footprint — stop below the door approach so stoop stays a valid A* endpoint.
	grid.block_rect(Rect2(-5.5, -5.0, 11.0, 5.25), 1.0)
	## Block only the inner cottage keep-clear (cobble/plaza loop runs outside this — see legacy lattice).
	grid.block_rect(cottage_keep, 0.0)
	## Primaries/secondaries stop before lawn R−8 (DESIGN §3 stage 2).
	grid.block_outside_circle(g, _Layout.GENERATED_LAWN_RADIUS - 8.0)
	## Forest wedge behind hero (+Z)
	grid.block_rect(Rect2(world.position.x, 4.0, world.size.x, world.position.y + world.size.y - 4.0), 0.0)

	## Pond: try validated centres in fan until one passes.
	var pond_center := Vector2.ZERO
	var pond_ok := false
	var try_st := _Layout._derive(st, _POND_SALT)
	for _pi: int in range(48):
		try_st = _Scatter.lcg_step(try_st ^ norm)
		var r := lerpf(16.0, 34.0, _Scatter.lcg_f01(try_st))
		try_st = _Scatter.lcg_step(try_st)
		var phi_deg := lerpf(_Layout.FAN_PHI_MIN_DEG, _Layout.FAN_PHI_MAX_DEG, _Scatter.lcg_f01(try_st))
		var phi := deg_to_rad(phi_deg)
		var c := g + Vector2(r * sin(phi), -r * cos(phi))
		var trial := VillageLayout.new()
		trial.is_generated = true
		trial.hamlet_centre_xz = g
		trial.plaza_rect = plaza_rect
		trial.lawn_radius = _Layout.GENERATED_LAWN_RADIUS
		trial.pond_cottage_clearance_m = _Layout.GENERATED_POND_COTTAGE_CLEARANCE_M
		trial.pond_path_clearance_m = _Layout.GENERATED_POND_PATH_CLEARANCE_M
		trial.cottages = []
		if _PondPlace.validate(c, trial, false):
			pond_center = c
			pond_ok = true
			break
	if not pond_ok:
		diag["abort"] = true
		diag["fail_reason"] = "pond_unresolved"
		diag["stage_reached"] = "reserve"
		return st

	var pond_block_r: float = _PondSite.BANK_OUTER_M + _Layout.GENERATED_POND_PATH_CLEARANCE_M + 1.2
	grid.block_circle(pond_center, pond_block_r)

	var is_blocked := func(p: Vector2) -> bool:
		if p.y > 4.0 - 1e-4:
			return true
		if p.distance_to(g) > _Layout.HAMLET_MAX_CORNER_FROM_G + 0.5:
			return true
		if p.distance_to(pond_center) < pond_block_r - 0.5:
			return true
		return false

	(grid as VillageOccupancyGrid).ensure_clearance_field()
	diag["grid"] = grid
	diag["pond_center"] = pond_center
	diag["pond_cottage_clearance_m"] = _Layout.GENERATED_POND_COTTAGE_CLEARANCE_M
	diag["is_blocked_cb"] = is_blocked
	diag["stage_reached"] = "reserve"
	diag["stage_ms"]["_sub_reserve_grid"] = _ms_since(t0)
	st = _Scatter.lcg_step(st ^ try_st)
	return st


## Quadrant counts around G: [nw, ne, sw, se] matching `VillagePlotSampler.quadrant_counts_for_centres`.
static func quadrant_counts_from_picked(picked: Array, g: Vector2) -> Array[int]:
	var cts: Array[int] = [0, 0, 0, 0]
	for item: Variant in picked:
		var spec: Dictionary = (item as Dictionary)["spec"] as Dictionary
		var c: Vector2 = spec["centre"] as Vector2
		var qi: int = _Sampler.quadrant_index(c, g)
		cts[qi] += 1
	return cts


static func _plaza_inset_points(g: Vector2, side: float) -> Array[Vector2]:
	var rect := _Layout.plaza_rect_at(g, side)
	var inset := _Layout._PLAZA_LOOP_CENTERLINE_INSET_M
	var sw := _Layout._inset_plaza_point(Vector2(rect.position.x, rect.end.y), g, inset)
	var se := _Layout._inset_plaza_point(rect.end, g, inset)
	var ne := _Layout._inset_plaza_point(Vector2(rect.end.x, rect.position.y), g, inset)
	var nw := _Layout._inset_plaza_point(rect.position, g, inset)
	var mid_s := _Layout._inset_plaza_point(Vector2((rect.position.x + rect.end.x) * 0.5, rect.end.y), g, inset)
	var mid_e := _Layout._inset_plaza_point(Vector2(rect.end.x, (rect.position.y + rect.end.y) * 0.5), g, inset)
	var mid_n := _Layout._inset_plaza_point(Vector2((rect.position.x + rect.end.x) * 0.5, rect.position.y), g, inset)
	var mid_w := _Layout._inset_plaza_point(Vector2(rect.position.x, (rect.position.y + rect.end.y) * 0.5), g, inset)
	## Order: SW, S-mid, SE, E, NE, N-mid, NW, W → closed loop
	return [sw, mid_s, se, mid_e, ne, mid_n, nw, mid_w] as Array[Vector2]


static func _build_plaza_paths(net: Variant, g: Vector2, side: float) -> Array[int]:
	var pts := _plaza_inset_points(g, side)
	var jids: Array[int] = []
	for p: Vector2 in pts:
		jids.append(net.add_junction(p, []))
	for i: int in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var seg := PackedVector2Array([a, b])
		net.add_path(seg, "plaza", jids[i], jids[(i + 1) % pts.size()])
	return jids


## Primary start slots: plaza loop index order matches `_plaza_inset_points` (SW, midS, SE, midE, NE, midN, NW, midW).
## Buckets enforce at most one primary per compass "side" so routes spread around the plaza.
const _PRIMARY_BUCKET_NORTH: Array[int] = [6, 5, 4] ## NW, N-mid, NE
const _PRIMARY_BUCKET_EAST: Array[int] = [3]
const _PRIMARY_BUCKET_WEST: Array[int] = [7]
const _PRIMARY_BUCKET_SW: Array[int] = [0]
const _PRIMARY_BUCKET_SE: Array[int] = [2]


static func _primary_bucket_defs() -> Array[Dictionary]:
	return [
		{"name": "north", "ids": _PRIMARY_BUCKET_NORTH},
		{"name": "east", "ids": _PRIMARY_BUCKET_EAST},
		{"name": "west", "ids": _PRIMARY_BUCKET_WEST},
		{"name": "sw", "ids": _PRIMARY_BUCKET_SW},
		{"name": "se", "ids": _PRIMARY_BUCKET_SE},
	]


static func _pick_primary_start_indices(st: int, n_prim: int) -> Array[int]:
	var defs: Array[Dictionary] = _primary_bucket_defs()
	var order: Array[int] = []
	for bi: int in range(defs.size()):
		order.append(bi)
	for i0: int in range(order.size() - 1, 0, -1):
		st = _Scatter.lcg_step(st)
		var j0: int = int(_Scatter.lcg_f01(st) * float(i0 + 1)) % (i0 + 1)
		var tmp: int = order[i0]
		order[i0] = order[j0]
		order[j0] = tmp
	var out: Array[int] = []
	var n: int = mini(n_prim, defs.size())
	for k: int in range(n):
		var def: Dictionary = defs[order[k]] as Dictionary
		var ids: Array = def["ids"] as Array
		st = _Scatter.lcg_step(st)
		var pick: int = int(_Scatter.lcg_f01(st) * float(ids.size())) % ids.size()
		out.append(int(ids[pick]))
	return out


static func _outward_bearing_from_plaza_start(g: Vector2, start: Vector2, st: int) -> float:
	var d: Vector2 = start - g
	if d.length_squared() < 1e-8:
		d = Vector2(0.0, -1.0)
	else:
		d = d.normalized()
	st = _Scatter.lcg_step(st)
	var jitter := deg_to_rad(lerpf(-30.0, 30.0, _Scatter.lcg_f01(st)))
	return atan2(d.y, d.x) + jitter


static func _stage2_primaries_hero(
		norm: int,
		st: int,
		g: Vector2,
		plaza_side: float,
		grid: Variant,
		net: Variant,
		pond_c: Vector2,
		plaza_jids: Array[int],
		diag: Dictionary,
) -> int:
	var pts := _plaza_inset_points(g, plaza_side)
	## South edge midpoint index 1 in our array (mid_s at pts[1])
	var plaza_south_mid: Vector2 = pts[1]
	var j_plaza_south: int = plaza_jids[1]
	var hero_st: Vector2 = _Layout.HERO_DOOR_STOOP
	var guide: PackedVector2Array = grid.astar(plaza_south_mid, hero_st, 1.8, 0.85)
	if guide.size() < 2:
		diag["abort"] = true
		diag["fail_reason"] = "hero_astar"
		diag["stage_reached"] = "primary_hero"
		return st
	var hero_params := _grow_params(_Layout._derive(st, 0x0000F311), 0.11, 7.0, 0.13)
	var hero_poly: PackedVector2Array = _Grower.grow_pursuit(plaza_south_mid, guide, hero_params, grid)
	if hero_poly.size() < 2:
		diag["abort"] = true
		diag["fail_reason"] = "hero_grow"
		diag["stage_reached"] = "primary_hero"
		return st
	var allow_v3_prehero: Array[Vector2] = net.v3_allowed_points()
	var allow_hero: Array[Vector2] = _path_cross_allowed_from_junctions(net, allow_v3_prehero, j_plaza_south, -1)
	if not _path_ok_hard(hero_poly, grid, net, [], allow_hero, []):
		diag["abort"] = true
		diag["fail_reason"] = "hero_hard"
		diag["stage_reached"] = "primary_hero"
		return st
	## Downstream contract (INV-9′): layout.paths[i][0] is near hero stoop — grow runs plaza → stoop, so reverse
	## and attach start junction at stoop, end at plaza south.
	var nhp: int = hero_poly.size()
	for ri: int in range(nhp / 2):
		var rj: int = nhp - 1 - ri
		var tmp_hp: Vector2 = hero_poly[ri]
		hero_poly[ri] = hero_poly[rj]
		hero_poly[rj] = tmp_hp
	var j_end: int = net.add_junction(hero_st, [])
	net.add_path(hero_poly, "hero", j_end, j_plaza_south)
	st = _Scatter.lcg_step(st)

	## 2–4 primaries (+ hero) — DESIGN §3 stage 2.
	var n_prim := 2 + int(_Scatter.lcg_f01(_Layout._derive(st, 0x00F001)) * 3.0)
	st = _Scatter.lcg_step(st)
	var start_indices: Array[int] = _pick_primary_start_indices(st, n_prim)
	diag["primary_start_indices"] = start_indices
	st = _Scatter.lcg_step(st ^ n_prim * 0x1357)
	for _k: int in range(start_indices.size()):
		st = _Scatter.lcg_step(st)
		var si: int = int(start_indices[_k])
		var start: Vector2 = pts[si]
		st = _Scatter.lcg_step(st)
		var outward: Vector2 = start - g
		if outward.length_squared() > 1e-8:
			outward = outward.normalized()
		else:
			outward = Vector2(0.0, -1.0)
		var pond_half := (pond_c - g).dot(outward) > 0.35
		var bearing: float
		if _k == 0 and pond_half:
			bearing = atan2(pond_c.x - start.x, -(pond_c.y - start.y)) + deg_to_rad(lerpf(-18.0, 18.0, _Scatter.lcg_f01(st)))
		else:
			bearing = _outward_bearing_from_plaza_start(g, start, st)
		var targ_len := lerpf(24.0, 36.0, _Scatter.lcg_f01(_Scatter.lcg_step(st)))
		var p_st := _Layout._derive(st, _PATH_SALT + _k * 199)
		st = _Scatter.lcg_step(st)
		var js_plaza: int = plaza_jids[si]
		var poly := _grow_primary_candidates(grid, net, start, bearing, targ_len, p_st, js_plaza)
		if poly.size() < 2:
			p_st = _Layout._derive(p_st ^ 0x6E5F, _PATH_SALT + _k * 311)
			var fan_t := start + Vector2(cos(bearing + 0.4), sin(bearing + 0.4)) * minf(targ_len * 0.65, 28.0)
			var fan_guide: PackedVector2Array = grid.astar(start, fan_t, 1.6, 0.9)
			if fan_guide.size() >= 2:
				var prm2 := _grow_params(p_st, 0.1, 8.5, 0.11)
				poly = _Grower.grow_pursuit(start, fan_guide, prm2, grid)
				var allow_fan: Array[Vector2] = _path_cross_allowed_from_junctions(net, net.v3_allowed_points(), js_plaza, -1)
				if poly.size() < 2 or not _path_ok_hard(poly, grid, net, [], allow_fan, []):
					poly = PackedVector2Array()
		if poly.size() < 2:
			continue
		var js := plaza_jids[si]
		var allow_pre: Array[Vector2] = _path_cross_allowed_from_junctions(net, net.v3_allowed_points(), js, -1)
		var bad_primary := false
		for pid_x: int in range(net.path_count()):
			if net.get_path_kind(pid_x) != "primary":
				continue
			var px: PackedVector2Array = net.get_path_polyline(pid_x)
			if net.crosses_unintended_two_paths(poly, px, allow_pre, 0.3):
				bad_primary = true
				break
		if bad_primary:
			continue
		var je: int = net.add_junction(poly[poly.size() - 1], [])
		## Debug: growth-time crossing vs plaza / other primaries (tightened allowed = junctions only).
		if norm == 8 or norm == 1:
			var allow_dbg: Array[Vector2] = _path_cross_allowed_from_junctions(net, net.v3_allowed_points(), js, je)
			var plaza_id: int = int(diag.get("plaza_path_id", 0))
			if plaza_id >= 0 and plaza_id < net.path_count():
				var p_plaza: PackedVector2Array = net.get_path_polyline(plaza_id)
				var cross_p: bool = net.crosses_unintended_two_paths(poly, p_plaza, allow_dbg, 0.3)
				var why_p: Dictionary = net.crosses_unintended_why_false(poly, plaza_id, allow_dbg, 0.3, [])
				diag["v3_accept_diag_%d_plaza" % norm] = {
					"primary_k": _k,
					"cross_two_paths": cross_p,
					"why_false_vs_plaza": why_p,
				}
			if norm == 1:
				for pid_e: int in range(net.path_count()):
					if net.get_path_kind(pid_e) != "primary":
						continue
					var pe: PackedVector2Array = net.get_path_polyline(pid_e)
					var sje: int = net.start_junction_id(pid_e)
					var eje: int = net.end_junction_id(pid_e)
					var allow_m: Array[Vector2] = allow_dbg.duplicate()
					_append_junction_point_if_valid(allow_m, sje, net)
					_append_junction_point_if_valid(allow_m, eje, net)
					if net.crosses_unintended_two_paths(poly, pe, allow_m, 0.3):
						diag["v3_accept_diag_1_primary_vs_%d" % pid_e] = {
							"primary_k": _k,
							"other_pid": pid_e,
							"note": "geometric_hit_before_add",
						}
		net.add_path(poly, "primary", js, je)
	var n_prim_added: int = 0
	for pid0: int in range(net.path_count()):
		if net.get_path_kind(pid0) == "primary":
			n_prim_added += 1
	if n_prim_added < 2:
		var used_starts: Dictionary = {}
		for pid_sp: int in range(net.path_count()):
			if net.get_path_kind(pid_sp) != "primary":
				continue
			var sj_u: int = net.start_junction_id(pid_sp)
			for si_u: int in range(plaza_jids.size()):
				if plaza_jids[si_u] == sj_u:
					used_starts[si_u] = true
		for si_fb: int in range(pts.size()):
			if used_starts.has(si_fb):
				continue
			st = _Scatter.lcg_step(st ^ si_fb * 0x817)
			var start_fb: Vector2 = pts[si_fb]
			var bearing_fb := _outward_bearing_from_plaza_start(g, start_fb, st)
			var targ_fb := lerpf(22.0, 32.0, _Scatter.lcg_f01(_Scatter.lcg_step(st)))
			var p_st_fb := _Layout._derive(st, _PATH_SALT + si_fb * 419)
			var poly_fb := _grow_primary_candidates(grid, net, start_fb, bearing_fb, targ_fb, p_st_fb, plaza_jids[si_fb])
			if poly_fb.size() < 2:
				continue
			var js_fb: int = plaza_jids[si_fb]
			var allow_fb: Array[Vector2] = _path_cross_allowed_from_junctions(net, net.v3_allowed_points(), js_fb, -1)
			var reject_fb := false
			for pid_f: int in range(net.path_count()):
				if net.get_path_kind(pid_f) != "primary":
					continue
				if net.crosses_unintended_two_paths(poly_fb, net.get_path_polyline(pid_f), allow_fb, 0.3):
					reject_fb = true
					break
			if reject_fb:
				continue
			var je_fb: int = net.add_junction(poly_fb[poly_fb.size() - 1], [])
			net.add_path(poly_fb, "primary", js_fb, je_fb)
			used_starts[si_fb] = true
			n_prim_added += 1
			if n_prim_added >= 2:
				break
	if n_prim_added < 2:
		diag["abort"] = true
		diag["fail_reason"] = "primary_count_%d" % n_prim_added
		diag["stage_reached"] = "primary"
	return st


static func _grow_params(base_st: int, amp: float, wave: float, k: float) -> _Grower.GrowParams:
	var p := _Grower.GrowParams.new()
	p.seed = base_st
	p.amp_rad = amp
	p.wavelength_m = wave
	p.k = k
	p.max_turn_deg = 12.0
	p.ds = 0.75
	p.lookahead_m = 3.0
	p.steer_gain = 0.22
	p.pursuit_lookahead_m = 4.0
	return p


static func _grow_primary_candidates(
		grid: Variant,
		net: Variant,
		start: Vector2,
		bearing: float,
		length_m: float,
		seed_base: int,
		start_junction_id: int,
) -> PackedVector2Array:
	var allow_v3: Array[Vector2] = net.v3_allowed_points()
	var allow_cross: Array[Vector2] = _path_cross_allowed_from_junctions(net, allow_v3, start_junction_id, -1)
	var others := _existing_polys(net)
	var weights := {
		"w1": 1.0,
		"w2": 1.0,
		"w3": 0.4,
		"w4": 0.0,
		"w5": 0.45,
		"clear_req": 0.9,
		"near_miss_m": 2.0,
		"end_trim_m": 1.5,
	}
	var cands: Array = []
	for ci: int in range(8):
		var pst := _Layout._derive(seed_base, 0xC4AD + ci * 17)
		var amp := lerpf(0.09, 0.14, _Scatter.lcg_f01(_Scatter.lcg_step(pst)))
		var wave := lerpf(7.0, 10.0, _Scatter.lcg_f01(_Scatter.lcg_step(pst)))
		var prm := _grow_params(pst, amp, wave, 0.095)
		var poly: PackedVector2Array = _Grower.grow_free(start, bearing, length_m, prm, grid, null)
		if poly.size() >= 2 and _path_ok_hard(poly, grid, net, [], allow_cross, []):
			cands.append(poly)
	if cands.is_empty():
		return PackedVector2Array()
	return _Grower.best_of_light(cands, grid, others, weights)


static func _grid_with_picked_blocked(base_grid: Variant, picked: Array) -> Variant:
	if picked.is_empty():
		return base_grid
	var g: VillageOccupancyGrid = (base_grid as VillageOccupancyGrid).copy() as VillageOccupancyGrid
	for item: Variant in picked:
		var sp: Dictionary = (item as Dictionary)["spec"] as Dictionary
		g.block_rect(_Backdrop.cottage_exterior_rect(sp), _PICKED_COTTAGE_PATH_BUF_M)
	g.ensure_clearance_field()
	return g


static func _picked_cottage_rects(picked: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for item: Variant in picked:
		var sp: Dictionary = (item as Dictionary)["spec"] as Dictionary
		out.append(_Backdrop.cottage_exterior_rect(sp).grow(_PICKED_COTTAGE_PATH_BUF_M))
	return out


static func _polyline_hits_picked_cottage_clearance(poly: PackedVector2Array, rects: Array[Rect2]) -> bool:
	if rects.is_empty():
		return false
	for i: int in range(poly.size() - 1):
		var seg := PackedVector2Array([poly[i], poly[i + 1]])
		for r: Rect2 in rects:
			if _Sampler.rect_poly_min_clearance(r, seg) < 1e-3:
				return true
	return false


static func _path_ok_hard(
		poly: PackedVector2Array,
		grid: Variant,
		net: Variant,
		ignore_ids: Array,
		allowed_cross: Array[Vector2],
		picked_cottage_rects: Array[Rect2] = [],
) -> bool:
	if poly.size() < 2:
		return false
	if _polyline_hits_picked_cottage_clearance(poly, picked_cottage_rects):
		return false
	for i: int in range(poly.size() - 1):
		var n := int(maxi(1, floorf(poly[i].distance_to(poly[i + 1]) / 0.5)))
		for k: int in range(n + 1):
			var t := float(k) / float(n)
			var p: Vector2 = poly[i].lerp(poly[i + 1], t)
			if not grid.is_free(p):
				return false
	if net.crosses_unintended_with_allowed(poly, allowed_cross, 0.3, ignore_ids):
		return false
	return true


## v3 growth: do not pass plaza/hero path ids as ignore_ids (validator never ignores them).
## Allowed crossings are junction endpoints only for this polyline (start, optional join-at-end).
static func _append_junction_point_if_valid(out: Array[Vector2], jid: int, net: Variant) -> void:
	if jid < 0 or jid >= net.junction_point_count():
		return
	out.append(net.junction_point_at(jid))


static func _path_cross_allowed_from_junctions(
		net: Variant,
		base_allowed: Array[Vector2],
		start_junction_id: int,
		end_junction_id: int = -1,
) -> Array[Vector2]:
	var out: Array[Vector2] = base_allowed.duplicate()
	_append_junction_point_if_valid(out, start_junction_id, net)
	_append_junction_point_if_valid(out, end_junction_id, net)
	return out


## Join snaps must be real junctions: split target path at the foot when not already an endpoint junction.
## Returns junction id at the join (or -1 on failure).
const _JOIN_SNAP_SPLIT_TOL := 0.35


static func _junction_id_at_path_foot(net: Variant, path_id: int, foot: Vector2, diag: Dictionary) -> int:
	var poly: PackedVector2Array = net.get_path_polyline(path_id)
	if poly.size() < 2:
		return -1
	var tol := _JOIN_SNAP_SPLIT_TOL
	if foot.distance_to(poly[0]) <= tol + 1e-4:
		return net.start_junction_id(path_id)
	if foot.distance_to(poly[poly.size() - 1]) <= tol + 1e-4:
		return net.end_junction_id(path_id)
	var jid: int = int(net.split_path_at_point(path_id, foot, tol))
	if jid < 0:
		diag["join_snap_splits_failed"] = int(diag.get("join_snap_splits_failed", 0)) + 1
	return jid


const _JUNCTION_EPS := 1e-3


static func _allowed_cross_points_match_junctions(net: Variant, pts: Array[Vector2], diag: Dictionary, ctx: String) -> bool:
	var nju: int = net.junction_point_count()
	for p in pts:
		var ok_j := false
		for ji: int in range(nju):
			if p.distance_to(net.junction_point_at(ji)) <= _JUNCTION_EPS:
				ok_j = true
				break
		if not ok_j:
			diag["join_allow_not_junction_count"] = int(diag.get("join_allow_not_junction_count", 0)) + 1
			push_error("VillageGeneratorV3 %s: allowed_cross point %s is not a junction" % [ctx, str(p)])
			return false
	return true


static func _v5_path_index_from_reason(reason: String) -> int:
	var key := "path "
	var p := reason.find(key)
	if p < 0:
		return -1
	var rest := reason.substr(p + key.length())
	var num := ""
	for k: int in range(mini(12, rest.length())):
		var ch: String = rest[k]
		if ch >= "0" and ch <= "9":
			num += ch
		else:
			break
	if num.is_empty():
		return -1
	return num.to_int()


static func _v3_path_pair_from_reason(reason: String) -> Vector2i:
	var key := "paths "
	var p := reason.find(key)
	if p < 0:
		return Vector2i(-1, -1)
	var rest := reason.substr(p + key.length()).strip_edges()
	var vs_pos := rest.find(" vs ")
	if vs_pos < 0:
		return Vector2i(-1, -1)
	var left := rest.substr(0, vs_pos).strip_edges()
	var right_rest := rest.substr(vs_pos + 4).strip_edges()
	var num_a := ""
	for k: int in range(mini(8, left.length())):
		var ch: String = left[k]
		if ch >= "0" and ch <= "9":
			num_a += ch
		else:
			break
	var num_b := ""
	for k2: int in range(mini(8, right_rest.length())):
		var ch2: String = right_rest[k2]
		if ch2 >= "0" and ch2 <= "9":
			num_b += ch2
		else:
			break
	if num_a.is_empty() or num_b.is_empty():
		return Vector2i(-1, -1)
	return Vector2i(num_a.to_int(), num_b.to_int())


## Snap first/last poly vertices onto their graph junctions so resample does not leave a stub edge (V5 kink).
static func _point_on_open_polyline(p: Vector2, poly: PackedVector2Array, tol: float) -> bool:
	if poly.size() < 2:
		return false
	for i: int in range(poly.size() - 1):
		var foot: Vector2 = Geometry2D.get_closest_point_to_segment(p, poly[i], poly[i + 1])
		if foot.distance_to(p) <= tol:
			return true
	return false


static func _junction_pins_for_path(net: Variant, pid: int, poly: PackedVector2Array) -> Array[Vector2]:
	var pins: Array[Vector2] = []
	var seen: Dictionary = {}
	var sj: int = net.start_junction_id(pid)
	var ej: int = net.end_junction_id(pid)
	if sj >= 0:
		var p0: Vector2 = net.junction_point_at(sj)
		pins.append(p0)
		seen[p0] = true
	if ej >= 0 and ej != sj:
		var p1: Vector2 = net.junction_point_at(ej)
		if not seen.has(p1):
			pins.append(p1)
			seen[p1] = true
	for ji: int in range(net.junction_point_count()):
		var jp: Vector2 = net.junction_point_at(ji)
		if seen.has(jp):
			continue
		if _point_on_open_polyline(jp, poly, 0.4):
			pins.append(jp)
			seen[jp] = true
	return pins


static func _snap_polyline_endpoints_to_junctions(net: Variant, pid: int, poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() < 2:
		return poly
	var sj: int = net.start_junction_id(pid)
	var ej: int = net.end_junction_id(pid)
	var out := poly.duplicate()
	if sj >= 0 and sj < net.junction_point_count():
		out[0] = net.junction_point_at(sj)
	if ej >= 0 and ej < net.junction_point_count():
		out[out.size() - 1] = net.junction_point_at(ej)
	return out


static func _existing_polys(net: Variant) -> Array:
	var out: Array = []
	for pid: int in range(net.path_count()):
		out.append(net.get_path_polyline(pid))
	return out


static func _rollback_path_split(
		net: Variant,
		paths_before: int,
		parent_pid: int,
		parent_poly: PackedVector2Array,
		parent_end_j: int,
) -> void:
	if net.path_count() > paths_before:
		net.truncate_paths(paths_before)
	net.set_path_polyline(parent_pid, parent_poly)
	net.set_end_junction(parent_pid, parent_end_j)


static func _network_has_v3_crossing(net: Variant) -> bool:
	var paths: Array = []
	for pid: int in range(net.path_count()):
		paths.append(net.get_path_polyline(pid))
	var j_pts: Array[Vector2] = []
	for ji: int in range(net.junction_point_count()):
		j_pts.append(net.junction_point_at(ji))
	return not _Validate.v3_crossings(paths, j_pts, 0.3).is_empty()


static func _stage3_secondaries(
		norm: int,
		st: int,
		g: Vector2,
		grid: Variant,
		net: Variant,
		pond_c: Vector2,
		diag: Dictionary,
) -> int:
	var prim_ids: Array[int] = []
	for pid: int in range(net.path_count()):
		if net.get_path_kind(pid) == "primary":
			prim_ids.append(pid)
	if prim_ids.is_empty():
		diag["abort"] = true
		diag["fail_reason"] = "no_primary"
		return st

	## Slightly denser branching (still within DESIGN 2–5) — more plot frontage for 8 cottages.
	var n_br := 4 + int(_Scatter.lcg_f01(_Layout._derive(st, 0x00B2E0)) * 2.0)
	st = _Scatter.lcg_step(st)
	for bi: int in range(n_br):
		var allow_v3: Array[Vector2] = net.v3_allowed_points()
		st = _Scatter.lcg_step(st)
		var pid: int = prim_ids[int(_Scatter.lcg_f01(st) * float(prim_ids.size())) % prim_ids.size()]
		var poly: PackedVector2Array = net.get_path_polyline(pid)
		var plen: float = net.length(pid)
		if plen < 12.0:
			continue
		var s0 := lerpf(0.32, 0.78, _Scatter.lcg_f01(st)) * plen
		st = _Scatter.lcg_step(st)
		var fr: Dictionary = net.point_at(pid, s0)
		var p0: Vector2 = fr["point"] as Vector2
		var paths_before_br: int = net.path_count()
		var parent_poly_s3: PackedVector2Array = net.get_path_polyline(pid)
		var parent_ej_s3: int = net.end_junction_id(pid)
		var j_attach: int = int(net.split_path_at_point(pid, p0, 0.6))
		if j_attach < 0:
			continue
		var pid_head: int = pid
		var pid_tail: int = pid
		if net.path_count() > paths_before_br:
			pid_tail = net.path_count() - 1
		var split_heading_ok := true
		for pid_chk_s3: int in [pid_head, pid_tail]:
			if pid_chk_s3 >= 0 and pid_chk_s3 < net.path_count():
				var split_poly_s3: PackedVector2Array = net.get_path_polyline(pid_chk_s3)
				if split_poly_s3.size() >= 2 and _Grower.max_heading_change_per_m(split_poly_s3) > 24.5:
					split_heading_ok = false
					break
		if not split_heading_ok:
			_rollback_path_split(net, paths_before_br, pid, parent_poly_s3, parent_ej_s3)
			continue
		var tan: Vector2 = fr["tangent"] as Vector2
		var ang := deg_to_rad(lerpf(38.0, 68.0, _Scatter.lcg_f01(st)))
		st = _Scatter.lcg_step(st)
		if _Scatter.lcg_f01(st) < 0.5:
			ang = -ang
		var bearing := atan2(tan.y, tan.x) + ang
		var blen := lerpf(8.0, 19.0, _Scatter.lcg_f01(_Scatter.lcg_step(st)))
		var pst := _Layout._derive(st, 0xB000 + bi)
		st = _Scatter.lcg_step(st)
		var branch: PackedVector2Array = _Grower.grow_free(p0, bearing, blen, _grow_params(pst, 0.1, 8.0, 0.09), grid, null)
		if branch.size() < 2:
			_rollback_path_split(net, paths_before_br, pid, parent_poly_s3, parent_ej_s3)
			continue
		## Join if near another path
		var endp: Vector2 = branch[branch.size() - 1]
		var ex_near: Array = [pid_head] if pid_head == pid_tail else [pid_head, pid_tail]
		var near: Dictionary = net.nearest_point(endp, ex_near)
		var snapped_join := false
		var j_join: int = -1
		if float(near.get("distance", INF)) < 3.0 + 1e-3:
			var npid: int = int(near.get("path_id", -1))
			if npid < 0:
				_rollback_path_split(net, paths_before_br, pid, parent_poly_s3, parent_ej_s3)
				continue
			var npt: Vector2 = near["point"] as Vector2
			j_join = _junction_id_at_path_foot(net, npid, npt, diag)
			if j_join < 0:
				_rollback_path_split(net, paths_before_br, pid, parent_poly_s3, parent_ej_s3)
				continue
			var jq: Vector2 = net.junction_point_at(j_join)
			branch.set(branch.size() - 1, jq)
			endp = jq
			snapped_join = true
		## Do not pass split parent path ids as ignore_ids: that hides unintended hits vs the *other*
		## segment of the same path (false negatives). Attachment is covered by junctions in `allow_br`.
		allow_v3 = net.v3_allowed_points()
		var allow_br: Array[Vector2] = _path_cross_allowed_from_junctions(
			net, allow_v3, j_attach, j_join if snapped_join else -1)
		if snapped_join:
			if not _allowed_cross_points_match_junctions(net, allow_br, diag, "stage3_join"):
				_rollback_path_split(net, paths_before_br, pid, parent_poly_s3, parent_ej_s3)
				continue
		if not _path_ok_hard(branch, grid, net, [], allow_br, []):
			_rollback_path_split(net, paths_before_br, pid, parent_poly_s3, parent_ej_s3)
			continue
		if net.crosses_unintended_with_allowed(branch, allow_br, 0.3, []):
			_rollback_path_split(net, paths_before_br, pid, parent_poly_s3, parent_ej_s3)
			continue
		if _Grower.max_heading_change_per_m(branch) > 24.5:
			_rollback_path_split(net, paths_before_br, pid, parent_poly_s3, parent_ej_s3)
			continue
		var paths_before_add_s3: int = net.path_count()
		var j1: int = net.add_junction(endp, [])
		net.add_path(branch, "secondary", j_attach, j1)
		if _network_has_v3_crossing(net):
			net.truncate_paths(paths_before_add_s3)
			_rollback_path_split(net, paths_before_br, pid, parent_poly_s3, parent_ej_s3)
			continue
	return st


static func _collect_path_ids(net: Variant, kinds: Array) -> Array[int]:
	var out: Array[int] = []
	for pid: int in range(net.path_count()):
		if kinds.has(net.get_path_kind(pid)):
			out.append(pid)
	return out


## Stage 5: greedy plot selection with up to 4 capacity-driven secondary growths when k < N.
static func _stage5_select_with_capacity(
		norm: int,
		kit_st: int,
		pick_st: int,
		st: int,
		g: Vector2,
		pond_c: Vector2,
		samp_params: Dictionary,
		sel_params: Dictionary,
		grid: Variant,
		net: Variant,
		diag: Dictionary,
) -> Dictionary:
	var ms: Dictionary = {}
	var t0 := Time.get_ticks_usec()
	var need: int = _Layout.GENERATED_HAMLET_COUNT
	var path_ids: Array[int] = _collect_path_ids(net, ["primary", "secondary"])
	var all_cands: Array = _Sampler.candidates(net, path_ids, _Backdrop.COTTAGES, kit_st, samp_params)
	ms["5a_candidates_initial"] = _ms_since(t0)
	t0 = Time.get_ticks_usec()
	var picked: Array = _Sampler.select(all_cands, need, pick_st, sel_params)
	ms["5b_select_initial"] = _ms_since(t0)
	if picked.size() <= 2:
		return {
			"ok": false,
			"fail_reason": "plot_select_%d" % picked.size(),
			"picked": picked,
			"candidates_n": all_cands.size(),
			"picked_n": picked.size(),
			"capacity_branches": 0,
			"stage_ms": ms,
		}
	if picked.is_empty():
		return {
			"ok": false,
			"fail_reason": "plot_select_%d" % picked.size(),
			"picked": picked,
			"candidates_n": all_cands.size(),
			"picked_n": picked.size(),
			"capacity_branches": 0,
			"stage_ms": ms,
		}
	var cap_br := 0
	## Extra capacity: up to 4 secondary branches in emptiest wedge; incremental candidates per new path only.
	while picked.size() < need and cap_br < 4:
		var grew := false
		var new_path_ids: Array[int] = []
		t0 = Time.get_ticks_usec()
		var cap_fail := 0
		for sub_try: int in range(10):
			var br_st := _Layout._derive(norm ^ (cap_br * 0x1009) ^ (sub_try * 0xACE1), _MAIN_SALT ^ 0xCAFEB0 ^ cap_br * 31)
			st = _Scatter.lcg_step(st ^ br_st)
			var gr: Dictionary = _grow_one_capacity_branch(
				br_st, st, g, grid, net, picked, _picked_cottage_rects(picked), diag)
			if not bool(gr.get("ok", false)):
				gr = _grow_capacity_from_endpoint(
					br_st, st, g, grid, net, picked, _picked_cottage_rects(picked), diag)
			if bool(gr.get("ok", false)):
				grew = true
				new_path_ids = gr.get("new_path_ids", []) as Array[int]
				break
			cap_fail += 1
		diag["capacity_grow_failures"] = int(diag.get("capacity_grow_failures", 0)) + cap_fail
		ms["5c_capacity_try_%d" % cap_br] = _ms_since(t0)
		cap_br += 1
		if grew:
			path_ids = _collect_path_ids(net, ["primary", "secondary"])
			var samp_inc := samp_params.duplicate(true)
			if new_path_ids.size() > 0:
				samp_inc["path_id_filter"] = PackedInt32Array(new_path_ids)
			t0 = Time.get_ticks_usec()
			var new_cands: Array = _Sampler.candidates(
				net, path_ids, _Backdrop.COTTAGES, _Layout._derive(kit_st ^ cap_br * 7919, 0x51), samp_inc)
			ms["5d_cands_cap_%d" % cap_br] = _ms_since(t0)
			_merge_candidate_lists(all_cands, new_cands)
			pick_st = _Layout._derive(pick_st ^ (cap_br * 0xD020), _PATH_SALT + cap_br)
			t0 = Time.get_ticks_usec()
			picked = _Sampler.append_to_selection(all_cands, picked, need, pick_st, sel_params)
			ms["5e_append_cap_%d" % cap_br] = _ms_since(t0)
	if picked.size() < need and cap_br > 0:
		## One full candidate refresh after capacity branches (replaces per-cap 5f incremental fallback).
		t0 = Time.get_ticks_usec()
		path_ids = _collect_path_ids(net, ["primary", "secondary"])
		var samp_full: Dictionary = samp_params.duplicate(true)
		samp_full.erase("path_id_filter")
		var more_all: Array = _Sampler.candidates(
			net, path_ids, _Backdrop.COTTAGES, _Layout._derive(kit_st ^ 0xBADC0DE ^ int(cap_br), 0x53), samp_full)
		ms["5f_cands_full_refresh"] = _ms_since(t0)
		_merge_candidate_lists(all_cands, more_all)
		pick_st = _Layout._derive(pick_st ^ 0x51FACE, _PATH_SALT + 199)
		t0 = Time.get_ticks_usec()
		picked = _Sampler.append_to_selection(all_cands, picked, need, pick_st, sel_params)
		ms["5g_append_after_full_refresh"] = _ms_since(t0)
	if picked.size() < need:
		return {
			"ok": false,
			"fail_reason": "plot_select_%d" % picked.size(),
			"picked": picked,
			"candidates_n": all_cands.size(),
			"picked_n": picked.size(),
			"capacity_branches": cap_br,
			"capacity_grow_failures": int(diag.get("capacity_grow_failures", 0)),
			"join_snap_splits_failed": int(diag.get("join_snap_splits_failed", 0)),
			"st": st,
			"stage_ms": ms,
		}
	return {
		"ok": true,
		"picked": picked,
		"candidates_n": all_cands.size(),
		"picked_n": picked.size(),
		"capacity_branches": cap_br,
		"capacity_grow_failures": int(diag.get("capacity_grow_failures", 0)),
		"join_snap_splits_failed": int(diag.get("join_snap_splits_failed", 0)),
		"st": st,
		"stage_ms": ms,
	}


static func _merge_candidate_lists(into: Array, more: Array) -> void:
	var have: Dictionary = {}
	for x: Variant in into:
		have[_candidate_dedup_key(x as Dictionary)] = true
	for y: Variant in more:
		var k: String = _candidate_dedup_key(y as Dictionary)
		if have.has(k):
			continue
		into.append(y)
		have[k] = true


static func _candidate_dedup_key(c: Dictionary) -> String:
	var spec: Dictionary = c["spec"] as Dictionary
	var cen: Vector2 = spec["centre"] as Vector2
	return "%d_%.2f_%d_%s" % [int(c["path_id"]), float(c["s"]), int(c["side"]), str(cen)]


## Emptiest quadrant anchor around hamlet G (nw/ne/sw/se).
static func _quadrant_anchor(g: Vector2, qi: int) -> Vector2:
	var off := Vector2(-24.0, -24.0)
	match qi:
		1:
			off = Vector2(24.0, -24.0)
		2:
			off = Vector2(-24.0, 24.0)
		3:
			off = Vector2(24.0, 24.0)
	return g + off


static func _pick_emptiest_quadrant_index(q_counts: Array, br_st: int) -> int:
	var min_c: int = 999
	for c_raw: Variant in q_counts:
		min_c = mini(min_c, int(c_raw))
	var candidates: Array[int] = []
	for qi: int in range(mini(4, q_counts.size())):
		if int(q_counts[qi]) == min_c:
			candidates.append(qi)
	if candidates.is_empty():
		return 0
	var pick_st := _Layout._derive(br_st, 0x71A9)
	var idx := int(_Scatter.lcg_f01(pick_st) * float(candidates.size())) % candidates.size()
	return candidates[idx]


static func _estimate_plot_frontage_slots(net: Variant, is_blocked: Callable) -> int:
	var slots := 0
	const skip_m := 3.0
	const step_m := 2.0
	const verge_m := 4.0
	for pid: int in range(net.path_count()):
		var k: String = net.get_path_kind(pid)
		if k != "primary" and k != "secondary":
			continue
		var plen: float = net.length(pid)
		if plen < skip_m * 2.0 + step_m:
			continue
		var s: float = skip_m
		while s <= plen - skip_m - 0.01:
			var fr: Dictionary = net.point_at(pid, s)
			var p0: Vector2 = fr["point"] as Vector2
			var nn: Vector2 = fr["normal"] as Vector2
			for side in [1, -1]:
				var centre: Vector2 = p0 + nn * float(side) * verge_m
				if not is_blocked.call(centre):
					slots += 1
			s += step_m
	return slots


## One secondary from the path point best serving the emptiest quadrant around G.
static func _grow_one_capacity_branch(
		br_st: int,
		st: int,
		g: Vector2,
		grid: Variant,
		net: Variant,
		picked: Array,
		picked_rects: Array[Rect2],
		diag: Dictionary,
) -> Dictionary:
	var grid_eff: Variant = _grid_with_picked_blocked(grid, picked)
	var q_counts: Array = quadrant_counts_from_picked(picked, g)
	var target_q: int = _pick_emptiest_quadrant_index(q_counts, br_st)
	var anchor: Vector2 = _quadrant_anchor(g, target_q)
	var site_pool: Array = []
	var sample_step := _CAP_BRANCH_S_STEP
	## Shorter paths than stage-3 secondaries still need wedge samples (else cap_growth never runs).
	var min_len := 5.0
	for pid: int in range(net.path_count()):
		var k: String = net.get_path_kind(pid)
		if k != "primary" and k != "secondary":
			continue
		var plen: float = net.length(pid)
		if plen < min_len * 2.0 + sample_step:
			continue
		var s: float = sample_step
		while s <= plen - sample_step - 0.01:
			var fr: Dictionary = net.point_at(pid, s)
			var p0: Vector2 = fr["point"] as Vector2
			var tan: Vector2 = fr["tangent"] as Vector2
			var nn: Vector2 = fr["normal"] as Vector2
			if tan.length_squared() < 1e-8:
				s += sample_step
				continue
			var to_anchor: Vector2 = anchor - p0
			var to_anchor_n: Vector2 = to_anchor.normalized() if to_anchor.length_squared() > 1e-6 else Vector2.ZERO
			for side in [1, -1]:
				var side_n: Vector2 = nn * float(side)
				var origin: Vector2 = p0 + side_n * 3.5
				var cnt: int = grid_eff.count_free_fan_cells(origin, side_n, 14.0, 55.0, 11, 10)
				var near_ct := _nearby_picked_count_on_side(p0, side_n, picked)
				var dist: float = origin.distance_to(anchor)
				var side_to_q: float = maxf(0.0, side_n.dot(to_anchor_n)) if to_anchor_n.length_squared() > 1e-8 else 0.0
				var sc: float = -dist + 8.0 * side_to_q + 0.12 * float(cnt) - 2.2 * float(near_ct)
				site_pool.append({
					"score": sc, "path_id": pid, "s": s, "side": side,
				})
			s += sample_step
	if site_pool.is_empty():
		return {"ok": false}
	site_pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))
	var site: Dictionary = site_pool[0] as Dictionary
	var best_pid: int = int(site["path_id"])
	var best_s: float = float(site["s"])
	var best_side: int = int(site["side"])
	var fr2: Dictionary = net.point_at(best_pid, best_s)
	var p_attach: Vector2 = fr2["point"] as Vector2
	var tan2: Vector2 = fr2["tangent"] as Vector2
	var paths_before_split: int = net.path_count()
	var parent_cap_poly: PackedVector2Array = net.get_path_polyline(best_pid)
	var parent_cap_ej: int = net.end_junction_id(best_pid)
	var j_attach: int = int(net.split_path_at_point(best_pid, p_attach, 0.65))
	if j_attach < 0:
		return {"ok": false}
	var pid_a: int = best_pid
	var pid_b: int = best_pid
	if net.path_count() > paths_before_split:
		pid_b = net.path_count() - 1
	var cap_split_ok := true
	for pid_chk: int in [pid_a, pid_b]:
		if pid_chk >= 0 and pid_chk < net.path_count():
			var split_poly: PackedVector2Array = net.get_path_polyline(pid_chk)
			if split_poly.size() >= 2 and _Grower.max_heading_change_per_m(split_poly) > 24.5:
				cap_split_ok = false
				break
	if not cap_split_ok:
		_rollback_path_split(net, paths_before_split, best_pid, parent_cap_poly, parent_cap_ej)
		return {"ok": false}
	var sgn: float = float(best_side)
	var ang_deg := lerpf(35.0, 70.0, _Scatter.lcg_f01(_Layout._derive(br_st, 0x51)))
	st = _Scatter.lcg_step(st)
	if _Scatter.lcg_f01(st) < 0.5:
		ang_deg = -ang_deg
	var bearing := atan2(tan2.y, tan2.x) + deg_to_rad(ang_deg * sgn)
	var to_anchor: Vector2 = anchor - p_attach
	if to_anchor.length_squared() > 16.0:
		var desired: float = atan2(to_anchor.y, to_anchor.x)
		bearing = lerp_angle(bearing, desired, 0.55)
	var min_q: int = 99
	for qc: Variant in q_counts:
		min_q = mini(min_q, int(qc))
	var blen := lerpf(8.0, 20.0, _Scatter.lcg_f01(_Scatter.lcg_step(st)))
	if min_q <= 0:
		blen = lerpf(14.0, 26.0, _Scatter.lcg_f01(_Scatter.lcg_step(st ^ 0x33)))
	var pst := _Layout._derive(br_st, 0xB100)
	var branch: PackedVector2Array = _Grower.grow_free(
		p_attach, bearing, blen, _grow_params(pst, 0.1, 8.0, 0.09), grid_eff, null)
	if branch.size() < 2:
		_rollback_path_split(net, paths_before_split, best_pid, parent_cap_poly, parent_cap_ej)
		return {"ok": false}
	var endp: Vector2 = branch[branch.size() - 1]
	var ex_near2: Array = [pid_a] if pid_a == pid_b else [pid_a, pid_b]
	var near: Dictionary = net.nearest_point(endp, ex_near2)
	var snapped_join2 := false
	var j_join2: int = -1
	if float(near.get("distance", INF)) < 3.0 + 1e-3:
		var npid2: int = int(near.get("path_id", -1))
		if npid2 < 0:
			_rollback_path_split(net, paths_before_split, best_pid, parent_cap_poly, parent_cap_ej)
			return {"ok": false}
		var npt2: Vector2 = near["point"] as Vector2
		j_join2 = _junction_id_at_path_foot(net, npid2, npt2, diag)
		if j_join2 < 0:
			_rollback_path_split(net, paths_before_split, best_pid, parent_cap_poly, parent_cap_ej)
			return {"ok": false}
		var jq2: Vector2 = net.junction_point_at(j_join2)
		branch.set(branch.size() - 1, jq2)
		endp = jq2
		snapped_join2 = true
	var allow_v3b: Array[Vector2] = net.v3_allowed_points()
	var allow_cap: Array[Vector2] = _path_cross_allowed_from_junctions(
		net, allow_v3b, j_attach, j_join2 if snapped_join2 else -1)
	if snapped_join2:
		if not _allowed_cross_points_match_junctions(net, allow_cap, diag, "capacity_join"):
			_rollback_path_split(net, paths_before_split, best_pid, parent_cap_poly, parent_cap_ej)
			return {"ok": false}
	if not _path_ok_hard(branch, grid_eff, net, [], allow_cap, picked_rects):
		_rollback_path_split(net, paths_before_split, best_pid, parent_cap_poly, parent_cap_ej)
		return {"ok": false}
	if net.crosses_unintended_with_allowed(branch, allow_cap, 0.3, []):
		_rollback_path_split(net, paths_before_split, best_pid, parent_cap_poly, parent_cap_ej)
		return {"ok": false}
	if _Grower.max_heading_change_per_m(branch) > 24.5:
		_rollback_path_split(net, paths_before_split, best_pid, parent_cap_poly, parent_cap_ej)
		return {"ok": false}
	var paths_before_add: int = net.path_count()
	var j1: int = net.add_junction(endp, [])
	net.add_path(branch, "secondary", j_attach, j1)
	var new_sec: int = net.path_count() - 1
	var new_ids: Array[int] = []
	new_ids.append(pid_a)
	if pid_b != pid_a:
		new_ids.append(pid_b)
	if new_sec >= paths_before_add:
		new_ids.append(new_sec)
	return {"ok": true, "new_path_ids": new_ids}


## Secondary from an existing path endpoint toward the emptiest quadrant anchor (no midpoint split).
static func _grow_capacity_from_endpoint(
		br_st: int,
		st: int,
		g: Vector2,
		grid: Variant,
		net: Variant,
		picked: Array,
		picked_rects: Array[Rect2],
		diag: Dictionary,
) -> Dictionary:
	var q_counts: Array = quadrant_counts_from_picked(picked, g)
	var target_q: int = _pick_emptiest_quadrant_index(q_counts, br_st)
	var anchor: Vector2 = _quadrant_anchor(g, target_q)
	var grid_eff: Variant = _grid_with_picked_blocked(grid, picked)
	var best_pid := -1
	var best_d := INF
	var best_end := Vector2.ZERO
	var best_j := -1
	for pid: int in range(net.path_count()):
		var k: String = net.get_path_kind(pid)
		if k != "primary" and k != "secondary":
			continue
		var poly: PackedVector2Array = net.get_path_polyline(pid)
		if poly.size() < 2:
			continue
		var endp: Vector2 = poly[poly.size() - 1]
		var d: float = endp.distance_to(anchor)
		if d < best_d:
			best_d = d
			best_pid = pid
			best_end = endp
			best_j = net.end_junction_id(pid)
	if best_pid < 0 or best_j < 0:
		return {"ok": false}
	var grow_dir: Vector2 = anchor - best_end
	if grow_dir.length_squared() < 16.0:
		return {"ok": false}
	var bearing: float = atan2(grow_dir.y, grow_dir.x)
	bearing += deg_to_rad(lerpf(-12.0, 12.0, _Scatter.lcg_f01(_Layout._derive(br_st, 0x90EB))))
	var blen: float = lerpf(12.0, 24.0, _Scatter.lcg_f01(_Scatter.lcg_step(st)))
	var pst := _Layout._derive(br_st, 0xB200)
	var branch: PackedVector2Array = _Grower.grow_free(
		best_end, bearing, blen, _grow_params(pst, 0.1, 8.0, 0.09), grid_eff, null)
	if branch.size() < 2 or _Grower.max_heading_change_per_m(branch) > 24.5:
		return {"ok": false}
	var allow_cap: Array[Vector2] = net.v3_allowed_points()
	if not _path_ok_hard(branch, grid_eff, net, [], allow_cap, picked_rects):
		return {"ok": false}
	if net.crosses_unintended_with_allowed(branch, allow_cap, 0.3, []):
		return {"ok": false}
	var j1: int = net.add_junction(branch[branch.size() - 1], [])
	net.add_path(branch, "secondary", best_j, j1)
	var new_ids: Array[int] = [best_pid, net.path_count() - 1]
	return {"ok": true, "new_path_ids": new_ids}


static func _nearby_picked_count_on_side(p0: Vector2, side_n: Vector2, picked_try: Array) -> int:
	if picked_try.is_empty():
		return 0
	var u := side_n.normalized()
	var cnt := 0
	for item: Variant in picked_try:
		var c: Dictionary = item as Dictionary
		var cen: Vector2 = (c["spec"] as Dictionary)["centre"] as Vector2
		var w: Vector2 = cen - p0
		if w.dot(u) > 2.5 and w.length() < 22.0:
			cnt += 1
	return cnt


static func _stage6_doors(net: Variant, picked: Array, diag: Dictionary) -> int:
	for item: Variant in picked:
		var c: Dictionary = item as Dictionary
		var stoop: Vector2 = c["stoop"] as Vector2
		## Straight stoop → conn_end must stay identical to the sampler (V6 / user rule). Splits only
		## attach the graph; do not replace conn_end with nearest_point snaps.
		var conn_end: Vector2 = c["door_connection_end"] as Vector2
		var split_tol := 1.5
		var pid0: int = int(c["path_id"])
		var j_path: int = int(net.split_path_at_point(pid0, conn_end, split_tol))
		if j_path < 0:
			var resolved: Dictionary = net.nearest_point(conn_end, [], ["primary", "secondary"])
			if resolved.is_empty() or float(resolved.get("distance", INF)) > 1.5:
				diag["abort"] = true
				diag["fail_reason"] = "door_no_path"
				return 0
			var pid: int = int(resolved["path_id"])
			j_path = int(net.split_path_at_point(pid, conn_end, split_tol))
		if j_path < 0:
			diag["abort"] = true
			diag["fail_reason"] = "door_split"
			return 0
		var st_len: float = stoop.distance_to(conn_end)
		if st_len > 6.0 + 0.02:
			diag["abort"] = true
			diag["fail_reason"] = "door_len_%.2f" % st_len
			return 0
		var poly := PackedVector2Array([stoop, conn_end])
		var j0: int = net.add_junction(stoop, [])
		net.add_path(poly, "door", j0, j_path)
	return 0


static func _junction_pin_flags(net: Variant, poly: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(poly.size())
	for i: int in range(poly.size()):
		out[i] = 0
	for ji: int in range(net.junction_point_count()):
		var jp: Vector2 = net.junction_point_at(ji)
		for i2: int in range(poly.size()):
			if poly[i2].distance_to(jp) <= _STAGE7_JUNCTION_PIN_M + 1e-4:
				out[i2] = 1
	return out


static func _smooth_open_poly(poly: PackedVector2Array, passes: int, alpha: float, pin: PackedByteArray) -> PackedVector2Array:
	var cur := poly.duplicate()
	if cur.size() < 3:
		return cur
	for _p: int in range(passes):
		var nxt := cur.duplicate()
		for i: int in range(1, cur.size() - 1):
			if pin.size() > i and pin[i] != 0:
				continue
			nxt[i] = cur[i].lerp((cur[i - 1] + cur[i + 1]) * 0.5, alpha)
		cur = nxt
	return cur


static func _stage7_resample_and_smooth_guarded(net: Variant, picked: Array, pond_c: Vector2, pond_cr: float) -> bool:
	var specs_for_v: Array = []
	for item0: Variant in picked:
		specs_for_v.append((item0 as Dictionary)["spec"] as Dictionary)
	var j_for_v3: Array[Vector2] = []
	for jk: int in range(net.junction_point_count()):
		j_for_v3.append(net.junction_point_at(jk))
	var npath: int = net.path_count()
	var originals: Array = []
	originals.resize(npath)
	for pid0: int in range(npath):
		originals[pid0] = net.get_path_polyline(pid0)
	var kinds_arr: Array = []
	var door_stoops_s7: Array = []
	for gi_k: int in range(npath):
		kinds_arr.append(net.get_path_kind(gi_k))
	for item_ds: Variant in picked:
		door_stoops_s7.append((item_ds as Dictionary)["stoop"])

	## Try coarser/finer resample + optional no-smooth: fixes seed 3 where 0.3 m dense resample introduced V3 Xings.
	const S7_STEP_MS: Array[float] = [0.3, 0.55, 0.8]
	var chosen: Array = []
	var mode := "none"
	var last_paths_orig: Array = []
	for att: int in range(S7_STEP_MS.size()):
		var step_m: float = S7_STEP_MS[att]
		var do_sm: bool = true
		var bases: Array = []
		var cands: Array = []
		bases.resize(npath)
		cands.resize(npath)
		for pid: int in range(npath):
			var kind2: String = net.get_path_kind(pid)
			var poly: PackedVector2Array = originals[pid] as PackedVector2Array
			if poly.size() < 2:
				bases[pid] = poly
				cands[pid] = poly
				continue
			var snapped: PackedVector2Array = _snap_polyline_endpoints_to_junctions(net, pid, poly)
			var pins: Array[Vector2] = _junction_pins_for_path(net, pid, snapped)
			var base: PackedVector2Array = _Grower.resample_pinned(snapped, step_m, pins)
			bases[pid] = base
			cands[pid] = base
			if kind2 == "door" or kind2 == "plaza":
				continue
			var pin_base := _junction_pin_flags(net, base)
			var sm_pass := 1
			var sm_alpha := 0.1
			if kind2 == "hero":
				sm_pass = 4
				sm_alpha = 0.28
			elif kind2 == "primary":
				sm_pass = 1
				sm_alpha = 0.06
			elif kind2 == "secondary":
				cands[pid] = base
				continue
			else:
				sm_pass = 2
				sm_alpha = 0.2
			cands[pid] = _smooth_open_poly(base, sm_pass, sm_alpha, pin_base)
		var paths_sm: Array = []
		var paths_bas: Array = []
		var paths_orig: Array = []
		paths_sm.resize(npath)
		paths_bas.resize(npath)
		paths_orig.resize(npath)
		for gi2: int in range(npath):
			var kk: String = net.get_path_kind(gi2)
			if kk == "door" or kk == "plaza":
				paths_sm[gi2] = bases[gi2]
				paths_bas[gi2] = bases[gi2]
			else:
				paths_sm[gi2] = cands[gi2]
				paths_bas[gi2] = bases[gi2]
			paths_orig[gi2] = originals[gi2]
		last_paths_orig = paths_orig
		var sub := "smoothed_s%.2f" % step_m
		if _stage7_bundle_passes(paths_sm, kinds_arr, specs_for_v, door_stoops_s7, pond_c, pond_cr, j_for_v3):
			chosen = paths_sm
			mode = sub
			break
		if _stage7_bundle_passes(paths_bas, kinds_arr, specs_for_v, door_stoops_s7, pond_c, pond_cr, j_for_v3):
			chosen = paths_bas
			mode = "%s_bases" % sub
			break
		if _stage7_bundle_passes(paths_orig, kinds_arr, specs_for_v, door_stoops_s7, pond_c, pond_cr, j_for_v3):
			chosen = paths_orig
			mode = "%s_orig_fallback" % sub
			break
	if chosen.is_empty() and not last_paths_orig.is_empty():
		chosen = last_paths_orig.duplicate()
		mode = "originals_only"
	for pi3: int in range(npath):
		net.set_path_polyline(pi3, chosen[pi3] as PackedVector2Array)
	var committed: Array = []
	for pci: int in range(npath):
		committed.append(net.get_path_polyline(pci) as Variant)
	var v3_committed: Array = _Validate.v3_crossings(committed, j_for_v3, 0.3)
	last_stage7_debug = {
		"commit_mode": mode,
		"v3_committed_n": v3_committed.size(),
		"v3_committed_first": str(v3_committed[0]) if not v3_committed.is_empty() else "",
	}
	if not v3_committed.is_empty():
		for pr: int in range(npath):
			net.set_path_polyline(pr, originals[pr] as PackedVector2Array)
		last_stage7_debug["rolled_back_to_originals"] = true
		return false
	return true


static func _stage7_bundle_passes(
		geoms: Array,
		kinds_arr: Array,
		cottages_specs: Array,
		door_stoops: Array,
		pond_c: Vector2,
		pond_cr: float,
		j_for_v3: Array[Vector2],
) -> bool:
	## v2 expects `Array` polylines (layout format); `PackedVector2Array` does not always cast.
	var paths_v2: Array = []
	for gv: Variant in geoms:
		if gv is PackedVector2Array:
			var arr2: Array = []
			var pk: PackedVector2Array = gv as PackedVector2Array
			for pt: Vector2 in pk:
				arr2.append(pt)
			paths_v2.append(arr2)
		else:
			paths_v2.append(gv)
	if not _Validate.v3_crossings(paths_v2, j_for_v3, 0.3).is_empty():
		return false
	if not _Validate.v2_paths_vs_cottages(
			paths_v2, kinds_arr, cottages_specs, door_stoops, pond_c, pond_cr).is_empty():
		return false
	return _Validate.v5_shape(paths_v2, kinds_arr).is_empty()


static func _build_layout(
		norm: int,
		g: Vector2,
		plaza_side: float,
		keep_clear: Rect2,
		cottage_keep: Rect2,
		net: Variant,
		picked: Array,
		pond_c: Vector2,
		diag: Dictionary,
) -> VillageLayout:
	var layout := VillageLayout.new()
	layout.is_generated = true
	layout.fallback = false
	layout.generation_seed = norm
	layout.hamlet_centre_xz = g
	layout.plaza_side_m = plaza_side
	layout.plaza_rect = _Layout.plaza_rect_at(g, plaza_side)
	layout.plaza_keep_clear = keep_clear
	layout.cottage_rings = []
	layout.lawn_radius = _Layout.GENERATED_LAWN_RADIUS
	layout.hill_inner = _Layout.GENERATED_HILL_INNER
	layout.pine_inner = _Layout.GENERATED_PINE_INNER
	layout.pine_outer = _Layout.GENERATED_PINE_OUTER
	layout.pine_count = _Layout.GENERATED_PINE_COUNT
	layout.fog_begin = _Layout.GENERATED_FOG_BEGIN
	layout.fog_end = 95.0
	layout.bush_filler_inner = 8.0
	layout.bush_filler_outer = _Layout.GENERATED_BUSH_FILLER_OUTER
	layout.stone_seed = _Layout._derive(norm, _Layout.STONES_SALT)
	layout.pond_cottage_clearance_m = _Layout.GENERATED_POND_COTTAGE_CLEARANCE_M
	layout.pond_path_clearance_m = _Layout.GENERATED_POND_PATH_CLEARANCE_M
	layout.min_stone_spacing = _Layout.GENERATED_STONE_SPACING
	layout.pond_center = pond_c
	layout.pond_placed = true

	layout.paths = net.to_layout_paths()
	layout.path_kinds = net.kinds_array()
	layout.edges = net.edges()

	layout.junction_points = []
	for ji2: int in range(net.junction_point_count()):
		layout.junction_points.append(net.junction_point_at(ji2))

	layout.cottages = []
	for item: Variant in picked:
		var rec: Dictionary = item as Dictionary
		layout.cottages.append(((rec["spec"] as Dictionary).duplicate(true)))

	if _PondPlace.validate(layout.pond_center, layout, true):
		pass
	else:
		layout.pond_center = _PondPlace.resolve_after_paths(layout)

	return layout


static func _door_polylines_for_validate(layout: VillageLayout, picked: Array) -> Array:
	var by_stoop: Dictionary = {}
	for pi: int in range(layout.path_kinds.size()):
		if str(layout.path_kinds[pi]) != "door":
			continue
		var poly: Array = layout.paths[pi] as Array
		if poly.size() < 2:
			continue
		var p0: Vector2 = poly[0] as Vector2
		by_stoop[p0] = poly
	var out: Array = []
	for item: Variant in picked:
		var c: Dictionary = item as Dictionary
		var stoop: Vector2 = c["stoop"] as Vector2
		var best: Variant = null
		var best_d := 0.65
		for key: Variant in by_stoop.keys():
			var k: Vector2 = key as Vector2
			var d: float = k.distance_to(stoop)
			if d < best_d:
				best_d = d
				best = by_stoop[key]
		if best != null:
			out.append(best)
		else:
			out.append(_poly_from_seg(stoop, c["door_connection_end"] as Vector2))
	return out


static func _validate_full(layout: VillageLayout, picked: Array, net: Variant) -> Dictionary:
	var door_stoops: Array = []
	var door_conns: Array = _door_polylines_for_validate(layout, picked)
	for item: Variant in picked:
		var c: Dictionary = item as Dictionary
		door_stoops.append(c["stoop"])

	var hero_rect := Rect2(-5.5, -5.0, 11.0, 8.5)
	var pond_r := _PondSite.BANK_OUTER_M + layout.pond_cottage_clearance_m
	var payload := {
		"cottages": layout.cottages,
		"paths": layout.paths,
		"kinds": layout.path_kinds,
		"path_kinds": layout.path_kinds,
		"door_stoops": door_stoops,
		"door_connections": door_conns,
		"plaza_keep_clear": layout.plaza_keep_clear,
		"hero_rect": hero_rect,
		"pond_center": layout.pond_center,
		"pond_clear_r": pond_r,
		"g": layout.hamlet_centre_xz,
		"max_corner_m": _Layout.HAMLET_MAX_CORNER_FROM_G,
		"min_gap_m": 4.0,
		"junction_points": layout.junction_points,
		"junction_tol": 0.3,
		"hero_stoop": _Layout.HERO_DOOR_STOOP,
		"plaza_root": _plaza_south_mid(layout.hamlet_centre_xz, layout.plaza_side_m),
		"network": net,
	}
	var allr: Dictionary = _Validate.all(payload)
	var counts := {}
	var samples := {}
	var ok := true
	var reason := ""
	for key: String in ["v1", "v2", "v3", "v4", "v5", "v6"]:
		var arr: Array = allr[key] as Array
		counts[key] = arr.size()
		var samp: Array = []
		for i: int in mini(3, arr.size()):
			samp.append(str(arr[i]))
		samples[key] = samp
		if not arr.is_empty():
			ok = false
			if reason.is_empty():
				reason = "%s:%s" % [key, str(arr[0])]
	return {"ok": ok, "counts": counts, "samples": samples, "reason": reason}


static func _plaza_south_mid(g: Vector2, side: float) -> Vector2:
	var pts := _plaza_inset_points(g, side)
	return pts[1]


static func _poly_from_seg(a: Vector2, b: Vector2) -> Array:
	var arr: Array = [a]
	var d := a.distance_to(b)
	var n := int(ceil(d / _Layout._MEANDER_RESAMPLE_M))
	for i: int in range(1, n + 1):
		var t := float(i) / float(n)
		arr.append(a.lerp(b, t))
	return arr

