extends GutTest

const GrassWindMath = preload("res://src/playground/grass_wind_math.gd")
const GrassWindParams = preload("res://src/playground/grass_wind_params.gd")
const GrassWindClock = preload("res://src/presentation/fauna/grass_wind_clock.gd")
const AmbientWind = preload("res://src/presentation/fauna/ambient_wind.gd")
const SimClock = preload("res://src/core/sim_clock.gd")


static func _reference_ivy_wind_tip_displace(
		vertex_model: Vector3,
		h: float,
		blade_height_h: float,
		model_matrix: Basis,
		root_world_xz: Vector2,
		blade_hash_01: float,
		wind_strength: float,
		wind_dir: Vector2,
		flutter_phase: float,
		g: float) -> Vector3:
	if wind_strength < 0.001:
		return vertex_model
	h = clampf(h, 0.0, 1.0)
	var H := maxf(blade_height_h, 1e-4)
	var dir_xz := wind_dir.normalized()
	var dir_world := Vector3(dir_xz.x, 0.0, dir_xz.y).normalized()
	var inv_model := model_matrix.inverse()
	var dir_model := (inv_model * dir_world).normalized()
	var lean := wind_strength * H * (0.10 + 0.45 * g) * h * h
	var offset_model := dir_model * lean
	var flutter := wind_strength * H * 0.04 * (0.4 + g) * sin(
		flutter_phase + blade_hash_01 * TAU + root_world_xz.dot(dir_xz) * 1.3) * h * h
	offset_model += dir_model * flutter
	var droop := (offset_model.length_squared() / (2.0 * H)) * h
	return vertex_model + offset_model - Vector3(0.0, droop, 0.0)


func _sample_inputs() -> Array:
	var samples: Array = []
	var model := Basis.from_euler(Vector3(0.2, 0.7, -0.1)).scaled(Vector3(1.0, 1.1, 1.0))
	for h in [0.0, 0.25, 0.55, 1.0]:
		for g in [0.0, 0.15, 0.62, 1.0]:
			samples.append({
				"vertex": Vector3(0.01, 0.08 * h, 0.002),
				"h": h,
				"H": 0.22,
				"model_matrix": model,
				"root_xz": Vector2(3.7, -1.2),
				"hash": 0.37,
				"g": g,
				"strength": 0.85,
				"dir": Vector2(0.96, 0.28),
				"flutter_phase": 1.1,
			})
	samples.append({
		"vertex": Vector3(0.0, 0.1, 0.0),
		"h": 0.5,
		"H": 0.2,
		"model_matrix": Basis.IDENTITY,
		"root_xz": Vector2(0.0, 0.0),
		"hash": 0.5,
		"g": 0.5,
		"strength": 0.0005,
		"dir": Vector2(1.0, 0.0),
		"flutter_phase": 0.0,
	})
	return samples


func test_variant0_displace_matches_production_formula() -> void:
	var params := GrassWindParams.new()
	for s in _sample_inputs():
		var inputs := {
			"vertex_model": s["vertex"],
			"h": s["h"],
			"blade_height_h": s["H"],
			"model_matrix": s["model_matrix"],
			"root_world_xz": s["root_xz"],
			"blade_hash_01": s["hash"],
			"wind_strength": s["strength"],
			"wind_dir": s["dir"],
			"flutter_phase": s["flutter_phase"],
		}
		var got := GrassWindMath.displace(0, params, inputs, s["g"])
		var want := _reference_ivy_wind_tip_displace(
			s["vertex"], s["h"], s["H"], s["model_matrix"], s["root_xz"], s["hash"],
			s["strength"], s["dir"], s["flutter_phase"], s["g"])
		for axis in ["x", "y", "z"]:
			assert_almost_eq(got[axis], want[axis], 1e-6,
				"v0 displace axis %s h=%s g=%s" % [axis, s["h"], s["g"]])


