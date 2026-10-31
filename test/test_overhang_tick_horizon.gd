## ivy-7dz — day-100 tick horizon uses runtime SimClock (SD-TIME-2), not const expr.
extends GutTest

const SimClock = preload("res://src/core/sim_clock.gd")


func test_day_100_normal_ticks_is_positive() -> void:
	var ticks := SimClock.ticks_for_game_days(100.0, SimClock.Speed.NORMAL)
	assert_gt(ticks, 0, "100 game-days at NORMAL must advance a positive tick count")
	assert_eq(ticks, SimClock.ticks_for_game_days(100.0, SimClock.Speed.NORMAL),
		"tick horizon must be stable across calls")


func test_capture_eave_wall_script_loads() -> void:
	var scr := load("res://tools/capture_eave_wall.gd") as GDScript
	assert_not_null(scr, "capture_eave_wall.gd must parse and load")
	assert_true(scr.can_instantiate(), "capture_eave_wall.gd must instantiate")


func test_capture_eave_repro_script_loads() -> void:
	var scr := load("res://tools/capture_eave_repro.gd") as GDScript
	assert_not_null(scr, "capture_eave_repro.gd must parse and load (ivy-7dz)")
