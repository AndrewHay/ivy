class_name WandererRouteGraph
extends RefCounted

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")

var houses: Array = []
var _nodes: PackedVector2Array = PackedVector2Array()
var _adj: Array = []  # Array of Array[{to:int, cost:float}]
var _segments: Array = []  # [Vector2, Vector2]
var bridge_count: int = 0
var node_count: int = 0
var _disabled: bool = false
var _params: WandererParams = null
var _node_component: PackedInt32Array = PackedInt32Array()


static func build(layout: VillageLayout, params: WandererParams) -> RefCounted:
	var hs: Array[Dictionary] = []
	for spec in layout.cottages:
		var door_info := VillageBackdrop.cottage_door(spec as Dictionary)
		hs.append({
			"name": String(spec.get("id", spec.get("name", "?"))),
			"door": door_info[0] as Vector2,
			"normal": door_info[1] as Vector2,
			"spec": spec,
		})
	var polylines: Array = []
	for p in layout.paths:
		polylines.append(p)
	var pond := {}
	if layout.pond_placed:
		pond = {
			"center": layout.pond_center,
			"clearance": layout.pond_path_clearance_m,
			"radius": VillagePondSite.MEAN_WATER_RADIUS_M,
		}
	var rects: Array = []
	for spec in layout.cottages:
		rects.append(VillageBackdrop.cottage_exterior_rect(spec as Dictionary))
	return from_raw(hs, polylines, params, pond, rects)


static func from_raw(
		house_in: Array,
		polylines: Array,
		params: WandererParams,
		pond: Dictionary = {},
		cottage_rects: Array = [],
) -> RefCounted:
	var g = (load("res://src/presentation/wanderer/wanderer_route_graph.gd") as GDScript).new()
	g._params = params
	if polylines.is_empty():
		g._disabled = true
		push_warning("WandererRouteGraph: no paths — wanderer disabled")
		return g
	g._build_base_graph(polylines)
	g._snap_endpoints(polylines, params.snap_m)
	var terminals: Array = g._collect_terminals(polylines)
	g._attach_houses(house_in, params, cottage_rects)
	g._bridge_components(terminals, params, pond, cottage_rects)
	g._finalize_reachability()
	if g.reachable_houses().size() < 2:
		g._disabled = true
		push_warning("WandererRouteGraph: fewer than 2 reachable houses")
	return g


func is_disabled() -> bool:
	return _disabled


func reachable_houses() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(houses.size()):
		if houses[i].get("reachable", false):
			out.append(i)
	return out


