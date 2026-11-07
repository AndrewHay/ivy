class_name VillagePondShape
extends RefCounted

## Organic pond outline built around local origin, then translated to [member _center].
## Red Blob Games noisy edges on an irregular seed loop.

const MEAN_WATER_RADIUS_M := VillagePondSite.MEAN_WATER_RADIUS_M
const BANK_OUTER_M := VillagePondSite.BANK_OUTER_M
const BANK_RING_WIDTH_M := VillagePondSite.BANK_RING_WIDTH_M
const SIZE_SCALE := VillagePondSite.SIZE_SCALE

const SEED_VERTEX_COUNT := 16
const RADIUS_MIN_M := 0.88 * SIZE_SCALE
const RADIUS_MAX_M := 2.45 * SIZE_SCALE
const _HARMONIC_K := [4, 7, 11, 13]
const _HARMONIC_AMP := [0.48, 0.39, 0.27, 0.18]
const NOISY_LEVELS := 5
const NOISY_AMPLITUDE := 0.48
const LAND_CELL_SCALE := 2.35
const SHAPE_LCG_SEED := 8624
const SMOOTH_ITERATIONS := 5
const RENDER_SPLINE_SAMPLES := 720

static var _classic: VillagePondShape
static var _active: VillagePondShape

var _center: Vector2 = Vector2.ZERO
var _water_cache: PackedVector2Array = PackedVector2Array()
var _water_render_cache: PackedVector2Array = PackedVector2Array()
var _bank_cache: PackedVector2Array = PackedVector2Array()
var _scatter_exclusion_cache: PackedVector2Array = PackedVector2Array()
const GRASS_SHORELINE_RAY_COUNT := 128
var _grass_shoreline_inner: PackedVector2Array = PackedVector2Array()
var _grass_shoreline_outer: PackedVector2Array = PackedVector2Array()
var _grass_bank_outer_fast: PackedVector2Array = PackedVector2Array()
var _grass_water_exclusion_fast: PackedVector2Array = PackedVector2Array()


static func classic() -> VillagePondShape:
	if _classic == null:
		_classic = VillagePondShape.new(VillagePondSite.CLASSIC_CENTER)
	return _classic


static func at(center: Vector2) -> VillagePondShape:
	return VillagePondShape.new(center)


static func set_active(shape: VillagePondShape) -> void:
	_active = shape


static func active() -> VillagePondShape:
	if _active != null:
		return _active
	return classic()


static func clear_cache_for_tests() -> void:
	_classic = null
	_active = null


func _init(center: Vector2 = Vector2.ZERO) -> void:
	_center = center


func center_xz() -> Vector2:
	return _center


func _water_outline_local() -> PackedVector2Array:
	if _water_cache.is_empty():
		_water_cache = _translate_outline(_build_water_outline(Vector2.ZERO))
	return _water_cache


func _water_render_outline_local() -> PackedVector2Array:
	if _water_render_cache.is_empty():
		var chaikin := _chaikin_closed(_local_water_render_outline(), SMOOTH_ITERATIONS)
		_water_render_cache = _translate_outline(_catmull_closed_resample(chaikin, RENDER_SPLINE_SAMPLES))
	return _water_render_cache


func _bank_outer_outline_local() -> PackedVector2Array:
	if _bank_cache.is_empty():
		var local_bank := _offset_outline_by_normal(
			_local_water_render_outline(), BANK_RING_WIDTH_M)
		_bank_cache = _translate_outline(local_bank)
	return _bank_cache


func _scatter_exclusion_outline_local() -> PackedVector2Array:
	if _scatter_exclusion_cache.is_empty():
		var local_bank := _offset_outline_by_normal(
			_local_water_render_outline(), BANK_RING_WIDTH_M + VillagePondSite.SCATTER_CLEARANCE_M)
		_scatter_exclusion_cache = _translate_outline(local_bank)
	return _scatter_exclusion_cache


func _local_water_render_outline() -> PackedVector2Array:
	var raw := _build_water_outline(Vector2.ZERO)
	return _catmull_closed_resample(_chaikin_closed(raw, SMOOTH_ITERATIONS), RENDER_SPLINE_SAMPLES)


