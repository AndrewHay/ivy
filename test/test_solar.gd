extends GutTest

## SD-TIME-6 fixed epoch: latitude 51.5 N, longitude 0, UTC, day-of-year 105.
## SD-CONV-2 frame: azimuth 0 = north = -Z, south = +Z.

const IvyParams = preload("res://src/params/ivy_params.gd")
const Solar = preload("res://src/env/solar.gd")

var _params: IvyParams
var _solar: Solar


func before_each() -> void:
	_params = IvyParams.new()
	_solar = Solar.new(_params)


func test_solar_noon_sun_is_due_south_and_up() -> void:
	var s := _solar.direction(12.0)
	assert_almost_eq(s.x, 0.0, 0.02, "noon sun has no east/west component")
	assert_gt(s.y, 0.0, "noon sun is above the horizon")
	assert_gt(s.z, 0.0, "noon sun is toward +Z (south), SD-CONV-2")
	assert_almost_eq(_solar.azimuth_deg(12.0), 180.0, 1.0)


func test_day_length_matches_fixed_epoch() -> void:
	assert_almost_eq(_solar.day_length_hours(), 13.5, 0.5)


func test_sunrise_and_sunset_near_due_east_and_west() -> void:
	var rise_az := _solar.azimuth_deg(_solar.sunrise_hour())
	var set_az := _solar.azimuth_deg(_solar.sunset_hour())
	assert_almost_eq(rise_az, 90.0, 20.0, "sunrise close to due east")
	assert_almost_eq(set_az, 270.0, 20.0, "sunset close to due west")


func test_sun_is_below_horizon_at_solar_midnight() -> void:
	assert_lt(_solar.sin_elevation(0.0), 0.0)
	assert_lt(_solar.elevation_deg(0.0), 0.0)


func test_elevation_rises_monotonically_to_solar_noon() -> void:
	var prev := _solar.sin_elevation(_solar.sunrise_hour())
	var hour := _solar.sunrise_hour() + 0.5
	while hour < 12.0:
		var cur := _solar.sin_elevation(hour)
		assert_gt(cur, prev, "elevation rising at hour %f" % hour)
		prev = cur
		hour += 0.5


func test_direction_is_unit_at_every_hour() -> void:
	for i in 24:
		assert_almost_eq(_solar.direction(float(i)).length(), 1.0, 1e-5, "hour %d" % i)


func test_hour_of_day_starts_at_start_hour() -> void:
	assert_almost_eq(_solar.hour_of_day(0.0), _params.start_hour, 1e-9)
	assert_almost_eq(_solar.hour_of_day(1.0), _params.start_hour, 1e-9)
	assert_almost_eq(_solar.hour_of_day(0.25), _params.start_hour + 6.0, 1e-6)


func test_deterministic_across_instances() -> void:
	var other := Solar.new(IvyParams.new())
	for i in 48:
		var hour := float(i) * 0.5
		assert_eq(_solar.direction(hour), other.direction(hour), "hour %f" % hour)
	assert_eq(_solar.day_average_direction(), other.day_average_direction())
	assert_eq(_solar.g_ref(), other.g_ref())


func test_day_average_direction_points_south_and_up() -> void:
	var avg := _solar.day_average_direction()
	assert_almost_eq(avg.length(), 1.0, 1e-5)
	assert_gt(avg.y, 0.0, "mean sun is above the horizon")
	assert_gt(avg.z, 0.0, "mean sun is southward")
	assert_almost_eq(avg.x, 0.0, 0.05, "mean sun has no net east/west bias")


func test_render_blend_is_one_at_watch_and_zero_at_time_lapse() -> void:
	assert_almost_eq(_solar.render_blend(_params.speed_watch), 1.0, 1e-9, "Watch is instantaneous")
	assert_almost_eq(_solar.render_blend(_params.speed_fast), 0.0, 1e-9, "Fast is day-average")
	assert_almost_eq(_solar.render_blend(_params.speed_grow), 0.0, 1e-9, "Grow is day-average")


func test_render_direction_follows_blend() -> void:
	var game_day := 0.5
	var live := _solar.direction_at(game_day)
	var avg := _solar.day_average_direction()
	assert_almost_eq(
		_solar.render_direction(game_day, _params.speed_watch).distance_to(live), 0.0, 1e-5
	)
	assert_almost_eq(
		_solar.render_direction(game_day, _params.speed_grow).distance_to(avg), 0.0, 1e-5
	)


func test_light_field_sun_is_never_blended() -> void:
	# SD-TIME-4: the field always uses S(t) at tick resolution regardless of speed.
	var game_day := 0.3333333
	assert_eq(_solar.direction_at(game_day), _solar.direction(_solar.hour_of_day(game_day)))


func test_diel_gate_is_mean_preserving_over_a_game_day() -> void:
	# SD-TIME-8b: mean of g_hat over the 24 ticks of a game-day is 1.
	var sum := 0.0
	for i in 24:
		sum += _solar.diel_gate(float(i) * _params.sim_tick)
	assert_almost_eq(sum / 24.0, 1.0, 0.02)


func test_diel_gate_magnitudes() -> void:
	# SD-TIME-8c: about 2.1 at solar noon, about 0.11 at night.
	var noon_day := (12.0 - _params.start_hour) / 24.0
	var midnight_day := (24.0 - _params.start_hour) / 24.0
	assert_almost_eq(_solar.diel_gate(noon_day), 2.1, 0.25)
	assert_almost_eq(_solar.diel_gate(midnight_day), 0.11, 0.04)
	assert_almost_eq(_solar.g_ref(), 0.45, 0.08)


func test_diel_gate_is_bounded() -> void:
	for i in 240:
		var g := _solar.diel_gate(float(i) / 10.0 * _params.sim_tick)
		assert_between(g, 0.0, 3.0)
