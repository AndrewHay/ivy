## VillageTerrain — static façade over the generated-village terrain field, plus the lawn / far
## mesh, LUT and pond helpers (AR-LANDSCAPE-FIRST, AR-LF-API / AR-LF-D3 / AR-LF-D6).
##
## sample_y(xz, layout, params, t_seed) == VillageTerrain.field(layout, params).sample_y(xz):
## fit(cap_sun(L + D + Rg)) (SD-VILLAGE-TERRAIN-17). One function from the hero stoop to the far
## mesh edge; HillsHeightfield.sample_y delegates here for generated variant 0 (AC-LT-SEAM).
## t_seed is kept for signature compatibility and ignored for generated layouts (the field owns
## its seeds).
##
## Flat-legacy / classic gate: variant == 1 or not layout.is_generated → Y_BASE (0.0) everywhere;
## consumers pass through unchanged (INV-15, AC-VT1).
class_name VillageTerrain
extends RefCounted

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const HillsParams = preload("res://src/playground/hills_params.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

## Datum for flat / classic layouts (World/Ground plane, SD-VILLAGE-TERRAIN-2).
const Y_BASE := 0.0
## Bank-outline clearance of the pond water (AC-LT-POND: water <= lowest bank outline − 2 cm).
const POND_WATER_BANK_CLEAR_M := 0.02
## Far mesh (AR-LF-D6): azimuth segments; ring radii grow geometrically by 1 + TAU / FAR_AZ_SEGS.
const FAR_AZ_SEGS := 192
## Inside test margin for lawn cell corners (a corner on the join circle counts as outside).
const _JOIN_EPS := 1e-6
## Hard tri cap of the near mesh (AC-LT-PERF: 8k target / 16k hard).
const NEAR_TRI_HARD_CAP := 16000
## Normal step shared by the near and far mesh join-loop vertices (bit-identical normals).
const JOIN_NORMAL_EPS := 0.35

static var _sample_lut_cache: Dictionary = {}
static var _displaced_mesh_cache: Dictionary = {}
static var _sun_az: Vector2 = Vector2(NAN, NAN)
static var _prod_hills: HillsParams = null


# ── Field and façade ──────────────────────────────────────────────────────────

static func terrain_seed(layout: VillageLayout, params: VillageTerrainParams) -> int:
	## Detail-stream seed (SD-VILLAGE-TERRAIN-5); kept for the façade signatures and caches.
	var norm := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	return VillageLayout._derive(norm, VillageLayout.VILLAGE_TERRAIN_SALT)


static func production_hills() -> HillsParams:
	if _prod_hills == null:
		_prod_hills = HillsParams.production()
	return _prod_hills


static func is_flat(layout: VillageLayout, params: VillageTerrainParams) -> bool:
	return params == null or params.variant == 1 or not layout.is_generated


static func layout_hills(layout: VillageLayout) -> HillsParams:
	## The HillsParams the layout's own terrain uses: layout.hills_params, else production.
	var hp := layout.hills_params as HillsParams
	return hp if hp != null else production_hills()


static func field(layout: VillageLayout, params: VillageTerrainParams, hills_params: HillsParams = null):
	## The resolved VillageTerrainField for (layout, params, hills_params), cached on the layout
	## (AR-LF-D10). No global field cache. Keyed on the HillsParams actually passed
	## (ivy-82zn.14.21 F5): null means the layout's own hills (layout_hills), whose field lives in
	## layout.terrain_field; any other HillsParams (value-different) gets its own entry in
	## layout.terrain_field_variants, so mixed callers never rebuild each other's field or drop
	## its mesh_min_y. A value-equal copy has the same signature and resolves the same instance.
	var own := layout_hills(layout)
	var hp := hills_params if hills_params != null else own
	var sig := params.field_signature()
	var hsig := hills_signature(hp)
	var is_own := hp == own or hsig == hills_signature(own)
	if is_own:
		var f = layout.terrain_field
		if f != null and f.signature == sig and f.hills_signature == hsig:
			return f
		f = _build_field(layout, params, hp, sig, hsig)
		layout.terrain_field = f
		return f
	var key := "%d|%d" % [sig, hsig]
	var variants: Dictionary = layout.terrain_field_variants
	if variants.has(key):
		return variants[key]
	for k: String in variants.keys():
		if int(variants[k].signature) != sig:
			variants.erase(k)  # stale terrain knobs
	var fv = _build_field(layout, params, hp, sig, hsig)
	variants[key] = fv
	return fv


static func _build_field(layout: VillageLayout, params: VillageTerrainParams, hp: HillsParams,
		sig: int, hsig: int):
	var f = VillageTerrainField.build(layout, params, hp)
	f.signature = sig
	f.hills_signature = hsig
	return f


static func hills_signature(hp: HillsParams) -> int:
	## The HillsParams fields the far ridges Rg read (ridge shape, wedge, radii).
	return hash([hp.variant, hp.layout_seed, hp.r_inner_m, hp.r_outer_m, hp.base_feature_m,
		hp.noise_octaves, hp.noise_persistence, hp.warp_strength, hp.height_scale_m, hp.layer_count,
		hp.layer_dist_0, hp.layer_dist_1, hp.layer_dist_2, hp.layer_dist_3, hp.layer_width_0,
		hp.layer_width_1, hp.layer_width_2, hp.layer_width_3, hp.layer_amp_scale_0,
		hp.layer_amp_scale_1, hp.layer_amp_scale_2, hp.layer_amp_scale_3, hp.radial_bias_power,
		hp.azimuth_centre_deg, hp.azimuth_half_width_deg, hp.azimuth_fade_width_deg])


static func sample_y(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		_t_seed: int = 0) -> float:
	## Single source of truth for generated terrain Y (backdrop frame). Defined for every xz.
	if is_flat(layout, params):
		return Y_BASE
	return field(layout, params).sample_y(xz)


static func sample_normal(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		_t_seed: int = 0,
		eps: float = 0.35) -> Vector3:
	if is_flat(layout, params):
		return Vector3.UP
	return field(layout, params).sample_normal(xz, eps)


static func sample_slope_deg(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		_t_seed: int = 0,
		eps: float = 0.4) -> float:
	## Gradient magnitude (central differences, eps 0.4 m: the SD-VILLAGE-TERRAIN-20 metric).
	if is_flat(layout, params):
		return 0.0
	return field(layout, params).sample_slope_deg(xz, eps)


static func hero_datum_y(layout: VillageLayout, params: VillageTerrainParams) -> float:
	## y_hero, the hero pad target: World lowers the backdrop by it (datum option A). 0 when flat.
	if is_flat(layout, params):
		return 0.0
	return float(field(layout, params).y_hero)


static func sun_corridor_azimuths() -> Vector2:
	## (A_rise, A_set) compass degrees from Solar at production IvyParams (AR-LF-D8).
	if is_nan(_sun_az.x):
		var s := Solar.new(IvyParams.new())
		_sun_az = Vector2(s.azimuth_deg(s.sunrise_hour()), s.azimuth_deg(s.sunset_hour()))
	return _sun_az


static func clear_caches() -> void:
	## Drop the LUT / mesh caches (playground knob edits, tests). Field caches live on layouts.
	_sample_lut_cache.clear()
	_displaced_mesh_cache.clear()


static func invalidate(layout: VillageLayout) -> void:
	layout.terrain_field = null
	layout.terrain_field_variants.clear()


# ── Ground material (shared terrain_tint.gdshaderinc, AR-LF-D9) ───────────────

static func apply_ground_material(mat: ShaderMaterial, params: VillageTerrainParams, f = null) -> void:
	## Slope / height tint uniforms. Set identically on the lawn and the far hills material, so the
	## factors match across the join loop. terrain_height_ref_y = y_hero (backdrop frame).
	mat.set_shader_parameter("terrain_slope_dark", params.ground_slope_dark)
	mat.set_shader_parameter("terrain_slope_full_deg", params.ground_slope_full_deg)
	mat.set_shader_parameter("terrain_height_tint", params.ground_height_tint)
	mat.set_shader_parameter("terrain_height_range_m", params.ground_height_range_m)
	var ref := 0.0
	if f != null and not f.flat:
		ref = float(f.y_hero)
	mat.set_shader_parameter("terrain_height_ref_y", ref)


static func terrain_tint_factor(ny: float, local_y: float, params: VillageTerrainParams, ref_y: float) -> float:
	## CPU mirror of terrain_tint.gdshaderinc: terrain_slope_dim(ny) · terrain_height_factor(y).
	var n := clampf(ny, 0.0, 1.0)
	var slope_mix := 1.0 - n
	if params.ground_slope_full_deg > 0.0:
		slope_mix = clampf(rad_to_deg(acos(n)) / params.ground_slope_full_deg, 0.0, 1.0)
	var dim := 1.0 - params.ground_slope_dark * slope_mix
	var t := clampf((local_y - ref_y) / maxf(params.ground_height_range_m, 0.01), -1.0, 1.0)
	return dim * (1.0 + params.ground_height_tint * t)


# ── Sample LUT (grass / scatter Y bakes, playground time-sliced job) ──────────

static func build_sample_lut(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int = 0,
		cell_m: float = 1.0) -> Dictionary:
	## Bilinear grid of the exact field over the lawn bbox (half = lawn_radius + cell).
	## Returns {origin_xz, cell_m, cols, rows, data}. Cached per (layout, field signature, cell).
	var job := lut_job_begin(layout, params, t_seed, cell_m)
	lut_job_step(job, -1)
	return job["lut"]


static func lut_job_begin(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int = 0,
		cell_m: float = 1.0) -> Dictionary:
	## Resumable build_sample_lut (ivy-82zn.14.7): same cells, same order, same values as a
	## one-shot build. Done jobs carry the LUT in job["lut"].
	var cache_key := _sample_lut_cache_key(layout, params, cell_m)
	if _sample_lut_cache.has(cache_key):
		return {"done": true, "lut": _sample_lut_cache[cache_key], "progress": 1.0}
	var g := layout.hamlet_centre_xz
	var half := layout.lawn_radius + cell_m
	var step := maxf(cell_m, 0.1)
	var cols := int(ceil(2.0 * half / step)) + 1
	var rows := cols
	var data := PackedFloat32Array()
	data.resize(cols * rows)
	var job := {
		"done": false,
		"progress": 0.0,
		"layout": layout,
		"params": params,
		"t_seed": t_seed,
		"key": cache_key,
		"origin": g - Vector2(half, half),
		"step": step,
		"cols": cols,
		"rows": rows,
		"data": data,
		"next": 0,
		"field": null,
	}
	if is_flat(layout, params):
		job["next"] = cols * rows
		_lut_job_finish(job)
	else:
		job["field"] = field(layout, params)
	return job


static func lut_job_step(job: Dictionary, budget_usec: int) -> bool:
	## Fill cells until the budget (µs) runs out; budget < 0 runs to completion. Returns done.
	if job["done"]:
		return true
	var f = job["field"]
	var origin: Vector2 = job["origin"]
	var step: float = job["step"]
	var cols: int = job["cols"]
	var total: int = cols * int(job["rows"])
	var data: PackedFloat32Array = job["data"]
	var i: int = job["next"]
	var t_end := Time.get_ticks_usec() + budget_usec
	while i < total:
		var xz := origin + Vector2(float(i % cols) * step, float(i / cols) * step)
		data[i] = f.sample_y(xz)
		i += 1
		if budget_usec >= 0 and Time.get_ticks_usec() >= t_end:
			break
	job["next"] = i
	job["data"] = data
	job["progress"] = float(i) / float(maxi(total, 1))
	if i >= total:
		_lut_job_finish(job)
	return job["done"]


static func _lut_job_finish(job: Dictionary) -> void:
	var built := {
		"origin_xz": job["origin"],
		"cell_m": job["step"],
		"cols": job["cols"],
		"rows": job["rows"],
		"data": job["data"],
	}
	if _sample_lut_cache.size() > 48:
		_sample_lut_cache.clear()
	_sample_lut_cache[job["key"]] = built
	job["lut"] = built
	job["done"] = true
	job["progress"] = 1.0


static func _sample_lut_cache_key(layout: VillageLayout, params: VillageTerrainParams, cell_m: float) -> String:
	var gen := layout.generation_seed if layout.is_generated else 0
	var lf: Dictionary = layout.landform
	return "%d|%d|%s|%.3f|%.5f|%d" % [gen, layout.get_instance_id(), str(lf.get("offset", Vector2.ZERO)),
		float(lf.get("rot_deg", 0.0)), cell_m, params.field_signature() if params != null else 0]


static func lut_sample(lut: Dictionary, xz: Vector2) -> float:
	## Bilinear sample from a LUT built by build_sample_lut.
	var origin: Vector2 = lut["origin_xz"]
	var cell: float = lut["cell_m"]
	var cols: int = lut["cols"]
	var rows: int = lut["rows"]
	var data: PackedFloat32Array = lut["data"]
	var fx := (xz.x - origin.x) / maxf(cell, 0.001)
	var fz := (xz.y - origin.y) / maxf(cell, 0.001)
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var ix1 := clampi(ix, 0, cols - 1)
	var ix2 := clampi(ix + 1, 0, cols - 1)
	var iz1 := clampi(iz, 0, rows - 1)
	var iz2 := clampi(iz + 1, 0, rows - 1)
	var v00: float = data[iz1 * cols + ix1]
	var v10: float = data[iz1 * cols + ix2]
	var v01: float = data[iz2 * cols + ix1]
	var v11: float = data[iz2 * cols + ix2]
	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), tz)