func _translate_outline(local_poly: PackedVector2Array) -> PackedVector2Array:
	if _center == Vector2.ZERO:
		return local_poly
	var out := PackedVector2Array()
	out.resize(local_poly.size())
	for i in range(local_poly.size()):
		out[i] = local_poly[i] + _center
	return out


func _build_water_surface_mesh(y: float) -> ArrayMesh:
	var poly := _water_render_outline_local()
	if poly.size() < 3:
		return ArrayMesh.new()
	var indices := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv_scale := MEAN_WATER_RADIUS_M * 2.4
	for i in range(poly.size()):
		var v: Vector2 = poly[i]
		st.set_uv((v - _center) / uv_scale + Vector2(0.5, 0.5))
		st.add_vertex(Vector3(v.x, y, v.y))
	if indices.is_empty():
		push_warning("VillagePondShape: triangulation failed; using fan fallback")
		for i in range(1, poly.size() - 1):
			st.add_index(0)
			st.add_index(i)
			st.add_index(i + 1)
	else:
		for idx in indices:
			st.add_index(idx)
	st.generate_normals()
	return st.commit()


func _is_in_water(p: Vector2, margin_m: float = 0.0) -> bool:
	var poly := _water_render_outline_local()
	if margin_m <= 0.0:
		return Geometry2D.is_point_in_polygon(p, poly)
	var expanded := _offset_outline_by_normal(_untranslate(poly), margin_m)
	return Geometry2D.is_point_in_polygon(p, _translate_outline(expanded))


func _is_on_clover_bank(p: Vector2) -> bool:
	if _is_in_water(p, 0.06):
		return false
	return Geometry2D.is_point_in_polygon(p, _bank_outer_outline_local())


func _downsample_closed_poly(poly: PackedVector2Array, target: int) -> PackedVector2Array:
	var n := poly.size()
	if n <= target or target < 3:
		return poly
	var out := PackedVector2Array()
	out.resize(target)
	for i in range(target):
		out[i] = poly[int(i * n / target) % n]
	return out


func _ensure_grass_shoreline_rays() -> void:
	if not _grass_shoreline_inner.is_empty():
		return
	_grass_shoreline_inner = _downsample_closed_poly(
		_water_render_outline_local(), GRASS_SHORELINE_RAY_COUNT)
	_grass_shoreline_outer = _downsample_closed_poly(
		_bank_outer_outline_local(), GRASS_SHORELINE_RAY_COUNT)
	_grass_bank_outer_fast = _grass_shoreline_outer
	var expanded := _offset_outline_by_normal(
		_untranslate(_water_render_outline_local()),
		VillagePondSite.SCATTER_CLEARANCE_M)
	_grass_water_exclusion_fast = _downsample_closed_poly(
		_translate_outline(expanded), GRASS_SHORELINE_RAY_COUNT)


func _is_in_water_grass_exclusion(p: Vector2) -> bool:
	_ensure_grass_shoreline_rays()
	return Geometry2D.is_point_in_polygon(p, _grass_water_exclusion_fast)


func _is_on_bank_outer_grass(p: Vector2) -> bool:
	_ensure_grass_shoreline_rays()
	return Geometry2D.is_point_in_polygon(p, _grass_bank_outer_fast)


## Same contract as [_bank_shoreline_along] but ~64 radial samples (grass hot path).
func _bank_shoreline_along_grass(p: Vector2) -> float:
	if _is_in_water(p, 0.04):
		return -1.0
	if not Geometry2D.is_point_in_polygon(p, _bank_outer_outline_local()):
		return -1.0
	_ensure_grass_shoreline_rays()
	var n := mini(_grass_shoreline_inner.size(), _grass_shoreline_outer.size())
	if n == 0:
		return -1.0
	var best_dist := INF
	var best_along := 0.5
	for i in range(n):
		var a: Vector2 = _grass_shoreline_inner[i]
		var b: Vector2 = _grass_shoreline_outer[i]
		var ab := b - a
		var ab_len_sq := ab.length_squared()
		var t := 0.5
		if ab_len_sq > 1e-10:
			t = clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
		var q := a.lerp(b, t)
		var d := p.distance_to(q)
		if d < best_dist:
			best_dist = d
			best_along = t
	return best_along


