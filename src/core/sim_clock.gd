class_name SimClock
extends RefCounted

enum Speed { PAUSE, WATCH, FAST, GROW }

const MAX_TICKS_PER_FRAME := 8

var params: IvyParams
var speed: Speed = Speed.GROW
var tick_index: int = 0
var game_day: float = 0.0
var _accumulator: float = 0.0


func _init(p: IvyParams) -> void:
	params = p
	_update_game_day()


func set_speed(new_speed: Speed) -> void:
	speed = new_speed


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