func candidates_from(house_idx: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if house_idx < 0 or house_idx >= houses.size():
		return out
	var comp: int = houses[house_idx].get("component", -1)
	for i in range(houses.size()):
		if i == house_idx:
			continue
		var h: Dictionary = houses[i]
		if h.get("reachable", false) and int(h.get("component", -1)) == comp:
			out.append(i)
	return out


func route(from_house: int, to_house: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if from_house < 0 or to_house < 0 or from_house >= houses.size() or to_house >= houses.size():
		return out
	var a: int = int(houses[from_house].get("node", -1))
	var b: int = int(houses[to_house].get("node", -1))
	if a < 0 or b < 0:
		return out
	var path_nodes := _dijkstra(a, b)
	for ni in path_nodes:
		out.append(_nodes[ni])
	var door_b: Vector2 = houses[to_house].get("door_spot", Vector2.ZERO)
	if path_nodes.is_empty() or _nodes[path_nodes[path_nodes.size() - 1]].distance_to(door_b) > 0.01:
		out.append(door_b)
	out = _dedupe_route(out)
	return out


func segments() -> Array:
	return _segments.duplicate(true)


func _build_base_graph(polylines: Array) -> void:
	for poly in polylines:
		var pts: Array = poly as Array
		if pts.size() < 2:
			continue
		var prev := -1
		for p in pts:
			var v := p as Vector2
			var idx := _find_or_add_node(v)
			if prev >= 0 and prev != idx:
				_add_edge(prev, idx)
			prev = idx


func _snap_endpoints(polylines: Array, snap_m: float) -> void:
	for poly in polylines:
		var pts: Array = poly as Array
		if pts.is_empty():
			continue
		for end_i in [0, pts.size() - 1]:
			var e := pts[end_i] as Vector2
			var e_idx := _find_node_near(e, 0.01)
			if e_idx < 0:
				continue
			var best_dist := snap_m + 1.0
			var best_q := Vector2.ZERO
			var best_split := [-1, -1, -1]
			for other_poly in polylines:
				if other_poly == poly:
					continue
				var opts: Array = other_poly as Array
				for si in range(opts.size() - 1):
					var a := opts[si] as Vector2
					var b := opts[si + 1] as Vector2
					var q := _closest_point_on_segment(e, a, b)
					var d := e.distance_to(q)
					if d <= snap_m and d < best_dist:
						best_dist = d
						best_q = q
						best_split = [_node_index(a), _node_index(b), si]
			if best_dist <= snap_m:
				var q_idx := _find_or_add_node(best_q)
				if best_split[0] >= 0 and best_split[1] >= 0:
					if best_split[0] != best_split[1] and _nodes[best_split[0]].distance_to(best_q) > 1e-3 \
							and _nodes[best_split[1]].distance_to(best_q) > 1e-3:
						_split_edge_at(best_split[0], best_split[1], q_idx)
				_add_edge(e_idx, q_idx)


func _attach_houses(house_in: Array, params: WandererParams, cottage_rects: Array) -> void:
	houses.clear()
	for i in range(house_in.size()):
		var h: Dictionary = house_in[i].duplicate(true)
		var door: Vector2 = h["door"]
		var normal: Vector2 = h["normal"]
		var stoop := door + normal * params.door_stoop_m
		var door_spot := door + normal * params.door_stand_off_m
		h["door_exterior"] = door
		h["stoop"] = stoop
		h["door_spot"] = door_spot
		h["reachable"] = false
		h["component"] = -1
		h["node"] = -1
		var best := -1
		var best_d := params.door_snap_m + 1.0
		for ni in range(_nodes.size()):
			var d := _nodes[ni].distance_to(stoop)
			if d <= params.door_snap_m and d < best_d:
				best_d = d
				best = ni
		if best >= 0:
			var door_idx := _find_or_add_node(door_spot)
			_add_edge(best, door_idx)
			_add_segment(_nodes[best], door_spot)
			h["node"] = door_idx
			h["reachable"] = true
		houses.append(h)


func _bridge_components(
		terminals: Array,
		params: WandererParams,
		pond: Dictionary,
		cottage_rects: Array,
) -> void:
	var safety := 32
	while safety > 0:
		safety -= 1
		_relabel_node_components()
		var comps := _distinct_house_components()
		if comps.size() <= 1:
			break
		var best_pair: Array = []
		var best_d := params.bridge_max_m + 1.0
		for a in comps:
			for b in comps:
				if a == b:
					continue
				for ta in terminals:
					if _component_of_node(int(ta)) != int(a):
						continue
					for tb in terminals:
						if _component_of_node(int(tb)) != int(b):
							continue
						var pa := _nodes[int(ta)]
						var pb := _nodes[int(tb)]
						var d := pa.distance_to(pb)
						if d <= params.bridge_max_m and d < best_d:
							if _bridge_rejected(pa, pb, params, pond, cottage_rects):
								continue
							best_d = d
							best_pair = [int(ta), int(tb), pa, pb]
		if best_pair.is_empty():
			break
		_connect_bridge(int(best_pair[0]), int(best_pair[1]), best_pair[2], best_pair[3], params)
		bridge_count += 1


func _connect_bridge(a: int, b: int, pa: Vector2, pb: Vector2, params: WandererParams) -> void:
	var hero := params.hero_xz
	var ra := pa.distance_to(hero)
	var rb := pb.distance_to(hero)
	var use_arc := ra >= params.bridge_min_ring_m and rb >= params.bridge_min_ring_m \
			and absf(ra - rb) <= params.bridge_max_delta_r_m
	var prev := a
	if use_arc:
		var arc_pts := _arc_points(hero, pa, pb, deg_to_rad(10.0))
		for pt in arc_pts:
			var idx := _find_or_add_node(pt)
			_add_edge(prev, idx)
			_add_segment(_nodes[prev], _nodes[idx])
			prev = idx
	else:
		_add_edge(a, b)
		_add_segment(pa, pb)
		return
	_add_edge(prev, b)
	_add_segment(_nodes[prev], _nodes[b])


func _arc_points(center: Vector2, a: Vector2, b: Vector2, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var aa := atan2(a.y - center.y, a.x - center.x)
	var ab := atan2(b.y - center.y, b.x - center.x)
	var delta := fposmod(ab - aa + PI, TAU) - PI
	if delta < 0:
		delta = -delta
		var t := aa
		aa = ab
		ab = t
		delta = -delta
	var r := a.distance_to(center)
	var steps := maxi(1, int(ceil(absf(delta) / step)))
	for i in range(1, steps):
		var ang := aa + delta * float(i) / float(steps)
		out.append(center + Vector2(cos(ang), sin(ang)) * r)
	return out


func _bridge_rejected(pa: Vector2, pb: Vector2, params: WandererParams, pond: Dictionary, cottage_rects: Array) -> bool:
	var hero := params.hero_xz
	for t in [0.0, 0.5, 1.0]:
		var p := pa.lerp(pb, t)
		if p.distance_to(hero) < params.hero_keepout_m:
			return true
	if not pond.is_empty():
		var pc: Vector2 = pond.get("center", Vector2.ZERO)
		var pr: float = float(pond.get("radius", 0.0)) + float(pond.get("clearance", params.pond_path_clearance_m))
		for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
			if pa.lerp(pb, t).distance_to(pc) < pr:
				return true
	for rect_v in cottage_rects:
		var rect: Rect2 = rect_v as Rect2
		var grown := rect.grow(params.cottage_bridge_grow_m)
		for t in [0.0, 0.5, 1.0]:
			if grown.has_point(pa.lerp(pb, t)):
				return true
	return false


func _finalize_reachability() -> void:
	_relabel_node_components()
	node_count = _nodes.size()
	for i in range(houses.size()):
		var h: Dictionary = houses[i]
		if not h.get("reachable", false):
			continue
		var ni: int = int(h.get("node", -1))
		h["component"] = _node_comp(ni)
		houses[i] = h


func _relabel_node_components() -> void:
	_node_component.resize(_nodes.size())
	for i in range(_node_component.size()):
		_node_component[i] = -1
	var comp_id := 0
	for i in range(_nodes.size()):
		if _node_component[i] >= 0:
			continue
		var q: Array = [i]
		_node_component[i] = comp_id
		var head := 0
		while head < q.size():
			var u: int = q[head]
			head += 1
			for e in _adj[u]:
				var v: int = int(e["to"])
				if _node_component[v] < 0:
					_node_component[v] = comp_id
					q.append(v)
		comp_id += 1


func _node_comp(node: int) -> int:
	if node < 0 or node >= _node_component.size():
		return -1
	return _node_component[node]


func _distinct_house_components() -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for h in houses:
		if not h.get("reachable", false):
			continue
		var c: int = _node_comp(int(h.get("node", -1)))
		if c >= 0 and not seen.has(c):
			seen[c] = true
			out.append(c)
	return out


func _component_of_node(start: int) -> int:
	return _node_comp(start)


func _dijkstra(from: int, to: int) -> PackedInt32Array:
	var n := _nodes.size()
	var dist: Array = []
	dist.resize(n)
	var prev: Array = []
	prev.resize(n)
	for i in range(n):
		dist[i] = INF
		prev[i] = -1
	dist[from] = 0.0
	var done: Dictionary = {}
	while done.size() < n:
		var u := -1
		var best := INF
		for i in range(n):
			if done.has(i):
				continue
			if float(dist[i]) < best:
				best = float(dist[i])
				u = i
		if u < 0 or best == INF:
			break
		done[u] = true
		if u == to:
			break
		for e in _adj[u]:
			var v: int = int(e["to"])
			var nd := float(dist[u]) + float(e["cost"])
			if nd < float(dist[v]):
				dist[v] = nd
				prev[v] = u
	var path := PackedInt32Array()
	var cur := to
	if prev[to] < 0 and from != to:
		return path
	while cur >= 0:
		path.insert(0, cur)
		if cur == from:
			break
		cur = int(prev[cur])
	return path


func _find_or_add_node(v: Vector2) -> int:
	var idx := _find_node_near(v, 1e-3)
	if idx >= 0:
		return idx
	idx = _nodes.size()
	_nodes.append(v)
	_adj.append([])
	return idx


func _find_node_near(v: Vector2, eps: float) -> int:
	for i in range(_nodes.size()):
		if _nodes[i].distance_to(v) <= eps:
			return i
	return -1


func _node_index(v: Vector2) -> int:
	return _find_node_near(v, 1e-3)


func _add_edge(a: int, b: int) -> void:
	if a < 0 or b < 0 or a == b:
		return
	var c := _nodes[a].distance_to(_nodes[b])
	if c < 1e-6:
		return
	if not _has_edge(a, b):
		_adj[a].append({"to": b, "cost": c})
		_adj[b].append({"to": a, "cost": c})
		_add_segment(_nodes[a], _nodes[b])


func _has_edge(a: int, b: int) -> bool:
	for e in _adj[a]:
		if int(e["to"]) == b:
			return true
	return false


func _split_edge_at(a: int, b: int, mid: int) -> void:
	_remove_edge(a, b)
	_add_edge(a, mid)
	_add_edge(mid, b)


func _remove_edge(a: int, b: int) -> void:
	_adj[a] = _adj[a].filter(func(e): return int(e["to"]) != b)
	_adj[b] = _adj[b].filter(func(e): return int(e["to"]) != a)
	_segments = _segments.filter(func(s): return not (
		(s[0] as Vector2).is_equal_approx(_nodes[a]) and (s[1] as Vector2).is_equal_approx(_nodes[b])
		or (s[0] as Vector2).is_equal_approx(_nodes[b]) and (s[1] as Vector2).is_equal_approx(_nodes[a])
	))


func _add_segment(a: Vector2, b: Vector2) -> void:
	_segments.append([a, b])


func _collect_terminals(polylines: Array) -> Array:
	var terminals: Array = []
	for poly in polylines:
		var pts: Array = poly as Array
		if pts.is_empty():
			continue
		for end_i in [0, pts.size() - 1]:
			var idx := _find_node_near(pts[end_i] as Vector2, 0.05)
			if idx >= 0:
				terminals.append(idx)
	return terminals


func _closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var t := ab.dot(p - a) / maxf(ab.length_squared(), 1e-9)
	t = clampf(t, 0.0, 1.0)
	return a + ab * t


static func leg_from_present(route: PackedVector2Array, present: Vector2, stoop: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(present)
	if present.distance_to(stoop) >= 0.01:
		out.append(stoop)
	if route.size() < 2:
		return out
	for i in range(1, route.size()):
		var pt := route[i]
		if out[out.size() - 1].distance_to(pt) < 0.01:
			continue
		out.append(pt)
	return out


func _dedupe_route(route: PackedVector2Array) -> PackedVector2Array:
	if route.size() < 2:
		return route
	var out := PackedVector2Array()
	out.append(route[0])
	for i in range(1, route.size()):
		if route[i].distance_to(out[out.size() - 1]) >= 0.01:
			out.append(route[i])
	return out
