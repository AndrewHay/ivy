class_name SimClock
extends RefCounted

enum Speed { PAUSE, WATCH, FAST, GROW }

const MAX_TICKS_PER_FRAME := 8

var params: IvyParams
var speed: Speed = Speed.GROW
var tick_index: int = 0
var game_day: float = 0.0
var _accumulator: float = 0.0
var _resume_speed: Speed = Speed.GROW


func _init(p: IvyParams) -> void:
	params = p
	_update_game_day()


func set_speed(new_speed: Speed) -> void:
	# Remember what we paused from so Space can resume it, whichever control paused.
	if new_speed == Speed.PAUSE and speed != Speed.PAUSE:
		_resume_speed = speed
	speed = new_speed


## Space: pause, or resume at the speed that was running before the pause.
func toggle_pause() -> void:
	set_speed(_resume_speed if speed == Speed.PAUSE else Speed.PAUSE)


## Number-key hotkeys for the speed buttons. Returns a Speed, or -1 for any other key.
## Pause has no number key; it lives on Space so it behaves as a toggle.
static func speed_for_hotkey(keycode: Key) -> int:
	match keycode:
		KEY_1:
			return Speed.WATCH
		KEY_2:
			return Speed.FAST
		KEY_3:
			return Speed.GROW
		_:
			return -1


func advance_real(delta: float) -> int:
	if speed == Speed.PAUSE:
		return 0
	var ticks_per_second := _ticks_per_second()
	_accumulator += delta * ticks_per_second
	var n := int(floor(_accumulator))
	if n > MAX_TICKS_PER_FRAME:
		n = MAX_TICKS_PER_FRAME
	_accumulator -= float(n)
	return n


func advance_ticks(n: int) -> void:
	for _i in range(n):
		tick_index += 1
	_update_game_day()


func dt_sim() -> float:
	return params.sim_tick


## Wall-clock seconds a game-day takes at the current speed. Drives the SD-TIME-4
## render-sun blend. Pause reports the Watch figure so pausing does not swap the
## rendered sun to the daily average.
func seconds_per_game_day() -> float:
	match speed:
		Speed.FAST:
			return params.speed_fast
		Speed.GROW:
			return params.speed_grow
		_:
			return params.speed_watch


func _ticks_per_second() -> float:
	match speed:
		Speed.WATCH:
			return 24.0 / params.speed_watch
		Speed.FAST:
			return 24.0 / params.speed_fast
		Speed.GROW:
			return 24.0 / params.speed_grow
		_:
			return 0.0


func _update_game_day() -> void:
	game_day = float(tick_index) * params.sim_tick


## Sub-tick time for rendering only — simulation stays on hourly ticks (SD-TIME-1).
func display_game_day() -> float:
	if speed == Speed.PAUSE:
		return game_day
	return game_day + _accumulator * params.sim_tick
