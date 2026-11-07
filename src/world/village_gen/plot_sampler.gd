## Plot sampling alongside paths for village generator v3 (decoupled from occupancy grid).
class_name VillagePlotSampler
extends RefCounted

## Stage 5 score weights (§3 stage 5 / DESIGN.md): facing, near_path, varied_spacing,
## open_space, plaza_bias; density_noise is applied as a multiplicative factor (see `select`).
const SCORE_WEIGHTS := {
	"facing": 3.0,
	"near_path": 2.0,
	"varied_spacing": 1.0,
	"open_space": 1.0,
	"plaza_bias": 0.5,
	"quadrant_balance": 0.55,
}

const _STEP_M := 1.5
const _SKIP_END_M := 3.0
const _JUNCTION_CLEAR_M := 4.0
const _PATH_BUFFER_M := 1.0
const _DOOR_STOOP_AHEAD_M := 0.5
const _OPEN_FAN_R_M := 6.0
const _OPEN_FAN_RAYS := 9
const _CARDINAL_YAWS: Array[int] = [0, 90, 180, 270]
## Spatial hash cell for junction clearance in candidate sweep (O(1) vs linear scan per sample).
const _JUNCTION_GRID_CELL_M := 4.0

const _LayoutValidate = preload("res://src/world/village_gen/village_validate.gd")
const _Layout := preload("res://src/world/village_layout.gd")


## One deterministic cosmetic roll per candidate (layout must match sampler rect/door).
static func _hamlet_variety_spec(spec: Dictionary, norm: int, path_id: int, s: float, side: int, template_name: String) -> Dictionary:
	var slot_i: int = int(hash(str(path_id) + "_" + str(snappedf(s, 0.01)) + "_" + str(side) + "_" + template_name))
	var v_st: int = _Layout._derive(norm ^ slot_i, _Layout.PLACEMENT_SALT)
	var vr := _Layout._apply_hamlet_kit_variety(v_st, spec, 0)
	return vr["spec"] as Dictionary


static func _poly_aabb_grow(poly: PackedVector2Array, pad: float) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var mn: Vector2 = poly[0]
	var mx: Vector2 = poly[0]
	for i: int in range(1, poly.size()):
		var p: Vector2 = poly[i]
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return Rect2(mn, mx - mn).grow(pad)


static func _rect_from_segment_grow(a: Vector2, b: Vector2, pad: float) -> Rect2:
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(mn, mx - mn).grow(pad)


static func _aabbs_intersect_expanded(a: Rect2, b: Rect2) -> bool:
	return a.grow(1e-4).intersects(b.grow(1e-4), true)


static func _path_bounds_for_prefilter(network: Variant, path_buffer_m: float) -> Array[Rect2]:
	var n: int = network.path_count()
	var out: Array[Rect2] = []
	out.resize(n)
	var pad: float = path_buffer_m + 0.15
	for pid: int in range(n):
		out[pid] = _poly_aabb_grow(network.get_path_polyline(pid), pad)
	return out


static func _junction_points_array(network: Variant) -> Array[Vector2]:
	var jn: int = network.junction_point_count()
	var arr: Array[Vector2] = []
	arr.resize(jn)
	for ji: int in range(jn):
		arr[ji] = network.junction_point_at(ji)
	return arr


static func _junction_proximity_grid(
		junc_pts: Array[Vector2], cell_m: float, clearance_m: float) -> Dictionary:
	var d2: float = clearance_m * clearance_m
	var buckets: Dictionary = {}
	for jp: Vector2 in junc_pts:
		var ik := int(floorf(jp.x / cell_m))
		var jk := int(floorf(jp.y / cell_m))
		var key := Vector2i(ik, jk)
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(jp)
	return {"cell_m": cell_m, "d2": d2, "buckets": buckets}


static func _too_near_junction_grid(grid: Dictionary, sample_pt: Vector2) -> bool:
	if not grid.has("buckets"):
		return false
	var cell_m: float = float(grid["cell_m"])
	var d2: float = float(grid["d2"])
	var buckets: Dictionary = grid["buckets"] as Dictionary
	var ix := int(floorf(sample_pt.x / cell_m))
	var iy := int(floorf(sample_pt.y / cell_m))
	for ox: int in range(-1, 2):
		for oy: int in range(-1, 2):
			var key := Vector2i(ix + ox, iy + oy)
			if not buckets.has(key):
				continue
			var cell: Array = buckets[key] as Array
			for jpv: Variant in cell:
				var jp: Vector2 = jpv as Vector2
				if sample_pt.distance_squared_to(jp) <= d2:
					return true
	return false


