class_name FaunaPresentationContext
extends RefCounted

var game_day: float = 0.0
## Local solar hour (SD-TIME-6 start_hour), same as Solar.hour_of_day(game_day).
var local_solar_hour: float = 12.0
var lit: float = 1.0
var render_blend: float = 1.0
var weather_activity_scale: float = 1.0
var wind: AmbientWind = null
var camera_global_position: Vector3 = Vector3.ZERO
var pivot_global_position: Vector3 = Vector3.ZERO
var backdrop_global_transform: Transform3D = Transform3D.IDENTITY
var paused: bool = false