## 0 = inner water edge, 1 = outer bank lip; -1 if not on bank band.
func _bank_shoreline_along(p: Vector2) -> float:
	if _is_in_water(p, 0.04):
		return -1.0
	if not Geometry2D.is_point_in_polygon(p, _bank_outer_outline_local()):
		return -1.0
	var inner := _water_render_outline_local()
	var outer := _bank_outer_outline_local()
	var n := mini(inner.size(), outer.size())
	if n == 0:
		return -1.0
	var best_dist := INF
	var best_along := 0.5
	for i in range(n):
		var a: Vector2 = inner[i]
		var b: Vector2 = outer[i]
		var ab := b - a
		var ab_len_sq := ab.length_squared()
		var t := 0.5
		if ab_len_sq > 1e-10:
			t = clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
		var q := a.lerp(b, t)
		var d := p.distance_to(q)
		if d < best_dist:
			best_dist = d
			best_along = t
	return best_along


func _blocks_scatter_at(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, _scatter_exclusion_outline_local())


func _untranslate(poly: PackedVector2Array) -> PackedVector2Array:
	if _center == Vector2.ZERO:
		return poly
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in range(poly.size()):
		out[i] = poly[i] - _center
	return out


## World-space bank outer polygon for **this** instance's center.
## Use when validating or querying a specific pond; [method bank_outer_outline_xz]
## reads the global [member _active] shape and ignores which instance you called it on.
func bank_outer_outline_world_xz() -> PackedVector2Array:
	return _bank_outer_outline_local()


# ── Static delegates (legacy call sites) ──────────────────────────────────────

static func water_outline_xz() -> PackedVector2Array:
	return active()._water_outline_local()


static func water_render_outline_xz() -> PackedVector2Array:
	return active()._water_render_outline_local()


static func bank_outer_outline_xz() -> PackedVector2Array:
	return active()._bank_outer_outline_local()


static func build_water_surface_mesh(y: float) -> ArrayMesh:
	return active()._build_water_surface_mesh(y)


static func is_in_water(p: Vector2, margin_m: float = 0.0) -> bool:
	return active()._is_in_water(p, margin_m)


static func is_on_clover_bank(p: Vector2) -> bool:
	return active()._is_on_clover_bank(p)


static func blocks_scatter_at(p: Vector2) -> bool:
	return active()._blocks_scatter_at(p)


static func bank_shoreline_along(p: Vector2) -> float:
	return active()._bank_shoreline_along(p)


static func bank_shoreline_along_grass(p: Vector2) -> float:
	return active()._bank_shoreline_along_grass(p)


static func is_in_water_grass_exclusion(p: Vector2) -> bool:
	return active()._is_in_water_grass_exclusion(p)


static func is_on_bank_outer_grass(p: Vector2) -> bool:
	return active()._is_on_bank_outer_grass(p)


static func _build_water_outline(origin: Vector2) -> PackedVector2Array:
	var corners := _build_irregular_seed_corners(origin)
	var st := SHAPE_LCG_SEED
	var loop: PackedVector2Array = PackedVector2Array()
	for i in range(corners.size()):
		var b0: Vector2 = corners[i]
		var b1: Vector2 = corners[(i + 1) % corners.size()]
		var edge_mid := (b0 + b1) * 0.5
		var outward := edge_mid - origin
		if outward.length_squared() < 1e-8:
			outward = Vector2(1.0, 0.0)
		else:
			outward = outward.normalized()
		var land_cell := edge_mid + outward * (MEAN_WATER_RADIUS_M * LAND_CELL_SCALE)
		var edge: Array[Vector2] = []
		st = _noisy_edge_collect(edge, origin, land_cell, b0, b1, NOISY_LEVELS, NOISY_AMPLITUDE, st)
		for j in range(edge.size()):
			if j == edge.size() - 1 and i < corners.size() - 1:
				continue
			loop.append(edge[j])
	return loop