## Quadrant index relative to hamlet G: [nw, ne, sw, se] order in count arrays.
static func quadrant_index(centre: Vector2, g: Vector2) -> int:
	var dx: float = centre.x - g.x
	var dy: float = centre.y - g.y
	if dx <= 0.0 and dy <= 0.0:
		return 0 ## nw
	if dx > 0.0 and dy <= 0.0:
		return 1 ## ne
	if dx <= 0.0 and dy > 0.0:
		return 2 ## sw
	return 3 ## se


static func candidates(
		network: Variant,
		path_ids: Array[int],
		kit: Array,
		rng_state: int,
		params := {}) -> Array[Dictionary]:
	var g: Vector2 = params.get("g", Vector2(0.0, -18.0)) as Vector2
	var max_corner_m: float = float(params.get("max_corner_m", 54.0))
	var pond_c: Vector2 = params.get("pond_center", Vector2.ZERO) as Vector2
	var pond_r: float = float(params.get("pond_clear_r", 0.0))
	var obstacle_rects: Array = params.get("obstacle_rects", []) as Array
	var is_blocked: Callable = params.get("is_blocked", func(_p: Vector2) -> bool:
		return false
	) as Callable
	var plaza_path_id: int = int(params.get("plaza_path_id", -1))
	var plaza_s_max: float = float(params.get("plaza_s_max", 20.0))
	var hero_avoid: Rect2 = params.get("hero_avoid_rect", Rect2()) as Rect2
	## When non-empty: only sample these path ids (incremental candidates after a new branch).
	var path_id_filter: PackedInt32Array = params.get("path_id_filter", PackedInt32Array()) as PackedInt32Array
	var junction_clear_m: float = float(params.get("junction_clear_m", _JUNCTION_CLEAR_M))
	var path_buffer_m: float = float(params.get("path_buffer_m", _PATH_BUFFER_M))
	var step_m: float = float(params.get("step_m", _STEP_M))
	var verge_min: float = float(params.get("verge_min_m", 1.6))
	var verge_max: float = float(params.get("verge_max_m", 3.6))
	var norm_seed: int = int(params.get("norm", 0))
	var g_hamlet: Vector2 = params.get("g", _Layout.VILLAGE_GREEN_G) as Vector2

	var path_bounds: Array[Rect2] = _path_bounds_for_prefilter(network, path_buffer_m)
	var junc_pts: Array[Vector2] = _junction_points_array(network)
	var junction_grid: Dictionary = {}
	if junction_clear_m > 0.05 and junc_pts.size() > 0:
		junction_grid = _junction_proximity_grid(junc_pts, _JUNCTION_GRID_CELL_M, junction_clear_m)
	var seg_index: Dictionary = _LayoutValidate.build_path_segment_bucket_index(network)

	var out: Array[Dictionary] = []
	for path_id in path_ids:
		if path_id_filter.size() > 0:
			var allow := false
			for pf: int in path_id_filter:
				if pf == path_id:
					allow = true
					break
			if not allow:
				continue
		if path_id < 0 or path_id >= network.path_count():
			continue
		var poly: PackedVector2Array = network.get_path_polyline(path_id)
		var path_len: float = network.length(path_id)
		if path_len < _SKIP_END_M * 2.0 + step_m:
			continue
		var s: float = _SKIP_END_M
		while s <= path_len - _SKIP_END_M - 0.01:
			var frame: Dictionary = network.point_at(path_id, s)
			var p0: Vector2 = frame["point"] as Vector2
			## When splits insert many junctions along polylines, a global clearance rejects everything — opt out with junction_clear_m ≤ 0.
			if junction_clear_m > 0.05 and not junction_grid.is_empty() \
					and _too_near_junction_grid(junction_grid, p0):
				s += step_m
				continue
			var t: Vector2 = frame["tangent"] as Vector2
			var n: Vector2 = frame["normal"] as Vector2
			for side in [1, -1]:
				rng_state = VillageScatterPositions.lcg_step(rng_state ^ int(s * 1000) ^ path_id * 7919 ^ (side * 17))
				var verge: float = lerpf(verge_min, verge_max, VillageScatterPositions.lcg_f01(rng_state))
				var side_n: Vector2 = n * float(side)
				for template: Variant in kit:
					if typeof(template) != TYPE_DICTIONARY:
						continue
					var kit_dict: Dictionary = template as Dictionary
					var best_yaw: int = 0
					var best_face: float = -INF
					for yaw: int in _CARDINAL_YAWS:
						var trial_spec: Dictionary = _spec_with_pose(kit_dict, p0, yaw)
						var door_n: Vector2 = VillageBackdrop.cottage_door(trial_spec)[1] as Vector2
						var face: float = door_n.dot(-side_n)
						if face > best_face:
							best_face = face
							best_yaw = yaw
					var spec_half: Dictionary = _spec_with_pose(kit_dict, p0, best_yaw)
					var rect_half: Rect2 = VillageBackdrop.cottage_exterior_rect(spec_half)
					var half_depth: float = _half_extent_along_unit(rect_half, side_n)
					var d_offset: float = half_depth + verge
					var centre: Vector2 = p0 + side_n * d_offset
					var spec: Dictionary = _spec_with_pose(kit_dict, centre, best_yaw)
					var tnm: String = String(kit_dict.get("name", "unknown"))
					spec = _hamlet_variety_spec(spec, norm_seed, path_id, s, side, tnm)
					var rect: Rect2 = VillageBackdrop.cottage_exterior_rect(spec)
					var door_rec := VillageBackdrop.cottage_door(spec)
					var door_pos: Vector2 = door_rec[0] as Vector2
					var door_n2: Vector2 = door_rec[1] as Vector2
					var stoop: Vector2 = door_pos + door_n2 * _DOOR_STOOP_AHEAD_M
					var near: Dictionary = _nearest_on_path_polyline(poly, stoop)
					var conn_end: Vector2 = near["point"] as Vector2
					## Cheap hard checks
					if is_blocked.call(centre):
						continue
					if _rect_corners_forest_blocked(rect, is_blocked):
						continue
					if _corners_exceed_max_dist(rect, g, max_corner_m):
						continue
					if pond_r > 1e-5 and _pond_clearance_fail(rect, pond_c, pond_r):
						continue
					if _rect_hits_obstacles(rect, obstacle_rects):
						continue
					if hero_avoid.size.length_squared() > 1e-6 and rect.intersects(hero_avoid):
						continue
					if _path_buffer_fail(network, rect, path_id, stoop, conn_end, path_buffer_m, path_bounds):
						continue
					## Reject if the straight stoop→path connector would violate the same buffer rules (stage 6 uses this segment).
					if _door_straight_buffer_fail(network, path_id, stoop, conn_end, path_buffer_m, path_bounds):
						continue
					## V3: straight connector must not cross other paths (e.g. plaza loop) except at allowed endpoints.
					if _LayoutValidate.door_connector_crosses_v3_prefilter(
							network, stoop, conn_end, path_id, 0.3, path_bounds, junc_pts, seg_index):
						continue
					## Score parts
					var toward_path: Vector2 = (conn_end - stoop)
					var door_len: float = stoop.distance_to(conn_end)
					## v3 door connections are ≤ 6 m (V5 / DESIGN §3 stage 6) — never select plots that need longer.
					if door_len > 6.0 + 0.02:
						continue
					var facing: float = _LayoutValidate.door_facing_dot(spec, stoop, conn_end)
					if facing < 0.7 - 1e-4:
						continue
					var align: float = _cardinal_tangent_align(t)
					var open_frac: float = _open_space_fraction(
						centre, -side_n, is_blocked, rng_state ^ 31)
					var plaza_b: float = 0.0
					if plaza_path_id == path_id and s <= plaza_s_max:
						plaza_b = 1.0
					var qidx: int = quadrant_index(centre, g_hamlet)
					var score: float = (
						SCORE_WEIGHTS["facing"] * facing * align
						+ SCORE_WEIGHTS["near_path"] * (1.0 / maxf(0.5, door_len))
						+ SCORE_WEIGHTS["open_space"] * open_frac
						+ SCORE_WEIGHTS["plaza_bias"] * plaza_b
					)
					out.append({
						"path_id": path_id,
						"s": s,
						"side": side,
						"verge": verge,
						"template": String(kit_dict.get("name", "unknown")),
						"spec": spec,
						"yaw_deg": best_yaw,
						"rect": rect,
						"stoop": stoop,
						"door_connection_end": conn_end,
						"door_len": door_len,
						"quadrant_index": qidx,
						"score_parts": {
							"facing": facing,
							"tangent_align": align,
							"door_len": door_len,
							"open_space": open_frac,
							"plaza_bias": plaza_b,
						},
						"score": score,
					})
			s += step_m
	return out


