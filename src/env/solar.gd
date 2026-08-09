class_name Solar
extends RefCounted

## NOAA solar position for the SD-TIME-6 fixed epoch, the SD-TIME-4 render-sun
## blend, and the SD-TIME-8 diel growth gate.
##
## Reference: https://gml.noaa.gov/grad/solcalc/solareqns.PDF
##
## Every angle crossing into world space goes through `Conv` (SD-CONV-7). Azimuth
## is measured clockwise from north, which is -Z (SD-CONV-2).

const HOURS_PER_DAY := 24
const MINUTES_PER_DEGREE_HOUR_ANGLE := 4.0
const DEGREES_PER_HOUR := 15.0

var params: IvyParams

var _day_average: Vector3 = Conv.UP
var _g_ref: float = 1.0


func _init(p: IvyParams) -> void:
	params = p
	_day_average = _compute_day_average()
	_g_ref = _compute_g_ref()


## Local clock hour for a simulation game-day. Runs start at `start_hour` (SD-TIME-6).
func hour_of_day(game_day: float) -> float:
	return fposmod(params.start_hour + game_day * float(HOURS_PER_DAY), float(HOURS_PER_DAY))


func equation_of_time_minutes(hour: float) -> float:
	var g := _fractional_year(hour)
	return 229.18 * (
		0.000075
		+ 0.001868 * cos(g)
		- 0.032077 * sin(g)
		- 0.014615 * cos(2.0 * g)
		- 0.040849 * sin(2.0 * g)
	)


func declination_rad(hour: float) -> float:
	var g := _fractional_year(hour)
	return (
		0.006918
		- 0.399912 * cos(g)
		+ 0.070257 * sin(g)
		- 0.006758 * cos(2.0 * g)
		+ 0.000907 * sin(2.0 * g)
		- 0.002697 * cos(3.0 * g)
		+ 0.001480 * sin(3.0 * g)
	)


## Degrees west of solar noon; 0 at solar noon, negative in the morning.
func hour_angle_deg(hour: float) -> float:
	var true_solar_minutes := (
		hour * 60.0
		+ equation_of_time_minutes(hour)
		+ MINUTES_PER_DEGREE_HOUR_ANGLE * params.longitude
	)
	return true_solar_minutes / MINUTES_PER_DEGREE_HOUR_ANGLE - 180.0


func sin_elevation(hour: float) -> float:
	var phi := deg_to_rad(params.latitude)
	var dec := declination_rad(hour)
	var ha := deg_to_rad(hour_angle_deg(hour))
	return sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(ha)


func elevation_deg(hour: float) -> float:
	return rad_to_deg(asin(clampf(sin_elevation(hour), -1.0, 1.0)))


func azimuth_deg(hour: float) -> float:
	var phi := deg_to_rad(params.latitude)
	var dec := declination_rad(hour)
	var ha := deg_to_rad(hour_angle_deg(hour))
	# atan2 form gives azimuth from south, positive toward west; +180 puts it on
	# the SD-CONV-2 clockwise-from-north convention.
	var from_south := atan2(sin(ha), cos(ha) * sin(phi) - tan(dec) * cos(phi))
	return fposmod(rad_to_deg(from_south) + 180.0, 360.0)


## Unit vector from the surface toward the sun.
func direction(hour: float) -> Vector3:
	return Conv.sun_direction(azimuth_deg(hour), elevation_deg(hour))


func direction_at(game_day: float) -> Vector3:
	return direction(hour_of_day(game_day))


## Irradiance-weighted mean sun direction for the fixed date (SD-TIME-4).
func day_average_direction() -> Vector3:
	return _day_average


## SD-TIME-4 blend factor: 1 = instantaneous sun, 0 = steady daily average.
func render_blend(seconds_per_game_day: float) -> float:
	return smoothstep(params.render_sun_blend_lo, params.render_sun_blend_hi, seconds_per_game_day)


## Sun direction for the *rendered* light and sky only. The light field never uses
## this — it always reads `direction_at()` at tick resolution (SD-TIME-4).
func render_direction(game_day: float, seconds_per_game_day: float) -> Vector3:
	var b := render_blend(seconds_per_game_day)
	if b >= 1.0:
		return direction_at(game_day)
	if b <= 0.0:
		return _day_average
	return _day_average.slerp(direction_at(game_day), b)


func day_length_hours() -> float:
	return 2.0 * _sunrise_hour_angle_deg() / DEGREES_PER_HOUR


func sunrise_hour() -> float:
	return _hour_of_hour_angle(-_sunrise_hour_angle_deg())


func sunset_hour() -> float:
	return _hour_of_hour_angle(_sunrise_hour_angle_deg())


## Unnormalized diel gate g(t) (SD-TIME-8). Elevation only — a scalar, never a
## direction (INV-3a).
func diel_gate_raw(hour: float) -> float:
	var s := maxf(0.0, sin_elevation(hour))
	return params.diel_night_floor + (1.0 - params.diel_night_floor) * pow(s, params.diel_exponent)


## Mean-preserving diel gate g_hat(t). Constant `g_ref` is legitimate because
## SD-TIME-6 fixes the date, which also removes the undefined day-0 case (AR-AMBIG-7).
func diel_gate(game_day: float) -> float:
	if _g_ref <= 1e-9:
		return 1.0
	return clampf(diel_gate_raw(hour_of_day(game_day)) / _g_ref, 0.0, 3.0)


func g_ref() -> float:
	return _g_ref


func _fractional_year(hour: float) -> float:
	return TAU / 365.0 * (float(params.day_of_year) - 1.0 + (hour - 12.0) / 24.0)


## Hour angle at which elevation crosses zero, in degrees. Clamped so polar day and
## polar night degrade to a full or empty day rather than a NaN.
func _sunrise_hour_angle_deg() -> float:
	var phi := deg_to_rad(params.latitude)
	var dec := declination_rad(12.0)
	return rad_to_deg(acos(clampf(-tan(phi) * tan(dec), -1.0, 1.0)))


func _hour_of_hour_angle(ha_deg: float) -> float:
	var offset := (
		equation_of_time_minutes(12.0) + MINUTES_PER_DEGREE_HOUR_ANGLE * params.longitude
	)
	return (MINUTES_PER_DEGREE_HOUR_ANGLE * (ha_deg + 180.0) - offset) / 60.0


func _compute_day_average() -> Vector3:
	var acc := Vector3.ZERO
	for i in HOURS_PER_DAY:
		var hour := float(i)
		var s := sin_elevation(hour)
		if s <= 0.0:
			continue
		acc += direction(hour) * pow(s, params.light_elevation_exponent_direct)
	if acc.length_squared() < 1e-12:
		return Conv.UP
	return acc.normalized()


func _compute_g_ref() -> float:
	var sum := 0.0
	for i in HOURS_PER_DAY:
		sum += diel_gate_raw(float(i))
	return sum / float(HOURS_PER_DAY)