static func _build_irregular_seed_corners(origin: Vector2) -> Array[Vector2]:
	var st := SHAPE_LCG_SEED
	var corners: Array[Vector2] = []
	st = _lcg_step(st)
	var angle_offset: float = _lcg_f01(st) * TAU
	for i in range(SEED_VERTEX_COUNT):
		var ang: float = angle_offset + (float(i) / float(SEED_VERTEX_COUNT)) * TAU
		var r: float = MEAN_WATER_RADIUS_M
		for hi in range(_HARMONIC_K.size()):
			st = _lcg_step(st)
			var phase: float = _lcg_f01(st) * TAU
			r += _HARMONIC_AMP[hi] * sin(float(_HARMONIC_K[hi]) * ang + phase)
		st = _lcg_step(st)
		r += (_lcg_f01(st) - 0.5) * 0.12 * SIZE_SCALE
		r = clampf(r, RADIUS_MIN_M, RADIUS_MAX_M)
		corners.append(origin + Vector2(cos(ang), sin(ang)) * r)
	return corners


static func _catmull_closed_resample(poly: PackedVector2Array, samples: int) -> PackedVector2Array:
	if poly.size() < 4 or samples < 4:
		return poly
	var n := poly.size()
	var out := PackedVector2Array()
	out.resize(samples)
	for s in range(samples):
		var t_seg := (float(s) / float(samples)) * float(n)
		var i := int(floor(t_seg)) % n
		var u: float = t_seg - floor(t_seg)
		var p0: Vector2 = poly[(i - 1 + n) % n]
		var p1: Vector2 = poly[i]
		var p2: Vector2 = poly[(i + 1) % n]
		var p3: Vector2 = poly[(i + 2) % n]
		out[s] = _catmull_rom(p0, p1, p2, p3, u)
	return out


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _chaikin_closed(poly: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var pts := poly
	for _pass in range(iterations):
		var n := pts.size()
		if n < 3:
			break
		var next := PackedVector2Array()
		for i in range(n):
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[(i + 1) % n]
			next.append(p0.lerp(p1, 0.25))
			next.append(p0.lerp(p1, 0.75))
		pts = next
	return pts


static func _offset_outline_by_normal(poly: PackedVector2Array, outward_m: float) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	out.resize(n)
	var origin := Vector2.ZERO
	for i in range(n):
		var prev: Vector2 = poly[(i - 1 + n) % n]
		var cur: Vector2 = poly[i]
		var next: Vector2 = poly[(i + 1) % n]
		var tangent := (next - prev)
		if tangent.length_squared() < 1e-10:
			tangent = next - cur
		if tangent.length_squared() < 1e-10:
			out[i] = cur
			continue
		tangent = tangent.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		if normal.dot(cur - origin) < 0.0:
			normal = -normal
		out[i] = cur + normal * outward_m
	return out


static func _noisy_edge_collect(
		out: Array[Vector2],
		ra: Vector2,
		rb: Vector2,
		b0: Vector2,
		b1: Vector2,
		level: int,
		amplitude: float,
		st: int) -> int:
	if level <= 0:
		out.append(b0)
		return st
	st = _lcg_step(st)
	var rm := ra.lerp(rb, 0.5 + (_lcg_f01(st) - 0.5) * amplitude)
	var bd := b1 - b0
	var denom := (rb.x - ra.x) * bd.y - (rb.y - ra.y) * bd.x
	var t := 0.5
	if absf(denom) > 1e-8:
		t = ((rm.x - ra.x) * bd.y - (rm.y - ra.y) * bd.x) / denom
		t = clampf(t, 0.08, 0.92)
	else:
		st = _lcg_step(st)
		t = 0.5 + (_lcg_f01(st) - 0.5) * amplitude
		t = clampf(t, 0.08, 0.92)
	var q := b0.lerp(b1, t)
	st = _noisy_edge_collect(out, ra, rm, b0, q, level - 1, amplitude, st)
	st = _noisy_edge_collect(out, rm, rb, q, b1, level - 1, amplitude, st)
	return st


static func _lcg_step(state: int) -> int:
	return (state * 1664525 + 1013904223) & 0x7FFFFFFF


static func _lcg_f01(state: int) -> float:
	return float(state & 0x7FFFFFFF) / float(0x7FFFFFFF)
