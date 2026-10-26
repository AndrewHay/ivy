class_name WindIndicator
extends Control

## HUD readout for SD-WIND-1: breeze direction (camera-relative) and strength gate.

const SIZE := 96.0
const _ARROW_LEN := 28.0

var _dir_xz := Vector2(1.0, 0.0)
var _strength := 0.0
var _active := false
var _yaw := 0.0
var _speed_caption := "still"


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE + 16.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_wind(dir_xz: Vector2, effective_strength: float, sim_speed: SimClock.Speed, camera_yaw: float) -> void:
	_dir_xz = dir_xz
	_strength = effective_strength
	_active = effective_strength > 0.001
	_yaw = camera_yaw
	_speed_caption = caption_for_speed(sim_speed, _active)
	queue_redraw()


static func caption_for_speed(speed: SimClock.Speed, wind_active: bool) -> String:
	if wind_active:
		return "Breeze"
	match speed:
		SimClock.Speed.PAUSE:
			return "Still · pause"
		SimClock.Speed.FAST:
			return "Still · fast"
		SimClock.Speed.GROW:
			return "Still · grow"
		_:
			return "Still"


static func arrow_end(dir_xz: Vector2, yaw: float, length: float) -> Vector2:
	return SunCompass._to_screen(dir_xz, yaw) * length


func caption_text() -> String:
	return _speed_caption


func _draw() -> void:
	var centre := Vector2(SIZE * 0.5, SIZE * 0.5)
	var font := ThemeDB.fallback_font
	var bg_a := 0.55 if _active else 0.4
	draw_circle(centre, 34.0, Color(0.05, 0.07, 0.09, bg_a))
	draw_arc(centre, 34.0, 0.0, TAU, 40, Color(1, 1, 1, 0.28 if _active else 0.18), 1.2)
	var tip := centre + arrow_end(_dir_xz, _yaw, _ARROW_LEN)
	var col := Color(0.55, 0.82, 0.95, 0.95) if _active else Color(0.55, 0.58, 0.62, 0.55)
	if _dir_xz.length_squared() > 1e-6:
		draw_line(centre, tip, col, 2.5 if _active else 1.5)
		var dir := (tip - centre).normalized()
		var wing := Vector2(-dir.y, dir.x) * 5.0
		draw_line(tip, tip - dir * 8.0 + wing, col, 2.0)
		draw_line(tip, tip - dir * 8.0 - wing, col, 2.0)
	if _active:
		var bar_w := 40.0
		var bar_x := centre.x - bar_w * 0.5
		var bar_y := centre.y + 22.0
		draw_rect(Rect2(bar_x, bar_y, bar_w, 4.0), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(bar_x, bar_y, bar_w * clampf(_strength, 0.0, 1.0), 4.0),
			Color(0.45, 0.78, 0.92, 0.85))
	var text := caption_text()
	draw_string(font, Vector2(0.0, SIZE + 12.0), text, HORIZONTAL_ALIGNMENT_CENTER, SIZE, 12,
		Color(1, 1, 1, 0.85 if _active else 0.55))
