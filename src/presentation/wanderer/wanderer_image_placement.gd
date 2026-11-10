class_name WandererImagePlacement
extends RefCounted

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")


static func compute(door_exterior: Vector2, n_in: Vector2, params: WandererParams, aspect: float) -> Dictionary:
	var n := n_in
	if n.length_squared() < 1e-8:
		n = Vector2(0.0, 1.0)
	else:
		n = n.normalized()
	var s := params.present_standoff()
	var P := door_exterior + n * s
	var H := params.structure_height_m * params.image_height_factor
	var W := H * aspect
	if W > params.image_max_width_m:
		var shrink := params.image_max_width_m / W
		W = params.image_max_width_m
		H *= shrink
	var left := Vector2(n.y, -n.x)
	var corner_y := params.figure_height_m + params.image_corner_lift_m
	var corner := Vector3(P.x, corner_y, P.y)
	var left3 := Vector3(left.x, 0.0, left.y)
	var centre := corner + left3 * (W * 0.5) + Vector3(0.0, H * 0.5, 0.0)
	var yaw := atan2(n.x, n.y)
	return {
		"size": Vector2(W, H),
		"normal": n,
		"left": left,
		"yaw": yaw,
		"centre": centre,
		"corner": corner,
		"figure_xz": P,
	}


static func quad_front_normal_xz(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


static func bottom_corners_world(placement: Dictionary) -> Array:
	var centre: Vector3 = placement["centre"]
	var sz: Vector2 = placement["size"]
	var yaw: float = placement["yaw"]
	var xf := Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), centre)
	var hw := sz.x * 0.5
	var hh := sz.y * 0.5
	return [
		xf * Vector3(-hw, -hh, 0.0),
		xf * Vector3(hw, -hh, 0.0),
	]
