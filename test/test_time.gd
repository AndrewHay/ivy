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
var _params: IvyParams
var _clock: SimClock


func before_each() -> void:
	_params = IvyParams.new()
	_clock = SimClock.new(_params)


## Real environment over a null-physics SurfaceQuery (no raycasts, open-sky bake).
## Mirrors the helper in test_leaf_placement.gd.
func _make_env_ctx(params: IvyParams, plant: PlantData) -> SimContext:
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), params)
	var env := IvyEnvironment.new()
	env.build(params, surface)
	return SimContext.new(params, env, surface, plant, null, null)


func test_fixed_tick_at_all_speeds() -> void:
	assert_almost_eq(_clock.dt_sim(), 1.0 / 24.0, 1e-9)
	_clock.set_speed(SimClock.Speed.WATCH)
	_clock.advance_ticks(24)
	assert_almost_eq(_clock.game_day, 1.0, 1e-6)
	_clock.set_speed(SimClock.Speed.GROW)
	_clock.advance_ticks(24)
	assert_almost_eq(_clock.game_day, 2.0, 1e-6)


func test_pause_advances_nothing() -> void:
	_clock.set_speed(SimClock.Speed.PAUSE)
	var n := _clock.advance_real(10.0)
	assert_eq(n, 0)
	assert_eq(_clock.tick_index, 0)


func test_advance_ticks_deterministic() -> void:
	var c1 := SimClock.new(_params)
	var c2 := SimClock.new(_params)
	c1.advance_ticks(720)
	c2.advance_ticks(720)
	assert_eq(c1.tick_index, c2.tick_index)
	assert_eq(c1.game_day, c2.game_day)


func test_seconds_per_game_day_drives_the_render_blend() -> void:
	# SD-TIME-2 / SD-TIME-4: the wall-clock length of a game-day is what the render-sun
	# blend reads. Pause has no rate, so it reports the Watch figure and stays live.
	_clock.set_speed(SimClock.Speed.WATCH)
	assert_almost_eq(_clock.seconds_per_game_day(), _params.speed_watch, 1e-9)
	_clock.set_speed(SimClock.Speed.FAST)
	assert_almost_eq(_clock.seconds_per_game_day(), _params.speed_fast, 1e-9)
	_clock.set_speed(SimClock.Speed.GROW)
	assert_almost_eq(_clock.seconds_per_game_day(), _params.speed_grow, 1e-9)
	_clock.set_speed(SimClock.Speed.PAUSE)
	assert_almost_eq(_clock.seconds_per_game_day(), _params.speed_watch, 1e-9)


func test_speed_mapping() -> void:
	_clock.set_speed(SimClock.Speed.WATCH)
	var ticks := 0
	while ticks < 24:
		var n := _clock.advance_real(_params.speed_watch / 24.0)
		if n > 0:
			_clock.advance_ticks(n)
		ticks += n
	assert_eq(_clock.tick_index, 24)


# ---------------------------------------------------------------------------
# AS-3(b): diel gate mean-preservation (INV-3a, SD-TIME-8b)
# ---------------------------------------------------------------------------

func test_diel_gate_mean_is_unity_over_24_ticks() -> void:
	## SD-TIME-8b: dividing by g_ref makes ĝ mean-preserving — mean(ĝ) = 1.0 over the
	## 24 hourly simulation ticks of one game-day.
	## This is the primary guarantee behind AS-3(b) as ratified: total daily elongation
	## with the gate on equals total daily elongation with the gate off, because the
	## gate multiplier averages to 1 over the full day.
	##
	## The tolerance is 1e-6, not a loose epsilon, because g_ref is the mean of g over
	## these very same 24 hours — so the result is exactly 1 by construction and any
	## slack here is slack in AS-3(b) itself. At the previous ±0.02 this assertion
	## would have passed a gate 1.9% off mean-preservation, which is the silent budget
	## drift AS-3(b) exists to catch (W-053).
	var solar := Solar.new(_params)
	var sum := 0.0
	for i in 24:
		var game_day := float(i) / 24.0   # ticks 0..23 sample hours 0..23
		sum += solar.diel_gate(game_day)
	var mean := sum / 24.0
	assert_almost_eq(mean, 1.0, 1e-6,
		"diel gate must be mean-preserving over 24 ticks (INV-3a, SD-TIME-8b)")


func test_diel_gate_scales_growth_rate_proportionally() -> void:
	## INV-3a: the gate acts on growth *magnitude* only. Doubling ĝ must exactly double
	## the growth rate — if the gate ever leaked into a saturating or directional term,
	## the response would stop being proportional.
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
	assert_gt(r_one, 0.0, "growth rate must be positive for a lit growing tip")
	assert_almost_eq(r_two, r_one * 2.0, r_one * 1e-9,
		"growth rate must scale linearly with the diel gate (INV-3a magnitude-only)")


