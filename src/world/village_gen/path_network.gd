## Path network for village generator v3: polylines, kinds, junctions, and graph queries.
##
## `edges()` node numbering:
##   - Node `0 .. J-1`: junctions in `add_junction` order (position = junction point).
##   - Node `J ..`: path endpoints not tied to a junction, assigned in `add_path` order
##     (each path may create 0, 1, or 2 such nodes at its loose ends).
##   - One undirected edge per path between its resolved start and end node ids
##     (order normalized to (min,max) in the returned array).
class_name VillagePathNetwork
extends RefCounted

const _GRID_CELL := 2.0

var _paths: Array = [] # PackedVector2Array each
var _kinds: Array[String] = []
var _start_junction: Array[int] = []
var _end_junction: Array[int] = []

## Each entry: { "point": Vector2, "path_ids": Array[int] }
var _junctions: Array = []


func add_junction(p: Vector2, path_ids: Array = []) -> int:
	var jid := _junctions.size()
	_junctions.append({"point": p, "path_ids": path_ids.duplicate()})
	return jid


func add_path(
		poly: PackedVector2Array,
		kind: String,
		start_junction_id: int = -1,
		end_junction_id: int = -1) -> int:
	var pid := _paths.size()
	_paths.append(poly.duplicate())
	_kinds.append(kind)
	_start_junction.append(start_junction_id)
	_end_junction.append(end_junction_id)
	return pid


## Replace geometry for an existing path id (junction bookkeeping unchanged).
func set_path_polyline(path_id: int, poly: PackedVector2Array) -> void:
	assert(path_id >= 0 and path_id < _paths.size())
	_paths[path_id] = poly.duplicate()


func set_end_junction(path_id: int, junction_id: int) -> void:
	assert(path_id >= 0 and path_id < _paths.size())
	_end_junction[path_id] = junction_id


## Drop paths added after `count` (e.g. undo a split tail and any branch added on a failed grow).
func truncate_paths(count: int) -> void:
	while _paths.size() > count:
		_paths.pop_back()
		_kinds.pop_back()
		_start_junction.pop_back()
		_end_junction.pop_back()


## Insert a junction on path `path_id` at the closest point to `q` (within `tol` m).
## Replaces that path with [start → q] and appends [q → end] as a new path of the same kind.
## Returns the junction id at `q`, or -1 if the split is invalid (off polyline / degenerate).
func split_path_at_point(path_id: int, q: Vector2, tol: float = 0.35) -> int:
	assert(path_id >= 0 and path_id < _paths.size())
	var poly: PackedVector2Array = _paths[path_id] as PackedVector2Array
	if poly.size() < 2:
		return -1
	var best_d: float = INF
	var best_i: int = 0
	var best_pt: Vector2 = poly[0]
	for i: int in range(poly.size() - 1):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var foot: Vector2 = Geometry2D.get_closest_point_to_segment(q, a, b)
		var d: float = foot.distance_to(q)
		if d < best_d:
			best_d = d
			best_i = i
			best_pt = foot
	if best_d > tol:
		return -1
	## Door foot on path endpoint: splitting would yield a degenerate segment — attach to existing junction.
	var p_first: Vector2 = poly[0]
	var p_last: Vector2 = poly[poly.size() - 1]
	if best_pt.distance_to(p_first) <= tol + 1e-4 and _start_junction[path_id] >= 0:
		return _start_junction[path_id]
	if best_pt.distance_to(p_last) <= tol + 1e-4 and _end_junction[path_id] >= 0:
		return _end_junction[path_id]
	## Reuse junction if one already sits near the split point.
	var jid: int = -1
	for j: int in _junctions.size():
		var jp: Vector2 = _junctions[j]["point"] as Vector2
		if jp.distance_to(best_pt) <= tol:
			jid = j
			break
	if jid < 0:
		jid = add_junction(best_pt, [])
	else:
		best_pt = _junctions[jid]["point"] as Vector2

	var sj: int = _start_junction[path_id]
	var ej: int = _end_junction[path_id]
	var kind: String = _kinds[path_id]

	var part_a := PackedVector2Array()
	for k: int in range(best_i + 1):
		part_a.append(poly[k])
	if part_a.is_empty() or best_pt.distance_to(part_a[part_a.size() - 1]) > 1e-4:
		part_a.append(best_pt)

	var part_b := PackedVector2Array()
	if best_pt.distance_to(poly[best_i + 1]) > 1e-4:
		part_b.append(best_pt)
	for k2: int in range(best_i + 1, poly.size()):
		part_b.append(poly[k2])

	if part_a.size() < 2 or part_b.size() < 2:
		return -1

	_paths[path_id] = part_a
	_end_junction[path_id] = jid
	add_path(part_b, kind, jid, ej)
	return jid


