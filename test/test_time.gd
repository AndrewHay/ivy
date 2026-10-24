extends GutTest

const IvyParams = preload("res://src/params/ivy_params.gd")
const SimClock = preload("res://src/core/sim_clock.gd")
const Solar = preload("res://src/env/solar.gd")
const Physiology = preload("res://src/sim/physiology.gd")
const SimContext = preload("res://src/sim/sim_context.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const Tip = preload("res://src/sim/tip.gd")
const IvyEnvironment = preload("res://src/env/environment.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
var _params: IvyParams
var _clock: SimClock


func before_each() -> void:
	_params = IvyParams.new()
	_clock = SimClock.new(_params)


func _make_env_ctx(params: IvyParams, plant: PlantData) -> SimContext:
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), params)
	var env := IvyEnvironment.new()
	env.build(params, surface)
	return SimContext.new(params, env, surface, plant, null, null)


func test_tick_size_depends_on_speed() -> void:
	assert_almost_eq(
		SimClock.sim_tick_size_for(SimClock.Speed.NORMAL),
		1.0 / (24.0 * SimClock.NORMAL_SEGMENTS_PER_SIM_HOUR),
		1e-9
	)
	assert_almost_eq(
		SimClock.sim_tick_size_for(SimClock.Speed.GROW),
		1.0 / (24.0 * SimClock.GROW_SEGMENTS_PER_SIM_HOUR),
		1e-9
	)


func test_one_game_day_of_ticks_at_normal() -> void:
	_clock.set_speed(SimClock.Speed.NORMAL)
	var ticks_per_day := int(24.0 * SimClock.NORMAL_SEGMENTS_PER_SIM_HOUR)
	_clock.advance_ticks(ticks_per_day)
	assert_almost_eq(_clock.game_day, 1.0, 1e-6)


func test_pause_advances_nothing() -> void:
	_clock.set_speed(SimClock.Speed.PAUSE)
	var n := _clock.advance_real(10.0)
	assert_eq(n, 0)
	assert_eq(_clock.tick_index, 0)
	assert_almost_eq(_clock.display_game_day(), 0.0, 1e-9)


func test_display_game_day_interpolates_between_ticks() -> void:
	_clock.set_speed(SimClock.Speed.NORMAL)
	_clock.advance_ticks(5)
	var base := _clock.display_game_day()
	_clock.advance_real(0.5)
	var mid := _clock.display_game_day()
	assert_gt(mid, base)
	assert_lt(mid, base + _clock.dt_sim())


func test_advance_ticks_deterministic() -> void:
	var c1 := SimClock.new(_params)
	var c2 := SimClock.new(_params)
	c1.set_speed(SimClock.Speed.NORMAL)
	c2.set_speed(SimClock.Speed.NORMAL)
	c1.advance_ticks(720)
	c2.advance_ticks(720)
	assert_eq(c1.tick_index, c2.tick_index)
	assert_eq(c1.game_day, c2.game_day)


func test_seconds_per_game_day_drives_the_render_blend() -> void:
	_clock.set_speed(SimClock.Speed.NORMAL)
	assert_almost_eq(_clock.seconds_per_game_day(), 360.0, 1e-9)
	_clock.set_speed(SimClock.Speed.FAST)
	assert_almost_eq(_clock.seconds_per_game_day(), 36.0, 1e-9)
	_clock.set_speed(SimClock.Speed.GROW)
	assert_almost_eq(_clock.seconds_per_game_day(), 360.0, 1e-9)
	_clock.set_speed(SimClock.Speed.PAUSE)
	assert_almost_eq(_clock.seconds_per_game_day(), 360.0, 1e-9)


func test_normal_speed_one_tick_per_second() -> void:
	_clock.set_speed(SimClock.Speed.NORMAL)
	var n := _clock.advance_real(1.0)
	assert_eq(n, 1)
	n = _clock.advance_real(1.0)
	assert_eq(n, 1)


func test_fast_speed_ten_ticks_per_second() -> void:
	_clock.set_speed(SimClock.Speed.FAST)
	var total := 0
	for _i in range(10):
		total += _clock.advance_real(0.1)
	assert_eq(total, 10)


func test_grow_speed_four_ticks_per_second() -> void:
	_clock.set_speed(SimClock.Speed.GROW)
	assert_eq(_clock.advance_real(1.0), 4)


func test_grow_speed_emits_segment_within_few_slots() -> void:
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), _params)
	var sim := SimRoot.new()
	sim.setup(_params, surface, null, 0, null, true)
	sim.get_clock().set_speed(SimClock.Speed.GROW)
	sim.advance_ticks(5)
	assert_gt(sim.plant.segment_count(), 0, "Grow: ~one segment per slot at full vigour")


func test_speed_change_preserves_game_day() -> void:
	_clock.set_speed(SimClock.Speed.GROW)
	_clock.advance_ticks(720)
	var day_before := _clock.display_game_day()
	_clock.set_speed(SimClock.Speed.NORMAL)
	assert_almost_eq(_clock.display_game_day(), day_before, 1e-6)
	assert_almost_eq(_clock.game_day, day_before, 1e-6)


