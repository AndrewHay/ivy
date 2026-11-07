extends GutTest

## Playground camera mirrors the main game's DebugCamera: Tab = mouse-look (off by
## default), click = glide pivot to ground point, wheel = zoom, R = reset.

const PlaygroundScene = preload("res://scenes/playground/grass_wind_playground.tscn")


func after_each() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _spawn() -> Node3D:
	var root: Node3D = PlaygroundScene.instantiate()
	add_child_autofree(root)
	await get_tree().process_frame
	return root


func _tab_press() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.pressed = true
	return ev


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _mouse_move(dx: float) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, 0.0)
	return ev


func _button(index: MouseButton, pos: Vector2 = Vector2.ZERO) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = true
	ev.position = pos
	return ev


func test_mouse_look_off_by_default_and_tab_toggles_it() -> void:
	var root := await _spawn()
	assert_false(root.get("_mouse_orbit"), "mouse-look is off by default (matches main game)")
	var yaw0: float = root.get("_orbit_yaw")
	root._unhandled_input(_mouse_move(50.0))
	assert_eq(root.get("_orbit_yaw"), yaw0, "mouse motion ignored while mouse-look is off")

	root._input(_tab_press())
	assert_true(root.get("_mouse_orbit"), "Tab turns mouse-look on")
	root._unhandled_input(_mouse_move(50.0))
	assert_ne(root.get("_orbit_yaw"), yaw0, "mouse motion rotates the camera while on")

	root._input(_tab_press())
	assert_false(root.get("_mouse_orbit"), "Tab again turns it off")
	var yaw_stopped: float = root.get("_orbit_yaw")
	root._unhandled_input(_mouse_move(50.0))
	assert_eq(root.get("_orbit_yaw"), yaw_stopped, "camera holds still when off")


func test_tab_echo_and_release_are_ignored() -> void:
	var root := await _spawn()
	var release := _tab_press()
	release.pressed = false
	root._input(release)
	var echo := _tab_press()
	echo.echo = true
	root._input(echo)
	assert_false(root.get("_mouse_orbit"), "only a fresh press toggles")


func test_wheel_zooms_multiplicatively_and_clamps() -> void:
	var root := await _spawn()
	var r0: float = root.get("_orbit_radius")
	root._unhandled_input(_button(MOUSE_BUTTON_WHEEL_UP))
	assert_almost_eq(float(root.get("_orbit_radius")), r0 * 0.9, 1e-4, "wheel up zooms in 0.9x")
	root._unhandled_input(_button(MOUSE_BUTTON_WHEEL_DOWN))
	assert_almost_eq(float(root.get("_orbit_radius")), r0, 1e-4, "wheel down undoes it")
	for _i in range(200):
		root._unhandled_input(_button(MOUSE_BUTTON_WHEEL_UP))
	assert_almost_eq(float(root.get("_orbit_radius")), 1.5, 1e-4, "zoom-in clamped")
	for _i in range(200):
		root._unhandled_input(_button(MOUSE_BUTTON_WHEEL_DOWN))
	assert_almost_eq(float(root.get("_orbit_radius")), 24.0, 1e-4, "zoom-out clamped")


func test_trackpad_pan_gesture_zooms() -> void:
	var root := await _spawn()
	var r0: float = root.get("_orbit_radius")
	var ev := InputEventPanGesture.new()
	ev.delta = Vector2(0.0, -1.0)  # two-finger scroll up == zoom in
	root._unhandled_input(ev)
	assert_lt(float(root.get("_orbit_radius")), r0)


func test_click_glides_pivot_to_ground_point_and_r_resets() -> void:
	var root := await _spawn()
	assert_eq(root.get("_pivot"), Vector3.ZERO)
	var size := root.get_viewport().get_visible_rect().size
	root._unhandled_input(_button(MOUSE_BUTTON_LEFT, Vector2(size.x * 0.75, size.y * 0.8)))
	assert_true(root.get("_gliding"), "click starts an origin glide")
	root._advance_glide(5.0)
	assert_false(root.get("_gliding"), "glide finishes")
	var pivot: Vector3 = root.get("_pivot")
	assert_ne(pivot, Vector3.ZERO, "pivot moved")
	assert_almost_eq(pivot.y, 0.0, 1e-3, "pivot lands on the ground plane")

	root._unhandled_input(_key(KEY_R))
	assert_eq(root.get("_pivot"), Vector3.ZERO, "R resets the pivot")


func test_click_ignored_while_mouse_look_on() -> void:
	var root := await _spawn()
	root._input(_tab_press())
	var size := root.get_viewport().get_visible_rect().size
	root._unhandled_input(_button(MOUSE_BUTTON_LEFT, Vector2(size.x * 0.75, size.y * 0.8)))
	assert_false(root.get("_gliding"), "no glide while mouse-look is captured")


func test_sky_click_does_not_move_pivot() -> void:
	var root := await _spawn()
	root._apply_camera_preset("eye")
	root._apply_orbit_camera()
	var hit: Vector3 = root._pick_ground_point(Vector2(10.0, 2.0))
	assert_false(hit.is_finite(), "ray above the horizon hits nothing")


func test_arrow_keys_rotate_in_three_degree_steps() -> void:
	var root := await _spawn()
	var yaw0: float = root.get("_orbit_yaw")
	root._unhandled_input(_key(KEY_RIGHT))
	assert_almost_eq(float(root.get("_orbit_yaw")) - yaw0, deg_to_rad(3.0), 1e-5)
