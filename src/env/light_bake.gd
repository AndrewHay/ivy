class_name LightBake
extends RefCounted

## SD-ENV-6 static-geometry precomputation, split across two resolutions per
## AR-FIELD-6:
##
##   SVF        coarse `vis_cell` grid, cosine-weighted rays, trilerped up
##   V_hours    same coarse grid, 24-bit direct-sun mask, trilerped up
##   P          full `field_cell` grid, pure arithmetic — needs no rays
##
## The split exists because 64 + 24 rays per fine cell is ~3.5 M GDScript raycasts and
## several seconds of load stall on every run (AR-AMBIG-4).
##
## Everything here is a cache behind `IvyEnvironment.invalidate()` (SD-ENV-7); the
## physiology layer must not know it exists.

const HOURS := 24
const CORNERS := 8

var params: IvyParams
var solar: Solar

var _sun_dir: PackedVector3Array = PackedVector3Array()
var _direct_elevation: PackedFloat32Array = PackedFloat32Array()
var _diffuse_elevation: PackedFloat32Array = PackedFloat32Array()

var _coarse: CellGrid
var _slot_of: Dictionary = {}
var _svf: PackedFloat32Array = PackedFloat32Array()
var _vis: PackedInt32Array = PackedInt32Array()

var _corner_slot: PackedInt32Array = PackedInt32Array()
var _corner_weight: PackedFloat32Array = PackedFloat32Array()


func _init(p: IvyParams, sun: Solar) -> void:
	params = p
	solar = sun
	_coarse = CellGrid.new(params.vis_cell)
	_corner_slot.resize(CORNERS)
	_corner_weight.resize(CORNERS)
	_precompute_sun_path()


# --- Spec section 5 sun model. Pure arithmetic, no geometry. ---


## `visibility` is V in [0,1] — fractional because it is trilerped from the coarse
## 24-bit mask, which is exactly the range spec section 6 gives V.
func p_direct(normal: Vector3, visibility: float, hour: int) -> float:
	var incidence := maxf(0.0, normal.dot(_sun_dir[hour]))
	if incidence <= 0.0:
		return 0.0
	return (
		params.light_p_max
		* params.weather_direct
		* visibility
		* _direct_elevation[hour]
		* incidence
	)


func p_diffuse(svf: float, hour: int) -> float:
	return params.light_p_sky * params.weather_sky * _diffuse_elevation[hour] * svf


func p_at(normal: Vector3, svf: float, visibility: float, hour: int) -> float:
	return p_direct(normal, visibility, hour) + p_diffuse(svf, hour)


## Mean of P over a game-day. Because the date is fixed and weather is pinned
## (SD-TIME-6, INV-9) this is also the value the SD-ENV-8 EWMA converges to.
func daily_mean_p(normal: Vector3, svf: float, visibility: float) -> float:
	var sum := 0.0
	for hour in HOURS:
		sum += p_at(normal, svf, visibility, hour)
	return sum / float(HOURS)


func daily_mean_p_masked(normal: Vector3, svf: float, mask: int) -> float:
	var sum := 0.0
	for hour in HOURS:
		sum += p_at(normal, svf, 1.0 if mask_has_hour(mask, hour) else 0.0, hour)
	return sum / float(HOURS)


## SD-EDGE-15 fallback: diffuse-only light at SVF = 1, for reads outside the
## allocated shell.
func diffuse_baseline_p_bar() -> float:
	var sum := 0.0
	for hour in HOURS:
		sum += p_diffuse(1.0, hour)
	return sum / float(HOURS)


static func mask_has_hour(mask: int, hour: int) -> bool:
	return (mask & (1 << hour)) != 0


func sun_direction_at_hour(hour: int) -> Vector3:
	return _sun_dir[hour]


# --- Raycast products, per point. ---


