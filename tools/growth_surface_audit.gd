extends RefCounted

## Growth-surface audit — SG-9 (a)-(c), SD-OPEN-28 (ivy-b1e.2).
##
## Judges a structure's growth surface (collision proxy + baked SDF) against the hero mesh the
## player sees. It measures and reports; it fixes nothing.
##
##   (a) signed gap `g` between hero and proxy on area-uniform samples of the hero's
##       ivy-reachable exterior. g > 0: the hero is recessed behind the proxy (ivy floats);
##       g < 0: the hero stands proud of it (ivy clips).
##   (b) hero recesses and proud features >= 0.05 m deep x >= 0.15 m wide (up to 1 m across),
##       with the proxy's depth at the same place, found on depth maps ray-cast from each side
##       and from above.
##   (c) the baked SDF against the collision mesh it was baked from.
##
## The thresholds below are the PROVISIONAL SG-9 numbers from DESIGN.md; ivy-b1e.4 ratifies them.
## Driver: tools/audit_growth_surface.gd. Self-test: test/test_growth_surface_audit.gd.

const PROXY_MASK := 1
## A layer nothing in the game uses, for the throwaway hero collision body.
const HERO_MASK := 1 << 19

# --- SG-9 thresholds (provisional) -------------------------------------------------------------
const GAP_P95_MAX := 0.03
const GAP_ABS_MAX := 0.05
const CONCAVITY_MIN_DEPTH := 0.05
const CONCAVITY_MIN_WIDTH := 0.15
const CONCAVITY_DEPTH_TOL := 0.03
const SDF_FACE_TOL := 0.01
const SDF_INSIDE_DEPTH := 0.10

# --- Method constants --------------------------------------------------------------------------
## Clear air a hero face needs in front of it to count as visible.
const VISIBLE_CLEARANCE := 0.25
## Share of the 17 probe directions around the outward normal that must reach open sky.
const ESCAPE_SHARE := 0.34
const FAR := 80.0
## How far either side of a hero sample the proxy is searched for.
const GAP_REACH := 0.60
const RELIEF_PITCH := 0.025
## A recess is measured against the proudest hero surface within this radius.
const ENVELOPE_RADIUS := 0.50
## An inward SDF probe only counts where at least this much solid lies behind the face.
const SDF_MIN_SOLID := 0.20
const SDF_RAYS := 3000

## SD-OPEN-27 exclusions that SD-OPEN-28 keeps: hero-only corner trim, sealed leaves and frames.
const UNREACHABLE_CATEGORIES: Array[String] = [
	"corner_sim_column", "corner_trim_wide", "corner_trim_block",
	"aperture_seal", "door_leaf", "door_frame",
]

var _space: PhysicsDirectSpaceState3D
var _query: PhysicsRayQueryParameters3D
var _pieces: Array = []
var _sdf = null  # MeshSdf
var _bounds: AABB = AABB()
var _probe_dirs: Array[Vector3] = []


## Category of a hero glTF node (extends tools/diagnose_hero_deviation.py classify_node).
static func classify(node_name: String) -> String:
	var n := node_name.to_lower()
	if "cornerexteriorwide" in n or "corner_exteriorwide" in n or "exteriorwide" in n:
		return "corner_trim_wide"
	if "cornerexterior" in n or "corner_exterior" in n:
		return "corner_trim_block"
	if "cornercolumn" in n or "corner_column" in n or "cornerblock" in n:
		return "corner_sim_column"
	if "door_2_round" in n or "door2round" in n:
		return "door_leaf"
	if "doorframe" in n:
		return "door_frame"
	if "roofcap" in n or "roof_cap" in n:
		return "roof_cap"
	if "midfloor" in n or "mid_floor" in n:
		return "mid_floor_slab"
	if "floorslab" in n or "floor_slab" in n:
		return "floor_slab"
	if "panel_" in n:
		return "aperture_panel"
	if "seal_" in n:
		return "aperture_seal"
	if "windowshutters" in n:
		return "shutter"
	if "chimney" in n:
		return "chimney"
	if "roof_front" in n:
		return "gable"
	if "roof" in n:
		return "roof"
	if "interior_" in n or "reveal" in n:
		return "interior"
	if "wall_" in n and "_door" in n:
		return "wall_door_bay"
	if "wall_" in n and "_window" in n:
		return "wall_window_bay"
	if "wall_" in n and "_straight" in n:
		return "wall_straight"
	if "wall_" in n:
		return "wall_other"
	return "other"


