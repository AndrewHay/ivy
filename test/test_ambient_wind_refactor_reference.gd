extends GutTest

## AmbientWind now delegates to GrassWindClock. This pins it against a literal copy of the
## ORIGINAL (pre-refactor) integration code so production wind cannot silently drift.

const FaunaConstants = preload("res://src/presentation/fauna/fauna_constants.gd")


class OldWind:
	var phase := 0.0
	var gust_phase := 0.0
	var drift_phase := 0.0
	var flutter_phase := 0.0
	var scroll := Vector2.ZERO
	var gate := 0.0
	var direction := Vector2(cos(AmbientWind.DIRECTION_BASE_ANGLE), sin(AmbientWind.DIRECTION_BASE_ANGLE))

	func advance(speed: SimClock.Speed, delta: float) -> void:
		if speed == SimClock.Speed.PAUSE:
			return
		var gate_target := 1.0 if speed == SimClock.Speed.NORMAL else 0.0
		gate = move_toward(gate, gate_target, AmbientWind.GATE_EASE_PER_SEC * delta)
		if speed != SimClock.Speed.NORMAL:
			return
		phase += delta * (TAU / FaunaConstants.WIND_CYCLE_SEC)
		if phase >= TAU:
			phase = fmod(phase, TAU)
		gust_phase += delta * (TAU / AmbientWind.WIND_GUST_PERIOD_SEC)
		if gust_phase >= TAU:
			gust_phase = fmod(gust_phase, TAU)
		drift_phase += delta * (TAU / AmbientWind.DIRECTION_DRIFT_PERIOD_SEC)
		if drift_phase >= TAU:
			drift_phase = fmod(drift_phase, TAU)
		flutter_phase += delta * (TAU / AmbientWind.FLUTTER_PERIOD_SEC)
		if flutter_phase >= TAU:
			flutter_phase = fmod(flutter_phase, TAU)
		var theta := AmbientWind.DIRECTION_BASE_ANGLE + AmbientWind.DIRECTION_MEANDER_RAD * sin(drift_phase)
		direction = Vector2(cos(theta), sin(theta))
		scroll += direction * (AmbientWind.GUST_SPEED_M_S * delta)
		scroll.x = fposmod(scroll.x, AmbientWind.GUST_TILE_M)
		scroll.y = fposmod(scroll.y, AmbientWind.GUST_TILE_M)

	func envelope() -> float:
		return 0.5 + 0.5 * sin(gust_phase)

	func effective_strength() -> float:
		return minf(AmbientWind.WIND_STRENGTH_CAP, AmbientWind.WIND_BASE_STRENGTH * envelope()) * gate


func _assert_same(wind: AmbientWind, old: OldWind, tag: String) -> void:
	assert_almost_eq(wind.get_phase(), old.phase, 1e-6, "%s phase" % tag)
	assert_almost_eq(wind.get_flutter_phase(), old.flutter_phase, 1e-6, "%s flutter" % tag)
	assert_almost_eq(wind.get_gust_envelope(), old.envelope(), 1e-6, "%s envelope" % tag)
	assert_almost_eq(wind.get_effective_strength(), old.effective_strength(), 1e-6, "%s strength" % tag)
	assert_almost_eq(wind.get_gust_scroll().x, old.scroll.x, 1e-5, "%s scroll.x" % tag)
	assert_almost_eq(wind.get_gust_scroll().y, old.scroll.y, 1e-5, "%s scroll.y" % tag)
	assert_almost_eq(wind.get_horizontal_direction().x, old.direction.x, 1e-6, "%s dir.x" % tag)
	assert_almost_eq(wind.get_horizontal_direction().y, old.direction.y, 1e-6, "%s dir.y" % tag)


func test_matches_original_algorithm_across_speeds_and_varied_dt() -> void:
	var wind := AmbientWind.new()
	add_child_autofree(wind)
	var old := OldWind.new()
	var speeds := [
		SimClock.Speed.NORMAL, SimClock.Speed.NORMAL, SimClock.Speed.PAUSE,
		SimClock.Speed.FAST, SimClock.Speed.NORMAL, SimClock.Speed.GROW,
		SimClock.Speed.NORMAL]
	var step := 0
	for i in range(900):
		var speed: SimClock.Speed = speeds[(i / 40) % speeds.size()]
		var dt := 0.008 + 0.03 * float(i % 7) / 6.0
		wind.advance(speed, dt)
		old.advance(speed, dt)
		step += 1
		if step % 25 == 0:
			_assert_same(wind, old, "step %d" % step)
	_assert_same(wind, old, "final")


func test_works_standalone_without_entering_the_tree() -> void:
	var wind := AmbientWind.new()  # no add_child: _ready never runs
	var old := OldWind.new()
	for i in range(200):
		wind.advance(SimClock.Speed.NORMAL, 0.033)
		old.advance(SimClock.Speed.NORMAL, 0.033)
	_assert_same(wind, old, "standalone")
	wind.free()
