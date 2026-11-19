extends RefCounted

## SG-9(d) growth probe on the relief test article (IMPLEMENTATION.md SD-MESH-19.5; ivy-b1e.6).
##
## Pure measurement: takes a grown PlantData (and the tips' end positions) and judges it against
## the ANALYTIC article, sharp-edged, never against the proxy under test. Geometry mirrors
## tools/build_relief_article.py (same table). Used by test/slow/test_relief_article_probe.gd;
## its measurements are unit-tested in test/test_relief_article_probe_metrics.gd.
##
## Criteria (SD-MESH-19.5):
##   D0 evidence    >= 20 rib/rail crossings (a stem with attached nodes on both sides),
##                  >= 5 stems with nodes in N1's floor zone, >= 1 in M1's
##   D1 floor       of front-side floor-zone nodes, >= 95 % within effective contact (0.045 m) of
##                  the floor plane AND median distance to the floor <= d_contact (0.02 m)
##                  (ratified in ivy-b1e.21)
##   D2 spanning    no front-side footprint node ATTACHED to the growth surface (|proxy phi| <=
##                  0.045 m, read from the variant's own baked SDF) farther than 0.05 m from the
##                  nearest article surface; floating far nodes are reported, not gated. Without a
##                  proxy field every node counts as attached. (ratified in ivy-b1e.21)
##   D3 solid       no tip end with analytic phi < 0; no node deeper than 0.01 m inside
##   D4 slot        no node inside S1 deeper than 0.02 m behind z = 0
## D5 (determinism) and D6 (falsifiability on the bounding box) compare runs; the test does that.
## Reported, not gated: turn angles at inside corners, a distance histogram per feature, the
## share of floor-zone nodes within 0.02 m and 0.02-0.045 m off the floor (AR-MESH-20.5), the
## floor p95, a flat-wall control (share within 0.02 m, median, p95), floating far nodes, and
## (filled in by the test) the share of SurfaceQuery.nearest() calls returned unrefined.

# --- SD-MESH-19.5 table (glTF = Godot axes; front face z = 0 facing +z; ground y = 0) -----------
const WALL_X := Vector2(-1.80, 1.80)
const WALL_Y := Vector2(0.0, 3.00)
const WALL_BACK_Z := -0.45
const RIB_CENTRES: Array[float] = [-1.575, -1.125, -0.675, -0.225]
const RIB_HALF := 0.075
const PROUD := 0.10
const RAIL_X := Vector2(-1.65, -0.15)
const RAIL_Y := Vector2(1.425, 1.575)
## [id, x0, x1, y0, y1, depth]
const N1 := ["N1", 0.30, 0.90, 0.60, 1.50, 0.20]
const M1 := ["M1", 1.20, 1.36, 0.60, 0.90, 0.06]
const S1 := ["S1", 1.50, 1.54, 1.50, 2.50, 0.10]
## [x0, x1, y0, y1, proud]
const U1 := [0.30, 0.90, 2.00, 2.60, 0.02]

# --- Criteria ---------------------------------------------------------------------------------
const D_CONTACT := 0.02  # SD-MESH-19.5 D1, IvyParams contact distance
## SurfaceQuery.effective_contact on a MeshSdf structure: contact + h/2 (AR-MESH-20.5).
const EFFECTIVE_CONTACT := 0.045
const FLOOR_ZONE_INSET := 0.075
const D0_MIN_CROSSINGS := 20
const D0_MIN_N1_STEMS := 5
const D0_MIN_M1_STEMS := 1
const D1_MIN_SHARE := 0.95
const D2_MAX_SPAN := 0.05
const D3_MAX_DEPTH := 0.01
const D4_MAX_DEPTH := 0.02
## Nodes behind this plane are on the article's back side: midway between N1's floor (z = -0.20,
## the deepest front relief) and the back face (z = -0.45).
const BACK_SIDE_Z := -0.325
## A crossing counts attached nodes up to this far beside the rib or rail.
const CROSSING_REACH := 0.30
## A node within this distance of an inside-corner line is "at" the corner (turn angles).
const CORNER_REACH := 0.05
## Flat-wall control strips (ivy-b1e.21, reported): plain front face between R4 and N1, and
## between N1 and M1.
const FLAT_X_A := Vector2(-0.15, 0.30)
const FLAT_X_B := Vector2(0.90, 1.20)
const HIST_EDGES: Array[float] = [0.005, 0.01, 0.02, 0.03, 0.045, 0.05, 0.10]