static func select(
		cands: Array,
		n: int,
		rng_state: int,
		params := {}) -> Array[Dictionary]:
	var min_gap_wall_m: float = float(params.get("min_gap_wall_m", 4.0))
	var noise_scale: float = float(params.get("density_noise_scale", 0.04))
	var max_same_template: int = int(params.get("max_same_template", 3))
	## Max cottages per quadrant (nw, ne, sw, se); cap 5 avoids stalling at 6/8 when two quadrants are empty.
	var quadrant_cap_max: int = int(params.get("quadrant_cap_max", 4))
	var hamlet_g: Vector2 = params.get("hamlet_g", _Layout.VILLAGE_GREEN_G) as Vector2
	var max_corner_m: float = float(params.get("max_corner_m", _Layout.HAMLET_MAX_CORNER_FROM_G))
	if cands.is_empty() or n <= 0:
		return []

	var noise := FastNoiseLite.new()
	noise.seed = rng_state ^ 0x9E3779B9
	noise.frequency = 0.02
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var sorted: Array = cands.duplicate()
	sorted.sort_custom(func(a: Variant, b: Variant) -> bool:
		return (a as Dictionary).get("score", -INF) > (b as Dictionary).get("score", -INF)
	)

	var picked: Array[Dictionary] = []
	var template_counts: Dictionary = {}
	var path_last_s: Dictionary = {}
	var q_counts: Array[int] = [0, 0, 0, 0]

	for item: Variant in sorted:
		var cand: Dictionary = item as Dictionary
		if picked.size() >= n:
			break
		## Always derive from `spec` — cached `rect` can drift if spec fields are normalized elsewhere.
		var rect: Rect2 = VillageBackdrop.cottage_exterior_rect(cand["spec"] as Dictionary)
		if max_corner_m > 0.0 and _corners_exceed_max_dist(rect, hamlet_g, max_corner_m):
			continue
		var template_name: String = String(cand["template"])
		if int(template_counts.get(template_name, 0)) >= max_same_template:
			continue
		var ok := true
		for pi: int in range(picked.size()):
			var prev: Dictionary = picked[pi] as Dictionary
			var pr: Rect2 = VillageBackdrop.cottage_exterior_rect(prev["spec"] as Dictionary)
			if _LayoutValidate.wall_gap_too_small(rect, pr, min_gap_wall_m):
				ok = false
				break
			if _door_conn_crosses_rect(
					cand["stoop"] as Vector2, cand["door_connection_end"] as Vector2,
					pr):
				ok = false
				break
			if _door_conn_crosses_rect(
					prev["stoop"] as Vector2, prev["door_connection_end"] as Vector2,
					rect):
				ok = false
				break
		if not ok:
			continue
		var qi0: int = int(cand.get("quadrant_index", quadrant_index(rect.get_center(), hamlet_g)))
		if q_counts[qi0] >= quadrant_cap_max:
			continue
		## varied spacing term (along same path)
		var pid: int = int(cand["path_id"])
		var s_val: float = float(cand["s"])
		var spacing_pen: float = 0.0
		if path_last_s.has(pid):
			var o: float = float(path_last_s[pid])
			var gap: float = absf(s_val - o)
			## penalize gaps equal to neighbour gap ±1m (toy heuristic)
			for prev2: Dictionary in picked:
				if int(prev2["path_id"]) != pid:
					continue
				var og: float = absf(float(prev2["s"]) - o)
				if absf(gap - og) <= 1.0:
					spacing_pen += 1.0
			## reward 6–14 m target
			if gap < 6.0:
				spacing_pen += (6.0 - gap) * 0.1
			elif gap > 14.0:
				spacing_pen += (gap - 14.0) * 0.05
		path_last_s[pid] = s_val

		var cx: float = rect.get_center().x
		var cy: float = rect.get_center().y
		var nmul: float = (noise.get_noise_2d(cx * noise_scale, cy * noise_scale) * 0.5 + 1.0)
		var qi: int = int(cand.get("quadrant_index", quadrant_index(rect.get_center(), hamlet_g)))
		var qpen: float = maxf(0.0, float(q_counts[qi]) - 1.0)
		if q_counts[qi] >= 3:
			qpen += float(q_counts[qi] - 2)
		var spread_bonus: float = 0.0
		if q_counts[qi] == 0:
			spread_bonus = 0.45
		var adjusted: float = (
			float(cand["score"])
			+ SCORE_WEIGHTS["varied_spacing"] * (-spacing_pen)
			- SCORE_WEIGHTS["quadrant_balance"] * qpen
			+ spread_bonus
		)
		adjusted *= nmul

		var entry: Dictionary = cand.duplicate(true)
		entry["score_selected"] = adjusted
		entry["spacing_penalty"] = spacing_pen
		var sp: Dictionary = entry["score_parts"] as Dictionary
		sp["quadrant_balance_pen"] = qpen
		sp["spread_quadrant_bonus"] = spread_bonus
		entry["score_parts"] = sp
		picked.append(entry)
		template_counts[template_name] = int(template_counts.get(template_name, 0)) + 1
		q_counts[qi] += 1

	return picked


