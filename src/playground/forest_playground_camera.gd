class_name ForestPlaygroundCamera
extends RefCounted

const HeroFog = preload("res://src/world/hero_fog.gd")

## Matches square-scenario generated village (capture QA / main.tscn).
const SQUARE_CAMERA_PIVOT := Vector3(-7.0, 1.56, 0.0)
const CANONICAL_AIM_Y := 2.0
const GENERATED_RIG_SCALE := 1.35
const CAMSUN_LOCAL := Vector3(0.0, 2.0, 8.0)
const FOV_DEG := 75.0


static func backdrop_origin() -> Vector3:
	return Vector3(SQUARE_CAMERA_PIVOT.x, 0.0, SQUARE_CAMERA_PIVOT.z)


static func rig_position() -> Vector3:
	var p := SQUARE_CAMERA_PIVOT
	return Vector3(p.x, p.y - CANONICAL_AIM_Y, p.z)


static func camsun_position() -> Vector3:
	return rig_position() + CAMSUN_LOCAL * GENERATED_RIG_SCALE


static func camsun_forward() -> Vector3:
	return Vector3(0.0, 0.0, -1.0)


static func aim_point() -> Vector3:
	return SQUARE_CAMERA_PIVOT


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
		hero_centre: bool,
		max_haze: float = 0.7) -> Dictionary:
	var cam_pos := camsun_position()
	var off := backdrop_origin()
	var fwd := camsun_forward()
	var half_h := deg_to_rad(FOV_DEG * 0.5)
	var anchor := hero_fog_anchor_world()
	var mode := HeroFog.CentreMode.HERO if hero_centre else HeroFog.CentreMode.CAMERA
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
		var haze := HeroFog.fog_amount_at_world_point(
			cam_pos, wp, anchor, fog_begin, fog_end, mode)
		if haze <= max_haze:
			visible += 1
			haze_sum += haze
	return {"in_fov": in_fov, "visible": visible, "mean_haze": haze_sum / maxf(visible, 1)}
