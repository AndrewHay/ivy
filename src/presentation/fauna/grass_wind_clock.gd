class_name GrassWindClock
extends RefCounted

## Pure SD-WIND-1 phase integration shared by AmbientWind and the grass-wind playground.

const FaunaConstants = preload("res://src/presentation/fauna/fauna_constants.gd")


static func gust_envelope(gust_phase: float) -> float:
	return 0.5 + 0.5 * sin(gust_phase)


static func direction_xz(
		base_angle_rad: float,
		meander_rad: float,
		drift_phase: float,
		freeze: bool) -> Vector2:
	if freeze:
		return Vector2(cos(base_angle_rad), sin(base_angle_rad))
	var theta := base_angle_rad + meander_rad * sin(drift_phase)
	return Vector2(cos(theta), sin(theta))


static func scroll_step(
		scroll: Vector2,
		dir: Vector2,
		speed_m_s: float,
		delta: float,
		tile_m: float) -> Vector2:
	var s := scroll + dir * (speed_m_s * delta)
	s.x = fposmod(s.x, tile_m)
	s.y = fposmod(s.y, tile_m)
	return s


static func effective_strength(
		base: float,
		cap: float,
		envelope: float,
		gate: float,
		envelope_on: bool = true) -> float:
	var env := envelope if envelope_on else 1.0
	return minf(cap, base * env) * gate


static func config_from_ambient_wind() -> Dictionary:
	return {
		"wind_cycle_sec": FaunaConstants.WIND_CYCLE_SEC,
		"gust_period_sec": 28.0,
		"direction_drift_period_sec": 90.0,
		"flutter_period_sec": 1.7,
		"direction_base_angle_rad": atan2(0.3, 1.0),
		"direction_meander_rad": 0.35,
		"freeze_direction": false,
		"gust_scroll_speed_m_s": 1.8,
		"gust_tile_m": 24.0,
		"wind_strength": 1.0,
		"strength_cap": 1.0,
		"gust_envelope_on": true,
		"time_scale": 1.0,
	}


static func make_initial_state(cfg: Dictionary) -> Dictionary:
	return {
		"phase": 0.0,
		"gust_phase": 0.0,
		"drift_phase": 0.0,
		"flutter_phase": 0.0,
		"scroll_xz": Vector2.ZERO,
		"direction_xz": direction_xz(
			cfg["direction_base_angle_rad"],
			cfg["direction_meander_rad"],
			0.0,
			cfg.get("freeze_direction", false)),
		"sim_time": 0.0,
	}


static func advance(state: Dictionary, cfg: Dictionary, delta: float, gate: float) -> Dictionary:
	var dt: float = delta * float(cfg.get("time_scale", 1.0))
	if dt <= 0.0:
		return state
	var out := state.duplicate(true)
	out["sim_time"] = out["sim_time"] + dt
	out["phase"] = out["phase"] + dt * (TAU / cfg["wind_cycle_sec"])
	if out["phase"] >= TAU:
		out["phase"] = fmod(out["phase"], TAU)
	out["gust_phase"] = out["gust_phase"] + dt * (TAU / cfg["gust_period_sec"])
	if out["gust_phase"] >= TAU:
		out["gust_phase"] = fmod(out["gust_phase"], TAU)
	out["drift_phase"] = out["drift_phase"] + dt * (TAU / cfg["direction_drift_period_sec"])
	if out["drift_phase"] >= TAU:
		out["drift_phase"] = fmod(out["drift_phase"], TAU)
	out["flutter_phase"] = out["flutter_phase"] + dt * (TAU / cfg["flutter_period_sec"])
	if out["flutter_phase"] >= TAU:
		out["flutter_phase"] = fmod(out["flutter_phase"], TAU)
	out["direction_xz"] = direction_xz(
		cfg["direction_base_angle_rad"],
		cfg["direction_meander_rad"],
		out["drift_phase"],
		cfg.get("freeze_direction", false))
	out["scroll_xz"] = scroll_step(
		out["scroll_xz"],
		out["direction_xz"],
		cfg["gust_scroll_speed_m_s"],
		dt,
		cfg["gust_tile_m"])
	out["effective_strength"] = effective_strength(
		cfg["wind_strength"],
		cfg["strength_cap"],
		gust_envelope(out["gust_phase"]),
		gate,
		cfg.get("gust_envelope_on", true))
	return out
