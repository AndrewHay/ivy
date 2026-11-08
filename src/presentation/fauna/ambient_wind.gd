class_name AmbientWind
extends Node

## Shared presentation breeze (SD-WIND-1 envelope + SD-WIND-2 gust field). Phase integrates only at NORMAL speed.

const GrassWindClock = preload("res://src/presentation/fauna/grass_wind_clock.gd")

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
var _clock_cfg: Dictionary = {}


func _ready() -> void:
	set_process(false)
	_clock_cfg = _build_clock_cfg()


func _build_clock_cfg() -> Dictionary:
	var cfg := GrassWindClock.config_from_ambient_wind()
	cfg["gust_period_sec"] = WIND_GUST_PERIOD_SEC
	cfg["direction_drift_period_sec"] = DIRECTION_DRIFT_PERIOD_SEC
	cfg["flutter_period_sec"] = FLUTTER_PERIOD_SEC
	cfg["direction_base_angle_rad"] = DIRECTION_BASE_ANGLE
	cfg["direction_meander_rad"] = DIRECTION_MEANDER_RAD
	cfg["gust_scroll_speed_m_s"] = GUST_SPEED_M_S
	cfg["gust_tile_m"] = GUST_TILE_M
	cfg["wind_strength"] = WIND_BASE_STRENGTH
	cfg["strength_cap"] = WIND_STRENGTH_CAP
	return cfg


func _clock_state_from_members() -> Dictionary:
	return {
		"phase": _phase,
		"gust_phase": _gust_phase,
		"drift_phase": _drift_phase,
		"flutter_phase": _flutter_phase,
		"scroll_xz": _scroll_xz,
		"direction_xz": _direction_xz,
		"sim_time": 0.0,
	}


func _apply_clock_state(state: Dictionary) -> void:
	_phase = state["phase"]
	_gust_phase = state["gust_phase"]
	_drift_phase = state["drift_phase"]
	_flutter_phase = state["flutter_phase"]
	_scroll_xz = state["scroll_xz"]
	_direction_xz = state["direction_xz"]


func advance(speed: SimClock.Speed, delta: float) -> void:
	_speed = speed
	if speed == SimClock.Speed.PAUSE:
		return
	var gate_target := 1.0 if speed == SimClock.Speed.NORMAL else 0.0
	_gate = move_toward(_gate, gate_target, GATE_EASE_PER_SEC * delta)
	if speed != SimClock.Speed.NORMAL:
		return
	if _clock_cfg.is_empty():
		# Not yet in the tree (no _ready): the pre-refactor code worked standalone too.
		_clock_cfg = _build_clock_cfg()
	var state := _clock_state_from_members()
	state = GrassWindClock.advance(state, _clock_cfg, delta, 1.0)
	_apply_clock_state(state)


func get_phase() -> float:
	return _phase


func get_horizontal_direction() -> Vector2:
	return _direction_xz


func get_gust_scroll() -> Vector2:
	return _scroll_xz


func get_flutter_phase() -> float:
	return _flutter_phase


func get_gust_envelope() -> float:
	return GrassWindClock.gust_envelope(_gust_phase)


func get_effective_strength() -> float:
	return GrassWindClock.effective_strength(
		WIND_BASE_STRENGTH,
		WIND_STRENGTH_CAP,
		get_gust_envelope(),
		_gate,
		true)


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