## Hero pieces under `root` as `{name, faces, transform}` (faces in piece space, transform to world).
static func collect_hero_pieces(root: Node, parent_xform: Transform3D = Transform3D.IDENTITY) -> Array:
	var out: Array = []
	var xform := parent_xform
	if root is Node3D:
		xform = parent_xform * (root as Node3D).transform
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		var faces: PackedVector3Array = (root as MeshInstance3D).mesh.get_faces()
		if faces.size() >= 3:
			out.append({"name": String(root.name), "faces": faces, "transform": xform})
	for child in root.get_children():
		out.append_array(collect_hero_pieces(child, xform))
	return out


## A static body carrying the hero pieces on HERO_MASK, so rays can ask where the visible wall is.
## Both sides of every hero triangle collide: kit pieces are often open or thin sheets.
static func make_hero_body(host: Node, pieces: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "GrowthSurfaceAuditHero"
	body.collision_layer = HERO_MASK
	body.collision_mask = 0
	host.add_child(body)
	for piece in pieces:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(piece["faces"])
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		col.transform = piece["transform"]
	return body


func setup(space: PhysicsDirectSpaceState3D, pieces: Array, sdf) -> void:
	_space = space
	_pieces = pieces
	_sdf = sdf
	_query = PhysicsRayQueryParameters3D.new()
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_bounds = sdf.mesh_aabb
	for piece in _pieces:
		piece["category"] = classify(piece["name"])
		var xf: Transform3D = piece["transform"]
		for v in (piece["faces"] as PackedVector3Array):
			_bounds = _bounds.expand(xf * v)
	# One direction along the normal, then rings at 45 and 75 degrees from it.
	_probe_dirs = [Vector3(0.0, 0.0, 1.0)]
	for ring in [[45.0, 0.0], [75.0, 22.5]]:
		var tilt := deg_to_rad(ring[0])
		for k in 8:
			var az := deg_to_rad(ring[1] + 45.0 * k)
			_probe_dirs.append(Vector3(sin(tilt) * cos(az), sin(tilt) * sin(az), cos(tilt)))


## options: samples (2000), seed (1), relief (true). Returns the report dictionary.
func run(options: Dictionary = {}) -> Dictionary:
	var report := {
		"hero_pieces": _pieces.size(),
		"a": _audit_gap(int(options.get("samples", 2000)), int(options.get("seed", 1))),
		"b": _audit_concavities() if bool(options.get("relief", true)) else {"skipped": true, "pass": true},
		"c": _audit_sdf(),
	}
	report["pass"] = bool(report["a"]["pass"]) and bool(report["b"]["pass"]) and bool(report["c"]["pass"])
	return report


# ------------------------------------------------------------------------------------------------
# Shared helpers
# ------------------------------------------------------------------------------------------------

func _cast(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	_query.from = from
	_query.to = to
	_query.collision_mask = mask
	return _space.intersect_ray(_query)


static func _pct(sorted_values: Array, f: float) -> float:
	if sorted_values.is_empty():
		return NAN
	return sorted_values[clampi(int(sorted_values.size() * f), 0, sorted_values.size() - 1)]


static func _basis_around(dir: Vector3) -> Basis:
	var ref := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
	var t := dir.cross(ref).normalized()
	return Basis(t, dir.cross(t).normalized(), dir)


## True when `point`, looking roughly along `dir`, has open sky in enough directions. Interior
## rooms are sealed by the proxy; points inside wall material are shut in by the hero's own skin.
func _open_to_sky(point: Vector3, dir: Vector3) -> bool:
	var basis := _basis_around(dir)
	var need := int(ceil(_probe_dirs.size() * ESCAPE_SHARE))
	var escaped := 0
	for i in _probe_dirs.size():
		if _cast(point, point + (basis * _probe_dirs[i]) * FAR, PROXY_MASK | HERO_MASK).is_empty():
			escaped += 1
			if escaped >= need:
				return true
		elif escaped + (_probe_dirs.size() - 1 - i) < need:
			return false
	return false


## The outward normal of a hero sample, or ZERO when neither side is exposed exterior.
func _exterior_normal(p: Vector3, n: Vector3) -> Vector3:
	for dir in [n, -n]:
		var eye: Vector3 = p + dir * VISIBLE_CLEARANCE
		var hit := _cast(eye, p - dir * 0.02, HERO_MASK)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(p) > 0.004:
			continue
		if _open_to_sky(eye, dir):
			return dir
	return Vector3.ZERO


# ------------------------------------------------------------------------------------------------
# (a) signed hero-vs-proxy gap
# ------------------------------------------------------------------------------------------------

## [g, source] with source 0 = ray along the proxy normal, 1 = SDF read (ray missed), 2 = no proxy
## within reach.
func _gap_at(p: Vector3, n_out: Vector3) -> Array:
	var phi: float = _sdf.signed_distance(p)
	var in_band: bool = absf(phi) < _sdf.band - 0.02
	var nrm: Vector3 = n_out
	var reach := GAP_REACH
	if in_band:
		# The proxy's outward normal is the SDF gradient. Where the hero face is roughly parallel
		# to it, measure straight out from the hero face instead: near a proxy edge the gradient
		# turns diagonal and would overstate a plain perpendicular gap.
		var grad: Vector3 = _sdf.gradient_normalized(p)
		if n_out.dot(grad) < 0.5:
			nrm = grad
		reach = minf(GAP_REACH, absf(phi) + 0.10)
	var hit := _cast(p + nrm * reach, p - nrm * reach, PROXY_MASK)
	if not hit.is_empty():
		return [((hit["position"] as Vector3) - p).dot(nrm), 0]
	if in_band:
		return [-phi, 1]
	return [GAP_REACH if phi < 0.0 else -GAP_REACH, 2]


static func _gap_stats(values: Array) -> Dictionary:
	var n := values.size()
	if n == 0:
		return {"n": 0}
	var signed_sorted: Array = values.duplicate()
	signed_sorted.sort()
	var abs_sorted: Array = values.map(func(x): return absf(x))
	abs_sorted.sort()
	var floating := values.filter(func(x): return x > GAP_P95_MAX).size()
	var clipping := values.filter(func(x): return x < -GAP_P95_MAX).size()
	return {
		"n": n,
		"median": _pct(signed_sorted, 0.5),
		"p95_abs": _pct(abs_sorted, 0.95),
		"max_abs": abs_sorted[-1],
		"float_share": float(floating) / n,
		"clip_share": float(clipping) / n,
	}


func _audit_gap(target: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tri := PackedVector3Array()
	var tri_piece := PackedInt32Array()
	var cumulative := PackedFloat64Array()
	var total_area := 0.0
	for pi in _pieces.size():
		var piece: Dictionary = _pieces[pi]
		if piece["category"] in UNREACHABLE_CATEGORIES:
			continue
		var faces: PackedVector3Array = piece["faces"]
		var xf: Transform3D = piece["transform"]
		for i in range(0, faces.size() - 2, 3):
			var a: Vector3 = xf * faces[i]
			var b: Vector3 = xf * faces[i + 1]
			var c: Vector3 = xf * faces[i + 2]
			var area := 0.5 * (b - a).cross(c - a).length()
			if area < 1e-9:
				continue
			tri.append(a)
			tri.append(b)
			tri.append(c)
			tri_piece.append(pi)
			total_area += area
			cumulative.append(total_area)
	var gaps: Array = []
	var by_category: Dictionary = {}
	var by_node: Dictionary = {}
	var sdf_fallback := 0
	var absent := 0
	var drawn := 0
	var max_draws := target * 80
	while gaps.size() < target and drawn < max_draws and not cumulative.is_empty():
		drawn += 1
		var ti := mini(cumulative.bsearch(rng.randf() * total_area), cumulative.size() - 1)
		var a: Vector3 = tri[ti * 3]
		var b: Vector3 = tri[ti * 3 + 1]
		var c: Vector3 = tri[ti * 3 + 2]
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var p := a + (b - a) * u + (c - a) * v
		if p.y < 0.0:
			continue
		# Godot front faces are wound clockwise, so this is the front-facing normal.
		var n_out := _exterior_normal(p, (c - a).cross(b - a).normalized())
		if n_out == Vector3.ZERO:
			continue
		var measured := _gap_at(p, n_out)
		var g: float = measured[0]
		if measured[1] == 1:
			sdf_fallback += 1
		elif measured[1] == 2:
			absent += 1
		gaps.append(g)
		var piece: Dictionary = _pieces[tri_piece[ti]]
		if not by_category.has(piece["category"]):
			by_category[piece["category"]] = []
		by_category[piece["category"]].append(g)
		if not by_node.has(piece["name"]):
			by_node[piece["name"]] = []
		by_node[piece["name"]].append(g)
	var out := _gap_stats(gaps)
	out["drawn"] = drawn
	out["seed"] = seed_value
	out["hero_area"] = total_area
	out["sdf_fallback"] = sdf_fallback
	out["absent"] = absent
	out["by_category"] = {}
	out["worst_nodes"] = []
	if gaps.is_empty():
		out["pass"] = false
		return out
	for cat in by_category:
		out["by_category"][cat] = _gap_stats(by_category[cat])
	var nodes: Array = []
	for node_name in by_node:
		var st := _gap_stats(by_node[node_name])
		st["name"] = node_name
		nodes.append(st)
	nodes.sort_custom(func(x, y): return x["p95_abs"] > y["p95_abs"])
	out["worst_nodes"] = nodes.slice(0, 8)
	out["pass"] = gaps.size() >= target \
			and out["p95_abs"] <= GAP_P95_MAX and out["max_abs"] <= GAP_ABS_MAX
	return out


# ------------------------------------------------------------------------------------------------
# (b) hero concavities vs the proxy
# ------------------------------------------------------------------------------------------------

## Depth maps are ray-cast inward from a plane 1 m outside the bounds, on a RELIEF_PITCH grid.
func _relief_views() -> Array:
	var lo := _bounds.position
	var hi := _bounds.end
	var y0 := maxf(lo.y, 0.02)
	return [
		{"name": "west (-X face)", "origin": Vector3(lo.x - 1.0, y0, lo.z), "dir": Vector3.RIGHT,
			"du": Vector3.BACK, "dv": Vector3.UP, "su": hi.z - lo.z, "sv": hi.y - y0, "reach": 1.0 + (hi.x - lo.x) * 0.5},
		{"name": "east (+X face)", "origin": Vector3(hi.x + 1.0, y0, lo.z), "dir": Vector3.LEFT,
			"du": Vector3.BACK, "dv": Vector3.UP, "su": hi.z - lo.z, "sv": hi.y - y0, "reach": 1.0 + (hi.x - lo.x) * 0.5},
		{"name": "south (-Z face)", "origin": Vector3(lo.x, y0, lo.z - 1.0), "dir": Vector3.BACK,
			"du": Vector3.RIGHT, "dv": Vector3.UP, "su": hi.x - lo.x, "sv": hi.y - y0, "reach": 1.0 + (hi.z - lo.z) * 0.5},
		{"name": "north (+Z face)", "origin": Vector3(lo.x, y0, hi.z + 1.0), "dir": Vector3.FORWARD,
			"du": Vector3.RIGHT, "dv": Vector3.UP, "su": hi.x - lo.x, "sv": hi.y - y0, "reach": 1.0 + (hi.z - lo.z) * 0.5},
		{"name": "top (from above)", "origin": Vector3(lo.x, hi.y + 1.0, lo.z), "dir": Vector3.DOWN,
			"du": Vector3.RIGHT, "dv": Vector3.BACK, "su": hi.x - lo.x, "sv": hi.z - lo.z, "reach": 1.0 + (hi.y - y0)},
	]


## Running minimum (or maximum) of radius `r` cells along the rows (`along_u`) or columns of a
## `nu` x `nv` grid, in O(n) per line (van Herk / Gil-Werman). Cells holding the identity
## (INF for min, -INF for max) are ignored.
static func _run_filter(src: PackedFloat32Array, nu: int, nv: int, r: int, take_max: bool, along_u: bool) -> PackedFloat32Array:
	var ident := -INF if take_max else INF
	var n := nu if along_u else nv
	var line_count := nv if along_u else nu
	var stride := 1 if along_u else nu
	var w := 2 * r + 1
	var padded := n + 2 * r
	var line := PackedFloat32Array()
	var prefix := PackedFloat32Array()
	var suffix := PackedFloat32Array()
	line.resize(padded)
	prefix.resize(padded)
	suffix.resize(padded)
	var out := PackedFloat32Array()
	out.resize(src.size())
	for li in line_count:
		var base := li * nu if along_u else li
		line.fill(ident)
		for i in n:
			line[i + r] = src[base + i * stride]
		for i in padded:
			if i % w == 0:
				prefix[i] = line[i]
			elif take_max:
				prefix[i] = maxf(prefix[i - 1], line[i])
			else:
				prefix[i] = minf(prefix[i - 1], line[i])
		for i in range(padded - 1, -1, -1):
			if i == padded - 1 or (i + 1) % w == 0:
				suffix[i] = line[i]
			elif take_max:
				suffix[i] = maxf(suffix[i + 1], line[i])
			else:
				suffix[i] = minf(suffix[i + 1], line[i])
		for i in n:
			# Window [i - r, i + r] is [i, i + 2r] in padded coordinates.
			if take_max:
				out[base + i * stride] = maxf(suffix[i], prefix[i + 2 * r])
			else:
				out[base + i * stride] = minf(suffix[i], prefix[i + 2 * r])
	return out


static func _filter_2d(src: PackedFloat32Array, nu: int, nv: int, r: int, take_max: bool) -> PackedFloat32Array:
	return _run_filter(_run_filter(src, nu, nv, r, take_max, true), nu, nv, r, take_max, false)


static func _swap(src: PackedFloat32Array, from_value: float, to_value: float) -> PackedFloat32Array:
	var out := src.duplicate()
	for i in out.size():
		if out[i] == from_value:
			out[i] = to_value
	return out


## [recess depth, proud height] per cell of a depth map `t` (INF = nothing hit).
##
## A recess is measured against the surface that would bridge it: the morphological opening of
## the depth map (min then max), which leaves planes and slopes untouched and fills hollows up
## to 2 x ENVELOPE_RADIUS wide. A proud feature is measured the other way round (max then min).
## Anything wider than that window is a wall in its own right and is judged by gate (a).
static func _relief_maps(t: PackedFloat32Array, nu: int, nv: int, r: int) -> Array:
	var bridge := _filter_2d(_swap(_filter_2d(t, nu, nv, r, false), INF, -INF), nu, nv, r, true)
	var floor_map := _filter_2d(_swap(_filter_2d(_swap(t, INF, -INF), nu, nv, r, true), -INF, INF), nu, nv, r, false)
	var recess := PackedFloat32Array()
	var proud := PackedFloat32Array()
	recess.resize(t.size())
	proud.resize(t.size())
	for i in t.size():
		if t[i] == INF:
			continue
		if bridge[i] != -INF:
			recess[i] = t[i] - bridge[i]
		if floor_map[i] != INF:
			proud[i] = floor_map[i] - t[i]
	return [recess, proud]


func _audit_concavities() -> Dictionary:
	var listed: Array = []
	var r_cells := int(round(ENVELOPE_RADIUS / RELIEF_PITCH))
	var min_cells := int(ceil(CONCAVITY_MIN_WIDTH / RELIEF_PITCH))
	for view in _relief_views():
		var nu := int(ceil(float(view["su"]) / RELIEF_PITCH))
		var nv := int(ceil(float(view["sv"]) / RELIEF_PITCH))
		if nu < min_cells or nv < min_cells:
			continue
		var dir: Vector3 = view["dir"]
		var reach: float = view["reach"]
		var hero_t := PackedFloat32Array()
		var proxy_t := PackedFloat32Array()
		hero_t.resize(nu * nv)
		proxy_t.resize(nu * nv)
		for iv in nv:
			for iu in nu:
				var from: Vector3 = view["origin"] + view["du"] * ((iu + 0.5) * RELIEF_PITCH) \
						+ view["dv"] * ((iv + 0.5) * RELIEF_PITCH)
				var to := from + dir * reach
				var idx := iv * nu + iu
				hero_t[idx] = INF
				proxy_t[idx] = INF
				var hh := _cast(from, to, HERO_MASK)
				if not hh.is_empty():
					var shape_idx := int(hh["shape"])
					var reachable := true
					if shape_idx >= 0 and shape_idx < _pieces.size():
						reachable = not (_pieces[shape_idx]["category"] in UNREACHABLE_CATEGORIES)
					if reachable:
						hero_t[idx] = ((hh["position"] as Vector3) - from).dot(dir)
				var ph := _cast(from, to, PROXY_MASK)
				if not ph.is_empty():
					proxy_t[idx] = ((ph["position"] as Vector3) - from).dot(dir)
		var hero_maps := _relief_maps(hero_t, nu, nv, r_cells)
		var proxy_maps := _relief_maps(proxy_t, nu, nv, r_cells)
		for kind in 2:
			var hero_map: PackedFloat32Array = hero_maps[kind]
			var proxy_map: PackedFloat32Array = proxy_maps[kind]
			var state := PackedByteArray()
			state.resize(nu * nv)
			for idx in nu * nv:
				state[idx] = 1 if hero_map[idx] >= CONCAVITY_MIN_DEPTH else 0
			# Connected components of flagged cells (4-neighbourhood).
			for start in nu * nv:
				if state[start] != 1:
					continue
				var cells := PackedInt32Array()
				var stack := PackedInt32Array([start])
				state[start] = 2
				var u_lo := nu
				var u_hi := -1
				var v_lo := nv
				var v_hi := -1
				while not stack.is_empty():
					var cur := stack[stack.size() - 1]
					stack.remove_at(stack.size() - 1)
					cells.append(cur)
					var cu := cur % nu
					@warning_ignore("integer_division")
					var cv := cur / nu
					u_lo = mini(u_lo, cu)
					u_hi = maxi(u_hi, cu)
					v_lo = mini(v_lo, cv)
					v_hi = maxi(v_hi, cv)
					for nb in [cur - 1 if cu > 0 else -1, cur + 1 if cu < nu - 1 else -1,
							cur - nu if cv > 0 else -1, cur + nu if cv < nv - 1 else -1]:
						if nb >= 0 and state[nb] == 1:
							state[nb] = 2
							stack.append(nb)
				if u_hi - u_lo + 1 < min_cells or v_hi - v_lo + 1 < min_cells:
					continue
				var hero_sizes: Array = []
				var proxy_sizes: Array = []
				var depths: Array = []
				for cell in cells:
					hero_sizes.append(hero_map[cell])
					depths.append(hero_t[cell])
					if proxy_t[cell] != INF:
						proxy_sizes.append(proxy_map[cell])
				hero_sizes.sort()
				proxy_sizes.sort()
				depths.sort()
				var hero_size := _pct(hero_sizes, 0.5)
				# No proxy under most of the feature: there is nothing to compare, so it is missing.
				var proxy_size: Variant = null
				if proxy_sizes.size() * 2 >= cells.size():
					proxy_size = _pct(proxy_sizes, 0.5)
				var centre: Vector3 = view["origin"] \
						+ view["du"] * ((u_lo + u_hi + 1) * 0.5 * RELIEF_PITCH) \
						+ view["dv"] * ((v_lo + v_hi + 1) * 0.5 * RELIEF_PITCH) \
						+ dir * _pct(depths, 0.5)
				listed.append({
					"kind": "recess" if kind == 0 else "proud",
					"view": view["name"],
					"centre": [centre.x, centre.y, centre.z],
					"width_u": (u_hi - u_lo + 1) * RELIEF_PITCH,
					"width_v": (v_hi - v_lo + 1) * RELIEF_PITCH,
					"area": cells.size() * RELIEF_PITCH * RELIEF_PITCH,
					"hero_depth": hero_size,
					"proxy_depth": proxy_size,
					"represented": proxy_size != null
							and absf(hero_size - float(proxy_size)) <= CONCAVITY_DEPTH_TOL,
				})
	listed.sort_custom(func(x, y): return x["area"] > y["area"])
	var missing := listed.filter(func(x): return not x["represented"])
	return {
		"listed": listed.size(),
		"unrepresented": missing.size(),
		"unrepresented_area": missing.reduce(func(acc, x): return acc + x["area"], 0.0),
		"concavities": listed,
		"pass": missing.is_empty(),
	}


# ------------------------------------------------------------------------------------------------
# (c) baked SDF vs the collision mesh
# ------------------------------------------------------------------------------------------------

func _audit_sdf() -> Dictionary:
	var centre: Vector3 = _sdf.mesh_aabb.get_center()
	var extent: float = _sdf.mesh_aabb.size.length() * 0.65
	var golden := PI * (3.0 - sqrt(5.0))
	var face: Array = []
	var inside: Array = []
	for i in SDF_RAYS:
		var y := 1.0 - 2.0 * (i + 0.5) / SDF_RAYS
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var dir := Vector3(cos(golden * i) * ring, y, sin(golden * i) * ring)
		var from := centre + dir * extent
		var hit := _cast(from, centre - dir * extent, PROXY_MASK)
		if hit.is_empty():
			continue
		var p: Vector3 = hit["position"]
		var n: Vector3 = hit["normal"]
		if n.dot(from - p) < 0.0:
			n = -n
		# Raw read at the face: no search along the normal for a better value.
		face.append(absf(_sdf.signed_distance(p)))
		if _cast(p - n * SDF_MIN_SOLID, p - n * 0.002, PROXY_MASK).is_empty():
			inside.append(_sdf.signed_distance(p - n * SDF_INSIDE_DEPTH))
	face.sort()
	inside.sort()
	var not_negative := inside.filter(func(x): return x >= 0.0).size()
	return {
		"face_n": face.size(),
		"face_median": _pct(face, 0.5),
		"face_p95": _pct(face, 0.95),
		"face_p99": _pct(face, 0.99),
		"face_max": face[-1] if not face.is_empty() else NAN,
		"inside_n": inside.size(),
		"inside_worst": inside[-1] if not inside.is_empty() else NAN,
		"inside_not_negative": not_negative,
		"pass": not face.is_empty() and face[-1] <= SDF_FACE_TOL
				and inside.size() >= 50 and not_negative == 0,
	}


# ------------------------------------------------------------------------------------------------
# Reporting
# ------------------------------------------------------------------------------------------------

static func _verdict(ok: bool) -> String:
	return "PASS" if ok else "FAIL"


static func format_report(structure_id: String, report: Dictionary) -> String:
	var a: Dictionary = report["a"]
	var b: Dictionary = report["b"]
	var c: Dictionary = report["c"]
	var lines: PackedStringArray = []
	lines.append("[audit] %s — hero pieces %d — %s" % [structure_id, report["hero_pieces"], _verdict(report["pass"])])
	if int(a.get("n", 0)) == 0:
		lines.append("  (a) no ivy-reachable hero samples found — FAIL")
	else:
		lines.append("  (a) hero-vs-proxy gap g, m (+ floats, - clips): n=%d of %d drawn (seed %d, hero area %.1f m2)" % [
			a["n"], a["drawn"], a["seed"], a["hero_area"]])
		lines.append("      median %+.4f  p95|g| %.4f  max|g| %.4f  floating>%.2f: %.1f%%  clipping>%.2f: %.1f%%  no proxy in reach: %d  SDF fallback: %d  -> %s (p95 <= %.2f, max <= %.2f)" % [
			a["median"], a["p95_abs"], a["max_abs"], GAP_P95_MAX, 100.0 * a["float_share"], GAP_P95_MAX,
			100.0 * a["clip_share"], a["absent"], a["sdf_fallback"], _verdict(a["pass"]), GAP_P95_MAX, GAP_ABS_MAX])
		var cats: Array = a["by_category"].keys()
		cats.sort_custom(func(x, y): return a["by_category"][x]["p95_abs"] > a["by_category"][y]["p95_abs"])
		for cat in cats:
			var st: Dictionary = a["by_category"][cat]
			lines.append("      %-18s n=%4d  median %+.4f  p95|g| %.4f  max|g| %.4f  floating %.1f%%  clipping %.1f%%" % [
				cat, st["n"], st["median"], st["p95_abs"], st["max_abs"], 100.0 * st["float_share"], 100.0 * st["clip_share"]])
		lines.append("      worst nodes by p95|g|:")
		for st in a["worst_nodes"]:
			lines.append("        %-52s n=%4d  median %+.4f  p95|g| %.4f  max|g| %.4f" % [
				st["name"], st["n"], st["median"], st["p95_abs"], st["max_abs"]])
	if b.get("skipped", false):
		lines.append("  (b) skipped")
	else:
		lines.append("  (b) hero recesses and proud features >= %.2f m deep x >= %.2f m wide: %d listed, %d not in the proxy within %.2f m (%.2f m2) -> %s" % [
			CONCAVITY_MIN_DEPTH, CONCAVITY_MIN_WIDTH, b["listed"], b["unrepresented"], CONCAVITY_DEPTH_TOL,
			b["unrepresented_area"], _verdict(b["pass"])])
		var shown := 0
		for cv in b["concavities"]:
			if cv["represented"] and b["unrepresented"] > 0:
				continue
			if shown >= 12:
				break
			shown += 1
			var proxy_txt := "none" if cv["proxy_depth"] == null else "%.3f" % cv["proxy_depth"]
			lines.append("      %-6s %-16s centre (%.2f, %.2f, %.2f)  %.2f x %.2f m  area %.2f m2  hero %.3f  proxy %s  %s" % [
				cv["kind"], cv["view"], cv["centre"][0], cv["centre"][1], cv["centre"][2], cv["width_u"],
				cv["width_v"], cv["area"], cv["hero_depth"], proxy_txt, "ok" if cv["represented"] else "MISSING"])
	lines.append("  (c) SDF vs collision: |phi| at the face n=%d  median %.4f  p95 %.4f  p99 %.4f  max %.4f; phi %.2f m inside n=%d  worst %+.4f  not negative: %d -> %s (max <= %.2f, all negative)" % [
		c["face_n"], c["face_median"], c["face_p95"], c["face_p99"], c["face_max"], SDF_INSIDE_DEPTH,
		c["inside_n"], c["inside_worst"], c["inside_not_negative"], _verdict(c["pass"]), SDF_FACE_TOL])
	return "\n".join(lines)