func kinds_array() -> Array[String]:
	return _kinds.duplicate()


func get_path_polyline(path_id: int) -> PackedVector2Array:
	assert(path_id >= 0 and path_id < _paths.size())
	return (_paths[path_id] as PackedVector2Array).duplicate()


func get_path_kind(path_id: int) -> String:
	assert(path_id >= 0 and path_id < _paths.size())
	return _kinds[path_id]


func path_count() -> int:
	return _paths.size()


func junction_point_count() -> int:
	return _junctions.size()


func junction_point_at(id: int) -> Vector2:
	assert(id >= 0 and id < _junctions.size())
	return _junctions[id]["point"] as Vector2


func start_junction_id(path_id: int) -> int:
	assert(path_id >= 0 and path_id < _paths.size())
	return _start_junction[path_id]


func end_junction_id(path_id: int) -> int:
	assert(path_id >= 0 and path_id < _paths.size())
	return _end_junction[path_id]


func length(path_id: int) -> float:
	assert(path_id >= 0 and path_id < _paths.size())
	return _poly_length(_paths[path_id] as PackedVector2Array)


func point_at(path_id: int, s: float) -> Dictionary:
	assert(path_id >= 0 and path_id < _paths.size())
	var poly: PackedVector2Array = _paths[path_id]
	if poly.size() < 2:
		return {"point": poly[0] if not poly.is_empty() else Vector2.ZERO,
			"tangent": Vector2.RIGHT, "normal": Vector2.UP}
	var total := _poly_length(poly)
	if total <= 1e-8:
		return {"point": poly[0], "tangent": Vector2.RIGHT, "normal": Vector2.UP}
	var sp: float = clampf(s, 0.0, total)
	var acc: float = 0.0
	var nseg: int = poly.size() - 1
	for i: int in nseg:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var sl: float = a.distance_to(b)
		if acc + sl >= sp - 1e-5 or i == nseg - 1:
			var t: float = 0.0 if sl < 1e-8 else (sp - acc) / sl
			t = clampf(t, 0.0, 1.0)
			var p: Vector2 = a.lerp(b, t)
			var tan: Vector2 = (b - a)
			if tan.length_squared() < 1e-10:
				tan = Vector2.RIGHT
			else:
				tan = tan.normalized()
			var n := Vector2(-tan.y, tan.x)
			return {"point": p, "tangent": tan, "normal": n}
		acc += sl
	var a2: Vector2 = poly[poly.size() - 2]
	var b2: Vector2 = poly[poly.size() - 1]
	var tan2 := (b2 - a2).normalized() if (b2 - a2).length_squared() > 1e-10 else Vector2.RIGHT
	return {"point": b2, "tangent": tan2, "normal": Vector2(-tan2.y, tan2.x)}


func nearest_point(
		p: Vector2,
		exclude_ids: Array = [],
		kinds_filter: Array = []) -> Dictionary:
	var best_dist: float = INF
	var best: Dictionary = {}
	var ex: Dictionary = {}
	for id_raw in exclude_ids:
		ex[int(id_raw)] = true
	var kind_ok := func(kind: String) -> bool:
		if kinds_filter.is_empty():
			return true
		return (kinds_filter as Array).has(kind)

	for pid: int in _paths.size():
		if ex.has(pid):
			continue
		if not kind_ok.call(_kinds[pid]):
			continue
		var poly: PackedVector2Array = _paths[pid]
		var nseg: int = maxi(0, poly.size() - 1)
		var acc: float = 0.0
		for i: int in nseg:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[i + 1]
			var ab := b - a
			var ab_len_sq := ab.length_squared()
			var t: float = 0.0
			if ab_len_sq > 1e-12:
				t = clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
			var q: Vector2 = a.lerp(b, t)
			var d: float = p.distance_to(q)
			var seg_len: float = sqrt(ab_len_sq)
			if d < best_dist:
				var tan: Vector2 = ab.normalized() if ab_len_sq > 1e-12 else Vector2.RIGHT
				var s_at: float = acc + t * seg_len
				best_dist = d
				best = {
					"path_id": pid,
					"s": s_at,
					"point": q,
					"tangent": tan,
					"normal": Vector2(-tan.y, tan.x),
					"distance": d,
				}
			acc += seg_len
	return best


