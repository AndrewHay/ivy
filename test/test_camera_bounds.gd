extends GutTest

const CameraBounds = preload("res://src/world/camera_bounds.gd")
const DebugCamera = preload("res://src/world/debug_camera.gd")


func test_clamp_eye_inside_unchanged() -> void:
	var c := Vector2(0.0, -18.0)
	var eye := Vector3(5.0, 8.0, -20.0)
	var out := CameraBounds.clamp_eye_xz(eye, c, 56.0, 2.0)
	assert_eq(out, eye)


func test_clamp_eye_outside_radial() -> void:
	var c := Vector2(0.0, 0.0)
	var eye := Vector3(100.0, 5.0, 0.0)
	var out := CameraBounds.clamp_eye_xz(eye, c, 10.0, 2.0)
	assert_almost_eq(Vector2(out.x, out.z).length(), 8.0, 1e-4)
	assert_almost_eq(out.y, 5.0, 1e-6)


func test_clamp_eye_degenerate_radius_zero() -> void:
	var out := CameraBounds.clamp_eye_xz(Vector3(5, 1, 5), Vector2.ZERO, 0.0, 0.0)
	assert_eq(out, Vector3(0, 1, 0))


func test_constrain_orbit_shrinks_radius_when_eye_outside() -> void:
	var centre := Vector2(-7.0, -18.0)
	var pivot := Vector3(-7.0, 1.5, 0.0)
	var yaw := 0.0
	var pitch := deg_to_rad(12.0)
	var radius := 80.0
	var r := CameraBounds.constrain_orbit(
		pivot, yaw, pitch, radius, centre, 56.0, 2.0, 0.75, 120.0)
	var eye := DebugCamera.solve(r["pivot"], r["yaw"], r["pitch"], r["radius"]).origin
	assert_lte(Vector2(eye.x, eye.z).distance_to(centre), 54.0 + 0.05,
		"eye must stay inside lawn disc")
	assert_lt(r["radius"], radius, "radius should shrink, not snap eye")


func test_constrain_pivot_clamped_to_disc() -> void:
	var centre := Vector2(0.0, 0.0)
	var pivot := Vector3(80.0, 2.0, 0.0)
	var r := CameraBounds.constrain_orbit(
		pivot, 0.0, 0.1, 5.0, centre, 20.0, 2.0, 1.0, 30.0)
	assert_lte(Vector2(r["pivot"].x, r["pivot"].z).length(), 18.0)