static var _solid: Array[AABB] = []
static var _air: Array[AABB] = []


# ------------------------------------------------------------------------------------------------
# Analytic article
# ------------------------------------------------------------------------------------------------

static func _box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> AABB:
	return AABB(Vector3(x0, y0, z0), Vector3(x1 - x0, y1 - y0, z1 - z0))


static func _recesses() -> Array:
	return [N1, M1, S1]


static func bays() -> Array:
	var out: Array = []
	for k in RIB_CENTRES.size() - 1:
		out.append(Vector2(RIB_CENTRES[k] + RIB_HALF, RIB_CENTRES[k + 1] - RIB_HALF))
	return out


## The article as boxes whose union is the solid, and boxes whose union is the air around it
## (both exact, interiors disjoint), so phi is the true distance on both sides.
static func _build() -> void:
	if not _solid.is_empty():
		return
	var xs: Array[float] = [WALL_X.x, WALL_X.y]
	var ys: Array[float] = [WALL_Y.x, WALL_Y.y]
	for r in _recesses():
		for v in [r[1], r[2]]:
			if not xs.has(v):
				xs.append(v)
		for v in [r[3], r[4]]:
			if not ys.has(v):
				ys.append(v)
	xs.sort()
	ys.sort()
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var cx := 0.5 * (xs[i] + xs[i + 1])
			var cy := 0.5 * (ys[j] + ys[j + 1])
			var top := 0.0
			for r in _recesses():
				if r[1] < cx and cx < r[2] and r[3] < cy and cy < r[4]:
					top = -float(r[5])
					_air.append(_box(xs[i], xs[i + 1], ys[j], ys[j + 1], top, 0.0))
			_solid.append(_box(xs[i], xs[i + 1], ys[j], ys[j + 1], WALL_BACK_Z, top))
	for c in RIB_CENTRES:
		_solid.append(_box(c - RIB_HALF, c + RIB_HALF, WALL_Y.x, WALL_Y.y, 0.0, PROUD))
	_solid.append(_box(RAIL_X.x, RAIL_X.y, RAIL_Y.x, RAIL_Y.y, 0.0, PROUD))
	_solid.append(_box(U1[0], U1[1], U1[2], U1[3], 0.0, U1[4]))
	# Air in the 0.10 m layer in front of the wall face, between the proud parts.
	var r1_left: float = RIB_CENTRES[0] - RIB_HALF
	var r4_right: float = RIB_CENTRES[-1] + RIB_HALF
	_air.append(_box(WALL_X.x, r1_left, WALL_Y.x, WALL_Y.y, 0.0, PROUD))
	for b in bays():
		_air.append(_box(b.x, b.y, WALL_Y.x, RAIL_Y.x, 0.0, PROUD))
		_air.append(_box(b.x, b.y, RAIL_Y.y, WALL_Y.y, 0.0, PROUD))
	_air.append(_box(r4_right, WALL_X.y, WALL_Y.x, WALL_Y.y, U1[4], PROUD))
	_air.append(_box(r4_right, U1[0], WALL_Y.x, WALL_Y.y, 0.0, U1[4]))
	_air.append(_box(U1[1], WALL_X.y, WALL_Y.x, WALL_Y.y, 0.0, U1[4]))
	_air.append(_box(U1[0], U1[1], WALL_Y.x, U1[2], 0.0, U1[4]))
	_air.append(_box(U1[0], U1[1], U1[3], WALL_Y.y, 0.0, U1[4]))
	# Everything outside the article's bounding box.
	var far := 20.0
	_air.append(_box(-far, WALL_X.x, -far, far, -far, far))
	_air.append(_box(WALL_X.y, far, -far, far, -far, far))
	_air.append(_box(-far, far, -far, WALL_Y.x, -far, far))
	_air.append(_box(-far, far, WALL_Y.y, far, -far, far))
	_air.append(_box(-far, far, -far, far, -far, WALL_BACK_Z))
	_air.append(_box(-far, far, -far, far, PROUD, far))