## Greedy top-up: same rules as `select`, starting from an existing `picked` (keeps order and counts).
static func append_to_selection(
		cands: Array,
		existing: Array,
		n: int,
		rng_state: int,
		params := {}) -> Array[Dictionary]:
	var min_gap_wall_m: float = float(params.get("min_gap_wall_m", 4.0))
	var noise_scale: float = float(params.get("density_noise_scale", 0.04))
	var max_same_template: int = int(params.get("max_same_template", 3))
	var quadrant_cap_max: int = int(params.get("quadrant_cap_max", 4))
	var hamlet_g: Vector2 = params.get("hamlet_g", _Layout.VILLAGE_GREEN_G) as Vector2
	var max_corner_m: float = float(params.get("max_corner_m", _Layout.HAMLET_MAX_CORNER_FROM_G))
	var picked: Array[Dictionary] = []
	for e: Variant in existing:
		picked.append((e as Dictionary).duplicate(true))
	if cands.is_empty() or n <= picked.size():
		return picked

	var noise := FastNoiseLite.new()
	noise.seed = rng_state ^ 0x9E3779B9
	noise.frequency = 0.02
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var sorted: Array = cands.duplicate()
	sorted.sort_custom(func(a: Variant, b: Variant) -> bool:
		return (a as Dictionary).get("score", -INF) > (b as Dictionary).get("score", -INF)
	)

	var template_counts: Dictionary = {}
	var path_last_s: Dictionary = {}
	var q_counts: Array[int] = [0, 0, 0, 0]
	for ent: Dictionary in picked:
		var tn: String = String(ent["template"])
		template_counts[tn] = int(template_counts.get(tn, 0)) + 1
		var pe: int = int(ent["path_id"])
		path_last_s[pe] = float(ent["s"])
		var spec_e: Dictionary = ent["spec"] as Dictionary
		var cen_e: Vector2 = spec_e["centre"] as Vector2
		q_counts[quadrant_index(cen_e, hamlet_g)] += 1

	for item: Variant in sorted:
		var cand: Dictionary = item as Dictionary
		if picked.size() >= n:
			break
		var rect: Rect2 = VillageBackdrop.cottage_exterior_rect(cand["spec"] as Dictionary)
		if max_corner_m > 0.0 and _corners_exceed_max_dist(rect, hamlet_g, max_corner_m):
			continue
		var template_name: String = String(cand["template"])
		if int(template_counts.get(template_name, 0)) >= max_same_template:
			continue
		var ok := true
		for pi: int in range(picked.size()):
			var prev: Dictionary = picked[pi] as Dictionary
			var pr: Rect2 = VillageBackdrop.cottage_exterior_rect(prev["spec"] as Dictionary)
			if _LayoutValidate.wall_gap_too_small(rect, pr, min_gap_wall_m):
				ok = false
				break
			if _door_conn_crosses_rect(
					cand["stoop"] as Vector2, cand["door_connection_end"] as Vector2,
					pr):
				ok = false
				break
			if _door_conn_crosses_rect(
					prev["stoop"] as Vector2, prev["door_connection_end"] as Vector2,
					rect):
				ok = false
				break
		if not ok:
			continue
		var qix: int = int(cand.get("quadrant_index", quadrant_index(rect.get_center(), hamlet_g)))
		if q_counts[qix] >= quadrant_cap_max:
			continue
		var pid: int = int(cand["path_id"])
		var s_val: float = float(cand["s"])
		var spacing_pen: float = 0.0
		if path_last_s.has(pid):
			var o: float = float(path_last_s[pid])
			var gap: float = absf(s_val - o)
			for prev2: Dictionary in picked:
				if int(prev2["path_id"]) != pid:
					continue
				var og: float = absf(float(prev2["s"]) - o)
				if absf(gap - og) <= 1.0:
					spacing_pen += 1.0
			if gap < 6.0:
				spacing_pen += (6.0 - gap) * 0.1
			elif gap > 14.0:
				spacing_pen += (gap - 14.0) * 0.05
		path_last_s[pid] = s_val

		var cx: float = rect.get_center().x
		var cy: float = rect.get_center().y
		var nmul: float = (noise.get_noise_2d(cx * noise_scale, cy * noise_scale) * 0.5 + 1.0)
		var qi2: int = int(cand.get("quadrant_index", quadrant_index(rect.get_center(), hamlet_g)))
		var qpen2: float = maxf(0.0, float(q_counts[qi2]) - 1.0)
		if q_counts[qi2] >= 3:
			qpen2 += float(q_counts[qi2] - 2)
		var spread_bonus2: float = 0.0
		if q_counts[qi2] == 0:
			spread_bonus2 = 0.45
		var adjusted: float = (
			float(cand["score"])
			+ SCORE_WEIGHTS["varied_spacing"] * (-spacing_pen)
			- SCORE_WEIGHTS["quadrant_balance"] * qpen2
			+ spread_bonus2
		)
		adjusted *= nmul

		var entry: Dictionary = cand.duplicate(true)
		entry["score_selected"] = adjusted
		entry["spacing_penalty"] = spacing_pen
		var sp2: Dictionary = entry["score_parts"] as Dictionary
		sp2["quadrant_balance_pen"] = qpen2
		sp2["spread_quadrant_bonus"] = spread_bonus2
		entry["score_parts"] = sp2
		picked.append(entry)
		template_counts[template_name] = int(template_counts.get(template_name, 0)) + 1
		q_counts[qi2] += 1

	return picked