## Cosine-weighted sky-view factor over the hemisphere about `normal`, restricted to
## the upper hemisphere about +Y (SD-CONV-4). Normalized so an unobstructed vertical
## wall reads 0.5 and an unobstructed upward face reads 1.0.
func sky_view_factor(surface: SurfaceQuery, point: Vector3, normal: Vector3) -> float:
	var n := normal.normalized()
	var basis := Conv.tangent_basis(n)
	var origin := point + n * params.bake_ray_offset
	var rays := params.svf_rays
	var open := 0
	for i in rays:
		var dir := _hemisphere_sample(basis, n, i, rays)
		if dir.y <= 0.0:
			continue
		if not surface.raycast(origin, origin + dir * params.bake_ray_length).hit:
			open += 1
	return float(open) / float(rays)


## 24-bit direct-sun visibility mask. Hours where the sun is down or behind the
## surface are left clear: `p_direct` is zero there anyway, so the raycast is skipped.
func visibility_mask(surface: SurfaceQuery, point: Vector3, normal: Vector3) -> int:
	var n := normal.normalized()
	var origin := point + n * params.bake_ray_offset
	var mask := 0
	for hour in HOURS:
		if _direct_elevation[hour] <= 0.0:
			continue
		var s := _sun_dir[hour]
		if n.dot(s) <= 0.0:
			continue
		if not surface.raycast(origin, origin + s * params.bake_ray_length).hit:
			mask |= 1 << hour
	return mask


# --- Coarse grid. ---


func bake(surface: SurfaceQuery, bounds: AABB) -> void:
	_slot_of.clear()
	_svf = PackedFloat32Array()
	_vis = PackedInt32Array()
	rebake_region(surface, bounds)


## Re-bakes the coarse cells intersecting `bounds`, leaving the rest untouched. This is
## the SD-ENV-7 seam Phase 2's moving geometry calls through.
func rebake_region(surface: SurfaceQuery, bounds: AABB) -> void:
	var lo := _coarse.cell_of(bounds.position)
	var hi := _coarse.cell_of(bounds.end)
	for xi in range(lo.x, hi.x + 1):
		for yi in range(lo.y, hi.y + 1):
			for zi in range(lo.z, hi.z + 1):
				_bake_coarse_cell(surface, Vector3i(xi, yi, zi))


func coarse_count() -> int:
	return _svf.size()


func svf_at(p: Vector3) -> float:
	var count := _gather_corners(p)
	if count == 0:
		return 1.0
	var sum := 0.0
	for k in count:
		sum += _corner_weight[k] * _svf[_corner_slot[k]]
	return clampf(sum, 0.0, 1.0)


func visibility_at(p: Vector3, hour: int) -> float:
	var count := _gather_corners(p)
	if count == 0:
		return 0.0
	return _corner_visibility(count, hour)


# --- Fine grid: the P(cell, hour) table. ---


## Fills the field's static channels and its `P(cell, hour)` table. A non-empty
## `region` restricts the work, which is what makes `invalidate(aabb)` cheap.
func fill_field(
	surface: SurfaceQuery, field: SparseHashField, grid: CellGrid, region: AABB = AABB()
) -> void:
	var limited := region.size.length_squared() > 0.0
	field.ensure_p_hour()
	for slot in field.slot_count():
		var cell := CellGrid.unpack_key(field.cell_key(slot))
		var p := grid.cell_point(cell)
		if limited and not region.has_point(p):
			continue
		var n := surface.surface_normal(p)
		# Read the bake products at the projected surface point, not at the lattice
		# point, so all three shell layers share one surface sample and the field
		# carries no fabricated radial gradient (AR-FIELD-3).
		var on_surface := surface.project_to_shell(p)
		var count := _gather_corners(on_surface)
		var svf := 1.0
		if count > 0:
			svf = 0.0
			for k in count:
				svf += _corner_weight[k] * _svf[_corner_slot[k]]
			svf = clampf(svf, 0.0, 1.0)
		field.write_slot(SparseHashField.Channel.SVF, slot, svf)
		field.write_slot(SparseHashField.Channel.F_M, slot, 1.0)
		for hour in HOURS:
			var v := 0.0
			if count > 0 and _direct_elevation[hour] > 0.0 and n.dot(_sun_dir[hour]) > 0.0:
				v = _corner_visibility(count, hour)
			field.set_p_hour(slot, hour, p_at(n, svf, v, hour))


