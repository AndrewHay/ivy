class_name HeroFog
extends RefCounted

const WorldFogParams = preload("res://src/world/world_fog_params.gd")

## Fog models (ivy-jnee):
## - CAMERA_DEPTH: legacy depth fog from camera (playground compare only).
## - HERO_SHIFTED_DEPTH: depth begin/end shifted each frame by camera→hero on view axis (previous production).
## - WORLD_AROUND_HERO: volumetric density in world XZ from hero; integrated along view in engine/tests.

enum FogModel {
	CAMERA_DEPTH,
	HERO_SHIFTED_DEPTH,
	WORLD_AROUND_HERO,
}

enum CentreMode { CAMERA, HERO } ## Legacy alias for shifted depth modes.

const DEFAULT_MODEL := FogModel.WORLD_AROUND_HERO
const DEFAULT_MODE := CentreMode.HERO ## Maps to HERO_SHIFTED_DEPTH for old call sites.


## Volumetric WORLD_AROUND_HERO needs Forward+; Compatibility falls back to hero-shifted depth.
static func effective_fog_model(
		requested: FogModel, rendering_method: String = "") -> FogModel:
	if requested != FogModel.WORLD_AROUND_HERO:
		return requested
	var method := rendering_method
	if method.is_empty():
		method = RenderingServer.get_current_rendering_method()
	if method != "forward_plus":
		return FogModel.HERO_SHIFTED_DEPTH
	return FogModel.WORLD_AROUND_HERO


static func fog_model_from_centre_mode(mode: CentreMode) -> FogModel:
	return FogModel.HERO_SHIFTED_DEPTH if mode == CentreMode.HERO else FogModel.CAMERA_DEPTH


static func fog_amount(distance: float, begin: float, end: float) -> float:
	if end <= begin:
		return 1.0 if distance >= begin else 0.0
	return clampf((distance - begin) / (end - begin), 0.0, 1.0)


static func world_density_at_xz(point: Vector3, anchor: Vector3, params: WorldFogParams) -> float:
	var d := Vector2(point.x - anchor.x, point.z - anchor.z).length()
	return world_density_at_distance(d, params)


static func world_density_at_distance(dist_from_hero: float, params: WorldFogParams) -> float:
	if params == null:
		return 0.0
	if dist_from_hero <= params.clear_radius_m:
		return 0.0
	var pad := maxf(params.clear_onset_pad_m, 8.0)
	var onset := _falloff01(
		dist_from_hero, params.clear_radius_m, params.clear_radius_m + pad,
		WorldFogParams.Falloff.SMOOTH)
	if onset <= 0.0:
		return 0.0
	var outer := maxf(params.outer_radius_m, params.thick_radius_m + 1.0)
	if dist_from_hero >= outer:
		return 0.0
	var rise := _falloff01(
		dist_from_hero, params.clear_radius_m, params.thick_radius_m, params.falloff)
	var fall := 1.0 - _falloff01(
		dist_from_hero, params.thick_radius_m, outer, WorldFogParams.Falloff.SMOOTH)
	return params.max_density * onset * rise * fall


static func _falloff01(
		d: float, begin: float, end: float, kind: WorldFogParams.Falloff) -> float:
	if d <= begin:
		return 0.0
	if d >= end:
		return 1.0
	var span := maxf(end - begin, 0.001)
	var t := clampf((d - begin) / span, 0.0, 1.0)
	match kind:
		WorldFogParams.Falloff.LINEAR:
			return t
		WorldFogParams.Falloff.SMOOTH:
			return t * t * (3.0 - 2.0 * t)
		_:
			return 1.0 - exp(-3.5 * t)


static func optical_depth_along_ray(
		camera_pos: Vector3,
		world_point: Vector3,
		anchor: Vector3,
		params: WorldFogParams) -> float:
	var steps := clampi(params.ray_steps, 2, 32)
	var seg := world_point - camera_pos
	var seg_len := seg.length()
	if seg_len < 1e-4:
		return world_density_at_xz(world_point, anchor, params) * 0.01
	var max_d := params.max_ray_distance_m
	var use_len := minf(seg_len, max_d)
	var dir := seg / seg_len
	var step := use_len / float(steps)
	var depth := 0.0
	for i in range(steps):
		var t := (float(i) + 0.5) / float(steps)
		var p := camera_pos + dir * (use_len * t)
		depth += world_density_at_xz(p, anchor, params) * step
	return depth


## Haze fraction [0,1] from integrated density along the view ray (transmittance model).
static func haze_along_view_ray(
		camera_pos: Vector3,
		world_point: Vector3,
		anchor: Vector3,
		params: WorldFogParams) -> float:
	var od := optical_depth_along_ray(camera_pos, world_point, anchor, params)
	return 1.0 - exp(-od)


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


static func haze_at_world_point(
		model: FogModel,
		camera_pos: Vector3,
		point: Vector3,
		anchor: Vector3,
		begin: float,
		end: float,
		params: WorldFogParams) -> float:
	match model:
		FogModel.CAMERA_DEPTH:
			return fog_amount_at_world_point(
				camera_pos, point, anchor, begin, end, CentreMode.CAMERA)
		FogModel.HERO_SHIFTED_DEPTH:
			return fog_amount_at_world_point(
				camera_pos, point, anchor, begin, end, CentreMode.HERO)
		_:
			return haze_along_view_ray(camera_pos, point, anchor, params)
