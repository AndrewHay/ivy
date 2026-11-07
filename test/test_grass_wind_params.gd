extends GutTest

const GrassWindParams = preload("res://src/playground/grass_wind_params.gd")
const AmbientWind = preload("res://src/presentation/fauna/ambient_wind.gd")


func test_defaults_match_ambient_wind_constants() -> void:
	var p := GrassWindParams.new()
	assert_almost_eq(p.wind_strength, AmbientWind.WIND_BASE_STRENGTH, 1e-6)
	assert_almost_eq(p.strength_cap, AmbientWind.WIND_STRENGTH_CAP, 1e-6)
	assert_almost_eq(p.gust_period_sec, AmbientWind.WIND_GUST_PERIOD_SEC, 1e-6)
	assert_almost_eq(p.gust_tile_m, AmbientWind.GUST_TILE_M, 1e-6)
	assert_almost_eq(p.gust_scroll_speed_m_s, AmbientWind.GUST_SPEED_M_S, 1e-6)
	assert_almost_eq(p.direction_meander_rad, AmbientWind.DIRECTION_MEANDER_RAD, 1e-6)
	assert_almost_eq(
		p.direction_drift_period_sec, AmbientWind.DIRECTION_DRIFT_PERIOD_SEC, 1e-6)
	assert_almost_eq(p.flutter_period_sec, AmbientWind.FLUTTER_PERIOD_SEC, 1e-6)
	var expected_deg := rad_to_deg(AmbientWind.DIRECTION_BASE_ANGLE)
	assert_almost_eq(p.direction_deg, expected_deg, 1e-4)


func test_group_c_shader_literal_defaults() -> void:
	var p := GrassWindParams.new()
	assert_almost_eq(p.lean_base, 0.10, 1e-6)
	assert_almost_eq(p.lean_gust_gain, 0.45, 1e-6)
	assert_almost_eq(p.flutter_amp, 0.04, 1e-6)
	assert_almost_eq(p.flutter_gust_base, 0.4, 1e-6)
	assert_almost_eq(p.flutter_space_freq, 1.3, 1e-6)
	assert_almost_eq(p.height_exp, 2.0, 1e-6)
	assert_almost_eq(p.gust_edge_lo, 0.38, 1e-6)
	assert_almost_eq(p.gust_edge_hi, 0.78, 1e-6)
	assert_true(p.droop_on)
	assert_true(p.gust_envelope_on)


func test_dict_round_trip() -> void:
	var p := GrassWindParams.new()
	p.wind_strength = 1.23
	p.variant = 2
	p.wave_length_m = 30.0
	p.freeze_direction = true
	var d := p.to_dict()
	var q := GrassWindParams.new()
	q.from_dict(d)
	assert_almost_eq(q.wind_strength, 1.23, 1e-6)
	assert_eq(q.variant, 2)
	assert_almost_eq(q.wave_length_m, 30.0, 1e-6)
	assert_true(q.freeze_direction)


func test_presets_override_named_knobs_only() -> void:
	var presets := GrassWindParams.presets()
	assert_true(presets.has("Dead calm"))
	var p := GrassWindParams.new()
	p.apply_preset("Dead calm")
	assert_almost_eq(p.wind_strength, 0.15, 1e-6)
	assert_false(p.gust_envelope_on)
	assert_almost_eq(p.lean_base, 0.10, 1e-6, "Unset knobs stay at production default")
	var wheat := GrassWindParams.new()
	wheat.apply_preset("Wheat field")
	assert_eq(wheat.variant, 1)
	assert_almost_eq(wheat.wave_length_m, 30.0, 1e-6)


func test_json_block_schema() -> void:
	var p := GrassWindParams.new()
	var block := p.to_json_block()
	assert_true(block.contains("\"schema\": \"grass_wind_playground.v1\""))
	assert_true(block.contains("\"variant\""))
	assert_true(block.contains("\"knobs\""))
	assert_true(block.contains("\"wind_strength\""))