func test_grass_wind_clock_matches_ambient_wind_integration() -> void:
	var wind := AmbientWind.new()
	add_child_autofree(wind)
	var cfg := GrassWindClock.config_from_ambient_wind()
	var clock_state := GrassWindClock.make_initial_state(cfg)
	var dt := 0.033
	for _step in range(120):
		wind.advance(SimClock.Speed.NORMAL, dt)
		clock_state = GrassWindClock.advance(clock_state, cfg, dt, 1.0)
		assert_almost_eq(clock_state["flutter_phase"], wind.get_flutter_phase(), 1e-6)
		assert_almost_eq(clock_state["scroll_xz"].x, wind.get_gust_scroll().x, 1e-6)
		assert_almost_eq(clock_state["scroll_xz"].y, wind.get_gust_scroll().y, 1e-6)
		assert_almost_eq(clock_state["direction_xz"].x, wind.get_horizontal_direction().x, 1e-6)
		assert_almost_eq(clock_state["direction_xz"].y, wind.get_horizontal_direction().y, 1e-6)
		var env_w := wind.get_gust_envelope()
		var env_c := GrassWindClock.gust_envelope(clock_state["gust_phase"])
		assert_almost_eq(env_c, env_w, 1e-6)
		assert_almost_eq(clock_state["phase"], wind.get_phase(), 1e-6)
		assert_almost_eq(
			clock_state["effective_strength"] * wind._gate,
			wind.get_effective_strength(),
			1e-6)


func test_variant3_spring_frac_uses_flutter_period() -> void:
	assert_almost_eq(GrassWindMath.variant3_cycle_frac(1.0, 2.0), 0.5, 1e-6)
	assert_almost_eq(GrassWindMath.variant3_cycle_frac(2.0, 2.0), 0.0, 1e-6)
	assert_almost_eq(GrassWindMath.variant3_cycle_frac(0.85, 1.7), 0.85 / 1.7, 1e-6)


func test_variants_1_to_4_match_spec_literals() -> void:
	var params := GrassWindParams.new()
	var root := Vector2(4.0, -2.0)
	var dir := Vector2(0.9, 0.436)
	dir = dir.normalized()
	var t := 2.3
	# Variant 1 wave g
	var phase_w := root.dot(dir) * (TAU / params.wave_length_m) - t * (
		TAU * params.wave_speed_m_s / params.wave_length_m)
	var g1 := pow(0.5 + 0.5 * sin(phase_w), params.wave_sharpness)
	var inputs_base := {
		"vertex_model": Vector3(0.0, 0.08, 0.0),
		"h": 0.8,
		"blade_height_h": 0.22,
		"model_matrix": Basis.IDENTITY,
		"root_world_xz": root,
		"blade_hash_01": 0.4,
		"wind_strength": 0.9,
		"wind_dir": dir,
		"flutter_phase": 0.5,
	}
	var d1 := GrassWindMath.displace(1, params, inputs_base, 0.0, t)
	var d1_g := GrassWindMath.displace(0, params, inputs_base, g1)
	assert_almost_eq(d1.x, d1_g.x, 1e-6)
	assert_almost_eq(d1.y, d1_g.y, 1e-6)
	assert_almost_eq(d1.z, d1_g.z, 1e-6)
	# Variant 2 — lean only (no flutter term)
	params.droop_on = false
	params.flutter_amp = 0.2
	var d2 := GrassWindMath.displace(2, params, inputs_base, 0.6)
	var d0 := GrassWindMath.displace(0, params, inputs_base, 0.6)
	var base: Vector3 = inputs_base["vertex_model"]
	assert_gt((d0 - base).length(), (d2 - base).length(), "v2 lean-only should be smaller than v0 with flutter")
	# Variant 4 front g
	var s := root.dot(dir)
	var f := fmod(t * params.front_speed_m_s, params.front_spacing_m)
	var d1f := fmod(s - f, params.front_spacing_m)
	var dist := minf(d1f, params.front_spacing_m - d1f)
	var g4 := params.front_peak * exp(-(dist * dist) / (2.0 * params.front_width_m * params.front_width_m))
	var d4 := GrassWindMath.displace(4, params, inputs_base, 0.0, t)
	var d4_g := GrassWindMath.displace(0, params, inputs_base, g4)
	for axis in ["x", "y", "z"]:
		assert_almost_eq(d4[axis], d4_g[axis], 1e-6)