static func lut_sample_normal(lut: Dictionary, xz: Vector2) -> Vector3:
	## FD upward normal from the LUT (eps = half a cell).
	var eps: float = (lut["cell_m"] as float) * 0.5
	var yx := lut_sample(lut, xz + Vector2(eps, 0.0))
	var yxm := lut_sample(lut, xz - Vector2(eps, 0.0))
	var yz := lut_sample(lut, xz + Vector2(0.0, eps))
	var yzm := lut_sample(lut, xz - Vector2(0.0, eps))
	return Vector3(yxm - yx, 2.0 * eps, yzm - yz).normalized()


# ── Join loop (AR-LF-D6) ──────────────────────────────────────────────────────

static func _join_data(layout: VillageLayout, step: float) -> Dictionary:
	## Crossings of the lawn mesh grid lines (origin G − lawn_radius, `step`) with the circle
	## r_j = lawn_radius: {points: sorted by atan2 angle, canon: key -> point}.
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	var x0 := g.x - r
	var z0 := g.y - r
	var cols := int(ceil(2.0 * r / step))
	var canon := {}
	var pts: Array[Vector2] = []
	for i in range(cols + 1):
		var xl := x0 + float(i) * step
		for p: Vector2 in _crossings_vertical(xl, g, r):
			_canon_add(p, canon, pts)
		var zl := z0 + float(i) * step
		for p: Vector2 in _crossings_horizontal(zl, g, r):
			_canon_add(p, canon, pts)
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return _loop_angle(a, g) < _loop_angle(b, g))
	return {"points": PackedVector2Array(pts), "canon": canon}


