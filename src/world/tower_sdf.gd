class_name TowerSdf
extends RefCounted

var spec: TowerSpec


func _init(s: TowerSpec) -> void:
	spec = s


func signed_distance(p: Vector3) -> float:
	var shell: float = _shell_distance(p)
	var lip: float = _lip_distance(p)
	# The solid is the union of shell and lip, hence min(). Openings are then
	# subtracted, which is max() against the negated opening distance.
	var phi: float = min(shell, lip)
	phi = max(phi, -_door_box_distance(p))
	phi = max(phi, -_window_box_distance(p))
	return phi


## Tight world bounds of the solid. Callers grow this by the shell halfwidth to get
## the region the environment field must cover.
func bounds() -> AABB:
	var r := spec.lip_radius()
	return AABB(
		Vector3(-r, 0.0, -r),
		Vector3(2.0 * r, spec.height + spec.lip_thickness, 2.0 * r)
	)


func gradient(p: Vector3) -> Vector3:
	const EPS := 0.001
	return Vector3(
		signed_distance(p + Vector3(EPS, 0, 0)) - signed_distance(p - Vector3(EPS, 0, 0)),
		signed_distance(p + Vector3(0, EPS, 0)) - signed_distance(p - Vector3(0, EPS, 0)),
		signed_distance(p + Vector3(0, 0, EPS)) - signed_distance(p - Vector3(0, 0, EPS))
	) / (2.0 * EPS)


func gradient_normalized(p: Vector3) -> Vector3:
	var g := gradient(p)
	if g.length_squared() < 1e-10:
		return Conv.UP
	return g.normalized()


func _shell_distance(p: Vector3) -> float:
	var r := Vector2(p.x, p.z).length()
	var d_radial := r - spec.radius_outer
	var d_bottom := -p.y
	var d_top := p.y - spec.height
	if p.y < 0.0:
		return max(d_radial, d_bottom)
	if p.y > spec.height:
		return max(d_radial, d_top)
	return d_radial


func _lip_distance(p: Vector3) -> float:
	# +INF is the identity for the union below; the lip volume starts at the top.
	if p.y < spec.height:
		return INF
	var r := Vector2(p.x, p.z).length()
	var d_radial := r - spec.lip_radius()
	var d_bottom := spec.height - p.y
	var d_top := p.y - (spec.height + spec.lip_thickness)
	return max(d_radial, max(d_bottom, d_top))


func _door_box_distance(p: Vector3) -> float:
	return _opening_box_distance(
		p, spec.door_azimuth, spec.door_width, 0.0, spec.door_height
	)


func _window_box_distance(p: Vector3) -> float:
	return _opening_box_distance(
		p, spec.window_azimuth, spec.window_size,
		spec.window_sill, spec.window_sill + spec.window_size
	)


## Signed distance to the box that carves an opening in the wall. Negative inside.
##
## The box must be bounded along the wall normal as well as tangentially and
## vertically. An unbounded half-space here reads as "inside the opening" for every
## point on the far side of the tower, which carves a slab straight through the
## building and makes the opposite wall report as empty space.
func _opening_box_distance(
	p: Vector3, azimuth_deg: float, width: float, y0: float, y1: float
) -> float:
	var az := deg_to_rad(azimuth_deg)
	var normal := Vector3(sin(az), 0.0, -cos(az))
	var tangent := Vector3(cos(az), 0.0, sin(az))
	# Span the full wall thickness, overshooting outward so the cut is clean.
	var n_lo := spec.radius_inner()
	var n_hi := spec.radius_outer + 0.1
	var center_n := (n_lo + n_hi) * 0.5
	var half_n := (n_hi - n_lo) * 0.5
	var half_w := width * 0.5
	var center_y := (y0 + y1) * 0.5
	var half_h := (y1 - y0) * 0.5
	var d_n := absf(p.dot(normal) - center_n) - half_n
	var d_t := absf(p.dot(tangent)) - half_w
	var d_y := absf(p.y - center_y) - half_h
	return max(d_n, max(d_t, d_y))
