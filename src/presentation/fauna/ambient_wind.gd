class_name AmbientWind
extends Node

## Shared presentation breeze (SD-WIND-1 envelope + SD-WIND-2 gust field). Phase integrates only at NORMAL speed.

const WIND_BASE_STRENGTH := 1.0
const WIND_STRENGTH_CAP := 1.0
const WIND_GUST_PERIOD_SEC := 28.0

const GUST_TILE_M := 24.0
const GUST_SPEED_M_S := 1.8
const DIRECTION_BASE_ANGLE := atan2(0.3, 1.0)
const DIRECTION_MEANDER_RAD := 0.35
const DIRECTION_DRIFT_PERIOD_SEC := 90.0
const FLUTTER_PERIOD_SEC := 1.7
const GATE_EASE_PER_SEC := 2.0

var _phase: float = 0.0
var _gust_phase: float = 0.0
var _drift_phase: float = 0.0
var _flutter_phase: float = 0.0
var _scroll_xz: Vector2 = Vector2.ZERO
var _gate: float = 0.0
var _direction_xz: Vector2 = Vector2(cos(DIRECTION_BASE_ANGLE), sin(DIRECTION_BASE_ANGLE))
var _speed: SimClock.Speed = SimClock.Speed.GROW


func _ready() -> void:
	set_process(false)


func advance(speed: SimClock.Speed, delta: float) -> void:
	_speed = speed
	if speed == SimClock.Speed.PAUSE:
		return
	var gate_target := 1.0 if speed == SimClock.Speed.NORMAL else 0.0
	_gate = move_toward(_gate, gate_target, GATE_EASE_PER_SEC * delta)
	if speed != SimClock.Speed.NORMAL:
		return
	_phase += delta * (TAU / FaunaConstants.WIND_CYCLE_SEC)
	if _phase >= TAU:
		_phase = fmod(_phase, TAU)
	_gust_phase += delta * (TAU / WIND_GUST_PERIOD_SEC)
	if _gust_phase >= TAU:
		_gust_phase = fmod(_gust_phase, TAU)
	_drift_phase += delta * (TAU / DIRECTION_DRIFT_PERIOD_SEC)
	if _drift_phase >= TAU:
		_drift_phase = fmod(_drift_phase, TAU)
	_flutter_phase += delta * (TAU / FLUTTER_PERIOD_SEC)
	if _flutter_phase >= TAU:
		_flutter_phase = fmod(_flutter_phase, TAU)
	var theta := DIRECTION_BASE_ANGLE + DIRECTION_MEANDER_RAD * sin(_drift_phase)
	_direction_xz = Vector2(cos(theta), sin(theta))
	_scroll_xz += _direction_xz * (GUST_SPEED_M_S * delta)
	_scroll_xz.x = fposmod(_scroll_xz.x, GUST_TILE_M)
	_scroll_xz.y = fposmod(_scroll_xz.y, GUST_TILE_M)


func get_phase() -> float:
	return _phase


func get_horizontal_direction() -> Vector2:
	return _direction_xz


func get_gust_scroll() -> Vector2:
	return _scroll_xz


func get_flutter_phase() -> float:
	return _flutter_phase


func get_gust_envelope() -> float:
	return 0.5 + 0.5 * sin(_gust_phase)


func get_effective_strength() -> float:
	return minf(WIND_STRENGTH_CAP, WIND_BASE_STRENGTH * get_gust_envelope()) * _gate


func push_shader_globals() -> void:
	RenderingServer.global_shader_parameter_set("ivy_wind_dir", get_horizontal_direction())
	RenderingServer.global_shader_parameter_set("ivy_wind_strength", get_effective_strength())
	RenderingServer.global_shader_parameter_set("ivy_wind_scroll", _scroll_xz)
	RenderingServer.global_shader_parameter_set("ivy_wind_flutter_phase", _flutter_phase)


func strength_for_species(species: FaunaConstants.Species) -> float:
	match species:
		FaunaConstants.Species.BUTTERFLY:
			return 0.35
		FaunaConstants.Species.BEE:
			return 0.10
		_:
			return 0.0