static func _dist_to_box(p: Vector3, b: AABB) -> float:
	var lo := b.position
	var hi := b.end
	var d := Vector3(maxf(maxf(lo.x - p.x, 0.0), p.x - hi.x), maxf(maxf(lo.y - p.y, 0.0), p.y - hi.y),
		maxf(maxf(lo.z - p.z, 0.0), p.z - hi.z))
	return d.length()


static func _strictly_inside(p: Vector3, b: AABB) -> bool:
	var lo := b.position
	var hi := b.end
	return p.x > lo.x and p.x < hi.x and p.y > lo.y and p.y < hi.y and p.z > lo.z and p.z < hi.z


## Exact signed distance to the sharp article: > 0 in air, < 0 inside solid.
static func phi(p: Vector3) -> float:
	_build()
	for b in _solid:
		if _strictly_inside(p, b):
			var depth := INF
			for a in _air:
				depth = minf(depth, _dist_to_box(p, a))
			return -depth
	var d := INF
	for b in _solid:
		d = minf(d, _dist_to_box(p, b))
	return d


# ------------------------------------------------------------------------------------------------
# Footprints and features
# ------------------------------------------------------------------------------------------------

static func _footprint(id: String, x0: float, x1: float, y0: float, y1: float, floor_z: float,
		zone_y0: float, zone_y1: float) -> Dictionary:
	return {"id": id, "x0": x0, "x1": x1, "y0": y0, "y1": y1, "floor_z": floor_z,
		"zx0": x0 + FLOOR_ZONE_INSET, "zx1": x1 - FLOOR_ZONE_INSET, "zy0": zone_y0, "zy1": zone_y1}


## The recess footprints: six panels, N1 and M1. A floor zone is the part of the floor at least
## FLOOR_ZONE_INSET from every side wall of that recess (a panel's open bottom at the ground and
## open top at the wall's top are not walls).
static func footprints() -> Array:
	var out: Array = []
	var bs := bays()
	for k in bs.size():
		var b: Vector2 = bs[k]
		out.append(_footprint("panel_%d_low" % (k + 1), b.x, b.y, WALL_Y.x, RAIL_Y.x, 0.0,
			WALL_Y.x, RAIL_Y.x - FLOOR_ZONE_INSET))
		out.append(_footprint("panel_%d_high" % (k + 1), b.x, b.y, RAIL_Y.y, WALL_Y.y, 0.0,
			RAIL_Y.y + FLOOR_ZONE_INSET, WALL_Y.y))
	for r in [N1, M1]:
		out.append(_footprint(r[0], r[1], r[2], r[3], r[4], -float(r[5]),
			float(r[3]) + FLOOR_ZONE_INSET, float(r[4]) - FLOOR_ZONE_INSET))
	return out


static func footprint(id: String) -> Dictionary:
	for fp in footprints():
		if fp["id"] == id:
			return fp
	return {}


static func in_footprint(fp: Dictionary, p: Vector3) -> bool:
	return p.x >= fp["x0"] and p.x <= fp["x1"] and p.y >= fp["y0"] and p.y <= fp["y1"]


static func in_floor_zone(fp: Dictionary, p: Vector3) -> bool:
	return p.x >= fp["zx0"] and p.x <= fp["zx1"] and p.y >= fp["zy0"] and p.y <= fp["zy1"]


## Which part of the article a node's projection on the wall plane falls on.
static func feature_of(p: Vector3) -> String:
	if p.x < WALL_X.x or p.x > WALL_X.y or p.y < WALL_Y.x or p.y > WALL_Y.y:
		return "off_article"
	for fp in footprints():
		if in_footprint(fp, p):
			return "panel" if String(fp["id"]).begins_with("panel") else String(fp["id"])
	for c in RIB_CENTRES:
		if absf(p.x - c) <= RIB_HALF:
			return "rib_rail"
	if p.x >= RAIL_X.x and p.x <= RAIL_X.y and p.y >= RAIL_Y.x and p.y <= RAIL_Y.y:
		return "rib_rail"
	if p.x >= S1[1] and p.x <= S1[2] and p.y >= S1[3] and p.y <= S1[4]:
		return "S1"
	if p.x >= U1[0] and p.x <= U1[1] and p.y >= U1[2] and p.y <= U1[3]:
		return "U1"
	return "flat"


