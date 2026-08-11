## AR-DBGCAM-6: tests for DebugCamera pure helpers and the script_driven gate.
##
## Three tests exactly as specified:
##   Test 1 — clamp_radius / clamp_pitch bound enforcement
##   Test 2 — solve() corners: y > 0 and axis distance > radius_outer
##   Test 3 — script_driven = true: synthetic input leaves current false and transform unchanged
##
## Plus, added after the zoom shipped broken on macOS (W-058): multiplicative zoom, the pan
## gesture branch trackpads actually need, and key auto-repeat.
##
## What is NOT tested (AR-DBGCAM-6 explicitly forbids it): "simulated drag moves the camera".
## A handler-stubbed implementation would still pass that test. The interactive feel (orbit
## direction, zoom direction, first-activation jump) requires a human pressing Play.
extends GutTest

const DebugCameraScript = preload("res://src/world/debug_camera.gd")


## AR-DBGCAM-6 Test 1 — out-of-range values must clamp into [3.0, 12.0] and [-5°, +85°].
## Catches someone widening min_radius, max_radius, or the pitch bounds so the camera
## can pass through the wall, drop below ground, or reach the look_at pole singularity.
func test_clamp_radius_enforces_min_and_max() -> void:
	var spec := TowerSpec.new()  # radius_outer=2.0, height=3.5 → min=3.0, max=12.0
	assert_almost_eq(DebugCameraScript.clamp_radius(-999.0, spec), 3.0, 1e-6,
		"radius far below min must clamp to 3.0 m")
	assert_almost_eq(DebugCameraScript.clamp_radius(999.0, spec), 12.0, 1e-6,
		"radius far above max must clamp to 12.0 m")
	assert_almost_eq(DebugCameraScript.clamp_radius(5.0, spec), 5.0, 1e-6,
		"in-range radius must pass through unchanged")


## AR-DBGCAM-6 Test 1 (continued) — pitch clamp.
func test_clamp_pitch_enforces_min_and_max() -> void:
	assert_almost_eq(DebugCameraScript.clamp_pitch(deg_to_rad(-90.0)), deg_to_rad(-5.0), 1e-5,
		"pitch below -5° must clamp to -5°")
	assert_almost_eq(DebugCameraScript.clamp_pitch(deg_to_rad(90.0)), deg_to_rad(85.0), 1e-5,
		"pitch above +85° must clamp to +85°")
	assert_almost_eq(DebugCameraScript.clamp_pitch(deg_to_rad(30.0)), deg_to_rad(30.0), 1e-5,
		"in-range pitch must pass through unchanged")


## AR-DBGCAM-6 Test 2 — at all four corners of the clamped bounds box, solve() places
## the camera above ground (y > 0). When the camera is within the tower's height band
## (y ≤ spec.height), it must also be outside the wall (axis dist > radius_outer). At
## steep pitches the camera rises above the tower entirely, so the wall check is restricted
## to corners where the height band is intersected — the regression we care about (reducing
## min_radius below the 1 m standoff) shows up there.
## Also catches clamp widening that drops the camera underground or reaches the +90° pole.
func test_solve_corners_are_above_ground_and_outside_wall() -> void:
	var spec := TowerSpec.new()  # radius_outer=2.0, height=3.5
	var pivot := Vector3(0.0, spec.height * 0.5, 0.0)
	var r_min: float = DebugCameraScript.clamp_radius(0.0, spec)
	var r_max: float = DebugCameraScript.clamp_radius(9999.0, spec)
	var p_min: float = DebugCameraScript.clamp_pitch(deg_to_rad(-90.0))
	var p_max: float = DebugCameraScript.clamp_pitch(deg_to_rad(90.0))

	var corners: Array = [
		[r_min, p_min],
		[r_min, p_max],
		[r_max, p_min],
		[r_max, p_max],
	]
	for corner in corners:
		var r: float = corner[0]
		var p: float = corner[1]
		var t: Transform3D = DebugCameraScript.solve(pivot, 0.0, p, r)
		assert_gt(t.origin.y, 0.0,
			"camera must be above ground at r=%.1f p_deg=%.1f (y=%.4f)" % [r, rad_to_deg(p), t.origin.y])
		# The tower wall exists only within [0, height]. Above that height the camera can be
		# closer to the axis than radius_outer without being inside the wall material.
		if t.origin.y <= spec.height:
			var axis_dist := Vector2(t.origin.x, t.origin.z).length()
			assert_gt(axis_dist, spec.radius_outer,
				"camera must be outside wall at r=%.1f p_deg=%.1f (axis_dist=%.4f)" % [r, rad_to_deg(p), axis_dist])