static func _spec_with_pose(
		template: Dictionary, centre: Vector2, yaw_deg: int) -> Dictionary:
	var spec: Dictionary = template.duplicate(true)
	spec["centre"] = centre
	spec["yaw_deg"] = yaw_deg
	if not spec.has("door"):
		spec["door"] = "front:1"
	return spec


static func _half_extent_along_unit(rect: Rect2, u: Vector2) -> float:
	var uc := u.normalized()
	return 0.5 * (rect.size.x * absf(uc.x) + rect.size.y * absf(uc.y))


static func _nearest_on_path_polyline(poly: PackedVector2Array, p: Vector2) -> Dictionary:
	var best_d: float = INF
	var best_q: Vector2 = poly[0] if poly.size() > 0 else p
	for i: int in maxi(0, poly.size() - 1):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
		var d: float = p.distance_to(q)
		if d < best_d:
			best_d = d
			best_q = q
	return {"point": best_q, "distance": best_d}


static func _nearest_on_path_id(network: Variant, path_id: int, p: Vector2) -> Dictionary:
	return _nearest_on_path_polyline(network.get_path_polyline(path_id), p)


static func _rect_edges(rect: Rect2) -> Array:
	var p: Vector2 = rect.position
	var s: Vector2 = rect.size
	var a: Vector2 = p
	var b: Vector2 = p + Vector2(s.x, 0.0)
	var c: Vector2 = p + s
	var d: Vector2 = p + Vector2(0.0, s.y)
	return [[a, b], [b, c], [c, d], [d, a]]