## Every concave edge of the article the stems pass ([a, b] segments), as in
## tools/build_relief_article.py inside_corner_lines().
static func inside_corner_lines() -> Array:
	var out: Array = []
	var y0 := WALL_Y.x
	var y1 := WALL_Y.y
	out.append([Vector3(RIB_CENTRES[0] - RIB_HALF, y0, 0.0), Vector3(RIB_CENTRES[0] - RIB_HALF, y1, 0.0)])
	out.append([Vector3(RIB_CENTRES[-1] + RIB_HALF, y0, 0.0), Vector3(RIB_CENTRES[-1] + RIB_HALF, y1, 0.0)])
	for b in bays():
		for xc in [b.x, b.y]:
			out.append([Vector3(xc, y0, 0.0), Vector3(xc, RAIL_Y.x, 0.0)])
			out.append([Vector3(xc, RAIL_Y.y, 0.0), Vector3(xc, y1, 0.0)])
			for yr in [RAIL_Y.x, RAIL_Y.y]:
				out.append([Vector3(xc, yr, 0.0), Vector3(xc, yr, PROUD)])
		for yr in [RAIL_Y.x, RAIL_Y.y]:
			out.append([Vector3(b.x, yr, 0.0), Vector3(b.y, yr, 0.0)])
	for r in [N1, M1]:
		var zf := -float(r[5])
		out.append([Vector3(r[1], r[3], zf), Vector3(r[1], r[4], zf)])
		out.append([Vector3(r[2], r[3], zf), Vector3(r[2], r[4], zf)])
		out.append([Vector3(r[1], r[3], zf), Vector3(r[2], r[3], zf)])
		out.append([Vector3(r[1], r[4], zf), Vector3(r[2], r[4], zf)])
		for cx in [r[1], r[2]]:
			for cy in [r[3], r[4]]:
				out.append([Vector3(cx, cy, zf), Vector3(cx, cy, 0.0)])
	return out


static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _pct(sorted_values: Array, f: float) -> float:
	if sorted_values.is_empty():
		return NAN
	return float(sorted_values[clampi(int(sorted_values.size() * f), 0, sorted_values.size() - 1)])


# ------------------------------------------------------------------------------------------------
# The probe
# ------------------------------------------------------------------------------------------------

## Diagnostic: at most this many deep nodes are kept as samples.
const D3_SAMPLES := 12


