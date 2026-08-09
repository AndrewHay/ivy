class_name IvyEnvironment
extends RefCounted

## Public environment API (SD-ENV). Owns the sparse field and the light bake, and
## applies one EWMA step of light memory per tick (SD-ENV-8).
##
## The bake is a cache, not an architecture: it is reachable only through `build` and
## `invalidate(aabb)`, and nothing in the physiology or geometry layer may know it
## exists (SD-ENV-7).

## D_L = 0.0864 · P̄_L (SD-ENV-2), converting W/m² to mol m⁻² day⁻¹.
const DL_SCALE := 0.0864

## The baked driving table is hourly, so one EWMA step advances one game-hour. This is
## the same step size `set_light_ewma_steady_state` solves its fixed point over.
const EWMA_STEP_DAYS := 1.0 / 24.0

var params: IvyParams
var surface: SurfaceQuery
var solar: Solar

var _field: SparseHashField
var _grid: CellGrid
var _bake: LightBake
var _writer_guard: Object = null
## Sky-only P̄_L, used as the out-of-shell read fallback (SD-EDGE-15). Reading zero
## there would fabricate a light gradient pointing back at the wall.
var _baseline_p_bar: float = 0.0


func build(p: IvyParams, surf: SurfaceQuery, sun: Solar = null) -> void:
	params = p
	surface = surf
	solar = sun if sun != null else Solar.new(p)
	_grid = CellGrid.new(params.field_cell)
	_field = SparseHashField.new(params.field_cell)
	# Grow by a cell beyond the shell halfwidth so the outermost allocated layer still
	# has neighbours on all sides to interpolate against (AR-AMBIG-1).
	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)
	_field.allocate_shell(surface, params.field_shell_halfwidth, bounds)
	_field.set_all(SparseHashField.Channel.CROWDING, 0.0)
	_field.set_all(SparseHashField.Channel.MATERIAL_ID, float(MaterialRegistry.BRICK_WALL))
	_bake = LightBake.new(params, solar)
	_bake.bake(surface, bounds)
	_bake.fill_field(surface, _field, _grid)
	_baseline_p_bar = _bake.diffuse_baseline_p_bar()
	warm_up(params.light_warmup_days)


func set_writer_guard(guard: Object) -> void:
	_writer_guard = guard


func tick(dt_sim: float, game_day: float) -> void:
	if _field == null:
		return
	_field.advance_light_ewma(params.light_ewma_alpha(dt_sim), _hour_index(game_day))


## Brings light memory to the state it would hold after an unbounded run at the fixed
## Phase 1 date. Solved in closed form rather than by iterating `light_warmup_days` of
## ticks: same recurrence, but exact and free (SD-TIME-7).
func warm_up(_days: float) -> void:
	if _field == null:
		return
	_field.set_light_ewma_steady_state(
		params.light_ewma_alpha(EWMA_STEP_DAYS), int(params.start_hour) % LightBake.HOURS
	)


## SD-ENV-7 seam for Phase 2 moving geometry. Re-bakes and re-fills only the affected
## region, then re-warms, because light memory over those cells is now wrong.
func invalidate(aabb: AABB) -> void:
	if _bake == null:
		return
	_bake.rebake_region(surface, aabb)
	_bake.fill_field(surface, _field, _grid, aabb)
	warm_up(params.light_warmup_days)


func sample_D_L(p: Vector3, tip_id: int, seg: int) -> float:
	return DL_SCALE * _sample(SparseHashField.Channel.P_BAR_L, p, tip_id, seg, _baseline_p_bar)


func sample_crowding(p: Vector3, tip_id: int, seg: int) -> float:
	return _sample(SparseHashField.Channel.CROWDING, p, tip_id, seg, 0.0)


func sample_SVF(p: Vector3, tip_id: int, seg: int) -> float:
	return _sample(SparseHashField.Channel.SVF, p, tip_id, seg, 1.0)


func sample_f_M(_p: Vector3) -> float:
	# Present in the equations, pinned to 1.0 (INV-9, SD-ENV-9).
	return 1.0


func sample_material_id(p: Vector3) -> int:
	return int(_field.read_trilinear(
		SparseHashField.Channel.MATERIAL_ID,
		surface.project_to_shell(p),
		MaterialRegistry.BRICK_WALL
	))


func grad_S_D_L(p: Vector3, basis: Basis, tip_id: int, seg: int) -> Vector3:
	return _grad(
		SparseHashField.Channel.P_BAR_L, p, basis, tip_id, seg, _baseline_p_bar
	) * DL_SCALE


func grad_S_crowding(p: Vector3, basis: Basis, tip_id: int, seg: int) -> Vector3:
	return _grad(SparseHashField.Channel.CROWDING, p, basis, tip_id, seg, 0.0)


func deposit_crowding(p: Vector3, amount: float) -> void:
	var slot := _field.slot_of_cell(_grid.cell_of(surface.project_to_shell(p)))
	if slot < 0:
		slot = _field.ensure_cell(_grid.cell_of(surface.project_to_shell(p)))
	_field.add_slot(SparseHashField.Channel.CROWDING, slot, amount, 0.0, 1.0)


## Mean P̄_L over every allocated cell whose surface normal faces `dir`, for the
## SD-ENV-10 regression check. Diagnostic only; not part of the simulation path.
func mean_p_bar_facing(dir: Vector3, min_dot: float = 0.85) -> float:
	var sum := 0.0
	var n := 0
	for slot in _field.slot_count():
		var cell := CellGrid.unpack_key(_field.cell_key(slot))
		var point := _grid.cell_point(cell)
		if surface.surface_normal(point).dot(dir) < min_dot:
			continue
		sum += _field.read_trilinear(
			SparseHashField.Channel.P_BAR_L, surface.project_to_shell(point), _baseline_p_bar
		)
		n += 1
	return sum / float(n) if n > 0 else 0.0


func _hour_index(game_day: float) -> int:
	return int(floor(solar.hour_of_day(game_day))) % LightBake.HOURS


func _sample(channel: int, p: Vector3, tip_id: int, seg: int, fallback: float) -> float:
	# `field_sample_jitter()` is already `ratio · field_cell`; scaling by the cell again
	# would collapse the offset to ~1 mm and defeat the SD-ENV-4 de-banding.
	var j := Hash64.jitter_vec3(tip_id, seg, channel) * params.field_sample_jitter()
	var pe := surface.project_to_shell(p + j)
	return _field.read_trilinear(channel, pe, fallback)


func _grad(channel: int, p: Vector3, basis: Basis, tip_id: int, seg: int, fallback: float) -> Vector3:
	var eps := params.gradient_epsilon()
	var u := basis.x
	var v := basis.y
	var ddu := (
		_sample(channel, p + u * eps, tip_id, seg + 1000, fallback)
		- _sample(channel, p - u * eps, tip_id, seg + 1001, fallback)
	) / (2.0 * eps)
	var ddv := (
		_sample(channel, p + v * eps, tip_id, seg + 1002, fallback)
		- _sample(channel, p - v * eps, tip_id, seg + 1003, fallback)
	) / (2.0 * eps)
	return u * ddu + v * ddv
