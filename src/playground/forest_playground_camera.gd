class_name ForestPlaygroundCamera
extends RefCounted

const HeroFog = preload("res://src/world/hero_fog.gd")
const WorldFogParams = preload("res://src/world/world_fog_params.gd")
const ForestCamRef = preload("res://src/world/forest_cam_ref.gd")

## Matches square-scenario generated village (capture QA / main.tscn).
const SQUARE_CAMERA_PIVOT := ForestCamRef.SQUARE_SCENARIO_PIVOT
const GENERATED_RIG_SCALE := ForestCamRef.GENERATED_RIG_SCALE
const FOV_DEG := ForestCamRef.FOV_DEG


static func backdrop_origin() -> Vector3:
	return ForestCamRef.backdrop_origin(SQUARE_CAMERA_PIVOT)


static func rig_position() -> Vector3:
	return ForestCamRef.rig_base_position(SQUARE_CAMERA_PIVOT)


static func camsun_position() -> Vector3:
	return ForestCamRef.camsun_eye(SQUARE_CAMERA_PIVOT, GENERATED_RIG_SCALE)


static func camsun_forward() -> Vector3:
	return ForestCamRef.camsun_forward()


static func aim_point() -> Vector3:
	return ForestCamRef.aim_point(SQUARE_CAMERA_PIVOT)


static func apply_camsun(cam: Camera3D) -> void:
	var eye := camsun_position()
	var aim := aim_point()
	cam.global_position = eye
	cam.look_at(aim, Vector3.UP)
	cam.fov = FOV_DEG


static func apply_wide(cam: Camera3D) -> void:
	## Azimuth 0 = +Z side (CamSun side), same as tools/run_ui_script.gd ORBIT / capture_generated_village.
	var pivot := aim_point()
	var radius := 90.0
	var height := 42.0
	var eye := Vector3(pivot.x + sin(0.0) * radius, height, pivot.z + cos(0.0) * radius)
	cam.global_position = eye
	cam.look_at(Vector3(pivot.x, pivot.y, pivot.z), Vector3.UP)
	cam.fov = FOV_DEG


## Horizontal FOV test: trees as layout XZ in backdrop-local space.
static func count_trees_in_camsun_fov(trees_layout: Array[Vector2]) -> int:
	var cam_pos := camsun_position()
	var off := backdrop_origin()
	var fwd := camsun_forward()
	var half_h := deg_to_rad(FOV_DEG * 0.5)
	var count := 0
	for p: Vector2 in trees_layout:
		var wp := Vector2(p.x + off.x, p.y + off.z)
		var rel := Vector3(wp.x - cam_pos.x, 0.0, wp.y - cam_pos.z)
		var dist := rel.length()
		if dist < 0.01:
			continue
		var dot := fwd.dot(rel / dist)
		if dot > 0.0 and acos(clampf(dot, -1.0, 1.0)) <= half_h:
			count += 1
	return count


static func hero_fog_anchor_world() -> Vector3:
	var off := backdrop_origin()
	var h := VillageLayout.HERO_DOOR_STOOP
	return Vector3(h.x + off.x, 1.0, h.y + off.z)


## Trees in horizontal CamSun FOV with fog amount <= max_haze (hero or camera centre).
static func count_trees_visible_in_camsun(
		trees_layout: Array[Vector2],
		fog_begin: float,
		fog_end: float,
		fog_model: HeroFog.FogModel,
		max_haze: float = 0.7,
		world_params: WorldFogParams = null) -> Dictionary:
	var cam_pos := camsun_position()
	var off := backdrop_origin()
	var fwd := camsun_forward()
	var half_h := deg_to_rad(FOV_DEG * 0.5)
	var anchor := hero_fog_anchor_world()
	var params := world_params if world_params != null else WorldFogParams.new()
	var in_fov := 0
	var visible := 0
	var haze_sum := 0.0
	for p: Vector2 in trees_layout:
		var wp := Vector3(p.x + off.x, 1.0, p.y + off.z)
		var rel := Vector3(wp.x - cam_pos.x, 0.0, wp.z - cam_pos.z)
		var dist := rel.length()
		if dist < 0.01:
			continue
		var dot := fwd.dot(rel / dist)
		if dot <= 0.0 or acos(clampf(dot, -1.0, 1.0)) > half_h:
			continue
		in_fov += 1
		var haze := HeroFog.haze_at_world_point(
			fog_model, cam_pos, wp, anchor, fog_begin, fog_end, params)
		if haze <= max_haze:
			visible += 1
			haze_sum += haze
	return {"in_fov": in_fov, "visible": visible, "mean_haze": haze_sum / maxf(visible, 1)}
