## Coarse XZ occupancy with lazy clearance field and A* routing (v3 path-first).
class_name VillageOccupancyGrid
extends RefCounted

const SQRT2 := 1.4142135623730951

var _bounds: Rect2
var _cell: float
var _nx: int
var _ny: int
## PackedByteArray: 1 = blocked, 0 = free
var _blocked: PackedByteArray
var _dist_dirty: bool = true
## Approximate distance (m) to nearest blocked cell centre; INF for interior unreachable (should not happen)
var _dist: PackedFloat32Array

func _init(world: Rect2, cell_size: float = 1.0) -> void:
	assert(cell_size > 0.0)
	_bounds = world
	_cell = cell_size
	var w := world.size.x
	var h := world.size.y
	_nx = maxi(1, int(ceil(w / _cell)))
	_ny = maxi(1, int(ceil(h / _cell)))
	_blocked.resize(_nx * _ny)
	_dist.resize(_nx * _ny)


func copy() -> VillageOccupancyGrid:
	var g: VillageOccupancyGrid = (load(get_script().resource_path) as GDScript).new(_bounds, _cell)
	g._blocked = _blocked.duplicate()
	g._dist = _dist.duplicate()
	g._dist_dirty = _dist_dirty
	return g


func _invalidate_distance() -> void:
	_dist_dirty = true


func _idx(ix: int, iy: int) -> int:
	return iy * _nx + ix


func _world_to_cell(p: Vector2) -> Vector2i:
	var lx := (p.x - _bounds.position.x) / _cell
	var ly := (p.y - _bounds.position.y) / _cell
	return Vector2i(clampi(int(floor(lx)), 0, _nx - 1), clampi(int(floor(ly)), 0, _ny - 1))


func _cell_centre_world(ix: int, iy: int) -> Vector2:
	return Vector2(
		_bounds.position.x + (float(ix) + 0.5) * _cell,
		_bounds.position.y + (float(iy) + 0.5) * _cell
	)


func _mark_blocked_ix(ix: int, iy: int) -> void:
	var i := _idx(ix, iy)
	if _blocked[i] == 0:
		_blocked[i] = 1
		_invalidate_distance()


func block_rect(r: Rect2, margin: float) -> void:
	var rr := r.abs()
	if margin != 0.0:
		rr = rr.grow(margin)
	var p0 := _world_to_cell(rr.position)
	var p1 := _world_to_cell(rr.position + rr.size - Vector2(1e-6, 1e-6))
	for ix in range(p0.x, p1.x + 1):
		for iy in range(p0.y, p1.y + 1):
			_mark_blocked_ix(ix, iy)


func block_circle(c: Vector2, radius: float) -> void:
	var cc := _world_to_cell(c)
	var cells_r := int(ceil(radius / _cell)) + 1
	var r2 := radius * radius
	for dx in range(-cells_r, cells_r + 1):
		for dy in range(-cells_r, cells_r + 1):
			var ix := cc.x + dx
			var iy := cc.y + dy
			if ix < 0 or iy < 0 or ix >= _nx or iy >= _ny:
				continue
			var wc := _cell_centre_world(ix, iy)
			if wc.distance_squared_to(c) <= r2:
				_mark_blocked_ix(ix, iy)


func block_outside_circle(c: Vector2, radius: float) -> void:
	var cc := _world_to_cell(c)
	var cells_r := int(ceil(radius / _cell)) + 1
	var r2 := radius * radius
	for ix in range(_nx):
		for iy in range(_ny):
			var wc := _cell_centre_world(ix, iy)
			if wc.distance_squared_to(c) > r2:
				_mark_blocked_ix(ix, iy)


func block_polyline(poly: Variant, radius: float) -> void:
	var pts: Array = poly as Array
	if pts.is_empty():
		return
	var r2 := radius * radius
	var pad := int(ceil(radius / _cell)) + 2
	for si in range(pts.size() - 1):
		var a: Vector2 = pts[si] as Vector2
		var b: Vector2 = pts[si + 1] as Vector2
		var smin := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(radius, radius)
		var smax := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(radius, radius)
		var p0 := _world_to_cell(smin)
		var p1 := _world_to_cell(smax)
		p0.x = clampi(p0.x - pad, 0, _nx - 1)
		p0.y = clampi(p0.y - pad, 0, _ny - 1)
		p1.x = clampi(p1.x + pad, 0, _nx - 1)
		p1.y = clampi(p1.y + pad, 0, _ny - 1)
		for ix in range(p0.x, p1.x + 1):
			for iy in range(p0.y, p1.y + 1):
				var wc := _cell_centre_world(ix, iy)
				if _point_segment_dist_sq(wc, a, b) <= r2:
					_mark_blocked_ix(ix, iy)


func _point_segment_dist_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab2 := ab.length_squared()
	if ab2 < 1e-12:
		return p.distance_squared_to(a)
	var t := clampf(p.dot(ab) - a.dot(ab), 0.0, ab2) / ab2
	var proj := a + ab * t
	return p.distance_squared_to(proj)


func is_free(p: Vector2) -> bool:
	var c := _world_to_cell(p)
	return _blocked[_idx(c.x, c.y)] == 0


