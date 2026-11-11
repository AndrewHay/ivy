class_name CameraBounds
extends RefCounted

## Generated village lawn: camera eye XZ must stay inside [lawn_radius − margin].
const LAWN_EYE_MARGIN_M := 2.0
## Top/overhead views from inside the lawn; does not restrict XZ.
const MAX_EYE_HEIGHT_M := 120.0


static func clamp_eye_xz(
		eye: Vector3, centre: Vector2, radius: float, margin: float) -> Vector3:
	var allowed := maxf(radius - margin, 0.0)
	var xz := Vector2(eye.x, eye.z)
	var delta := xz - centre
	var dist := delta.length()
	if dist <= allowed or dist < 1e-6:
		return Vector3(eye.x, clampf(eye.y, 0.05, MAX_EYE_HEIGHT_M), eye.z)
	var dir := delta / dist
	var clamped := centre + dir * allowed
	return Vector3(clamped.x, clampf(eye.y, 0.05, MAX_EYE_HEIGHT_M), clamped.y)


static func eye_inside(
		eye: Vector3, centre: Vector2, radius: float, margin: float) -> bool:
	return Vector2(eye.x, eye.z).distance_to(centre) <= maxf(radius - margin, 0.0) + 1e-4


static func _orbit_offset(yaw: float, pitch: float, radius: float) -> Vector3:
	return Vector3(
		radius * sin(yaw) * cos(pitch),
		radius * sin(pitch),
		radius * cos(yaw) * cos(pitch))


## Keeps pivot XZ inside the lawn and reduces orbit radius until the eye is inside (smooth zoom cap).
static func clamp_pivot_xz_for_orbit(
		pivot: Vector3,
		centre: Vector2,
		lawn_radius: float,
		margin: float,
		orbit_radius: float,
		pitch: float) -> Vector3:
	var allowed_eye := maxf(lawn_radius - margin, 0.0)
	var horiz := orbit_radius * absf(cos(pitch))
	var pivot_allowed := maxf(allowed_eye - horiz, 0.0)
	var xz := Vector2(pivot.x, pivot.z)
	var delta := xz - centre
	var dist := delta.length()
	if dist <= pivot_allowed or dist < 1e-6 or pivot_allowed <= 0.0:
		return Vector3(pivot.x, pivot.y, pivot.z)
	var dir := delta / dist
	var clamped := centre + dir * pivot_allowed
	return Vector3(clamped.x, pivot.y, clamped.y)


static func constrain_orbit(
		pivot: Vector3,
		yaw: float,
		pitch: float,
		radius: float,
		centre: Vector2,
		lawn_radius: float,
		margin: float,
		zoom_min: float,
		zoom_max: float) -> Dictionary:
	var p := clamp_pivot_xz_for_orbit(pivot, centre, lawn_radius, margin, radius, pitch)
	var r := clampf(radius, zoom_min, zoom_max)
	pitch = DebugCamera.clamp_pitch(pitch, r, p.y)
	for _attempt in range(80):
		var eye := p + _orbit_offset(yaw, pitch, r)
		eye.y = clampf(eye.y, 0.05, MAX_EYE_HEIGHT_M)
		if eye_inside(eye, centre, lawn_radius, margin):
			break
		r = maxf(zoom_min, r * 0.92)
		pitch = DebugCamera.clamp_pitch(pitch, r, p.y)
	r = clampf(r, zoom_min, zoom_max)
	pitch = DebugCamera.clamp_pitch(pitch, r, p.y)
	var eye_final := p + _orbit_offset(yaw, pitch, r)
	eye_final = clamp_eye_xz(eye_final, centre, lawn_radius, margin)
	if not eye_inside(eye_final, centre, lawn_radius, margin) and r > zoom_min + 1e-4:
		r = zoom_min
		pitch = DebugCamera.clamp_pitch(pitch, r, p.y)
	return {
		"pivot": p,
		"yaw": yaw,
		"pitch": pitch,
		"radius": r,
	}


static func clamp_free_camera_eye(
		eye: Vector3, centre: Vector2, lawn_radius: float, margin: float = LAWN_EYE_MARGIN_M) -> Vector3:
	return clamp_eye_xz(eye, centre, lawn_radius, margin)