## Intentional cross loci for growth-time checks — **junction coordinates only**.
## Path polyline endpoints that are not junctions must not mask a real intersection (false negatives vs validator).
func v3_allowed_points() -> Array[Vector2]:
	var allowed: Array[Vector2] = []
	for j: int in _junctions.size():
		var jp: Vector2 = _junctions[j]["point"] as Vector2
		allowed.append(jp)
	return allowed


## Same geometric test as `crosses_unintended`, but caller supplies `allowed` (junction coords for growth / v3).
func crosses_unintended_with_allowed(
		poly: PackedVector2Array,
		allowed_points: Array[Vector2],
		tol: float = 0.3,
		ignore_ids: Array = []) -> bool:
	var ign: Dictionary = {}
	for id_raw in ignore_ids:
		ign[int(id_raw)] = true
	var buckets: Dictionary = _build_segment_buckets(ign)
	var nseg: int = maxi(0, poly.size() - 1)
	for i: int in nseg:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		for cell in _cells_for_segment(a, b):
			if not buckets.has(cell):
				continue
			for rec in buckets[cell] as Array:
				var p0: Vector2 = rec["a"]
				var p1: Vector2 = rec["b"]
				if _segment_hits_segment(a, b, p0, p1, allowed_points, tol):
					return true
	return false


func crosses_unintended(
		poly: PackedVector2Array,
		allowed_points: Array[Vector2],
		tol: float = 0.3,
		ignore_ids: Array = []) -> bool:
	return crosses_unintended_with_allowed(poly, allowed_points, tol, ignore_ids)


## Explain why `crosses_unintended_with_allowed` returned false for `query` vs path `other_path_id`.
## For debugging: which bucket hits, ignore_ids, and first "suppressed" hit near an allowed point.
func crosses_unintended_why_false(
		query: PackedVector2Array,
		other_path_id: int,
		allowed_points: Array[Vector2],
		tol: float = 0.3,
		ignore_ids: Array = []) -> Dictionary:
	var out := {
		"would_cross": false,
		"reason": "",
		"other_path_id": other_path_id,
		"ignore_other": false,
		"buckets_overlap": 0,
		"segment_checks": 0,
		"first_suppressed": {},
	}
	var ign: Dictionary = {}
	for id_raw in ignore_ids:
		ign[int(id_raw)] = true
	out["ignore_other"] = ign.has(other_path_id)
	if other_path_id < 0 or other_path_id >= _paths.size():
		out["reason"] = "invalid_other_path_id"
		return out
	if query.size() < 2:
		out["reason"] = "query_too_short"
		return out
	## Only segments from `other_path_id` (not full spatial hash).
	var opoly: PackedVector2Array = _paths[other_path_id] as PackedVector2Array
	var nseg_o: int = maxi(0, opoly.size() - 1)
	var bucket_other: Dictionary = {}
	for seg_j: int in nseg_o:
		var c0: Vector2 = opoly[seg_j]
		var c1: Vector2 = opoly[seg_j + 1]
		for cell in _cells_for_segment(c0, c1):
			if not bucket_other.has(cell):
				bucket_other[cell] = []
			(bucket_other[cell] as Array).append({"seg_i": seg_j, "a": c0, "b": c1})
	var qn: int = maxi(0, query.size() - 1)
	for qi: int in qn:
		var a: Vector2 = query[qi]
		var b: Vector2 = query[qi + 1]
		var seen_cells: Dictionary = {}
		for cell in _cells_for_segment(a, b):
			if not bucket_other.has(cell):
				continue
			if seen_cells.has(cell):
				continue
			seen_cells[cell] = true
			out["buckets_overlap"] = int(out["buckets_overlap"]) + 1
			for rec in bucket_other[cell] as Array:
				out["segment_checks"] = int(out["segment_checks"]) + 1
				var c: Vector2 = rec["a"]
				var d: Vector2 = rec["b"]
				if _segment_hits_segment_explain(a, b, c, d, allowed_points, tol, out):
					out["would_cross"] = true
					out["reason"] = "geometric_hit"
					return out
	if int(out["buckets_overlap"]) == 0:
		out["reason"] = "no_spatial_bucket_overlap_2m_grid"
	else:
		out["reason"] = "hits_suppressed_near_allowed_or_colinear_allowed"
	return out


