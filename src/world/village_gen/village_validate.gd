## Pure layout validation (village generator v3, invariants V1–V6).
class_name VillageLayoutValidate
extends RefCounted

const _PathGrower := preload("res://src/world/village_gen/path_grower.gd")
const _PathNetworkScr := preload("res://src/world/village_gen/path_network.gd")
const _DOOR_EXEMPT_KINDS: Array[String] = ["door"]

const _INV8_GROW_M := 0.35
const _DOOR_STOOP_TAIL_M := 0.5
const _V3_SEG_GRID_CELL_M := 2.0


static func v1_cottages(
		cottages: Array,
		plaza_keep_clear: Rect2,
		hero_rect: Rect2,
		pond_center: Vector2,
		pond_clear_r: float,
		g: Vector2,
		max_corner_m: float,
		min_gap_m: float) -> Array[String]:
	var viol: Array[String] = []
	if cottages.is_empty():
		return ["v1: no cottages"]
	var rects: Array[Rect2] = []
	for ci: int in cottages.size():
		var spec: Dictionary = cottages[ci] as Dictionary
		var r: Rect2 = VillageBackdrop.cottage_exterior_rect(spec)
		rects.append(r)
		if plaza_keep_clear.intersects(r) or plaza_keep_clear.encloses(r):
			viol.append("v1: cottage %d overlaps plaza keep-clear" % ci)
		if hero_rect.intersects(r):
			viol.append("v1: cottage %d overlaps hero" % ci)
		for c in _rect_corners(r):
			if pond_clear_r > 1e-6 and c.distance_to(pond_center) < pond_clear_r:
				viol.append("v1: cottage %d breaks pond clearance" % ci)
				break
		for c in _rect_corners(r):
			if c.distance_to(g) > max_corner_m:
				viol.append("v1: cottage %d corner beyond max from G" % ci)
				break
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			if wall_gap_too_small(rects[i], rects[j], min_gap_m):
				viol.append("v1: cottages %d and %d under min wall gap" % [i, j])
	return viol


static func v2_paths_vs_cottages(
		paths: Array,
		kinds: Array,
		cottages: Array,
		door_stoops: Array,
		pond_center: Vector2,
		pond_path_clear_r: float) -> Array[String]:
	var viol: Array[String] = []
	var grown: Array[Rect2] = []
	for spec: Variant in cottages:
		grown.append(VillageBackdrop.cottage_exterior_rect(spec as Dictionary).grow(_INV8_GROW_M))
	var pond_r: float = maxf(0.0, pond_path_clear_r)

	var door_slot: int = 0
	for pi: int in paths.size():
		var poly: Array = paths[pi] as Array
		var kind: String = str(kinds[pi]) if pi < kinds.size() else "primary"
		var door_tail_verts: Dictionary = {}
		if kind == "door":
			if door_slot < door_stoops.size():
				door_tail_verts = _door_tail_vertex_set(poly, door_stoops[door_slot] as Vector2)
			door_slot += 1
		for vi: int in poly.size():
			var p: Vector2 = poly[vi] as Vector2
			if pond_r > 1e-6 and p.distance_to(pond_center) < pond_r:
				viol.append("v2: path %d in pond corridor" % pi)
			for ci: int in grown.size():
				if not grown[ci].has_point(p):
					continue
				if kind in _DOOR_EXEMPT_KINDS and door_tail_verts.has(vi):
					continue
				viol.append("v2: path %d vtx %d inside cottage %d clearance" % [pi, vi, ci])
	return viol


static func _door_tail_vertex_set(poly: Array, stoop: Vector2) -> Dictionary:
	var out: Dictionary = {}
	if poly.is_empty():
		return out
	var acc: float = 0.0
	for i: int in poly.size():
		if i == 0:
			out[0] = true
			continue
		var prev: Vector2 = poly[i - 1] as Vector2
		var pv: Vector2 = poly[i] as Vector2
		acc += prev.distance_to(pv)
		if acc <= _DOOR_STOOP_TAIL_M + 0.05:
			out[i] = true
	return out


## First geometric locus where an unintended cross occurs (for diagnostics).
static func _near_any_allowed_pt(p: Vector2, allowed: Array[Vector2], tol: float) -> bool:
	for q in allowed:
		if p.distance_to(q) <= tol:
			return true
	return false


