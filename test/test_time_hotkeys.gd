## Keyboard time controls: Space toggles pause, 1/2/3 pick Watch/Fast/Grow.
extends GutTest

const IvyParams = preload("res://src/params/ivy_params.gd")
const SimClock = preload("res://src/core/sim_clock.gd")

var _clock: SimClock


func before_each() -> void:
	_clock = SimClock.new(IvyParams.new())


func test_toggle_pause_resumes_the_speed_it_paused_from() -> void:
	_clock.set_speed(SimClock.Speed.FAST)
	_clock.toggle_pause()
	assert_eq(_clock.speed, SimClock.Speed.PAUSE, "first toggle pauses")
	_clock.toggle_pause()
	assert_eq(_clock.speed, SimClock.Speed.FAST,
		"second toggle must resume Fast, not fall back to a default speed")


## The Pause button calls set_speed(PAUSE) directly; Space must still resume from there.
func test_resume_remembers_speed_when_paused_via_set_speed() -> void:
	_clock.set_speed(SimClock.Speed.WATCH)
	_clock.set_speed(SimClock.Speed.PAUSE)
	_clock.toggle_pause()
	assert_eq(_clock.speed, SimClock.Speed.WATCH)


## Pausing twice in a row (button then Space) must not overwrite the remembered speed with PAUSE.
func test_repeated_pause_does_not_lose_resume_speed() -> void:
	_clock.set_speed(SimClock.Speed.FAST)
	_clock.set_speed(SimClock.Speed.PAUSE)
	_clock.set_speed(SimClock.Speed.PAUSE)
	_clock.toggle_pause()
	assert_eq(_clock.speed, SimClock.Speed.FAST)


func test_number_keys_map_to_speeds_and_other_keys_do_not() -> void:
	assert_eq(SimClock.speed_for_hotkey(KEY_1), SimClock.Speed.WATCH)
	assert_eq(SimClock.speed_for_hotkey(KEY_2), SimClock.Speed.FAST)
	assert_eq(SimClock.speed_for_hotkey(KEY_3), SimClock.Speed.GROW)
	assert_eq(SimClock.speed_for_hotkey(KEY_4), -1, "no fourth speed")
	assert_eq(SimClock.speed_for_hotkey(KEY_W), -1, "W is camera zoom, not a time key")
