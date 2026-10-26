## SD-WIND-1 mechanical tests for AmbientWind + SimClock gate.
extends GutTest

const AmbientWind = preload("res://src/presentation/fauna/ambient_wind.gd")
const SimClock = preload("res://src/core/sim_clock.gd")
const FaunaConstants = preload("res://src/presentation/fauna/fauna_constants.gd")


func _wind() -> AmbientWind:
	var w := AmbientWind.new()
	add_child_autofree(w)
	return w


func test_normal_integrates_phase_and_strength() -> void:
	var w := _wind()
	var p0 := w.get_phase()
	w.advance(SimClock.Speed.NORMAL, 0.5)
	assert_gt(w.get_phase(), p0, "Phase advances at NORMAL")
	assert_gt(w.get_effective_strength(), 0.0, "Strength positive at NORMAL")


func test_pause_freezes_phase_zero_strength() -> void:
	var w := _wind()
	w.advance(SimClock.Speed.NORMAL, 1.0)
	var p := w.get_phase()
	w.advance(SimClock.Speed.PAUSE, 1.0)
	assert_almost_eq(w.get_phase(), p, 1e-6, "Phase frozen at PAUSE")
	assert_almost_eq(w.get_effective_strength(), 0.0, 1e-6)


func test_fast_and_grow_no_integration() -> void:
	for spd in [SimClock.Speed.FAST, SimClock.Speed.GROW]:
		var w := _wind()
		w.advance(SimClock.Speed.NORMAL, 0.25)
		var p := w.get_phase()
		w.advance(spd, 1.0)
		assert_almost_eq(w.get_phase(), p, 1e-6, "Phase frozen at %s" % spd)
		assert_almost_eq(w.get_effective_strength(), 0.0, 1e-6)


func test_fauna_wind_product() -> void:
	var w := _wind()
	w.advance(SimClock.Speed.NORMAL, 0.2)
	var eff := w.get_effective_strength()
	assert_almost_eq(
		w.strength_for_species(FaunaConstants.Species.BUTTERFLY) * eff,
		0.35 * eff, 1e-6)
	w.advance(SimClock.Speed.GROW, 0.5)
	assert_almost_eq(
		w.strength_for_species(FaunaConstants.Species.BUTTERFLY) * w.get_effective_strength(),
		0.0, 1e-6)


func test_gust_envelope_range() -> void:
	var w := _wind()
	for _i in range(20):
		w.advance(SimClock.Speed.NORMAL, 1.4)
		var g := w.get_gust_envelope()
		assert_gte(g, 0.0)
		assert_lte(g, 1.0)


func test_pause_then_normal_resumes_integration() -> void:
	var w := _wind()
	w.advance(SimClock.Speed.NORMAL, 0.3)
	var p_frozen := w.get_phase()
	w.advance(SimClock.Speed.PAUSE, 2.0)
	assert_almost_eq(w.get_phase(), p_frozen, 1e-6)
	w.advance(SimClock.Speed.NORMAL, 0.3)
	assert_gt(w.get_phase(), p_frozen, "Phase resumes after PAUSE → NORMAL")


func test_ambient_wind_no_sim_imports() -> void:
	var text := FileAccess.get_file_as_string("res://src/presentation/fauna/ambient_wind.gd")
	assert_false(text.contains("src/sim/"), "AmbientWind must not reference src/sim/*")