static func _seg_pair_unintended_cross_loc(
		a0: Vector2, a1: Vector2, c0: Vector2, c1: Vector2,
		allowed: Array[Vector2], tol: float) -> Variant:
	var hit := false
	var ipt: Variant = Geometry2D.segment_intersects_segment(a0, a1, c0, c1)
	if ipt != null:
		hit = true
	elif _segments_colinear_overlap_v3(a0, a1, c0, c1):
		hit = true
	if not hit:
		return null
	var q: Vector2
	if ipt != null:
		q = ipt as Vector2 if ipt is Vector2 else Vector2(ipt as Vector2i)
	else:
		q = _overlap_mid_v3(a0, a1, c0, c1)
	if _near_any_allowed_pt(q, allowed, tol):
		return null
	if _segments_colinear_overlap_v3(a0, a1, c0, c1):
		var m1: Vector2 = _closest_on_seg_v3(a0, a1, c0)
		var m2: Vector2 = _closest_on_seg_v3(a0, a1, c1)
		if not _near_any_allowed_pt(m1, allowed, tol) and not _near_any_allowed_pt(m2, allowed, tol):
			return q
		return null
	return q


static func _closest_on_seg_v3(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab := b - a
	var ab_len2 := ab.length_squared()
	if ab_len2 < 1e-12:
		return a
	var t := clampf((p - a).dot(ab) / ab_len2, 0.0, 1.0)
	return a.lerp(b, t)


static func _segments_colinear_overlap_v3(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab := (b - a)
	if ab.length_squared() < 1e-12:
		return false
	var t_ab := ab / ab.length()
	var cd := (d - c)
	if cd.length_squared() < 1e-12:
		return false
	var t_cd := cd / cd.length()
	if absf(t_ab.dot(Vector2(-t_cd.y, t_cd.x))) > 0.02:
		return false
	var ca := (c - a)
	if absf(ca.dot(Vector2(-t_ab.y, t_ab.x))) > 0.05:
		return false
	var u0: float = 0.0
	var u1: float = ab.length()
	var vc: float = ca.dot(t_ab)
	var vd: float = (d - a).dot(t_ab)
	var lo: float = maxf(minf(u0, u1), minf(vc, vd))
	var hi: float = minf(maxf(u0, u1), maxf(vc, vd))
	return hi - lo > 0.02


static func _overlap_mid_v3(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var abn := (b - a).normalized()
	var ac0: float = (c - a).dot(abn)
	var ac1: float = (d - a).dot(abn)
	var lo: float = maxf(0.0, minf(ac0, ac1))
	var hi: float = minf(a.distance_to(b), maxf(ac0, ac1))
	return a + abn * ((lo + hi) * 0.5)


static func v3_first_crossing_debug(
		paths: Array, kinds: Array, junction_points: Array[Vector2], tol: float) -> Dictionary:
	## Intentional crossings: junction coordinates only (path endpoints that are not junctions must not mask Xings).
	var allowed: Array[Vector2] = []
	for jp in junction_points:
		allowed.append(jp)
	for i: int in paths.size():
		var pa: PackedVector2Array = _to_packed(paths[i])
		if pa.size() < 2:
			continue
		for j: int in range(i + 1, paths.size()):
			var pb: PackedVector2Array = _to_packed(paths[j])
			if pb.size() < 2:
				continue
			if not _aabbs_overlap(_poly_aabb(pa), _poly_aabb(pb), tol):
				continue
			for ia: int in pa.size() - 1:
				var a0: Vector2 = pa[ia]
				var a1: Vector2 = pa[ia + 1]
				for ib: int in pb.size() - 1:
					var b0: Vector2 = pb[ib]
					var b1: Vector2 = pb[ib + 1]
					var loc: Variant = _seg_pair_unintended_cross_loc(a0, a1, b0, b1, allowed, tol)
					if loc != null:
						var ka: String = str(kinds[i]) if i < kinds.size() else ""
						var kb: String = str(kinds[j]) if j < kinds.size() else ""
						return {
							"path_i": i,
							"path_j": j,
							"kind_i": ka,
							"kind_j": kb,
							"location": loc as Vector2,
							"seg_i": ia,
							"seg_j": ib,
						}
	return {}


## Same allowed-points model as `v3_crossings`: reject straight stoop→conn_end if it would fail V3 vs existing paths.
## On `own_path_id`, only the segment containing `conn_end` is skipped (attachment foot); other segments count.
static func door_connector_crosses_v3(
		network: Variant, stoop: Vector2, conn_end: Vector2, own_path_id: int, tol: float) -> bool:
	var jn: int = network.junction_point_count()
	var allowed: Array[Vector2] = []
	for ji: int in range(jn):
		allowed.append(network.junction_point_at(ji))
	for pid2: int in range(network.path_count()):
		var oth: PackedVector2Array = network.get_path_polyline(pid2)
		if oth.size() < 2:
			continue
		for ib: int in oth.size() - 1:
			var b0: Vector2 = oth[ib]
			var b1: Vector2 = oth[ib + 1]
			if pid2 == own_path_id:
				var foot: Vector2 = Geometry2D.get_closest_point_to_segment(conn_end, b0, b1)
				if foot.distance_to(conn_end) <= 0.35:
					continue
			var loc: Variant = _seg_pair_unintended_cross_loc(stoop, conn_end, b0, b1, allowed, tol)
			if loc != null:
				return true
	return false


static func build_path_segment_bucket_index(network: Variant) -> Dictionary:
	var buckets: Dictionary = {}
	var npaths: int = network.path_count()
	for pid2: int in range(npaths):
		var oth: PackedVector2Array = network.get_path_polyline(pid2)
		var nseg: int = maxi(0, oth.size() - 1)
		for ib: int in nseg:
			var b0: Vector2 = oth[ib]
			var b1: Vector2 = oth[ib + 1]
			var rec := {"path_id": pid2, "seg_i": ib, "a": b0, "b": b1}
			for cell in _v3_cells_for_segment(b0, b1):
				if not buckets.has(cell):
					buckets[cell] = []
				(buckets[cell] as Array).append(rec)
	return {"cell_m": _V3_SEG_GRID_CELL_M, "buckets": buckets}


static func _v3_cells_for_segment(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var x0: int = int(floor(mn.x / _V3_SEG_GRID_CELL_M))
	var x1: int = int(floor(mx.x / _V3_SEG_GRID_CELL_M))
	var y0: int = int(floor(mn.y / _V3_SEG_GRID_CELL_M))
	var y1: int = int(floor(mx.y / _V3_SEG_GRID_CELL_M))
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			out.append(Vector2i(cx, cy))
	return out


## Same as `door_connector_crosses_v3` with optional AABB prefilter on each other path (`path_bounds` from sampler).
static func door_connector_crosses_v3_prefilter(
		network: Variant,
		stoop: Vector2,
		conn_end: Vector2,
		own_path_id: int,
		tol: float,
		path_bounds: Array[Rect2],
		junction_points: Array[Vector2],
		seg_index: Dictionary = {}) -> bool:
	var allowed: Array[Vector2] = junction_points
	if allowed.is_empty():
		var jn: int = network.junction_point_count()
		if jn > 0:
			allowed = []
			allowed.resize(jn)
			for ji: int in range(jn):
				allowed[ji] = network.junction_point_at(ji)
	if not seg_index.is_empty() and seg_index.has("buckets"):
		return _door_connector_hits_segment_buckets(
			stoop, conn_end, own_path_id, tol, path_bounds, allowed, seg_index)
	var seg_bb := Rect2()
	var mn := Vector2(minf(stoop.x, conn_end.x), minf(stoop.y, conn_end.y))
	var mx := Vector2(maxf(stoop.x, conn_end.x), maxf(stoop.y, conn_end.y))
	seg_bb = Rect2(mn, mx - mn).grow(tol + 0.2)
	for pid2: int in range(network.path_count()):
		if pid2 < path_bounds.size() and not _aabbs_overlap(seg_bb, path_bounds[pid2], 0.0):
			continue
		var oth: PackedVector2Array = network.get_path_polyline(pid2)
		if oth.size() < 2:
			continue
		for ib: int in oth.size() - 1:
			var b0: Vector2 = oth[ib]
			var b1: Vector2 = oth[ib + 1]
			if pid2 == own_path_id:
				var foot: Vector2 = Geometry2D.get_closest_point_to_segment(conn_end, b0, b1)
				if foot.distance_to(conn_end) <= 0.35:
					continue
			var loc: Variant = _seg_pair_unintended_cross_loc(stoop, conn_end, b0, b1, allowed, tol)
			if loc != null:
				return true
	return false


static func _door_connector_hits_segment_buckets(
		stoop: Vector2,
		conn_end: Vector2,
		own_path_id: int,
		tol: float,
		path_bounds: Array[Rect2],
		allowed: Array[Vector2],
		seg_index: Dictionary) -> bool:
	var cell_m: float = float(seg_index.get("cell_m", _V3_SEG_GRID_CELL_M))
	var buckets: Dictionary = seg_index["buckets"] as Dictionary
	var mn := Vector2(minf(stoop.x, conn_end.x), minf(stoop.y, conn_end.y))
	var mx := Vector2(maxf(stoop.x, conn_end.x), maxf(stoop.y, conn_end.y))
	var seg_bb := Rect2(mn, mx - mn).grow(tol + 0.2)
	var ix0: int = int(floor(mn.x / cell_m)) - 1
	var ix1: int = int(floor(mx.x / cell_m)) + 1
	var iy0: int = int(floor(mn.y / cell_m)) - 1
	var iy1: int = int(floor(mx.y / cell_m)) + 1
	var seen: Dictionary = {}
	for cx in range(ix0, ix1 + 1):
		for cy in range(iy0, iy1 + 1):
			var key := Vector2i(cx, cy)
			if not buckets.has(key):
				continue
			for rec_v: Variant in buckets[key] as Array:
				var rec: Dictionary = rec_v as Dictionary
				var pid2: int = int(rec["path_id"])
				var seg_i: int = int(rec.get("seg_i", 0))
				var uid := "%d:%d" % [pid2, seg_i]
				if seen.has(uid):
					continue
				seen[uid] = true
				if pid2 < path_bounds.size() and not _aabbs_overlap(seg_bb, path_bounds[pid2], 0.0):
					continue
				var b0: Vector2 = rec["a"] as Vector2
				var b1: Vector2 = rec["b"] as Vector2
				if pid2 == own_path_id:
					var foot: Vector2 = Geometry2D.get_closest_point_to_segment(conn_end, b0, b1)
					if foot.distance_to(conn_end) <= 0.35:
						continue
				var loc: Variant = _seg_pair_unintended_cross_loc(stoop, conn_end, b0, b1, allowed, tol)
				if loc != null:
					return true
	return false


static func v5_debug_path(paths: Array, kinds: Array, path_index: int) -> Dictionary:
	var out := {
		"path_index": path_index,
		"kind": "",
		"rate_deg_per_m": 0.0,
		"window_i": -1,
		"window_j": -1,
		"arc_m": 0.0,
	}
	if path_index < 0 or path_index >= paths.size():
		return out
	out["kind"] = str(kinds[path_index]) if path_index < kinds.size() else ""
	var poly: PackedVector2Array = _to_packed(paths[path_index])
	var wk: Dictionary = _PathGrower.v5_worst_heading_window(poly)
	out["rate_deg_per_m"] = wk["rate_deg_per_m"]
	out["window_i"] = wk["i"]
	out["window_j"] = wk["j"]
	out["arc_m"] = wk["arc_m"]
	return out


static func v3_crossings(paths: Array, junction_points: Array[Vector2], tol: float) -> Array[String]:
	var viol: Array[String] = []
	var allowed: Array[Vector2] = []
	for jp in junction_points:
		allowed.append(jp)
	var seen: Dictionary = {}
	var npaths: int = paths.size()
	var aabbs: Array = [] # Rect2 per path index (-empty if <2 verts)
	aabbs.resize(npaths)
	var packed_cache: Array = []
	packed_cache.resize(npaths)
	for ia: int in range(npaths):
		var ppa: PackedVector2Array = _to_packed(paths[ia])
		packed_cache[ia] = ppa
		aabbs[ia] = _poly_aabb(ppa) if ppa.size() >= 2 else Rect2()
	var net_pair: Variant = _PathNetworkScr.new()
	for i: int in range(npaths):
		var pa: PackedVector2Array = packed_cache[i] as PackedVector2Array
		if pa.size() < 2:
			continue
		var abb_a: Rect2 = aabbs[i] as Rect2
		for j: int in range(i + 1, npaths):
			var pb: PackedVector2Array = packed_cache[j] as PackedVector2Array
			if pb.size() < 2:
				continue
			if not _aabbs_overlap(abb_a, aabbs[j] as Rect2, tol):
				continue
			if net_pair.crosses_unintended_two_paths(pa, pb, allowed, tol):
				var key := "%d-%d" % [mini(i, j), maxi(i, j)]
				if not seen.has(key):
					seen[key] = true
					viol.append("v3: unintended crossing paths %d vs %d" % [i, j])
	return viol


static func _poly_aabb(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var mn: Vector2 = poly[0]
	var mx: Vector2 = poly[0]
	for i: int in range(1, poly.size()):
		var p: Vector2 = poly[i]
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	return Rect2(mn, mx - mn)


static func _aabbs_overlap(a: Rect2, b: Rect2, margin: float) -> bool:
	var aa: Rect2 = a.grow(margin)
	var bb: Rect2 = b.grow(margin)
	return aa.intersects(bb, true)


## v3 for one path vs all others (`candidate` replaces `all_paths[path_index]` for allowed endpoints).
static func v3_crossings_for_path(
		all_paths: Array,
		path_index: int,
		candidate: PackedVector2Array,
		junction_points: Array[Vector2],
		tol: float) -> Array[String]:
	var allowed: Array[Vector2] = []
	for jp in junction_points:
		allowed.append(jp)
	var net_pair: Variant = _PathNetworkScr.new()
	var bb_c := _poly_aabb(candidate)
	if candidate.size() < 2:
		return []
	var other_aabbs: Array = []
	other_aabbs.resize(all_paths.size())
	for oi: int in all_paths.size():
		if oi == path_index:
			continue
		var op: PackedVector2Array = _to_packed(all_paths[oi])
		other_aabbs[oi] = _poly_aabb(op) if op.size() >= 2 else Rect2()
	for pj: int in all_paths.size():
		if pj == path_index:
			continue
		var other: PackedVector2Array = _to_packed(all_paths[pj])
		if other.size() < 2:
			continue
		if not _aabbs_overlap(bb_c, other_aabbs[pj] as Rect2, tol):
			continue
		if net_pair.crosses_unintended_two_paths(candidate, other, allowed, tol):
			return ["v3: unintended crossing paths %d vs %d" % [mini(path_index, pj), maxi(path_index, pj)]]
	return []


static func v2_path_vs_cottages(
		poly_raw: Variant,
		kind: String,
		cottages: Array,
		door_stoop: Variant,
		pond_center: Vector2,
		pond_path_clear_r: float) -> Array[String]:
	var as_arr: Array
	if poly_raw is Array:
		as_arr = poly_raw as Array
	else:
		var packed: PackedVector2Array = _to_packed(poly_raw)
		as_arr = []
		for i: int in range(packed.size()):
			as_arr.append(packed[i])
	var paths_one: Array = [as_arr]
	var kinds_one: Array = [kind]
	var stoop_arr: Array = []
	if kind == "door" and door_stoop != null:
		stoop_arr.append(door_stoop)
	return v2_paths_vs_cottages(paths_one, kinds_one, cottages, stoop_arr, pond_center, pond_path_clear_r)


static func _to_packed(raw: Variant) -> PackedVector2Array:
	if raw is PackedVector2Array:
		return raw as PackedVector2Array
	var arr: Array = raw as Array
	var out := PackedVector2Array()
	for p: Variant in arr:
		out.append(p as Vector2)
	return out


static func v4_connectivity(
		network_or_paths: Variant,
		door_stoops: Array,
		hero_stoop: Vector2,
		plaza_root: Vector2,
		tol: float = 0.6) -> Array[String]:
	var net: Variant
	if typeof(network_or_paths) == TYPE_DICTIONARY:
		var data: Dictionary = network_or_paths as Dictionary
		net = _network_from_paths(data.get("paths", []) as Array, data.get("kinds", []) as Array, tol)
	else:
		net = network_or_paths
	for ds: Variant in door_stoops:
		var p: Vector2 = ds as Vector2
		if not net.connected(p, plaza_root, tol):
			return ["v4: door stoop not connected to plaza"]
	if not net.connected(hero_stoop, plaza_root, tol):
		return ["v4: hero stoop not connected to plaza"]
	return []


static func _network_from_paths(paths: Array, kinds: Array, tol: float) -> Variant:
	var net: Variant = load("res://src/world/village_gen/path_network.gd").new()
	if paths.is_empty():
		return net
	var endpoints: Array[Vector2] = []
	var path_pairs: Array = []
	for p_raw: Variant in paths:
		var poly: PackedVector2Array = _to_packed(p_raw)
		if poly.size() < 2:
			continue
		path_pairs.append({"a": poly[0], "b": poly[poly.size() - 1]})
		endpoints.append(poly[0])
		endpoints.append(poly[poly.size() - 1])
	var reps: Array[Vector2] = []
	var cluster_of: Array[int] = []
	for p: Vector2 in endpoints:
		var cid: int = -1
		for j: int in reps.size():
			if (reps[j] - p).length() <= tol:
				cid = j
				reps[j] = reps[j].lerp(p, 0.5)
				break
		if cid < 0:
			cid = reps.size()
			reps.append(p)
		cluster_of.append(cid)
	for j: int in reps.size():
		net.add_junction(reps[j], [])
	var pair_idx := 0
	for i: int in paths.size():
		var poly: PackedVector2Array = _to_packed(paths[i])
		if poly.size() < 2:
			continue
		var k: String = str(kinds[i]) if i < kinds.size() else "primary"
		var ca: int = cluster_of[pair_idx * 2]
		var cb: int = cluster_of[pair_idx * 2 + 1]
		pair_idx += 1
		net.add_path(poly, k, ca, cb)
	return net


static func v5_shape(paths: Array, kinds: Array) -> Array[String]:
	var viol: Array[String] = []
	for pi: int in paths.size():
		var kind: String = str(kinds[pi]) if pi < kinds.size() else "primary"
		var poly: PackedVector2Array = _to_packed(paths[pi])
		var path_len: float = _poly_length(poly)
		if kind == "door":
			if path_len > 6.0 + 0.01:
				viol.append("v5: door path %d length %.2f > 6m" % [pi, path_len])
			continue
		if kind == "plaza":
			continue
		## DESIGN V5: max heading change per metre over any 1 m window (dense 0.3 m samples → use sliding window, not vertex×min(seg)).
		var rate: float = _PathGrower.max_heading_change_per_m(poly)
		if rate > 25.0 + 0.02:
			viol.append("v5: path %d heading change %.2f°/m > 25" % [pi, rate])
		if kind == "primary" or kind == "secondary":
			if path_len >= 15.0 - 0.01:
				var chord: float = poly[0].distance_to(poly[poly.size() - 1])
				var ratio: float = path_len / maxf(chord, 1e-4)
				if ratio < 1.03 - 1e-3 or ratio > 1.3 + 1e-3:
					viol.append("v5: path %d len/chord out of range" % pi)
				var dev := _max_lateral_dev(poly)
				if dev < 0.8 - 0.05:
					viol.append("v5: path %d lateral dev %.2f < 0.8" % [pi, dev])
	return viol


## Shared V6 facing dot (sampler + validator must agree).
static func door_facing_dot(spec: Dictionary, stoop: Vector2, conn_end: Vector2) -> float:
	var door_n: Vector2 = VillageBackdrop.cottage_door(spec)[1] as Vector2
	var toward: Vector2 = conn_end - stoop
	if toward.length_squared() < 1e-10:
		return -1.0
	return door_n.dot(toward.normalized())


static func v6_doors_face_paths(cottages: Array, door_connections: Array) -> Array[String]:
	var viol: Array[String] = []
	var n: int = mini(cottages.size(), door_connections.size())
	for i: int in n:
		var spec: Dictionary = cottages[i] as Dictionary
		var poly: PackedVector2Array = _to_packed(door_connections[i])
		if poly.size() < 2:
			viol.append("v6: door %d connection too short" % i)
			continue
		var dotv: float = door_facing_dot(spec, poly[0], poly[poly.size() - 1])
		if dotv < 0.7 - 1e-4:
			viol.append("v6: door %d facing dot %.2f < 0.7" % [i, dotv])
	return viol


static func all(layout_like: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var cottages: Array = layout_like.get("cottages", []) as Array
	var paths: Array = layout_like.get("paths", []) as Array
	var kinds: Array = layout_like.get("kinds", layout_like.get("path_kinds", [])) as Array
	var door_stoops: Array = layout_like.get("door_stoops", []) as Array
	var door_connections: Array = layout_like.get("door_connections", []) as Array
	var plaza_keep: Rect2 = layout_like.get("plaza_keep_clear", Rect2()) as Rect2
	var hero_rect: Rect2 = layout_like.get("hero_rect", Rect2()) as Rect2
	var pond_c: Vector2 = layout_like.get("pond_center", Vector2.ZERO) as Vector2
	var pond_cr: float = float(layout_like.get("pond_clear_r", 0.0))
	var g: Vector2 = layout_like.get("g", Vector2(0.0, -18.0)) as Vector2
	var max_corner: float = float(layout_like.get("max_corner_m", 54.0))
	var min_gap: float = float(layout_like.get("min_gap_m", 4.0))
	var junctions: Array = layout_like.get("junction_points", []) as Array
	var junction_vec: Array[Vector2] = []
	for j_raw: Variant in junctions:
		junction_vec.append(j_raw as Vector2)
	var tol: float = float(layout_like.get("junction_tol", 0.3))
	var hero_stoop: Vector2 = layout_like.get("hero_stoop", Vector2.ZERO) as Vector2
	var plaza_root: Vector2 = layout_like.get("plaza_root", Vector2.ZERO) as Vector2

	out["v1"] = v1_cottages(cottages, plaza_keep, hero_rect, pond_c, pond_cr, g, max_corner, min_gap)
	out["v2"] = v2_paths_vs_cottages(paths, kinds, cottages, door_stoops, pond_c, pond_cr)
	out["v3"] = v3_crossings(paths, junction_vec, tol)
	var net_var: Variant = layout_like.get("network", layout_like.get("paths_network", null))
	out["v4"] = v4_connectivity(net_var if net_var != null else {"paths": paths, "kinds": kinds},
		door_stoops, hero_stoop, plaza_root)
	out["v5"] = v5_shape(paths, kinds)
	out["v6"] = v6_doors_face_paths(cottages, door_connections)
	return out


static func _rect_corners(r: Rect2) -> Array[Vector2]:
	return [
		r.position,
		r.position + Vector2(r.size.x, 0.0),
		r.position + r.size,
		r.position + Vector2(0.0, r.size.y),
	]


## Wall-to-wall clearance for axis-aligned exteriors (interior overlap → 0; edge overlap → 1-D gap).
static func wall_gap_too_small(a: Rect2, b: Rect2, min_gap: float) -> bool:
	return exterior_separation_m(a, b) < min_gap


static func exterior_separation_m(a: Rect2, b: Rect2) -> float:
	var ax0: float = a.position.x
	var ay1: float = a.position.y + a.size.y
	var ax1: float = a.position.x + a.size.x
	var ay0: float = a.position.y
	var bx0: float = b.position.x
	var bx1: float = b.position.x + b.size.x
	var by0: float = b.position.y
	var by1: float = b.position.y + b.size.y
	var ox0: float = maxf(ax0, bx0)
	var ox1: float = minf(ax1, bx1)
	var oy0: float = maxf(ay0, by0)
	var oy1: float = minf(ay1, by1)
	var x_ov: float = ox1 - ox0
	var y_ov: float = oy1 - oy0
	var d: float
	if x_ov > 1e-4 and y_ov > 1e-4:
		d = 0.0
	elif x_ov > 1e-4:
		d = maxf(0.0, maxf(by0 - ay1, ay0 - by1))
	elif y_ov > 1e-4:
		d = maxf(0.0, maxf(bx0 - ax1, ax0 - bx1))
	else:
		var dx: float = maxf(0.0, maxf(bx0 - ax1, ax0 - bx1))
		var dy: float = maxf(0.0, maxf(by0 - ay1, ay0 - by1))
		d = sqrt(dx * dx + dy * dy) if dx > 1e-6 and dy > 1e-6 else maxf(dx, dy)
	return d


static func _poly_length(poly: PackedVector2Array) -> float:
	var L: float = 0.0
	for i: int in maxi(0, poly.size() - 1):
		L += poly[i].distance_to(poly[i + 1])
	return L


static func _max_lateral_dev(poly: PackedVector2Array) -> float:
	if poly.size() < 2:
		return 0.0
	var a: Vector2 = poly[0]
	var b: Vector2 = poly[poly.size() - 1]
	var best: float = 0.0
	for i: int in range(1, poly.size() - 1):
		var p: Vector2 = poly[i]
		var d: float = Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
		best = maxf(best, d)
	return best