## Zoom is multiplicative, so a notch must scale the radius rather than subtract from it —
## that is what keeps the feel even at 3 m and at 12 m. Catches a regression to additive
## stepping, and confirms the result is still clamped.
func test_zoom_is_multiplicative_and_clamped() -> void:
	var spec := TowerSpec.new()
	assert_almost_eq(DebugCameraScript.zoom(10.0, 1.0, spec), 9.0, 1e-6,
		"one notch in must scale radius by 0.9")
	assert_almost_eq(DebugCameraScript.zoom(9.0, -1.0, spec), 10.0, 1e-6,
		"one notch out must invert one notch in")
	# Equal notch counts must produce equal *ratios* at different radii. An additive
	# implementation would produce equal differences instead and fail here.
	var near_ratio: float = DebugCameraScript.zoom(4.0, 1.0, spec) / 4.0
	var far_ratio: float = DebugCameraScript.zoom(11.0, 1.0, spec) / 11.0
	assert_almost_eq(near_ratio, far_ratio, 1e-6,
		"a notch must scale by the same ratio near and far, not by a fixed distance")
	assert_almost_eq(DebugCameraScript.zoom(3.2, 40.0, spec), 3.0, 1e-6,
		"zooming far in must clamp at the wall standoff")
	assert_almost_eq(DebugCameraScript.zoom(11.0, -40.0, spec), 12.0, 1e-6,
		"zooming far out must clamp at max radius")


## macOS trackpads emit InputEventPanGesture and never a wheel button, so a handler that only
## checks InputEventMouseButton silently does nothing on a MacBook — which is exactly how the
## zoom shipped broken. Asserts the pan branch exists and moves the camera. This is not the
## forbidden "simulated drag" test: it would fail, not pass, with the branch removed.
func test_pan_gesture_zooms_because_macos_sends_no_wheel_events() -> void:
	var sentinel := Camera3D.new()
	sentinel.current = true
	add_child(sentinel)

	var cam := DebugCameraScript.new()
	cam.spec = TowerSpec.new()
	add_child(cam)
	var before: float = cam._radius

	var ev := InputEventPanGesture.new()
	ev.delta = Vector2(0.0, -2.0)  # negative y = zoom in, per _NOTCHES_PER_PAN_UNIT sign
	cam._unhandled_input(ev)

	assert_lt(cam._radius, before,
		"a pan gesture must change the orbit radius; macOS sends no wheel events at all")


## Holding a zoom key must keep zooming, which relies on accepting auto-repeat (echo) events.
## Catches an `if not event.echo: return` style guard being added, which would make the keys
## feel dead when held.
func test_key_zoom_accepts_auto_repeat_so_holding_keeps_zooming() -> void:
	var sentinel := Camera3D.new()
	sentinel.current = true
	add_child(sentinel)

	var cam := DebugCameraScript.new()
	cam.spec = TowerSpec.new()
	add_child(cam)

	var ev := InputEventKey.new()
	ev.keycode = KEY_UP
	ev.pressed = true
	ev.echo = true

	var before: float = cam._radius
	cam._unhandled_input(ev)
	var after_one: float = cam._radius
	assert_lt(after_one, before, "an echoed zoom-in key must still zoom")

	cam._unhandled_input(ev)
	assert_lt(cam._radius, after_one, "each repeat must zoom further, not saturate")


## AR-DBGCAM-6 Test 3 — the AS-4 determinism guard.
## With script_driven = true, delivering a synthetic mouse event must NOT change current
## or the transform. Catches removal of the script_driven gate inside _unhandled_input —
## the one regression that would allow automated runs to capture the debug view.
func test_script_driven_blocks_current_and_transform_on_synthetic_input() -> void:
	# A sentinel Camera3D with current=true prevents the DebugCamera from auto-activating
	# when it enters the (otherwise camera-free) GUT test viewport. Without the sentinel,
	# Godot makes the first Camera3D in a viewport current regardless of its authored value.
	var sentinel := Camera3D.new()
	sentinel.current = true
	add_child(sentinel)

	var cam := DebugCameraScript.new()
	cam.spec = TowerSpec.new()
	# Must be set before add_child so _ready() sees it and disables the input path.
	cam.script_driven = true
	add_child(cam)

	assert_false(cam.current,
		"DebugCamera must start with current = false (authored default, AR-DBGCAM-2)")
	var initial_xform := cam.global_transform

	# Deliver a synthetic wheel event directly, bypassing the engine event system.
	# The in-function script_driven guard must intercept this call before any writes.
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	cam._unhandled_input(ev)

	assert_false(cam.current,
		"current must remain false after synthetic input when script_driven = true (AR-DBGCAM-5)")
	assert_eq(cam.global_transform, initial_xform,
		"transform must be unchanged after synthetic input when script_driven = true (AR-DBGCAM-5)")
