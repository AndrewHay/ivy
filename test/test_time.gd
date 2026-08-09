extends GutTest

const IvyParams = preload("res://src/params/ivy_params.gd")
const SimClock = preload("res://src/core/sim_clock.gd")
var _params: IvyParams
var _clock: SimClock


func before_each() -> void:
	_params = IvyParams.new()
	_clock = SimClock.new(_params)


func test_fixed_tick_at_all_speeds() -> void:
	assert_almost_eq(_clock.dt_sim(), 1.0 / 24.0, 1e-9)
	_clock.set_speed(SimClock.Speed.WATCH)
	_clock.advance_ticks(24)
	assert_almost_eq(_clock.game_day, 1.0, 1e-6)
	_clock.set_speed(SimClock.Speed.GROW)
	_clock.advance_ticks(24)
	assert_almost_eq(_clock.game_day, 2.0, 1e-6)


func test_pause_advances_nothing() -> void:
	_clock.set_speed(SimClock.Speed.PAUSE)
	var n := _clock.advance_real(10.0)
	assert_eq(n, 0)
	assert_eq(_clock.tick_index, 0)


func test_advance_ticks_deterministic() -> void:
	var c1 := SimClock.new(_params)
	var c2 := SimClock.new(_params)
	c1.advance_ticks(720)
	c2.advance_ticks(720)
	assert_eq(c1.tick_index, c2.tick_index)
	assert_eq(c1.game_day, c2.game_day)


func test_seconds_per_game_day_drives_the_render_blend() -> void:
	# SD-TIME-2 / SD-TIME-4: the wall-clock length of a game-day is what the render-sun
	# blend reads. Pause has no rate, so it reports the Watch figure and stays live.
	_clock.set_speed(SimClock.Speed.WATCH)
	assert_almost_eq(_clock.seconds_per_game_day(), _params.speed_watch, 1e-9)
	_clock.set_speed(SimClock.Speed.FAST)
	assert_almost_eq(_clock.seconds_per_game_day(), _params.speed_fast, 1e-9)
	_clock.set_speed(SimClock.Speed.GROW)
	assert_almost_eq(_clock.seconds_per_game_day(), _params.speed_grow, 1e-9)
	_clock.set_speed(SimClock.Speed.PAUSE)
	assert_almost_eq(_clock.seconds_per_game_day(), _params.speed_watch, 1e-9)


func test_speed_mapping() -> void:
	_clock.set_speed(SimClock.Speed.WATCH)
	var ticks := 0
	while ticks < 24:
		var n := _clock.advance_real(_params.speed_watch / 24.0)
		if n > 0:
			_clock.advance_ticks(n)
		ticks += n
	assert_eq(_clock.tick_index, 24)
