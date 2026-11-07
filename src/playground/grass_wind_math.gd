class_name GrassWindMath
extends RefCounted

const GrassWindParams = preload("res://src/playground/grass_wind_params.gd")


static func variant3_cycle_frac(sim_time: float, flutter_period_sec: float) -> float:
	var period := maxf(flutter_period_sec, 1e-6)
	return fmod(sim_time / period, 1.0)


static func displace(
		variant: int,
		params: GrassWindParams,
		inputs: Dictionary,
		g: float,
		sim_time: float = 0.0) -> Vector3:
	match variant:
		0:
			return _displace_v0(params, inputs, g)
		1:
			return _displace_v1(params, inputs, g, sim_time)
		2:
			return _displace_v2(params, inputs, g)
		3:
			return _displace_v3(params, inputs, g, sim_time)
		4:
			return _displace_v4(params, inputs, g, sim_time)
		_:
			return _displace_v0(params, inputs, g)


static func _displace_v0(params: GrassWindParams, inputs: Dictionary, g: float) -> Vector3:
	var strength: float = inputs["wind_strength"]
	if strength < 0.001:
		return inputs["vertex_model"]
	var h: float = clampf(inputs["h"], 0.0, 1.0)
	var H: float = maxf(inputs["blade_height_h"], 1e-4)
	var dir_xz: Vector2 = (inputs["wind_dir"] as Vector2).normalized()
	var model_matrix: Basis = inputs["model_matrix"]
	var dir_world := Vector3(dir_xz.x, 0.0, dir_xz.y).normalized()
	var inv_model := model_matrix.inverse()
	var dir_model := (inv_model * dir_world).normalized()
	var h_pow := pow(h, params.height_exp)
	var lean := strength * H * (params.lean_base + params.lean_gust_gain * g) * h_pow
	var offset_model := dir_model * lean
	var root_xz: Vector2 = inputs["root_world_xz"]
	var blade_hash: float = inputs["blade_hash_01"]
	var flutter := strength * H * params.flutter_amp * (params.flutter_gust_base + g) * sin(
		inputs["flutter_phase"]
		+ blade_hash * TAU
		+ root_xz.dot(dir_xz) * params.flutter_space_freq) * h_pow
	offset_model += dir_model * flutter
	if params.droop_on:
		var droop := (offset_model.length_squared() / (2.0 * H)) * h
		return inputs["vertex_model"] + offset_model - Vector3(0.0, droop, 0.0)
	return inputs["vertex_model"] + offset_model


static func _displace_v2(params: GrassWindParams, inputs: Dictionary, g: float) -> Vector3:
	var strength: float = inputs["wind_strength"]
	if strength < 0.001:
		return inputs["vertex_model"]
	var h: float = clampf(inputs["h"], 0.0, 1.0)
	var H: float = maxf(inputs["blade_height_h"], 1e-4)
	var dir_xz: Vector2 = (inputs["wind_dir"] as Vector2).normalized()
	var model_matrix: Basis = inputs["model_matrix"]
	var dir_world := Vector3(dir_xz.x, 0.0, dir_xz.y).normalized()
	var dir_model := (model_matrix.inverse() * dir_world).normalized()
	var h_pow := pow(h, params.height_exp)
	var lean := strength * H * (params.lean_base + params.lean_gust_gain * g) * h_pow
	var offset_model := dir_model * lean
	if params.droop_on:
		var droop := (offset_model.length_squared() / (2.0 * H)) * h
		return inputs["vertex_model"] + offset_model - Vector3(0.0, droop, 0.0)
	return inputs["vertex_model"] + offset_model


static func _wave_g(params: GrassWindParams, root_xz: Vector2, dir_xz: Vector2, sim_time: float) -> float:
	var phase_w := root_xz.dot(dir_xz) * (TAU / params.wave_length_m) - sim_time * (
		TAU * params.wave_speed_m_s / params.wave_length_m)
	return pow(0.5 + 0.5 * sin(phase_w), params.wave_sharpness)


static func _displace_v1(params: GrassWindParams, inputs: Dictionary, _g: float, sim_time: float) -> Vector3:
	var dir_xz: Vector2 = (inputs["wind_dir"] as Vector2).normalized()
	var g := _wave_g(params, inputs["root_world_xz"], dir_xz, sim_time)
	return _displace_v0(params, inputs, g)


static func _displace_v3(params: GrassWindParams, inputs: Dictionary, g: float, sim_time: float) -> Vector3:
	var strength: float = inputs["wind_strength"]
	if strength < 0.001:
		return inputs["vertex_model"]
	var h: float = clampf(inputs["h"], 0.0, 1.0)
	var H: float = maxf(inputs["blade_height_h"], 1e-4)
	var dir_xz: Vector2 = (inputs["wind_dir"] as Vector2).normalized()
	var model_matrix: Basis = inputs["model_matrix"]
	var dir_model := (model_matrix.inverse() * Vector3(dir_xz.x, 0.0, dir_xz.y).normalized()).normalized()
	var h_pow := pow(h, params.height_exp)
	var target := strength * H * (params.lean_base + params.lean_gust_gain * g) * h_pow
	var frac := variant3_cycle_frac(sim_time, params.flutter_period_sec)
	var blade_hash: float = inputs["blade_hash_01"]
	var ring := params.overshoot_gain * target * exp(-params.spring_damping * frac) * sin(
		TAU * params.spring_freq_hz * sim_time + blade_hash * TAU * params.phase_spread)
	var offset_model := dir_model * (target + ring)
	if params.droop_on:
		var droop := (offset_model.length_squared() / (2.0 * H)) * h
		return inputs["vertex_model"] + offset_model - Vector3(0.0, droop, 0.0)
	return inputs["vertex_model"] + offset_model


static func _front_g(params: GrassWindParams, root_xz: Vector2, dir_xz: Vector2, sim_time: float) -> float:
	var s := root_xz.dot(dir_xz)
	var f := fmod(sim_time * params.front_speed_m_s, params.front_spacing_m)
	var d1 := fmod(s - f, params.front_spacing_m)
	var d := minf(d1, params.front_spacing_m - d1)
	return params.front_peak * exp(-(d * d) / (2.0 * params.front_width_m * params.front_width_m))


static func _displace_v4(params: GrassWindParams, inputs: Dictionary, _g: float, sim_time: float) -> Vector3:
	var dir_xz: Vector2 = (inputs["wind_dir"] as Vector2).normalized()
	var g := _front_g(params, inputs["root_world_xz"], dir_xz, sim_time)
	return _displace_v0(params, inputs, g)