## Measures a grown plant. `tip_ends` is every tip's current position (live or not).
## `proxy_phi` (optional, Vector3 -> float), e.g. the baked SDF of the growth surface, is read at
## every node too: nodes it puts more than D3_MAX_DEPTH inside are counted separately, which tells
## a stem inside the proxy from a probe that disagrees with the proxy.
static func analyse(plant: PlantData, tip_ends: Array, proxy_phi: Callable = Callable()) -> Dictionary:
	_build()
	var fps := footprints()
	var corners := inside_corner_lines()
	# Per-stem polylines, in emission order.
	var by_tip: Dictionary = {}
	for i in plant.segment_count():
		var t := int(plant.seg_tip[i])
		if not by_tip.has(t):
			by_tip[t] = []
		by_tip[t].append(i)
	var nodes := 0
	var floor_nodes := 0
	var floor_ok := 0
	var floor_band := 0
	var floor_behind := 0
	var floor_eff := 0
	var floor_d: Array = []
	var flat_d: Array = []
	var far_nodes := 0
	var far_max := 0.0
	var floating_far := 0
	var floating_max := 0.0
	var deep_nodes := 0
	var deep_in_proxy := 0
	var deep_by_feature: Dictionary = {}
	var deep_samples: Array = []
	var slot_nodes := 0
	var below_ground := 0
	var n1_tips: Dictionary = {}
	var m1_tips: Dictionary = {}
	var crossings := 0
	var turns: Array = []
	var hist: Dictionary = {}
	var tip_ids: Array = by_tip.keys()
	tip_ids.sort()
	for tip_id in tip_ids:
		var segs: Array = by_tip[tip_id]
		var pts: Array = [plant.seg_a[segs[0]]]
		for i in segs:
			pts.append(plant.seg_b[i])
		var rib_left: Array = []
		var rib_right: Array = []
		for _k in RIB_CENTRES.size():
			rib_left.append(false)
			rib_right.append(false)
		var rail_below := false
		var rail_above := false
		for p in pts:
			nodes += 1
			var d := phi(p)
			if p.y < 0.0:
				below_ground += 1
			var feat := feature_of(p)
			if d < -D3_MAX_DEPTH:
				deep_nodes += 1
				deep_by_feature[feat] = int(deep_by_feature.get(feat, 0)) + 1
				if deep_samples.size() < D3_SAMPLES:
					deep_samples.append([p, d, tip_id])
			var pphi := float(proxy_phi.call(p)) if proxy_phi.is_valid() else 0.0
			if pphi < -D3_MAX_DEPTH:
				deep_in_proxy += 1
			# D2 (ivy-b1e.21): a node is on the growth surface when the proxy's own field puts it
			# within effective contact; without a proxy field every node counts as attached.
			var attached := absf(pphi) <= EFFECTIVE_CONTACT
			# The footprints are projections on the front wall plane, so only nodes on the front
			# side are judged against them (ivy-9bt7: stems on the back face were counted as
			# floor-zone nodes 0.25 m behind N1's floor and as nodes threaded into S1).
			var front: bool = p.z > BACK_SIDE_Z
			if p.z >= 0.0 and feat == "flat" and ((p.x >= FLAT_X_A.x and p.x <= FLAT_X_A.y)
					or (p.x >= FLAT_X_B.x and p.x <= FLAT_X_B.y)):
				flat_d.append(absf(d))
			if front and p.x >= S1[1] and p.x <= S1[2] and p.y >= S1[3] and p.y <= S1[4] \
					and p.z < -D4_MAX_DEPTH:
				slot_nodes += 1
			if not hist.has(feat):
				hist[feat] = []
				for _b in HIST_EDGES.size() + 2:
					hist[feat].append(0)
			var bin := 0
			if d >= 0.0:
				bin = 1
				while bin <= HIST_EDGES.size() and d > HIST_EDGES[bin - 1]:
					bin += 1
			hist[feat][bin] += 1
			for fp in fps:
				if not front or not in_footprint(fp, p):
					continue
				if attached:
					if d > D2_MAX_SPAN:
						far_nodes += 1
					far_max = maxf(far_max, d)
				elif d > D2_MAX_SPAN:
					floating_far += 1
					floating_max = maxf(floating_max, d)
				if in_floor_zone(fp, p):
					floor_nodes += 1
					var dz := absf(p.z - float(fp["floor_z"]))
					floor_d.append(dz)
					if dz <= EFFECTIVE_CONTACT:
						floor_eff += 1
					if p.z < float(fp["floor_z"]) - D_CONTACT:
						floor_behind += 1
					if dz <= D_CONTACT:
						floor_ok += 1
					elif dz <= EFFECTIVE_CONTACT:
						floor_band += 1
					if fp["id"] == "N1":
						n1_tips[tip_id] = true
					elif fp["id"] == "M1":
						m1_tips[tip_id] = true
				break
			if absf(d) > EFFECTIVE_CONTACT or p.y < WALL_Y.x or p.y > WALL_Y.y:
				continue
			for k in RIB_CENTRES.size():
				var xl: float = RIB_CENTRES[k] - RIB_HALF
				var xr: float = RIB_CENTRES[k] + RIB_HALF
				if p.x >= xl - CROSSING_REACH and p.x < xl:
					rib_left[k] = true
				elif p.x > xr and p.x <= xr + CROSSING_REACH:
					rib_right[k] = true
			if p.x >= RAIL_X.x and p.x <= RAIL_X.y:
				if p.y >= RAIL_Y.x - CROSSING_REACH and p.y < RAIL_Y.x:
					rail_below = true
				elif p.y > RAIL_Y.y and p.y <= RAIL_Y.y + CROSSING_REACH:
					rail_above = true
		for k in RIB_CENTRES.size():
			if rib_left[k] and rib_right[k]:
				crossings += 1
		if rail_below and rail_above:
			crossings += 1
		# Turn angles between consecutive segments meeting at an inside corner.
		for s in range(1, segs.size()):
			var i: int = segs[s - 1]
			var j: int = segs[s]
			var q: Vector3 = plant.seg_b[i]
			if q.distance_to(plant.seg_a[j]) > 1e-5:
				continue
			var at_corner := false
			for line in corners:
				if _dist_to_segment(q, line[0], line[1]) <= CORNER_REACH:
					at_corner = true
					break
			if not at_corner:
				continue
			var u: Vector3 = (plant.seg_b[i] - plant.seg_a[i]).normalized()
			var v: Vector3 = (plant.seg_b[j] - plant.seg_a[j]).normalized()
			turns.append(rad_to_deg(acos(clampf(u.dot(v), -1.0, 1.0))))
	var tips_inside := 0
	for e in tip_ends:
		if phi(e) < 0.0:
			tips_inside += 1
	turns.sort()
	floor_d.sort()
	flat_d.sort()
	var flat_ok := 0
	for v in flat_d:
		if float(v) <= D_CONTACT:
			flat_ok += 1
	var r := {
		"segments": plant.segment_count(),
		"length": plant.total_length,
		"stems": tip_ids.size(),
		"nodes": nodes,
		"below_ground": below_ground,
		"crossings": crossings,
		"n1_stems": n1_tips.size(),
		"m1_stems": m1_tips.size(),
		"floor_nodes": floor_nodes,
		"d1_share": float(floor_ok) / floor_nodes if floor_nodes > 0 else 0.0,
		"floor_band_share": float(floor_band) / floor_nodes if floor_nodes > 0 else 0.0,
		"floor_behind_share": float(floor_behind) / floor_nodes if floor_nodes > 0 else 0.0,
		"d1_share_effective": float(floor_eff) / floor_nodes if floor_nodes > 0 else 0.0,
		"d1_median": _pct(floor_d, 0.5),
		"floor_p95": _pct(floor_d, 0.95),
		"flat_nodes": flat_d.size(),
		"flat_share": float(flat_ok) / flat_d.size() if not flat_d.is_empty() else 0.0,
		"flat_median": _pct(flat_d, 0.5),
		"flat_p95": _pct(flat_d, 0.95),
		"d2_far_nodes": far_nodes,
		"d2_max": far_max,
		"d2_floating_far_nodes": floating_far,
		"d2_floating_max": floating_max,
		"d3_tips_inside": tips_inside,
		"d3_nodes_deep": deep_nodes,
		"d3_by_feature": deep_by_feature,
		"d3_samples": deep_samples,
		"d3_nodes_deep_in_proxy": deep_in_proxy if proxy_phi.is_valid() else -1,
		"d4_slot_nodes": slot_nodes,
		"turn_n": turns.size(),
		"turn_p95": _pct(turns, 0.95),
		"turn_max": turns[-1] if not turns.is_empty() else NAN,
		"histogram": hist,
	}
	r["d0_pass"] = crossings >= D0_MIN_CROSSINGS and n1_tips.size() >= D0_MIN_N1_STEMS \
			and m1_tips.size() >= D0_MIN_M1_STEMS
	r["d1_pass"] = floor_nodes > 0 and float(r["d1_share_effective"]) >= D1_MIN_SHARE \
			and float(r["d1_median"]) <= D_CONTACT
	r["d2_pass"] = far_nodes == 0
	r["d3_pass"] = tips_inside == 0 and deep_nodes == 0
	r["d4_pass"] = slot_nodes == 0
	return r


