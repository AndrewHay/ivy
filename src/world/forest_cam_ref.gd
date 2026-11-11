class_name ForestCamRef
extends RefCounted

const ForestParams = preload("res://src/playground/forest_params.gd")

## CamSun framing for generated village forest placement (shared production + playground).
const SQUARE_SCENARIO_PIVOT := Vector3(-7.0, 1.56, 0.0)
const CANONICAL_AIM_Y := 2.0
const CAMSUN_LOCAL := Vector3(0.0, 2.0, 8.0)
const GENERATED_RIG_SCALE := 1.35
const FOV_DEG := 75.0


static func backdrop_origin(orbit_pivot: Vector3) -> Vector3:
	return Vector3(orbit_pivot.x, 0.0, orbit_pivot.z)


static func rig_base_position(orbit_pivot: Vector3) -> Vector3:
	return Vector3(orbit_pivot.x, orbit_pivot.y - CANONICAL_AIM_Y, orbit_pivot.z)


static func camsun_eye(orbit_pivot: Vector3, rig_scale: float) -> Vector3:
	return rig_base_position(orbit_pivot) + CAMSUN_LOCAL * rig_scale


static func camsun_forward() -> Vector3:
	return Vector3(0.0, 0.0, -1.0)


static func aim_point(orbit_pivot: Vector3) -> Vector3:
	return orbit_pivot


static func resolve_orbit_pivot(params: ForestParams) -> Vector3:
	if params != null and params.cam_orbit_pivot.is_finite():
		return params.cam_orbit_pivot
	return SQUARE_SCENARIO_PIVOT


static func resolve_rig_scale(params: ForestParams) -> float:
	if params != null and params.cam_rig_scale > 0.0:
		return params.cam_rig_scale
	return GENERATED_RIG_SCALE
