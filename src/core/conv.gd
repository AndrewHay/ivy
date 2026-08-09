class_name Conv
extends RefCounted

const UP := Vector3(0.0, 1.0, 0.0)
const GRAVITY := Vector3(0.0, -1.0, 0.0)
const NORTH := Vector3(0.0, 0.0, -1.0)
const EAST := Vector3(1.0, 0.0, 0.0)
const SOUTH := Vector3(0.0, 0.0, 1.0)
const WEST := Vector3(-1.0, 0.0, 0.0)

const TANGENT_DEGENERATE_THRESHOLD := 0.05


static func sun_direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var alpha := deg_to_rad(elevation_deg)
	var cos_a := cos(alpha)
	return Vector3(
		cos_a * sin(az),
		sin(alpha),
		-cos_a * cos(az)
	).normalized()


static func solar_noon_direction(elevation_deg: float) -> Vector3:
	return sun_direction(180.0, elevation_deg)


static func tangent_basis(normal: Vector3) -> Basis:
	var n := normal.normalized()
	var ref := UP
	var u_raw := n.cross(ref)
	if u_raw.length() < TANGENT_DEGENERATE_THRESHOLD:
		ref = Vector3(0.0, 0.0, 1.0)
		u_raw = n.cross(ref)
	var u := u_raw.normalized()
	var v := n.cross(u).normalized()
	return Basis(u, v, n)


static func project_to_tangent_plane(vec: Vector3, normal: Vector3) -> Vector3:
	var n := normal.normalized()
	return vec - n * vec.dot(n)