static func _loop_angle(p: Vector2, g: Vector2) -> float:
	return fposmod(atan2(p.y - g.y, p.x - g.x), TAU)


static func _canon_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 1e4), roundi(p.y * 1e4))


static func _canon_add(p: Vector2, canon: Dictionary, pts: Array[Vector2]) -> void:
	var k := _canon_key(p)
	if canon.has(k):
		return
	canon[k] = p
	pts.append(p)


static func _crossings_vertical(xl: float, g: Vector2, r: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var dx := xl - g.x
	if dx * dx > r * r:
		return out
	var hz := sqrt(maxf(r * r - dx * dx, 0.0))
	out.append(Vector2(xl, g.y - hz))
	if hz > 0.0:
		out.append(Vector2(xl, g.y + hz))
	return out


static func _crossings_horizontal(zl: float, g: Vector2, r: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var dz := zl - g.y
	if dz * dz > r * r:
		return out
	var hx := sqrt(maxf(r * r - dz * dz, 0.0))
	out.append(Vector2(g.x - hx, zl))
	if hx > 0.0:
		out.append(Vector2(g.x + hx, zl))
	return out


static func join_loop(layout: VillageLayout, params: VillageTerrainParams) -> PackedVector2Array:
	## The shared vertices of the lawn and far meshes, sorted by angle (AR-LF-D6).
	return _join_data(layout, mesh_step(layout, params.terrain_mesh_step_m))["points"]


## Increment by which mesh_step coarsens a step that would exceed NEAR_TRI_HARD_CAP.
const _MESH_STEP_COARSEN_M := 0.25


static func near_tri_bound(r: float, step: float) -> int:
	## Upper bound on the lawn mesh triangles at (r_j, step): cells fully inside the disc have total
	## area <= PI r^2 (2 tris each); the circle crosses each of the cols + 1 grid lines per axis at
	## most twice, so it visits <= 4 (cols + 1) boundary cells, each clipped to <= 6 vertices
	## (<= 4 tris).
	var cols := int(ceil(2.0 * r / step))
	return int(ceil(2.0 * PI * r * r / (step * step))) + 16 * (cols + 1)


static func mesh_step(layout: VillageLayout, requested_m: float) -> float:
	## The lawn mesh / join loop cell actually used: requested_m (>= 0.1), coarsened in 0.25 m
	## increments until near_tri_bound fits NEAR_TRI_HARD_CAP (ivy-82zn.14.21 F1). The game's 2 m
	## is never touched; the playground knob minimum (1 m) becomes 1.25 m at r_j 56 and 1.5 m at
	## r_j 64. build_mesh, mesh_from_lut, join_loop and mesh_surface_lut all go through here, so the
	## lawn and far meshes always share one loop and no row is ever dropped.
	var s := maxf(requested_m, 0.1)
	while near_tri_bound(layout.lawn_radius, s) > NEAR_TRI_HARD_CAP:
		s += _MESH_STEP_COARSEN_M
	return s


# ── Near (lawn) mesh (SD-VILLAGE-TERRAIN-8, AR-LF-D6 boundary clip) ───────────

static func build_mesh(layout: VillageLayout, params: VillageTerrainParams) -> ArrayMesh:
	## Generated variant 0: Cartesian-grid LawnTerrain clipped to the join loop. Flat / classic:
	## the lightweight fan (INV-15).
	if is_flat(layout, params):
		return _build_flat_fan(layout)
	var step := mesh_step(layout, params.terrain_mesh_step_m)
	var mesh_key := "%s|mesh" % _sample_lut_cache_key(layout, params, step)
	if _displaced_mesh_cache.has(mesh_key):
		return _displaced_mesh_cache[mesh_key]
	var lut := build_sample_lut(layout, params, 0, step)
	var mesh := mesh_from_lut(layout, step, lut, params)
	if _displaced_mesh_cache.size() > 24:
		_displaced_mesh_cache.clear()
	_displaced_mesh_cache[mesh_key] = mesh
	return mesh


static func mesh_from_lut(layout: VillageLayout, step: float, lut: Dictionary,
		params: VillageTerrainParams = null) -> ArrayMesh:
	## Lawn mesh at `step` from a built LUT (game build and playground preview). Interior cells as
	## two triangles [c0, c1, c2], [c0, c2, c3]; boundary cells clipped to the circle with the join
	## loop points as vertices. With params, loop vertices take the exact field y and normal
	## (shared with the far mesh); without (a coarse preview), the LUT. Null when no triangles.
	## `step` is coarsened by mesh_step so the triangles fit NEAR_TRI_HARD_CAP; pass a LUT built at
	## mesh_step(layout, step) for vertices on LUT nodes (otherwise they are bilinear in the LUT).
	step = mesh_step(layout, step)
	var f = null
	if params != null and not is_flat(layout, params):
		f = field(layout, params)
	var jd := _join_data(layout, step)
	var canon: Dictionary = jd["canon"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	var x0 := g.x - r
	var z0 := g.y - r
	var cols := int(ceil(2.0 * r / step))
	var tris := 0
	var lo := INF
	for iz in range(cols):
		for ix in range(cols):
			var ax0 := x0 + float(ix) * step
			var az0 := z0 + float(iz) * step
			var ax1 := x0 + float(ix + 1) * step
			var az1 := z0 + float(iz + 1) * step
			var c: Array[Vector2] = [Vector2(ax0, az0), Vector2(ax1, az0), Vector2(ax1, az1), Vector2(ax0, az1)]
			var inside: Array[bool] = []
			var n_in := 0
			for cp: Vector2 in c:
				var is_in := cp.distance_to(g) < r - _JOIN_EPS
				inside.append(is_in)
				if is_in:
					n_in += 1
			if n_in == 4:
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					for idx: int in tri:
						lo = minf(lo, _emit_lut_vertex(st, c[idx], lut))
					tris += 1
				continue
			var poly: Array[Dictionary] = []
			for e in range(4):
				var a: Vector2 = c[e]
				var b: Vector2 = c[(e + 1) % 4]
				if inside[e]:
					poly.append({"p": a, "loop": false})
				for p: Vector2 in _edge_crossings(a, b, g, r):
					var kp := _canon_key(p)
					var q: Vector2 = canon.get(kp, p)
					if poly.is_empty() or (poly[poly.size() - 1]["p"] as Vector2).distance_to(q) > 1e-7:
						poly.append({"p": q, "loop": true})
			if poly.size() >= 2 and (poly[0]["p"] as Vector2).distance_to(poly[poly.size() - 1]["p"]) <= 1e-7:
				poly.pop_back()
			if poly.size() < 3:
				continue
			for k in range(1, poly.size() - 1):
				for v: Dictionary in [poly[0], poly[k], poly[k + 1]]:
					if bool(v["loop"]):
						lo = minf(lo, _emit_loop_vertex(st, v["p"], f, lut))
					else:
						lo = minf(lo, _emit_lut_vertex(st, v["p"], lut))
				tris += 1
	if tris <= 0:
		return null
	if f != null:
		f.note_mesh_min(lo, VillageTerrainField.MESH_LAWN)
	return st.commit()


static func _emit_lut_vertex(st: SurfaceTool, p: Vector2, lut: Dictionary) -> float:
	var y := lut_sample(lut, p)
	st.set_normal(lut_sample_normal(lut, p))
	st.set_color(Color(1, 1, 1, 1))
	st.add_vertex(Vector3(p.x, y, p.y))
	return y


static func _emit_loop_vertex(st: SurfaceTool, p: Vector2, f, lut: Dictionary) -> float:
	if f == null:
		return _emit_lut_vertex(st, p, lut)
	var y: float = f.sample_y(p)
	st.set_normal(f.sample_normal(p, JOIN_NORMAL_EPS))
	st.set_color(Color(1, 1, 1, 1))
	st.add_vertex(Vector3(p.x, y, p.y))
	return y


static func _edge_crossings(a: Vector2, b: Vector2, g: Vector2, r: float) -> Array[Vector2]:
	## Circle crossings on an axis-aligned cell edge a→b, in travel order, using the same line
	## formulas as the join loop (bit-identical points).
	var cand: Array[Vector2] = []
	if a.x == b.x:
		cand = _crossings_vertical(a.x, g, r)
	else:
		cand = _crossings_horizontal(a.y, g, r)
	var out: Array[Vector2] = []
	var len := a.distance_to(b)
	for p: Vector2 in cand:
		var t := (p - a).dot(b - a) / maxf(len * len, 1e-12)
		if t >= -1e-9 and t <= 1.0 + 1e-9:
			out.append(p)
	if out.size() == 2 and (out[0] - a).length_squared() > (out[1] - a).length_squared():
		out.reverse()
	return out


# ── Far mesh (AR-LF-D6; called by HillsHeightfield.build_mesh) ────────────────

static func far_ring_growth() -> float:
	## Ratio between consecutive far-mesh ring radii.
	return 1.0 + TAU / float(FAR_AZ_SEGS)


static func far_ring_radii(rj: float, r_outer: float) -> Array[float]:
	## The far mesh's vertex rings outside the join loop: rj * growth^k (k >= 1) below r_outer, then
	## r_outer. Shared by build_far_mesh and VillageTerrainField.terrain_min_y (ivy-82zn.14.30 F1)
	## so the early ground estimate samples exactly the far vertices.
	var growth := far_ring_growth()
	var radii: Array[float] = []
	var rr := rj * growth
	while rr < r_outer:
		radii.append(rr)
		rr *= growth
	radii.append(r_outer)
	return radii


static func far_ring_dir(i: int) -> Vector2:
	## Unit direction of far-mesh azimuth i (0 .. FAR_AZ_SEGS - 1).
	var a := TAU * float(i) / float(FAR_AZ_SEGS)
	return Vector2(cos(a), sin(a))


static func build_far_mesh(layout: VillageLayout, params: VillageTerrainParams,
		hills_params: HillsParams = null) -> ArrayMesh:
	## Indexed polar mesh from the join loop out to HillsParams.r_outer_m. Its inner boundary is
	## the join loop (same points, same y and normal as the lawn mesh); FAR_AZ_SEGS azimuths; ring
	## radii grow by 1 + TAU / FAR_AZ_SEGS. Interior normals by central differences on the grid.
	## No base lift.
	var hp := hills_params if hills_params != null else production_hills()
	var f = field(layout, params, hp)
	var g := layout.hamlet_centre_xz
	var rj := layout.lawn_radius
	var loop := join_loop(layout, params)
	var n_loop := loop.size()
	var m := FAR_AZ_SEGS
	var growth := far_ring_growth()
	var radii := far_ring_radii(rj, hp.r_outer_m)
	var k_rings := radii.size()
	# y grid with a virtual ring inside (r_j) and outside, for central-difference normals.
	var ring_r: Array[float] = [rj]
	ring_r.append_array(radii)
	ring_r.append(hp.r_outer_m * growth)
	var ys := PackedFloat32Array()
	ys.resize(ring_r.size() * m)
	for k in range(ring_r.size()):
		for i in range(m):
			ys[k * m + i] = f.sample_y(g + far_ring_dir(i) * ring_r[k])
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var lo := INF
	for p: Vector2 in loop:
		var y: float = f.sample_y(p)
		verts.append(Vector3(p.x, y, p.y))
		norms.append(f.sample_normal(p, JOIN_NORMAL_EPS))
		cols.append(Color(1, 1, 1, 1))
		lo = minf(lo, y)
	for kk in range(k_rings):
		var k := kk + 1  # index into ring_r / ys
		for i in range(m):
			var a := TAU * float(i) / float(m)
			var y := ys[k * m + i]
			verts.append(Vector3(g.x + cos(a) * ring_r[k], y, g.y + sin(a) * ring_r[k]))
			var ip := (i + 1) % m
			var im := (i + m - 1) % m
			var ap := TAU * float(i + 1) / float(m)
			var am := TAU * float(i - 1) / float(m)
			var p_ip := Vector3(g.x + cos(ap) * ring_r[k], ys[k * m + ip], g.y + sin(ap) * ring_r[k])
			var p_im := Vector3(g.x + cos(am) * ring_r[k], ys[k * m + im], g.y + sin(am) * ring_r[k])
			var p_kp := Vector3(g.x + cos(a) * ring_r[k + 1], ys[(k + 1) * m + i], g.y + sin(a) * ring_r[k + 1])
			var p_km := Vector3(g.x + cos(a) * ring_r[k - 1], ys[(k - 1) * m + i], g.y + sin(a) * ring_r[k - 1])
			var nrm := (p_ip - p_im).cross(p_kp - p_km)
			if nrm.y < 0.0:
				nrm = -nrm
			norms.append(nrm.normalized() if nrm.length_squared() > 1e-12 else Vector3.UP)
			cols.append(Color(1, 1, 1, 1))
			lo = minf(lo, y)
	var idx := PackedInt32Array()
	# Zipper: join loop (0..n_loop-1) to ring 0 (n_loop .. n_loop + m - 1), merged by angle.
	var ring0 := n_loop
	var la := 0
	var rb := 0
	var step_a := TAU / float(m)
	while la < n_loop or rb < m:
		var next_l := INF
		if la < n_loop:
			next_l = _loop_angle(loop[(la + 1) % n_loop], g) + (TAU if la + 1 >= n_loop else 0.0)
		var next_r := INF
		if rb < m:
			next_r = float(rb + 1) * step_a
		if next_l <= next_r:
			_tri(idx, verts, la % n_loop, (la + 1) % n_loop, ring0 + rb % m)
			la += 1
		else:
			_tri(idx, verts, la % n_loop, ring0 + (rb + 1) % m, ring0 + rb % m)
			rb += 1
	for kk in range(k_rings - 1):
		var b0 := n_loop + kk * m
		var b1 := n_loop + (kk + 1) * m
		for i in range(m):
			var i1 := (i + 1) % m
			_tri(idx, verts, b0 + i, b0 + i1, b1 + i1)
			_tri(idx, verts, b0 + i, b1 + i1, b1 + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	f.note_mesh_min(lo, VillageTerrainField.MESH_FAR)
	return mesh


static func _tri(idx: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int) -> void:
	## Append a triangle wound like the lawn cells (positive xz cross product).
	var pa := verts[a]
	var pb := verts[b]
	var pc := verts[c]
	var cross := (pb.x - pa.x) * (pc.z - pa.z) - (pb.z - pa.z) * (pc.x - pa.x)
	idx.append(a)
	if cross >= 0.0:
		idx.append(b)
		idx.append(c)
	else:
		idx.append(c)
		idx.append(b)


# ── Rendered lawn surface (pond bank drape, ivy-82zn.14.10) ───────────────────

static func mesh_surface_lut(layout: VillageLayout, params: VillageTerrainParams) -> Dictionary:
	## The LUT build_mesh triangulates (mesh_step cells; cached). {} for flat / classic.
	if is_flat(layout, params):
		return {}
	return build_sample_lut(layout, params, 0, mesh_step(layout, params.terrain_mesh_step_m))


static func mesh_surface_y_from_lut(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		lut: Dictionary) -> float:
	## Height of the rendered LawnTerrain at xz for interior cells: the same two triangles per cell
	## as mesh_from_lut ([c0, c1, c2], [c0, c2, c3]). The pond (≥ 20 m inside r_j) never touches a
	## clipped boundary cell (AR-LF-RISK-7).
	if lut.is_empty() or is_flat(layout, params):
		return VillageBackdrop.LAWN_GROUND_Y_OFFSET
	var step: float = maxf(float(lut["cell_m"]), 0.1)
	var g := layout.hamlet_centre_xz
	var x0 := g.x - layout.lawn_radius
	var z0 := g.y - layout.lawn_radius
	var ix := floori((xz.x - x0) / step)
	var iz := floori((xz.y - z0) / step)
	var ax0 := x0 + float(ix) * step
	var az0 := z0 + float(iz) * step
	var ax1 := ax0 + step
	var az1 := az0 + step
	var fx := clampf((xz.x - ax0) / step, 0.0, 1.0)
	var fz := clampf((xz.y - az0) / step, 0.0, 1.0)
	var y0 := lut_sample(lut, Vector2(ax0, az0))
	var y1 := lut_sample(lut, Vector2(ax1, az0))
	var y2 := lut_sample(lut, Vector2(ax1, az1))
	var y3 := lut_sample(lut, Vector2(ax0, az1))
	var y: float
	if fx >= fz:
		y = y0 + fx * (y1 - y0) + fz * (y2 - y1)
	else:
		y = y0 + fz * (y3 - y0) + fx * (y2 - y3)
	return Y_BASE + y


static func mesh_surface_y(xz: Vector2, layout: VillageLayout, params: VillageTerrainParams) -> float:
	return mesh_surface_y_from_lut(xz, layout, params, mesh_surface_lut(layout, params))


static func max_mesh_cell_slope_deg(layout: VillageLayout, params: VillageTerrainParams) -> float:
	## Steepest triangle of the rendered lawn mesh grid (cliff guard: no lawn cell > 40°).
	var lut := mesh_surface_lut(layout, params)
	if lut.is_empty():
		return 0.0
	var step: float = float(lut["cell_m"])
	var g := layout.hamlet_centre_xz
	var outer := layout.lawn_radius
	var cols := int(ceil(2.0 * outer / step))
	var worst := 0.0
	for iz in range(cols):
		for ix in range(cols):
			var ax0 := g.x - outer + float(ix) * step
			var az0 := g.y - outer + float(iz) * step
			var c := [Vector2(ax0, az0), Vector2(ax0 + step, az0), Vector2(ax0 + step, az0 + step),
				Vector2(ax0, az0 + step)]
			var inside := 0
			for cp: Vector2 in c:
				if cp.distance_to(g) < outer:
					inside += 1
			if inside == 0:
				continue
			var y0 := lut_sample(lut, c[0])
			var y1 := lut_sample(lut, c[1])
			var y2 := lut_sample(lut, c[2])
			var y3 := lut_sample(lut, c[3])
			var ga := Vector2(y1 - y0, y2 - y1) / step
			var gb := Vector2(y2 - y3, y3 - y0) / step
			worst = maxf(worst, maxf(ga.length(), gb.length()))
	return rad_to_deg(atan(worst))


# ── Pond water level (SD-VILLAGE-TERRAIN-19, AR-LF-GAP-7) ──────────────────────

static func pond_bank_outline_min_y(
		layout: VillageLayout,
		params: VillageTerrainParams,
		_t_seed: int = 0) -> float:
	## Lowest sample_y along the pond's bank outer outline (computed once per field).
	if is_flat(layout, params):
		return Y_BASE
	return float(field(layout, params).pond_outline_min_y())


static func pond_water_y(
		layout: VillageLayout,
		params: VillageTerrainParams,
		_t_seed: int = 0,
		outline_min_y: float = NAN) -> float:
	## Water surface: lowest bank point of the capped field − pond_freeboard_m, never above the
	## lowest bank outline point − POND_WATER_BANK_CLEAR_M, on the exact field and on the RENDERED
	## lawn (the 2 m mesh dips a few cm under the exact field between vertices; AC-LT-POND).
	## outline_min_y: a precomputed exact outline minimum (the playground slices it); NAN = field's.
	## Classic / variant 1: VillageBackdrop.POND_WATER_Y_OFFSET (INV-15).
	if is_flat(layout, params):
		return VillageBackdrop.POND_WATER_Y_OFFSET
	var f = field(layout, params)
	var exact_min: float = float(f.pond_outline_min_y()) if is_nan(outline_min_y) else outline_min_y
	var lut := mesh_surface_lut(layout, params)
	var mesh_min := INF
	for xz in VillagePondShape.at(layout.pond_center).bank_outer_outline_world_xz():
		mesh_min = minf(mesh_min, mesh_surface_y_from_lut(xz, layout, params, lut))
	return minf(float(f.pond_bank_y) - params.pond_freeboard_m,
		minf(exact_min, mesh_min) - POND_WATER_BANK_CLEAR_M)


# ── Helpers ───────────────────────────────────────────────────────────────────

static func rect_sdf(xz: Vector2, rect: Rect2) -> float:
	## Signed distance to an axis-aligned rect: negative inside.
	var c := rect.get_center()
	var dx := absf(xz.x - c.x) - rect.size.x * 0.5
	var dz := absf(xz.y - c.y) - rect.size.y * 0.5
	if dx <= 0.0 and dz <= 0.0:
		return maxf(dx, dz)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


static func _build_flat_fan(layout: VillageLayout) -> ArrayMesh:
	## Lightweight fan mesh for flat/classic path — byte-parity node (AR-VT-DECIDE-3 §flat).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 72
	var c := layout.hamlet_centre_xz if layout.is_generated else Vector2.ZERO
	var r := layout.lawn_radius if layout.is_generated else 58.0
	var y := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	for i in range(segs):
		var a0 := (float(i) / segs) * TAU
		var a1 := (float(i + 1) / segs) * TAU
		st.set_normal(Vector3.UP)
		st.set_color(Color(1, 1, 1, 1))
		st.add_vertex(Vector3(c.x, y, c.y))
		st.add_vertex(Vector3(c.x + cos(a0) * r, y, c.y + sin(a0) * r))
		st.add_vertex(Vector3(c.x + cos(a1) * r, y, c.y + sin(a1) * r))
	return st.commit()