func test_diel_gate_never_reaches_direction_code() -> void:
	## INV-3a: "must never appear in any directional term." The gate is computed in
	## `sim_root` and handed only to `Physiology.accumulate_budget`, which multiplies a
	## scalar rate. `growth_step.gd` owns the direction sum, so a reference to the gate
	## appearing there is the specific regression this guards — the assertion listed in
	## the SD-TIME test surface but never implemented until W-053.
	var offenders: PackedStringArray = []
	for path in ["res://src/sim/growth_step.gd", "res://src/sim/tip_manager.gd"]:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), str("could not read ", path))
		for needle in ["diel_gate", "g_hat"]:
			if text.contains(needle):
				offenders.append(str(path, " references '", needle, "'"))
	assert_eq(offenders.size(), 0, str(
		"the diel gate must not reach direction-computing code (INV-3a): ", offenders))


func test_diel_gate_noon_above_one_midnight_below_one() -> void:
	## SD-TIME-8c: ĝ ≈ 2.1 at solar noon, ≈ 0.11 at night (offset from start_hour=6
	## by 6 h for noon, by 18 h for midnight).
	var solar := Solar.new(_params)
	var noon_day := 6.0 / 24.0   # start_hour=6, noon is 6 h in = game_day 0.25
	var midnight_day := 18.0 / 24.0  # midnight is 18 h in = game_day 0.75
	var g_noon := solar.diel_gate(noon_day)
	var g_midnight := solar.diel_gate(midnight_day)
	assert_gt(g_noon, 1.5, "gate at noon must be well above 1.0 (SD-TIME-8c: ≈2.1)")
	assert_lt(g_midnight, 0.20, "gate at midnight must be near zero (SD-TIME-8c: ≈0.11)")


func test_diel_gate_is_deterministic_no_rng() -> void:
	## The gate is pure mathematics of solar angles and params — no RNG draws.
	## Confirmed by calling it twice: identical inputs must produce identical outputs.
	## This is the key property that makes the gate-disabled comparison valid:
	## setting diel_gate_enabled=false introduces zero new RNG calls, so neither run
	## has any extra draws relative to the other. Draw sequences diverge only because
	## different growth magnitudes change WHEN per-metre events (branching, leaves)
	## fire during the day, not because of any randomness in the gate itself.
	var solar := Solar.new(_params)
	var v1 := solar.diel_gate(0.3)
	var v2 := solar.diel_gate(0.3)
	assert_almost_eq(v1, v2, 1e-9,
		"diel_gate must be deterministic (no RNG dependency — SD-RNG-4 analogue)")


# ---------------------------------------------------------------------------
# AS-3(c): D_L EWMA time constant (SD-ENV-8, τ_L = 3 game-days)
# ---------------------------------------------------------------------------

func test_dl_ewma_time_constant_is_three_days() -> void:
	## SD-ENV-8: light memory applies one EWMA step per tick with
	## α = exp(−dt_sim / τ_L), τ_L = light_memory = 3 game-days.
	## AS-3(c) clause: after 72 ticks (3 game-days × 24 ticks/day) of zero input,
	## D_L must decay to exp(−1) ≈ 0.3679 of its initial value.
	## Tolerance ±0.5% (the exact closed-form solution, not an approximation).
	var dt := _params.sim_tick        # = 1/24 game-day
	var alpha := _params.light_ewma_alpha(dt)
	# Verify alpha is the correct value for tau_L = 3
	var expected_alpha := exp(-dt / _params.light_memory)
	assert_almost_eq(alpha, expected_alpha, 1e-9,
		"light_ewma_alpha must equal exp(-dt/tau_L)")
	# Simulate 72 EWMA steps with zero driving input (step-down from 1.0 to 0.0).
	var dl := 1.0
	for _i in range(72):
		dl = alpha * dl  # + (1.0 - alpha) * 0.0
	# After exactly 3 time constants, the value should be exp(−1).
	assert_almost_eq(dl, exp(-1.0), 0.005,
		"D_L after 72 zero-input EWMA steps must equal exp(-1) (tau_L=3 game-days, AS-3c)")


func test_dl_ewma_alpha_uses_light_memory_param() -> void:
	## Changing light_memory must change the EWMA decay rate.
	## This confirms the parameter is wired into the formula (INV-6).
	var p_fast := IvyParams.new()
	p_fast.light_memory = 1.0
	var alpha_fast := p_fast.light_ewma_alpha(p_fast.sim_tick)
	var alpha_default := _params.light_ewma_alpha(_params.sim_tick)
	assert_lt(alpha_fast, alpha_default,
		"shorter light_memory must give smaller alpha (faster decay)")


func test_dl_ewma_one_tick_does_not_snap_instantly() -> void:
	## After one tick from initial state 1.0 with zero input, D_L must still be
	## close to 1.0 (≥0.95), because τ_L = 3 days ≫ dt = 1/24 day.
	## This confirms the lag — D_L cannot jump immediately to the new light level.
	var alpha := _params.light_ewma_alpha(_params.sim_tick)
	var dl_after_one_tick := alpha * 1.0  # single EWMA step with zero input
	assert_gte(dl_after_one_tick, 0.95,
		"D_L must lag instantaneous light — one tick must change it by <5% (tau_L=3 >> dt)")
