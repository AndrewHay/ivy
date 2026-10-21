## ivy-at5 — the sun compass: where is the sun, as the player sees the building?
##
## The disc is a top-down plan with the camera's look direction at the top, so "the sun is on the
## right" means the right of the screen. A high sun sits near the middle and a low one at the rim.
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SunCompassScript = preload("res://src/ui/sun_compass.gd")
const R := 50.0

## Camera at yaw 0 stands on the south side looking north (DebugCamera: yaw = atan2(offset.x, offset.z)).
const SOUTH_SIDE := 0.0


func _sun(azimuth_deg: float, elevation_deg: float) -> Vector3:
	return Conv.sun_direction(azimuth_deg, elevation_deg)


# ── geometry ───────────────────────────────────────────────────────────────

func test_sun_behind_the_camera_is_at_the_bottom() -> void:
	# Sun due south, camera on the south side looking north: the sun is at the camera's back.
	var p := SunCompassScript.sun_offset(_sun(180.0, 10.0), SOUTH_SIDE, R)
	assert_almost_eq(p.x, 0.0, 0.5)
	assert_gt(p.y, 0.0, "screen y grows downward, so behind the camera is positive y")


func test_sun_in_front_of_the_camera_is_at_the_top() -> void:
	var p := SunCompassScript.sun_offset(_sun(0.0, 10.0), SOUTH_SIDE, R)
	assert_almost_eq(p.x, 0.0, 0.5)
	assert_lt(p.y, 0.0)


func test_sun_to_the_east_is_on_the_right_when_looking_north() -> void:
	var p := SunCompassScript.sun_offset(_sun(90.0, 10.0), SOUTH_SIDE, R)
	assert_gt(p.x, 0.0)
	assert_almost_eq(p.y, 0.0, 0.5)


func test_orbiting_the_camera_turns_the_compass() -> void:
	# Camera moved round to the east side (yaw 90 degrees) looking west: now east is behind it.
	var p := SunCompassScript.sun_offset(_sun(90.0, 10.0), deg_to_rad(90.0), R)
	assert_almost_eq(p.x, 0.0, 0.5)
	assert_gt(p.y, 0.0)


func test_high_sun_is_near_the_middle_and_low_sun_at_the_rim() -> void:
	var high := SunCompassScript.sun_offset(_sun(180.0, 85.0), SOUTH_SIDE, R)
	var low := SunCompassScript.sun_offset(_sun(180.0, 2.0), SOUTH_SIDE, R)
	assert_lt(high.length(), 0.15 * R, "a sun almost overhead sits near the centre")
	assert_gt(low.length(), 0.9 * R, "a sun on the horizon sits at the rim")


func test_overhead_sun_does_not_blow_up() -> void:
	var p := SunCompassScript.sun_offset(Vector3.UP, 0.7, R)
	assert_true(is_finite(p.x) and is_finite(p.y))
	assert_almost_eq(p.length(), 0.0, 0.01)


func test_sun_below_the_horizon_is_pinned_to_the_rim_and_reported_as_night() -> void:
	var down := _sun(180.0, -20.0)
	assert_false(SunCompassScript.is_up(down))
	assert_true(SunCompassScript.is_up(_sun(180.0, 20.0)))
	assert_almost_eq(SunCompassScript.sun_offset(down, SOUTH_SIDE, R).length(), R, 0.5)


func test_cardinal_letters_follow_the_camera() -> void:
	var north := SunCompassScript.cardinal_offset("N", SOUTH_SIDE, R)
	assert_lt(north.y, 0.0, "north is ahead when the camera looks north")
	var east := SunCompassScript.cardinal_offset("E", SOUTH_SIDE, R)
	assert_gt(east.x, 0.0)
	# Camera on the east side looking west: west is ahead (top), north is on the right.
	var west := SunCompassScript.cardinal_offset("W", deg_to_rad(90.0), R)
	assert_lt(west.y, 0.0)
	var north_right := SunCompassScript.cardinal_offset("N", deg_to_rad(90.0), R)
	assert_gt(north_right.x, 0.0)
	for letter in ["N", "E", "S", "W"]:
		assert_almost_eq(SunCompassScript.cardinal_offset(letter, 1.1, R).length(), R, 0.01)


func test_caption_is_plain_language() -> void:
	assert_eq(SunCompassScript.caption(_sun(180.0, 30.0)), "Sun")
	assert_eq(SunCompassScript.caption(_sun(180.0, -10.0)), "Night")


# ── in the real HUD ────────────────────────────────────────────────────────

func _boot() -> Node:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	main.get_node("UI/BuildingPicker")._on_entry_pressed("cylinder")
	for _i in range(900):
		if main._hud != null:
			break
		await get_tree().process_frame
	await get_tree().process_frame
	return main


func test_hud_shows_the_compass_in_the_bottom_left_corner() -> void:
	var main := await _boot()
	var compass: Control = main._hud.get_sun_compass()
	assert_not_null(compass, "free-plant HUD must have a sun compass")
	var viewport := main.get_viewport().get_visible_rect().size
	var rect := Rect2(compass.global_position, compass.size)
	assert_gt(compass.size.x, 60.0, "compass must have a real size")
	assert_true(Rect2(Vector2.ZERO, viewport).encloses(rect), "compass must be fully on screen: %s" % rect)
	assert_lt(rect.position.x, viewport.x * 0.3, "bottom-left, not the middle")
	assert_gt(rect.end.y, viewport.y * 0.7)
	assert_eq(compass.mouse_filter, Control.MOUSE_FILTER_IGNORE, "must never block clicks to the planting tool")


func test_hud_compass_tracks_the_sun_and_the_camera() -> void:
	var main := await _boot()
	var compass: Control = main._hud.get_sun_compass()
	var clock: SimClock = main._sim.get_clock()
	main._hud.refresh(clock, main._world.get_sky_sun(), 0.0)
	var a: Vector2 = compass.marker_offset()
	main._hud.refresh(clock, main._world.get_sky_sun(), deg_to_rad(90.0))
	var b: Vector2 = compass.marker_offset()
	assert_gt(a.distance_to(b), 1.0, "orbiting the camera must move the sun marker round the disc")
	assert_almost_eq(a.length(), b.length(), 0.5, "…without changing how high the sun is")
