class_name SunCompass
extends Control

## A small top-down plan of the sky, drawn in a corner of the HUD (ivy-at5).
##
## The top of the disc is the way the camera is looking, so "the sun is on the right" means
## the right of the screen. N/E/S/W turn as the player orbits. A high sun sits near the middle
## and a low one at the rim; once it is below the horizon it is pinned to the rim, hollow and
## dim, under the caption "Night". The direction is the one the sky light uses, so it always
## agrees with where the shadows fall.
##
## The geometry is in static helpers so it can be tested without drawing anything.

const SIZE := 112.0
const _RADIUS := 38.0  ## Rim of the disc, from its centre. Letters sit just outside it.
const _MARKER_RADIUS := 7.0
const _CARDINALS := {
	"N": Vector2(0.0, -1.0),  # world (x, z): north is -Z
	"E": Vector2(1.0, 0.0),
	"S": Vector2(0.0, 1.0),
	"W": Vector2(-1.0, 0.0),
}

var _sun_dir: Vector3 = Vector3.UP
var _yaw: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE + 18.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `sun_dir` points from the ground toward the sun; `camera_yaw` is DebugCamera's yaw.
func set_sun(sun_dir: Vector3, camera_yaw: float) -> void:
	_sun_dir = sun_dir
	_yaw = camera_yaw
	queue_redraw()


## Where the sun marker is, relative to the centre of the disc.
func marker_offset() -> Vector2:
	return sun_offset(_sun_dir, _yaw, _RADIUS)


func caption_text() -> String:
	return caption(_sun_dir)


func _draw() -> void:
	var centre := Vector2(SIZE * 0.5, SIZE * 0.5)
	var font := ThemeDB.fallback_font
	draw_circle(centre, _RADIUS + 14.0, Color(0.05, 0.07, 0.09, 0.55))
	draw_arc(centre, _RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 1.5)
	for letter in _CARDINALS:
		var p := centre + cardinal_offset(letter, _yaw, _RADIUS + 8.0)
		var colour := Color(1, 1, 1, 0.9) if letter == "N" else Color(1, 1, 1, 0.6)
		draw_string(font, p + Vector2(-5.0, 5.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, colour)
	var m := centre + marker_offset()
	if is_up(_sun_dir):
		draw_circle(m, _MARKER_RADIUS + 2.0, Color(1.0, 0.85, 0.35, 0.35))
		draw_circle(m, _MARKER_RADIUS, Color(1.0, 0.85, 0.3))
		draw_arc(m, _MARKER_RADIUS, 0.0, TAU, 20, Color(0.55, 0.38, 0.05), 1.5)
	else:
		draw_arc(m, _MARKER_RADIUS, 0.0, TAU, 20, Color(0.6, 0.68, 0.85, 0.8), 2.0)
	var text := caption_text()
	draw_string(font, Vector2(0.0, SIZE + 12.0), text, HORIZONTAL_ALIGNMENT_CENTER, SIZE, 13,
		Color(1, 1, 1, 0.85))


## ─── Pure helpers — static, testable headlessly ──────────────────────────────

## A horizontal world direction (x, z) as a unit vector on the screen (x right, y down) for a
## camera at `yaw` (DebugCamera: yaw = atan2(offset.x, offset.z), so yaw 0 is a camera on the
## south side looking north).
static func _to_screen(horizontal: Vector2, yaw: float) -> Vector2:
	if horizontal.length_squared() < 1e-8:
		return Vector2.ZERO
	var h := horizontal.normalized()
	var right := Vector2(cos(yaw), -sin(yaw))
	var ahead := Vector2(-sin(yaw), -cos(yaw))
	return Vector2(h.dot(right), -h.dot(ahead))


static func sun_offset(sun_dir: Vector3, yaw: float, radius: float) -> Vector2:
	var elevation := asin(clampf(sun_dir.y, -1.0, 1.0))
	var height := clampf(elevation / (PI * 0.5), 0.0, 1.0)  # 0 on the horizon, 1 overhead
	return _to_screen(Vector2(sun_dir.x, sun_dir.z), yaw) * radius * (1.0 - height)


static func cardinal_offset(letter: String, yaw: float, radius: float) -> Vector2:
	return _to_screen(_CARDINALS[letter], yaw) * radius


static func is_up(sun_dir: Vector3) -> bool:
	return sun_dir.y > 0.0


static func caption(sun_dir: Vector3) -> String:
	return "Sun" if is_up(sun_dir) else "Night"