## Minimum distance from closed segment (a,b) to closed rect boundary; 0 if segment intersects rect interior or edge.
static func _segment_rect_min_distance(a: Vector2, b: Vector2, rect: Rect2) -> float:
	if rect.has_point(a) or rect.has_point(b):
		return 0.0
	for edge: Variant in _rect_edges(rect):
		var e: Array = edge as Array
		var u: Vector2 = e[0] as Vector2
		var v: Vector2 = e[1] as Vector2
		if Geometry2D.segment_intersects_segment(a, b, u, v) != null:
			return 0.0
	var best: float = INF
	for edge2: Variant in _rect_edges(rect):
		var e2: Array = edge2 as Array
		var u2: Vector2 = e2[0] as Vector2
		var v2: Vector2 = e2[1] as Vector2
		best = minf(best, _segment_pair_min_dist(a, b, u2, v2))
	return best


## Public for tests / generator: min distance from rect boundary to polyline segments; 0 if intersects.
static func rect_poly_min_clearance(rect: Rect2, poly: PackedVector2Array) -> float:
	var best: float = INF
	for i: int in maxi(0, poly.size() - 1):
		var da: Vector2 = poly[i]
		var db: Vector2 = poly[i + 1]
		best = minf(best, _segment_rect_min_distance(da, db, rect))
	return best