func crosses_unintended_two_paths(
		poly_a: PackedVector2Array,
		poly_b: PackedVector2Array,
		allowed_points: Array[Vector2],
		tol: float = 0.3) -> bool:
	if poly_a.size() < 2 or poly_b.size() < 2:
		return false
	for ia: int in poly_a.size() - 1:
		var sa: Vector2 = poly_a[ia]
		var sb: Vector2 = poly_a[ia + 1]
		for ib: int in poly_b.size() - 1:
			var sc: Vector2 = poly_b[ib]
			var sd: Vector2 = poly_b[ib + 1]
			if _segment_hits_segment(sa, sb, sc, sd, allowed_points, tol):
				return true
	return false


func _segment_hits_segment_explain(
		a: Vector2, b: Vector2, c: Vector2, d: Vector2,
		allowed: Array[Vector2], tol: float,
		out: Dictionary) -> bool:
	var hit: bool = false
	var ipt: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
	if ipt != null:
		hit = true
	elif _segments_colinear_overlap(a, b, c, d):
		hit = true
	if not hit:
		return false
	var q: Vector2
	if ipt != null:
		if ipt is Vector2:
			q = ipt as Vector2
		else:
			q = Vector2(ipt as Vector2i)
	else:
		q = _overlap_mid(a, b, c, d)
	if _near_any_allowed(q, allowed, tol):
		if not (out["first_suppressed"] as Dictionary).has("q"):
			(out["first_suppressed"] as Dictionary)["q"] = q
			(out["first_suppressed"] as Dictionary)["stage"] = "midpoint"
		return false
	if _segments_colinear_overlap(a, b, c, d):
		var m1: Vector2 = _closest_on_segment(a, b, c)
		var m2: Vector2 = _closest_on_segment(a, b, d)
		if not _near_any_allowed(m1, allowed, tol) and not _near_any_allowed(m2, allowed, tol):
			return true
		if not (out["first_suppressed"] as Dictionary).has("q"):
			(out["first_suppressed"] as Dictionary)["q"] = q
			(out["first_suppressed"] as Dictionary)["stage"] = "colinear_endpoints_not_both_allowed"
		return false
	return true


func _segment_hits_segment(
		a: Vector2, b: Vector2, c: Vector2, d: Vector2,
		allowed: Array[Vector2], tol: float) -> bool:
	var hit: bool = false
	var ipt: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
	if ipt != null:
		hit = true
	elif _segments_colinear_overlap(a, b, c, d):
		hit = true
	if not hit:
		return false
	## Intersection locus: use midpoint for segment-segment from Godot, else overlap center.
	var q: Vector2
	if ipt != null:
		if ipt is Vector2:
			q = ipt as Vector2
		else:
			q = Vector2(ipt as Vector2i)
	else:
		q = _overlap_mid(a, b, c, d)
	if _near_any_allowed(q, allowed, tol):
		return false
	## If intersection is only along an interval, require both ends of overlap to be allowed
	## when colinear overlap; otherwise still flag.
	if _segments_colinear_overlap(a, b, c, d):
		var m1: Vector2 = _closest_on_segment(a, b, c)
		var m2: Vector2 = _closest_on_segment(a, b, d)
		if not _near_any_allowed(m1, allowed, tol) and not _near_any_allowed(m2, allowed, tol):
			return true
		return false
	return true