## Count distinct free cells hit by rays in a symmetric fan (capacity heuristic for “open side”).
func count_free_fan_cells(
		origin: Vector2,
		dir_world: Vector2,
		radius_m: float,
		half_spread_deg: float,
		n_rays: int,
		radius_steps: int,
) -> int:
	if radius_m <= 0.01 or n_rays < 1 or radius_steps < 1:
		return 0
	var d0 := dir_world
	if d0.length_squared() < 1e-8:
		return 0
	d0 = d0.normalized()
	var have := {}
	var cnt := 0
	var spread := deg_to_rad(half_spread_deg)
	for ri: int in n_rays:
		var t: float = 0.0
		if n_rays > 1:
			t = lerpf(-spread, spread, float(ri) / float(n_rays - 1))
		var ray_dir: Vector2 = d0.rotated(t)
		for k: int in range(1, radius_steps + 1):
			var dist: float = radius_m * float(k) / float(radius_steps)
			var p: Vector2 = origin + ray_dir * dist
			if not is_free(p):
				continue
			var c := _world_to_cell(p)
			var key: int = c.y * _nx + c.x
			if have.has(key):
				continue
			have[key] = true
			cnt += 1
	return cnt


func _ensure_distance_field() -> void:
	if not _dist_dirty:
		return
	## Two-pass 8-neighbor chamfer (fast O(n); good enough for gradients + A* weights).
	var inf := INF
	for i in range(_dist.size()):
		_dist[i] = inf if _blocked[i] == 0 else 0.0
	var c1 := _cell
	var c2 := SQRT2 * _cell
	for iy in range(_ny):
		for ix in range(_nx):
			var i := _idx(ix, iy)
			if _blocked[i] != 0:
				continue
			var d: float = _dist[i]
			if ix > 0:
				d = minf(d, _dist[_idx(ix - 1, iy)] + c1)
			if iy > 0:
				d = minf(d, _dist[_idx(ix, iy - 1)] + c1)
			if ix > 0 and iy > 0:
				d = minf(d, _dist[_idx(ix - 1, iy - 1)] + c2)
			if ix < _nx - 1 and iy > 0:
				d = minf(d, _dist[_idx(ix + 1, iy - 1)] + c2)
			_dist[i] = d
	for iy2 in range(_ny - 1, -1, -1):
		for ix2 in range(_nx - 1, -1, -1):
			var j := _idx(ix2, iy2)
			if _blocked[j] != 0:
				continue
			var d2: float = _dist[j]
			if ix2 < _nx - 1:
				d2 = minf(d2, _dist[_idx(ix2 + 1, iy2)] + c1)
			if iy2 < _ny - 1:
				d2 = minf(d2, _dist[_idx(ix2, iy2 + 1)] + c1)
			if ix2 < _nx - 1 and iy2 < _ny - 1:
				d2 = minf(d2, _dist[_idx(ix2 + 1, iy2 + 1)] + c2)
			if ix2 > 0 and iy2 < _ny - 1:
				d2 = minf(d2, _dist[_idx(ix2 - 1, iy2 + 1)] + c2)
			_dist[j] = d2
	_dist_dirty = false


## Warm the distance field once after the grid is fully blocked (saves first-astar latency).
func ensure_clearance_field() -> void:
	_ensure_distance_field()


func clearance(p: Vector2) -> float:
	_ensure_distance_field()
	var c := _world_to_cell(p)
	var i := _idx(c.x, c.y)
	if _blocked[i] != 0:
		return 0.0
	return _dist[i]


func clearance_gradient(p: Vector2) -> Vector2:
	_ensure_distance_field()
	var c := _world_to_cell(p)
	var h := _cell
	var gx := (clearance(p + Vector2(h, 0.0)) - clearance(p - Vector2(h, 0.0))) * 0.5
	var gy := (clearance(p + Vector2(0.0, h)) - clearance(p - Vector2(0.0, h))) * 0.5
	var g := Vector2(gx, gy)
	if g.length_squared() < 1e-16:
		return Vector2.RIGHT
	return g.normalized()


func astar(
	a: Vector2,
	b: Vector2,
	clearance_weight: float = 2.0,
	min_clearance: float = 0.0,
) -> PackedVector2Array:
	_ensure_distance_field()
	var ca := _world_to_cell(a)
	var cb := _world_to_cell(b)
	if _blocked[_idx(ca.x, ca.y)] != 0 or _blocked[_idx(cb.x, cb.y)] != 0:
		return PackedVector2Array()
	var ag := AStarGrid2D.new()
	ag.region = Rect2i(0, 0, _nx, _ny)
	ag.cell_size = Vector2(_cell, _cell)
	ag.offset = _bounds.position
	ag.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	ag.update()
	for iy in range(_ny):
		for ix in range(_nx):
			var id := Vector2i(ix, iy)
			if _blocked[_idx(ix, iy)] != 0:
				ag.set_point_solid(id, true)
				continue
			var d_here: float = _dist[_idx(ix, iy)]
			if d_here + 1e-6 < min_clearance:
				ag.set_point_solid(id, true)
				continue
			var pen := clearance_weight / (d_here + 0.5)
			ag.set_point_weight_scale(id, 1.0 + pen)
	var wp: PackedVector2Array = ag.get_point_path(ca, cb)
	if wp.is_empty():
		return wp
	wp[0] = a
	wp[wp.size() - 1] = b
	return wp