static func _rect_corners(r: Rect2) -> Array[Vector2]:
	return [
		r.position,
		r.position + Vector2(r.size.x, 0.0),
		r.position + r.size,
		r.position + Vector2(0.0, r.size.y),
	]


static func _rect_corners_forest_blocked(rect: Rect2, is_blocked: Callable) -> bool:
	for c in _rect_corners(rect):
		if is_blocked.call(c):
			return true
	return false


static func _corners_exceed_max_dist(rect: Rect2, g: Vector2, max_m: float) -> bool:
	for c in _rect_corners(rect):
		if c.distance_to(g) > max_m:
			return true
	return false


static func _pond_clearance_fail(rect: Rect2, pond_c: Vector2, clear_r: float) -> bool:
	for c in _rect_corners(rect):
		if c.distance_to(pond_c) < clear_r:
			return true
	return rect.has_point(pond_c)


static func _rect_hits_obstacles(rect: Rect2, obstacles: Array) -> bool:
	for o_raw in obstacles:
		var o: Rect2 = o_raw as Rect2
		if rect.intersects(o):
			return true
	return false


static func _conn_end_on_segment(poly: PackedVector2Array, conn_end: Vector2, tol: float = 0.2) -> bool:
	for i: int in maxi(0, poly.size() - 1):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var foot: Vector2 = Geometry2D.get_closest_point_to_segment(conn_end, a, b)
		if foot.distance_to(conn_end) <= tol:
			return true
	return false


