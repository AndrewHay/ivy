## SD-WIND-2 mechanical tests for shared gust field (AmbientWind v3).
extends GutTest

const AmbientWind = preload("res://src/presentation/fauna/ambient_wind.gd")
const SimClock = preload("res://src/core/sim_clock.gd")
const FaunaConstants = preload("res://src/presentation/fauna/fauna_constants.gd")


func _wind() -> AmbientWind:
	var w := AmbientWind.new()
	add_child_autofree(w)
	return w


func _dir_angle(w: AmbientWind) -> float:
	return w.get_horizontal_direction().angle()


func test_scroll_advances_along_wind_and_wraps() -> void:
	var w := _wind()
	for _i in range(30):
		w.advance(SimClock.Speed.NORMAL, 0.1)
	var s := w.get_gust_scroll()
	assert_gte(s.x, 0.0)
	assert_lt(s.x, AmbientWind.GUST_TILE_M)
	assert_gte(s.y, 0.0)
	assert_lt(s.y, AmbientWind.GUST_TILE_M)
	w.advance(SimClock.Speed.NORMAL, 100.0)
	var s2 := w.get_gust_scroll()
	assert_gte(s2.x, 0.0)
	assert_lt(s2.x, AmbientWind.GUST_TILE_M)
	assert_gte(s2.y, 0.0)
	assert_lt(s2.y, AmbientWind.GUST_TILE_M)


func test_scroll_frozen_when_not_normal() -> void:
	var w := _wind()
	w.advance(SimClock.Speed.NORMAL, 0.5)
	var s0 := w.get_gust_scroll()
	w.advance(SimClock.Speed.PAUSE, 2.0)
	assert_eq(w.get_gust_scroll(), s0)
	w.advance(SimClock.Speed.FAST, 1.0)
	assert_eq(w.get_gust_scroll(), s0)


func test_direction_no_discontinuity_across_phase_wraps() -> void:
	var w := _wind()
	var max_step := 0.0
	var prev := _dir_angle(w)
	# Integrate well past multiple legacy 10 s phase wraps (get_phase unchanged).
	var steps := int(ceil(FaunaConstants.WIND_CYCLE_SEC * 3.0 / 0.05))
	for _i in range(steps):
		w.advance(SimClock.Speed.NORMAL, 0.05)
		var a := _dir_angle(w)
		var d := absf(wrapf(a - prev, -PI, PI))
		max_step = maxf(max_step, d)
		prev = a
	assert_lt(max_step, 0.02, "Direction should meander smoothly, not snap at phase wrap")


func test_direction_continuous_across_drift_wrap() -> void:
	var w := _wind()
	var period := AmbientWind.DIRECTION_DRIFT_PERIOD_SEC
	w.advance(SimClock.Speed.NORMAL, period - 0.1)
	var before := _dir_angle(w)
	w.advance(SimClock.Speed.NORMAL, 0.2)
	var after := _dir_angle(w)
	var delta := absf(wrapf(after - before, -PI, PI))
	assert_lt(delta, 0.02, "Drift phase wrap must not snap direction")


func test_flutter_phase_wraps_at_tau() -> void:
	var w := _wind()
	w.advance(SimClock.Speed.NORMAL, AmbientWind.FLUTTER_PERIOD_SEC * 2.5)
	var fp := w.get_flutter_phase()
	assert_gte(fp, 0.0)
	assert_lt(fp, TAU + 1e-5)


func test_gate_eases_to_one_at_normal() -> void:
	var w := _wind()
	w.advance(SimClock.Speed.NORMAL, 0.6)
	assert_almost_eq(w.get_effective_strength(), w.get_gust_envelope() * AmbientWind.WIND_BASE_STRENGTH, 0.05)


func test_gate_eases_to_zero_at_fast() -> void:
	var w := _wind()
	w.advance(SimClock.Speed.NORMAL, 1.0)
	w.advance(SimClock.Speed.FAST, 0.6)
	assert_lt(w.get_effective_strength(), 0.001)


func test_pause_holds_strength_and_all_state() -> void:
	var w := _wind()
	w.advance(SimClock.Speed.NORMAL, 2.0)
	var strength_hold := w.get_effective_strength()
	var scroll_hold := w.get_gust_scroll()
	var dir_hold := w.get_horizontal_direction()
	var flutter_hold := w.get_flutter_phase()
	var phase_hold := w.get_phase()
	w.advance(SimClock.Speed.PAUSE, 5.0)
	assert_almost_eq(w.get_effective_strength(), strength_hold, 1e-6)
	assert_eq(w.get_gust_scroll(), scroll_hold)
	assert_eq(w.get_horizontal_direction(), dir_hold)
	assert_almost_eq(w.get_flutter_phase(), flutter_hold, 1e-6)
	assert_almost_eq(w.get_phase(), phase_hold, 1e-6)


func test_push_shader_globals_callable() -> void:
	var w := _wind()
	w.advance(SimClock.Speed.NORMAL, 0.2)
	w.push_shader_globals()
	assert_true(true, "push_shader_globals should not throw when globals are declared")
