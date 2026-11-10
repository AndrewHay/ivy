class_name HeroFog
extends RefCounted

## Depth fog in Godot is measured from the camera. HERO mode shifts begin/end each frame
## by the anchor's depth along the camera forward axis so haze matches distance from a
## fixed hero anchor instead. Exact on the view centre ray; approximate at screen edges
## (peripheral points share one offset).

enum CentreMode { CAMERA, HERO }

const DEFAULT_MODE := CentreMode.HERO


static func fog_amount(distance: float, begin: float, end: float) -> float:
	if end <= begin:
		return 1.0 if distance >= begin else 0.0
	return clampf((distance - begin) / (end - begin), 0.0, 1.0)


static func view_ray_depth_offset(camera: Transform3D, anchor: Vector3) -> float:
	var fwd := -camera.basis.z.normalized()
	return fwd.dot(anchor - camera.origin)


static func apply_depth_fog_to_environment(
		env: Environment,
		camera: Transform3D,
		anchor: Vector3,
		begin: float,
		end: float,
		mode: CentreMode) -> void:
	if mode == CentreMode.CAMERA:
		env.fog_depth_begin = begin
		env.fog_depth_end = end
		return
	var off := view_ray_depth_offset(camera, anchor)
	env.fog_depth_begin = begin + off
	env.fog_depth_end = end + off


static func fog_amount_at_world_point(
		camera_pos: Vector3,
		point: Vector3,
		anchor: Vector3,
		begin: float,
		end: float,
		mode: CentreMode) -> float:
	match mode:
		CentreMode.CAMERA:
			return fog_amount(camera_pos.distance_to(point), begin, end)
		_:
			return fog_amount(anchor.distance_to(point), begin, end)