static func _segment_pair_min_dist(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> float:
	## Minimum distance between two closed segments (cheap corner + intersection check).
	if Geometry2D.segment_intersects_segment(p1, p2, q1, q2) != null:
		return 0.0
	var m := INF
	for p in [p1, p2]:
		m = minf(m, Geometry2D.get_closest_point_to_segment(p, q1, q2).distance_to(p))
	for q in [q1, q2]:
		m = minf(m, Geometry2D.get_closest_point_to_segment(q, p1, p2).distance_to(q))
	return m


static func _door_straight_buffer_fail(
		network: Variant,
		own_path_id: int,
		stoop: Vector2,
		conn_end: Vector2,
		buf: float,
		path_bounds: Array[Rect2]) -> bool:
	var door_bb: Rect2 = _rect_from_segment_grow(stoop, conn_end, buf + 0.2)
	for pid: int in range(network.path_count()):
		if network.get_path_kind(pid) == "plaza":
			continue
		if pid < path_bounds.size() and not _aabbs_intersect_expanded(door_bb, path_bounds[pid]):
			continue
		var poly: PackedVector2Array = network.get_path_polyline(pid)
		for i: int in maxi(0, poly.size() - 1):
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[i + 1]
			var exempt := false
			if pid == own_path_id and _conn_end_on_segment(poly, conn_end):
				var foot: Vector2 = Geometry2D.get_closest_point_to_segment(conn_end, a, b)
				if foot.distance_to(conn_end) <= 0.2:
					exempt = true
			if exempt:
				continue
			if _segment_pair_min_dist(stoop, conn_end, a, b) < buf - 1e-4:
				return true
	return false


static func _path_buffer_fail(
		network: Variant,
		rect: Rect2,
		own_path_id: int,
		stoop: Vector2,
		conn_end: Vector2,
		buf: float,
		path_bounds: Array[Rect2]) -> bool:
	var rect_bb: Rect2 = rect.grow(buf + 0.15)
	for pid: int in range(network.path_count()):
		## Plaza cobble loop hugs the village centre; cottages may stand near it — keep-clear + V1 handle overlap.
		if network.get_path_kind(pid) == "plaza":
			continue
		if pid < path_bounds.size() and not _aabbs_intersect_expanded(rect_bb, path_bounds[pid]):
			continue
		if pid == own_path_id:
			## allow proximity along door connector by trimming that segment on own path
			var poly: PackedVector2Array = network.get_path_polyline(pid)
			if _rect_too_close_to_poly_except_segment(rect, poly, stoop, conn_end, buf):
				return true
		else:
			var poly2: PackedVector2Array = network.get_path_polyline(pid)
			if _rect_too_close_to_poly(rect, poly2, buf):
				return true
	return false


static func _rect_too_close_to_poly(rect: Rect2, poly: PackedVector2Array, min_dist: float) -> bool:
	for i: int in maxi(0, poly.size() - 1):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		if _segment_rect_min_distance(a, b, rect) < min_dist - 1e-4:
			return true
	return false


static func _rect_too_close_to_poly_except_segment(
		rect: Rect2,
		poly: PackedVector2Array,
		stoop: Vector2,
		conn_end: Vector2,
		min_dist: float) -> bool:
	for i: int in maxi(0, poly.size() - 1):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		if _segment_eq(a, b, stoop, conn_end):
			continue
		if _segment_rect_min_distance(a, b, rect) < min_dist - 1e-4:
			return true
	return false


static func _segment_eq(a: Vector2, b: Vector2, c: Vector2, d: Vector2, tol: float = 0.35) -> bool:
	return (a.distance_to(c) < tol and b.distance_to(d) < tol) or (a.distance_to(d) < tol and b.distance_to(c) < tol)


static func _cardinal_tangent_align(t: Vector2) -> float:
	var ang: float = absf(rad_to_deg(atan2(t.y, t.x)))
	var mod90: float = fposmod(ang, 90.0)
	var dev: float = minf(mod90, 90.0 - mod90)
	if dev >= 25.0:
		return 0.0
	return 1.0 - dev / 25.0


static func _open_space_fraction(origin: Vector2, back_dir: Vector2, is_blocked: Callable, seed: int) -> float:
	var u := back_dir.normalized()
	var perp := Vector2(-u.y, u.x)
	var hits: int = 0
	var total: int = _OPEN_FAN_RAYS
	for i: int in total:
		var t2: float = lerpf(-0.65, 0.65, float(i) / float(maxi(1, total - 1)))
		var dir: Vector2 = (u + perp * t2).normalized()
		var sample: Vector2 = origin + dir * _OPEN_FAN_R_M
		var jitter: float = VillageScatterPositions.lcg_f01(seed ^ (i * 9176)) * 0.4
		if is_blocked.call(origin + dir * (_OPEN_FAN_R_M * (0.35 + jitter))):
			hits += 1
	return 1.0 - float(hits) / float(total)


## Public alias for tests — delegates to VillageLayoutValidate (same rule as V1).
static func wall_gap_too_small(a: Rect2, b: Rect2, min_gap: float) -> bool:
	return _LayoutValidate.wall_gap_too_small(a, b, min_gap)


static func _door_conn_crosses_rect(st: Vector2, en: Vector2, rect: Rect2) -> bool:
	if st.distance_squared_to(en) < 1e-8:
		return false
	var corners := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	]
	var n1: int = corners.size()
	for i: int in n1:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % n1]
		if Geometry2D.segment_intersects_segment(st, en, a, b) != null:
			return true
	return false
