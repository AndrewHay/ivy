class_name AmbientWind
extends Node

## Shared presentation breeze (SD-WIND-1, SD-FAUNA-11). Phase integrates only at NORMAL speed.

const WIND_BASE_STRENGTH := 1.0
const WIND_STRENGTH_CAP := 1.0
const WIND_GUST_PERIOD_SEC := 28.0
const DIRECTION_DRIFT_SCALE := 0.13

var _phase: float = 0.0
var _gust_phase: float = 0.0
var _direction_xz: Vector2 = Vector2(1.0, 0.3).normalized()
var _speed: SimClock.Speed = SimClock.Speed.GROW


func _ready() -> void:
	set_process(false)


func advance(speed: SimClock.Speed, delta: float) -> void:
	_speed = speed
	if speed != SimClock.Speed.NORMAL:
		return
	_phase += delta * (TAU / FaunaConstants.WIND_CYCLE_SEC)
	if _phase > TAU:
		_phase = fmod(_phase, TAU)
	_gust_phase += delta * (TAU / WIND_GUST_PERIOD_SEC)
	if _gust_phase > TAU:
		_gust_phase = fmod(_gust_phase, TAU)
	_direction_xz = Vector2(
		cos(_phase * DIRECTION_DRIFT_SCALE),
		sin(_phase * DIRECTION_DRIFT_SCALE)).normalized()


func get_phase() -> float:
	return _phase


func get_horizontal_direction() -> Vector2:
	return _direction_xz


func get_gust_envelope() -> float:
	return 0.5 + 0.5 * sin(_gust_phase)


func get_effective_strength() -> float:
	if _speed != SimClock.Speed.NORMAL:
		return 0.0
	return minf(WIND_STRENGTH_CAP, WIND_BASE_STRENGTH * get_gust_envelope())


func strength_for_species(species: FaunaConstants.Species) -> float:
	match species:
		FaunaConstants.Species.BUTTERFLY:
			return 0.35
		FaunaConstants.Species.BEE:
			return 0.10
		_:
			return 0.0