func test_grow_speed_produces_stem_within_half_game_day() -> void:
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), _params)
	var sim := SimRoot.new()
	sim.setup(_params, surface, null, 0, null, true)
	sim.get_clock().set_speed(SimClock.Speed.GROW)
	var ticks := SimClock.ticks_for_game_days(0.5, SimClock.Speed.GROW)
	sim.advance_ticks(ticks)
	assert_gt(sim.plant.segment_count(), 0, "expected at least one segment in half a game-day at Grow")


func test_geometric_night_blocks_growth_ticks() -> void:
	var solar := Solar.new(_params)
	assert_false(solar.is_geometric_night(0.25))
	var ticks_to_midnight := int(round(0.75 * SimClock.ticks_per_game_day_for(SimClock.Speed.GROW)))
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), _params)
	var sim := SimRoot.new()
	sim.setup(_params, surface, null, 0, null, true)
	sim.get_clock().set_speed(SimClock.Speed.GROW)
	sim.advance_ticks(ticks_to_midnight)
	assert_true(solar.is_geometric_night(sim.get_clock().game_day))
	var segs_at_night := sim.plant.segment_count()
	sim.advance_ticks(10)
	assert_eq(sim.plant.segment_count(), segs_at_night, "no new segments during geometric night")


func test_night_wall_clock_runs_eight_times_faster() -> void:
	_clock.set_speed(SimClock.Speed.NORMAL)
	var ticks_to_midnight := int(round(0.75 * SimClock.ticks_per_game_day_for(SimClock.Speed.NORMAL)))
	_clock.advance_ticks(ticks_to_midnight)
	assert_eq(_clock.advance_real(0.125), 1)
	assert_eq(_clock.advance_real(0.125), 1)


# ... rest of diel gate tests unchanged from line 130

func test_diel_gate_mean_is_unity_over_24_ticks() -> void:
	var solar := Solar.new(_params)
	var sum := 0.0
	for i in 24:
		var game_day := float(i) / 24.0
		sum += solar.diel_gate(game_day)
	var mean := sum / 24.0
	assert_almost_eq(mean, 1.0, 1e-6)


func test_diel_gate_scales_growth_rate_proportionally() -> void:
	var params := IvyParams.new()
	var plant := PlantData.new()
	var ctx := _make_env_ctx(params, plant)
	var tip := Tip.new()
	tip.id = 0
	tip.state = Tip.State.GROWING
	tip.position = Vector3(0.0, 1.0, 2.0)
	tip.last_contact_normal = Vector3(0.0, 0.0, 1.0)

	var r_one := Physiology.growth_rate(tip, 1.0, ctx)
	var r_two := Physiology.growth_rate(tip, 2.0, ctx)
	assert_gt(r_one, 0.0)
	assert_almost_eq(r_two, r_one * 2.0, r_one * 1e-9)


func test_diel_gate_never_reaches_direction_code() -> void:
	var offenders: PackedStringArray = []
	for path in ["res://src/sim/growth_step.gd", "res://src/sim/tip_manager.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), str("could not read ", path))
		for needle in ["diel_gate", "g_hat"]:
			if text.contains(needle):
				offenders.append(str(path, " references '", needle, "'"))
	assert_eq(offenders.size(), 0)


func test_diel_gate_noon_above_one_midnight_below_one() -> void:
	var solar := Solar.new(_params)
	var noon_day := 6.0 / 24.0
	var midnight_day := 18.0 / 24.0
	var g_noon := solar.diel_gate(noon_day)
	var g_midnight := solar.diel_gate(midnight_day)
	assert_gt(g_noon, 1.5)
	assert_lt(g_midnight, 0.20)


func test_diel_gate_is_deterministic_no_rng() -> void:
	var solar := Solar.new(_params)
	var v1 := solar.diel_gate(0.3)
	var v2 := solar.diel_gate(0.3)
	assert_almost_eq(v1, v2, 1e-9)


func test_dl_ewma_time_constant_is_three_days() -> void:
	var dt := _params.sim_tick
	var alpha := _params.light_ewma_alpha(dt)
	var expected_alpha := exp(-dt / _params.light_memory)
	assert_almost_eq(alpha, expected_alpha, 1e-9)
	var dl := 1.0
	for _i in range(72):
		dl = alpha * dl
	assert_almost_eq(dl, exp(-1.0), 0.005)


func test_dl_ewma_alpha_uses_light_memory_param() -> void:
	var p_fast := IvyParams.new()
	p_fast.light_memory = 1.0
	var alpha_fast := p_fast.light_ewma_alpha(p_fast.sim_tick)
	var alpha_default := _params.light_ewma_alpha(_params.sim_tick)
	assert_lt(alpha_fast, alpha_default)


func test_dl_ewma_one_tick_does_not_snap_instantly() -> void:
	var alpha := _params.light_ewma_alpha(_params.sim_tick)
	var dl_after_one_tick := alpha * 1.0
	assert_gte(dl_after_one_tick, 0.95)
