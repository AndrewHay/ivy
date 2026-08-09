class_name SparseHashField
extends RefCounted

## Sparse allocation plus parallel structure-of-arrays channels (AR-FIELD-2).
##
## `read_trilinear` is the only read primitive. There is deliberately no nearest-cell
## accessor on the public surface — SD-ENV-3 is enforced by absence rather than by
## discipline, because nearest-cell sampling is the direct cause of the grid banding
## on the artifact blacklist (R-3).

enum Channel { P_BAR_L, CROWDING, SVF, MATERIAL_ID, F_M }

const HOURS := 24

var _grid: CellGrid
var _slot_of: Dictionary = {}
var _cells: PackedInt64Array = PackedInt64Array()
var _ch: Array = []
## slot * HOURS + hour -> baked instantaneous P (SD-ENV-6).
var _p_hour: PackedFloat32Array = PackedFloat32Array()


func _init(cell_size: float) -> void:
	_grid = CellGrid.new(cell_size)
	for _i in Channel.size():
		_ch.append(PackedFloat32Array())


func slot_count() -> int:
	return _cells.size()


func cell_key(slot: int) -> int:
	return _cells[slot]


## Allocates every cell whose lattice point lies within `halfwidth` of the surface.
## Three layers, not one: trilinear interpolation of a single-layer shell is undefined
## (AR-AMBIG-1).
func allocate_shell(surface: SurfaceQuery, halfwidth: float, bounds: AABB) -> void:
	var lo := _grid.cell_of(bounds.position)
	var hi := _grid.cell_of(bounds.end)
	for yi in range(lo.y, hi.y + 1):
		for xi in range(lo.x, hi.x + 1):
			for zi in range(lo.z, hi.z + 1):
				var cell := Vector3i(xi, yi, zi)
				if absf(surface.signed_distance(_grid.cell_point(cell))) <= halfwidth:
					ensure_cell(cell)


func ensure_cell(c: Vector3i) -> int:
	var key := CellGrid.pack_key(c)
	if _slot_of.has(key):
		return _slot_of[key]
	var slot := _cells.size()
	_slot_of[key] = slot
	_cells.append(key)
	for i in range(_ch.size()):
		var arr: PackedFloat32Array = _ch[i]
		arr.append(0.0)
	if not _p_hour.is_empty():
		_p_hour.resize(_cells.size() * HOURS)
	return slot


func set_all(channel: int, value: float) -> void:
	var arr: PackedFloat32Array = _ch[channel]
	for i in range(arr.size()):
		arr[i] = value


func write_slot(channel: int, slot: int, value: float) -> void:
	var arr: PackedFloat32Array = _ch[channel]
	arr[slot] = value


func add_slot(channel: int, slot: int, delta: float, lo: float, hi: float) -> void:
	var arr: PackedFloat32Array = _ch[channel]
	arr[slot] = clampf(arr[slot] + delta, lo, hi)


func ensure_p_hour() -> void:
	_p_hour.resize(_cells.size() * HOURS)


func set_p_hour(slot: int, hour: int, value: float) -> void:
	_p_hour[slot * HOURS + hour] = value


func p_hour(slot: int, hour: int) -> float:
	return _p_hour[slot * HOURS + hour]


## One SD-ENV-8 EWMA step over every allocated cell, driven by the baked table.
## `a` is recomputed by the caller each tick from the live `light_memory`, so a
## runtime parameter edit changes the next step only and never rewrites history.
func advance_light_ewma(a: float, hour: int) -> void:
	if _p_hour.is_empty():
		return
	var arr: PackedFloat32Array = _ch[Channel.P_BAR_L]
	var b := 1.0 - a
	var n := arr.size()
	for slot in n:
		arr[slot] = a * arr[slot] + b * _p_hour[slot * HOURS + hour]


## Closed-form fixed point of `advance_light_ewma` under a periodic driving signal:
## the state the EWMA converges to when the date is fixed and weather pinned
## (SD-TIME-6, INV-9). `start_hour` is the hour the next step will apply.
##
## Solving x = a^24 x + (1-a) * sum_j a^(23-j) P_(start+j) exactly is both faster and
## more accurate than iterating the recurrence for a warm-up window, and it is the
## same recurrence — not a different model.
func set_light_ewma_steady_state(a: float, start_hour: int) -> void:
	if _p_hour.is_empty():
		return
	var denom := 1.0 - pow(a, float(HOURS))
	if denom < 1e-9:
		return
	var w := PackedFloat32Array()
	w.resize(HOURS)
	for j in HOURS:
		w[j] = (1.0 - a) * pow(a, float(HOURS - 1 - j)) / denom
	var arr: PackedFloat32Array = _ch[Channel.P_BAR_L]
	for slot in arr.size():
		var base := slot * HOURS
		var acc := 0.0
		for j in HOURS:
			acc += w[j] * _p_hour[base + (start_hour + j) % HOURS]
		arr[slot] = acc


func read_trilinear(channel: int, p: Vector3, fallback: float) -> float:
	var base := Vector3i(
		int(floor(p.x / _grid.cell_size)),
		int(floor(p.y / _grid.cell_size)),
		int(floor(p.z / _grid.cell_size))
	)
	var fx := (p.x / _grid.cell_size) - float(base.x)
	var fy := (p.y / _grid.cell_size) - float(base.y)
	var fz := (p.z / _grid.cell_size) - float(base.z)
	var sum := 0.0
	var weight_sum := 0.0
	var arr: PackedFloat32Array = _ch[channel]
	for dx in 2:
		for dy in 2:
			for dz in 2:
				var key := CellGrid.pack_key(base + Vector3i(dx, dy, dz))
				if not _slot_of.has(key):
					continue
				var w := _tri_weight(fx, dx) * _tri_weight(fy, dy) * _tri_weight(fz, dz)
				sum += w * arr[_slot_of[key]]
				weight_sum += w
	if weight_sum < 1e-6:
		return fallback
	# Renormalizing by the realized weight, rather than blending unallocated corners
	# against `fallback`, is what stops the shell boundary fabricating a strong radial
	# gradient that would yank floating tips back at the wall (AR-AMBIG-2).
	return sum / weight_sum


func slot_of_cell(c: Vector3i) -> int:
	var key := CellGrid.pack_key(c)
	return _slot_of.get(key, -1)


func _tri_weight(f: float, corner: int) -> float:
	return f if corner == 1 else 1.0 - f