static func _v(ok: bool) -> String:
	return "PASS" if ok else "FAIL"


static func format_report(label: String, r: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("[probe] %s: %d stems, %d segments, %.2f m of stem, %d nodes (%d below ground)" % [
		label, r["stems"], r["segments"], r["length"], r["nodes"], r["below_ground"]])
	lines.append("  D0 evidence: %d rib/rail crossings (>= %d), %d stems in N1's floor zone (>= %d), %d in M1's (>= %d) -> %s" % [
		r["crossings"], D0_MIN_CROSSINGS, r["n1_stems"], D0_MIN_N1_STEMS, r["m1_stems"], D0_MIN_M1_STEMS, _v(r["d0_pass"])])
	lines.append("  D1 floor contact: %d floor-zone nodes, %.1f %% within %.3f m of the floor (>= %.0f %%) and median %.4f m (<= %.2f m) -> %s" % [
		r["floor_nodes"], 100.0 * float(r["d1_share_effective"]), EFFECTIVE_CONTACT, 100.0 * D1_MIN_SHARE,
		r["d1_median"], D_CONTACT, _v(r["d1_pass"])])
	lines.append("      reported: %.1f %% within %.2f m, floor p95 %.4f m; more than %.2f m behind the floor plane: %.1f %%" % [
		100.0 * float(r["d1_share"]), D_CONTACT, r["floor_p95"], D_CONTACT,
		100.0 * float(r.get("floor_behind_share", 0.0))])
	lines.append("      reported: flat control %d nodes, %.1f %% within %.2f m, median %.4f m, p95 %.4f m" % [
		r["flat_nodes"], 100.0 * float(r["flat_share"]), D_CONTACT, r["flat_median"], r["flat_p95"]])
	lines.append("  D2 spanning: %d attached footprint nodes farther than %.2f m from the article, max %.4f m -> %s" % [
		r["d2_far_nodes"], D2_MAX_SPAN, r["d2_max"], _v(r["d2_pass"])])
	lines.append("      reported: %d floating footprint nodes (|proxy phi| > %.3f m) farther than %.2f m, max %.4f m" % [
		r["d2_floating_far_nodes"], EFFECTIVE_CONTACT, D2_MAX_SPAN, r["d2_floating_max"]])
	lines.append("  D3 inside solid: %d tip ends with phi < 0, %d nodes deeper than %.2f m -> %s" % [
		r["d3_tips_inside"], r["d3_nodes_deep"], D3_MAX_DEPTH, _v(r["d3_pass"])])
	if int(r.get("d3_nodes_deep", 0)) > 0:
		lines.append("      deep nodes by feature %s; by the proxy's own field %d" % [
			str(r["d3_by_feature"]), int(r.get("d3_nodes_deep_in_proxy", -1))])
		for s in r["d3_samples"]:
			lines.append("      deep node %s phi %.4f stem %d" % [s[0], s[1], s[2]])
	lines.append("  D4 slot S1: %d nodes deeper than %.2f m behind z = 0 -> %s" % [
		r["d4_slot_nodes"], D4_MAX_DEPTH, _v(r["d4_pass"])])
	lines.append("  reported: turn angle at inside corners n=%d p95 %.1f deg max %.1f deg" % [
		r["turn_n"], r["turn_p95"], r["turn_max"]])
	lines.append("  reported: floor-zone nodes 0.02-0.045 m off the floor: %.1f %%" % (100.0 * float(r["floor_band_share"])))
	if r.has("unrefined_share"):
		lines.append("  reported: nearest() calls returned unrefined: %.2f %% of %d" % [
			100.0 * float(r["unrefined_share"]), int(r.get("nearest_calls", 0))])
	var head := "  reported: distance to the article per feature (bins: <0"
	var prev := 0.0
	for e in HIST_EDGES:
		head += ", %.3f-%.3f" % [prev, e]
		prev = e
	head += ", >%.2f)" % HIST_EDGES[-1]
	lines.append(head)
	var feats: Array = (r["histogram"] as Dictionary).keys()
	feats.sort()
	for f in feats:
		lines.append("      %-12s %s" % [f, str(r["histogram"][f])])
	return "\n".join(lines)
