class_name SimClock
extends RefCounted

enum Speed { PAUSE, NORMAL, FAST, GROW }

const MAX_TICKS_PER_FRAME := 8

# --------------------------------------------------------------------------
# SD-TIME-2 gameplay wall-clock rates
#
# Normal: 1 simulated hour every NORMAL_WALL_SEC_PER_HOUR seconds, with
#   NORMAL_SEGMENTS_PER_SIM_HOUR growth steps per hour (one segment slot per second).
# Fast: same segment cadence as Normal but 10× calendar speed.
# Grow: same calendar as Normal but GROW_SEGMENTS_PER_SIM_HOUR segment slots per hour.
#
# To revert to legacy param-based speeds, restore the pre-2026-10 branch.
# --------------------------------------------------------------------------
const NORMAL_WALL_SEC_PER_HOUR := 15.0
const NORMAL_SEGMENTS_PER_SIM_HOUR := 15.0
const FAST_TIME_MULTIPLIER := 10.0
const GROW_SEGMENTS_PER_SIM_HOUR := 60.0
const HOURS_PER_GAME_DAY := 24.0

# SD-TIME-NIGHT: geometric night (sin_elevation ≤ 0) advances 8× faster in wall time.
const NIGHT_TIME_COMPRESSION := 8.0

var params: IvyParams
var _solar: Solar
var speed: Speed = Speed.GROW
var tick_index: int = 0
var game_day: float = 0.0
var _accumulator: float = 0.0
var _resume_speed: Speed = Speed.GROW


func _init(p: IvyParams) -> void:
	params = p
	_solar = Solar.new(p)
	_update_game_day()


func set_speed(new_speed: Speed) -> void:
	if new_speed == speed:
		return
	var day := display_game_day()
	if new_speed == Speed.PAUSE:
		if speed != Speed.PAUSE:
			_resume_speed = speed
		game_day = day
		tick_index = int(floor(day / sim_tick_size_for(_resume_speed)))
		_accumulator = 0.0
		speed = Speed.PAUSE
		return
	if speed == Speed.PAUSE:
		day = game_day
	speed = new_speed
	var tick_size := sim_tick_size_for(speed)
	tick_index = int(floor(day / tick_size))
	var whole := float(tick_index) * tick_size
	_accumulator = (day - whole) / tick_size
	_update_game_day()


func toggle_pause() -> void:
	set_speed(_resume_speed if speed == Speed.PAUSE else Speed.PAUSE)


static func speed_for_hotkey(keycode: Key) -> int:
	match keycode:
		KEY_1:
			return Speed.NORMAL
		KEY_2:
			return Speed.FAST
		KEY_3:
			return Speed.GROW
		_:
			return -1


static func segments_per_sim_hour_for(s: Speed) -> float:
	if s == Speed.GROW:
		return GROW_SEGMENTS_PER_SIM_HOUR
	return NORMAL_SEGMENTS_PER_SIM_HOUR


## Growth steps per simulated hour (one step = one segment budget slot at full vigour).
static func ticks_per_sim_hour_for(s: Speed) -> float:
	return segments_per_sim_hour_for(s)


static func ticks_per_game_day_for(s: Speed) -> float:
	return HOURS_PER_GAME_DAY * ticks_per_sim_hour_for(s)


static func ticks_for_game_days(days: float, s: Speed) -> int:
	return int(round(days * ticks_per_game_day_for(s)))


static func sim_tick_size_for(s: Speed) -> float:
	return 1.0 / (HOURS_PER_GAME_DAY * ticks_per_sim_hour_for(s))


static func wall_seconds_per_game_day_for(s: Speed) -> float:
	var hour_rate := 1.0
	if s == Speed.FAST:
		hour_rate = FAST_TIME_MULTIPLIER
	return HOURS_PER_GAME_DAY * NORMAL_WALL_SEC_PER_HOUR / hour_rate


static func nominal_ticks_per_second_for(s: Speed) -> float:
	if s == Speed.PAUSE:
		return 0.0
	var hours_per_15s := 1.0
	if s == Speed.FAST:
		hours_per_15s = FAST_TIME_MULTIPLIER
	var tph := ticks_per_sim_hour_for(s)
	return hours_per_15s * tph / NORMAL_WALL_SEC_PER_HOUR


func advance_real(delta: float) -> int:
	if speed == Speed.PAUSE:
		return 0
	var ticks_per_second := nominal_ticks_per_second_for(speed) * _clock_rate_scale()
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
	return sim_tick_size_for(speed)


func seconds_per_game_day() -> float:
	match speed:
		Speed.FAST:
			return wall_seconds_per_game_day_for(Speed.FAST)
		Speed.GROW:
			return wall_seconds_per_game_day_for(Speed.GROW)
		_:
			return wall_seconds_per_game_day_for(Speed.NORMAL)


func _update_game_day() -> void:
	game_day = float(tick_index) * sim_tick_size_for(speed)


func display_game_day() -> float:
	if speed == Speed.PAUSE:
		return game_day
	return game_day + _accumulator * dt_sim()


func _clock_rate_scale() -> float:
	var hour := _solar.hour_of_day(display_game_day())
	if _solar.sin_elevation(hour) <= 0.0:
		return NIGHT_TIME_COMPRESSION
	return 1.0