static func _closest_on_segment(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab := b - a
	var ab_len2 := ab.length_squared()
	if ab_len2 < 1e-12:
		return a
	var t: float = clampf((p - a).dot(ab) / ab_len2, 0.0, 1.0)
	return a.lerp(b, t)


static func _segments_colinear_overlap(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
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
	## 1D overlap on line
	var u0: float = 0.0
	var u1: float = ab.length()
	var vc: float = ca.dot(t_ab)
	var vd: float = (d - a).dot(t_ab)
	var lo: float = maxf(minf(u0, u1), minf(vc, vd))
	var hi: float = minf(maxf(u0, u1), maxf(vc, vd))
	return hi - lo > 0.02


static func _overlap_mid(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var ab := (b - a).normalized()
	var ac0: float = (c - a).dot(ab)
	var ac1: float = (d - a).dot(ab)
	var lo: float = maxf(0.0, minf(ac0, ac1))
	var hi: float = minf(a.distance_to(b), maxf(ac0, ac1))
	var mid_u: float = (lo + hi) * 0.5
	return a + ab * mid_u


static func _near_any_allowed(p: Vector2, allowed: Array[Vector2], tol: float) -> bool:
	for q in allowed:
		if p.distance_to(q) <= tol:
			return true
	return false


func _build_segment_buckets(ignore_path_ids: Dictionary) -> Dictionary:
	var buckets: Dictionary = {}
	for path_id: int in _paths.size():
		if ignore_path_ids.has(path_id):
			continue
		var poly: PackedVector2Array = _paths[path_id]
		var nseg: int = maxi(0, poly.size() - 1)
		for seg_i: int in nseg:
			var p0: Vector2 = poly[seg_i]
			var p1: Vector2 = poly[seg_i + 1]
			var rec := {"path_id": path_id, "seg_i": seg_i, "a": p0, "b": p1}
			for c in _cells_for_segment(p0, p1):
				if not buckets.has(c):
					buckets[c] = []
				(buckets[c] as Array).append(rec)
	return buckets


func _cells_for_segment(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var x0: int = int(floor(mn.x / _GRID_CELL))
	var x1: int = int(floor(mx.x / _GRID_CELL))
	var y0: int = int(floor(mn.y / _GRID_CELL))
	var y1: int = int(floor(mx.y / _GRID_CELL))
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			out.append(Vector2i(cx, cy))
	return out


func min_distance_to_paths(
		poly: PackedVector2Array,
		ignore_ids: Array = [],
		trim_ends_m: float = 0.0) -> float:
	var ign: Dictionary = {}
	for id_raw in ignore_ids:
		ign[int(id_raw)] = true
	var best: float = INF
	var nseg: int = maxi(0, poly.size() - 1)
	for i: int in nseg:
		var sa: Vector2 = poly[i]
		var sb: Vector2 = poly[i + 1]
		var a: Vector2 = sa
		var b: Vector2 = sb
		var seg_len: float = sa.distance_to(sb)
		if seg_len > trim_ends_m * 2.0 + 1e-3:
			a = sa.move_toward(sb, trim_ends_m)
			b = sb.move_toward(sa, trim_ends_m)
		for pid: int in _paths.size():
			if ign.has(pid):
				continue
			var opoly: PackedVector2Array = _paths[pid]
			var m1: int = maxi(0, opoly.size() - 1)
			for j: int in m1:
				var oa: Vector2 = opoly[j]
				var ob: Vector2 = opoly[j + 1]
				var d: float = _segment_segment_dist(a, b, oa, ob)
				best = minf(best, d)
	return best


static func _segment_segment_dist(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var best: float = INF
	best = minf(best, a.distance_to(c))
	best = minf(best, a.distance_to(d))
	best = minf(best, b.distance_to(c))
	best = minf(best, b.distance_to(d))
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	best = minf(best, Geometry2D.get_closest_point_to_segment(a, c, d).distance_to(a))
	best = minf(best, Geometry2D.get_closest_point_to_segment(b, c, d).distance_to(b))
	best = minf(best, Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c))
	best = minf(best, Geometry2D.get_closest_point_to_segment(d, a, b).distance_to(d))
	return best


func to_layout_paths() -> Array:
	var out: Array = []
	for poly in _paths:
		var arr: Array[Vector2] = []
		for p in poly as PackedVector2Array:
			arr.append(p as Vector2)
		out.append(arr)
	return out


func edges() -> Array[Vector2i]:
	var jcount := _junctions.size()
	var next_ep := jcount
	var node_a: Array[int] = []
	var node_b: Array[int] = []
	for pid: int in _paths.size():
		var poly: PackedVector2Array = _paths[pid]
		var sj: int = _start_junction[pid]
		var ej: int = _end_junction[pid]
		var ns: int = sj if sj >= 0 else next_ep
		if sj < 0:
			next_ep += 1
		var ne: int = ej if ej >= 0 else next_ep
		if ej < 0:
			next_ep += 1
		if poly.is_empty():
			node_a.append(ns)
			node_b.append(ne)
			continue
		node_a.append(ns)
		node_b.append(ne)
	var out: Array[Vector2i] = []
	for i: int in node_a.size():
		var u: int = node_a[i]
		var v: int = node_b[i]
		if u == v:
			continue
		if u > v:
			var t: int = u
			u = v
			v = t
		out.append(Vector2i(u, v))
	return out


func _build_graph_positions() -> Dictionary:
	var jcount := _junctions.size()
	var next_ep := jcount
	var pos: Dictionary = {}
	for j: int in jcount:
		pos[j] = _junctions[j]["point"] as Vector2
	var path_u: Array[int] = []
	var path_v: Array[int] = []
	for pid: int in _paths.size():
		var poly: PackedVector2Array = _paths[pid]
		var sj: int = _start_junction[pid]
		var ej: int = _end_junction[pid]
		var ns: int = sj if sj >= 0 else next_ep
		if sj < 0:
			if not poly.is_empty():
				pos[ns] = poly[0]
			next_ep += 1
		var ne: int = ej if ej >= 0 else next_ep
		if ej < 0:
			if not poly.is_empty():
				pos[ne] = poly[poly.size() - 1]
			next_ep += 1
		path_u.append(ns)
		path_v.append(ne)
	return {"pos": pos, "path_u": path_u, "path_v": path_v}


func connected(from_point: Vector2, to_point: Vector2, tol: float = 0.6) -> bool:
	var d := _build_graph_positions()
	var pos: Dictionary = d["pos"] as Dictionary
	var nodes_from: Array[int] = _nodes_near(pos, from_point, tol)
	var nodes_to: Array[int] = _nodes_near(pos, to_point, tol)
	if nodes_from.is_empty() or nodes_to.is_empty():
		return false
	var adj := _adjacency_from_paths(d)
	for start in nodes_from:
		if adj.is_empty():
			break
		var visited: Dictionary = {}
		var q: Array[int] = [int(start)]
		visited[int(start)] = true
		while not q.is_empty():
			var u: int = q.pop_front()
			if u in nodes_to:
				return true
			for v in adj[u] as Array:
				var vi: int = int(v)
				if not visited.has(vi):
					visited[vi] = true
					q.append(vi)
	return false


func connectivity_ok(
		required_points: Array[Vector2],
		root_point: Vector2,
		tol: float = 0.6) -> bool:
	var d := _build_graph_positions()
	var pos: Dictionary = d["pos"] as Dictionary
	var roots: Array[int] = _nodes_near(pos, root_point, tol)
	if roots.is_empty():
		return false
	var adj := _adjacency_from_paths(d)
	var visited: Dictionary = {}
	var q: Array[int] = []
	for r in roots:
		var ri: int = int(r)
		if not visited.has(ri):
			visited[ri] = true
			q.append(ri)
	while not q.is_empty():
		var u: int = q.pop_front()
		for v in adj[u] as Array:
			var vi: int = int(v)
			if not visited.has(vi):
				visited[vi] = true
				q.append(vi)
	for rp in required_points:
		var ok := false
		for k in pos.keys():
			var kk: int = int(k)
			if visited.has(kk) and (pos[kk] as Vector2).distance_to(rp as Vector2) <= tol:
				ok = true
				break
		if not ok:
			return false
	return true


static func _nodes_near(pos: Dictionary, p: Vector2, tol: float) -> Array[int]:
	var out: Array[int] = []
	for k in pos.keys():
		var kk: int = int(k)
		if (pos[kk] as Vector2).distance_to(p) <= tol:
			out.append(kk)
	return out


func _adjacency_from_paths(d: Dictionary) -> Dictionary:
	var adj: Dictionary = {}
	var pos: Dictionary = d["pos"] as Dictionary
	for k in pos.keys():
		adj[int(k)] = []
	var pu: Array = d["path_u"]
	var pv: Array = d["path_v"]
	for i: int in pu.size():
		var u: int = int(pu[i])
		var v: int = int(pv[i])
		(adj[u] as Array).append(v)
		(adj[v] as Array).append(u)
	return adj


static func _poly_length(poly: PackedVector2Array) -> float:
	var L: float = 0.0
	for i: int in maxi(0, poly.size() - 1):
		L += poly[i].distance_to(poly[i + 1])
	return L