func _precompute_sun_path() -> void:
	_sun_dir.resize(HOURS)
	_direct_elevation.resize(HOURS)
	_diffuse_elevation.resize(HOURS)
	for hour in HOURS:
		var h := float(hour)
		var s := maxf(0.0, solar.sin_elevation(h))
		_sun_dir[hour] = solar.direction(h)
		_direct_elevation[hour] = pow(s, params.light_elevation_exponent_direct)
		_diffuse_elevation[hour] = pow(s, params.light_elevation_exponent_diffuse)


func _bake_coarse_cell(surface: SurfaceQuery, cell: Vector3i) -> void:
	var p := _coarse.cell_point(cell)
	# A fine sample sits on the surface, so its eight coarse corners can be as far out
	# as one coarse cell diagonal. Baking to that radius guarantees every fine sample
	# has full trilerp support and never falls back to the unallocated defaults.
	if absf(surface.signed_distance(p)) > params.vis_cell * sqrt(3.0):
		return
	var n := surface.surface_normal(p)
	var on_surface := surface.project_to_shell(p)
	var svf := sky_view_factor(surface, on_surface, n)
	var mask := visibility_mask(surface, on_surface, n)
	var key := CellGrid.pack_key(cell)
	if _slot_of.has(key):
		var slot: int = _slot_of[key]
		_svf[slot] = svf
		_vis[slot] = mask
		return
	_slot_of[key] = _svf.size()
	_svf.append(svf)
	_vis.append(mask)


## Collects the allocated corners of the coarse cube containing `p` into
## `_corner_slot` / `_corner_weight`, with weights renormalized to sum to 1. Returns
## the corner count, 0 when nothing is allocated nearby.
func _gather_corners(p: Vector3) -> int:
	var size := _coarse.cell_size
	var bx := int(floor(p.x / size))
	var by := int(floor(p.y / size))
	var bz := int(floor(p.z / size))
	var fx := p.x / size - float(bx)
	var fy := p.y / size - float(by)
	var fz := p.z / size - float(bz)
	var count := 0
	var total := 0.0
	for dx in 2:
		var wx := fx if dx == 1 else 1.0 - fx
		for dy in 2:
			var wy := fy if dy == 1 else 1.0 - fy
			for dz in 2:
				var key := CellGrid.pack_key(Vector3i(bx + dx, by + dy, bz + dz))
				if not _slot_of.has(key):
					continue
				var w := wx * wy * (fz if dz == 1 else 1.0 - fz)
				if w <= 0.0:
					continue
				_corner_slot[count] = _slot_of[key]
				_corner_weight[count] = w
				total += w
				count += 1
	if total < 1e-6:
		return 0
	for k in count:
		_corner_weight[k] /= total
	return count


func _corner_visibility(count: int, hour: int) -> float:
	var bit := 1 << hour
	var v := 0.0
	for k in count:
		if (_vis[_corner_slot[k]] & bit) != 0:
			v += _corner_weight[k]
	# The float32 corner weights sum to 1 only to their own precision, so an
	# all-visible cell lands a few ULPs above 1. Visibility is a fraction by
	# definition and feeds `p_direct` as a multiplier; let it exceed 1 and it
	# silently inflates irradiance.
	return clampf(v, 0.0, 1.0)


## Deterministic cosine-weighted hemisphere direction. Hammersley, not an RNG, so
## INV-7 cannot be perturbed by adding or reordering bake work (SD-RNG-4).
func _hemisphere_sample(basis: Basis, n: Vector3, i: int, count: int) -> Vector3:
	var u1 := (float(i) + 0.5) / float(count)
	# The half-step azimuth offset keeps samples off exactly pi, where the +Y horizon
	# test would otherwise land on a sample and bias a vertical wall's SVF below 0.5.
	var u2 := fmod(_radical_inverse_2(i) + 0.5 / float(count), 1.0)
	var r := sqrt(u1)
	var theta := TAU * u2
	return basis.x * (r * cos(theta)) + basis.y * (r * sin(theta)) + n * sqrt(maxf(0.0, 1.0 - u1))


static func _radical_inverse_2(i: int) -> float:
	var bits := i
	var result := 0.0
	var f := 0.5
	while bits > 0:
		if bits & 1:
			result += f
		bits >>= 1
		f *= 0.5
	return result
