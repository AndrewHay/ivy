extends Node

var params: IvyParams
var clock: SimClock
var solar: Solar
var env: IvyEnvironment
var surface: SurfaceQuery
var plant: PlantData
var tips: TipManager
var ctx: SimContext

var _space: PhysicsDirectSpaceState3D
var _scenario  # StructureScenario
var _seed_index: int = 0


func setup(
	p: IvyParams,
	surf: SurfaceQuery,
	scenario = null,
	seed_index: int = 0
) -> void:
	params = p
	for problem in params.validate():
		push_error("IvyParams: %s" % problem)
	surface = surf
	_scenario = scenario
	_seed_index = seed_index
	clock = SimClock.new(params)
	# Starts paused so nothing advances before a caller asks. Running on the real frame
	# delta from `_ready` makes the tick count depend on wall-clock timing, which breaks
	# reproducibility (INV-7) for anything driving the sim from a script.
	clock.set_speed(SimClock.Speed.PAUSE)
	solar = Solar.new(params)
	env = IvyEnvironment.new()
	env.build(params, surface, solar)
	env.set_writer_guard(Physiology)
	plant = PlantData.new()
	tips = TipManager.new()
	ctx = SimContext.new(params, env, surface, plant, tips, clock)
	if _scenario != null:
		_seed_scenario(_seed_index)
	else:
		_seed_m1()


func set_seed_index(index: int) -> void:
	_seed_index = index


func reseed() -> void:
	clock.tick_index = 0
	clock._update_game_day()
	plant = PlantData.new()
	tips = TipManager.new()
	ctx = SimContext.new(params, env, surface, plant, tips, clock)
	if _scenario != null:
		_seed_scenario(_seed_index)
	else:
		_seed_m1()


func _seed_scenario(index: int) -> void:
	if _scenario == null:
		push_error("SimRoot: no scenario for seed index %d" % index)
		return
	index = clampi(index, 0, _scenario.seed_positions.size() - 1)
	var toward_wall: Vector3 = _scenario.seed_normals[index].normalized()
	var seed_pos: Vector3 = _scenario.seed_positions[index]
	# seed_normals point toward the wall (exterior → interior). Ray from outside
	# through the authored seed hits the exterior face; nearest() fails on MeshSdf
	# when the probe lands inside the hollow (> band from any face).
	var hit := surface.raycast(seed_pos - toward_wall * 3.0, seed_pos + toward_wall * 3.0)
	if hit.hit:
		var pos := hit.position + hit.normal * 0.01
		tips.add_seed(pos, hit.normal, 12345 + index, params)
		return
	if surface.backend_tag() == "TowerSdf":
		# Headless reseed tests use TowerSdf without a physics space; nearest() reaches
		# the analytic surface from an exterior probe.
		var probe := seed_pos + toward_wall * 3.0
		var anchor := surface.nearest(probe)
		var pos := anchor.position + anchor.normal * 0.01
		tips.add_seed(pos, anchor.normal, 12345 + index, params)
		return
	push_error("SimRoot: seed %d raycast missed wall at %s" % [index, seed_pos])


func _seed_m1() -> void:
	# Derive the anchor from geometry rather than hardcoding a radius (SD-AGENCY-1),
	# then stand it 0.01 m proud of the wall (SD-AGENCY-4) so the first adhesion
	# query has a non-zero distance to work with (SD-GEO-2).
	var probe := Vector3(0.0, params.ground_y_min, 0.0) + Conv.SOUTH * 8.0
	var anchor := surface.nearest(probe)
	var pos := anchor.position + anchor.normal * 0.01
	tips.add_seed(pos, anchor.normal, 12345, params)


func _process(delta: float) -> void:
	if clock == null:
		return
	var n := clock.advance_real(delta)
	for _i in range(n):
		_tick()
	_sync_plant_render()


func _sync_plant_render() -> void:
	# Guard: advance_ticks() is used in headless test contexts where SimRoot is not
	# added to a scene tree; get_parent() would be null there (and there is nothing
	# to render to anyway).
	if not is_inside_tree():
		return
	var pr := get_parent().get_node_or_null("PlantRender")
	if pr != null and pr.has_method("sync"):
		pr.sync(plant)


func _tick() -> void:
	env.tick(clock.dt_sim(), clock.game_day)
	# Mean-preserving diel gate (INV-3a): growth magnitude follows the day, but the
	# daily total is unchanged, so time-lapse speeds do not grow more or less ivy.
	var g_hat := solar.diel_gate(clock.game_day)
	tips.refresh_vigour(ctx)
	for tip in tips.live_in_id_order():
		Physiology.accumulate_budget(tip, g_hat, ctx)
		var emitted := 0
		while tip.growth_budget >= params.segment_length and emitted < params.max_segments_per_tick:
			GrowthStep.step_tip(tip, ctx)
			tip.growth_budget -= params.segment_length
			emitted += 1
	tips.apply_pending_branches()
	tips.apply_lifecycle(ctx)
	clock.tick_index += 1
	clock._update_game_day()


func advance_ticks(n: int) -> void:
	for _i in range(n):
		_tick()
	_sync_plant_render()


func get_clock() -> SimClock:
	return clock
