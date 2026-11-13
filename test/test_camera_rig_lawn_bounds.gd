## ivy-7h1f: CameraRig preset eyes stay inside generated village lawn disc.
## WP7: AC-VT11 extension — eye never below terrain floor (CameraBounds floor_y arg).
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")
const CameraRig = preload("res://src/world/camera_rig.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")

const _GEN_SEED := 7


func _boot_generated() -> Node:
	var main := MainScene.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", SquareScenario)
	add_child_autofree(main)
	for _i in range(30):
		await get_tree().process_frame
	var world := main.get_node("World")
	world.call("set_village_mode", GameModes.GENERATED, _GEN_SEED)
	world.call("rebuild_backdrop")
	for _i in range(5):
		await get_tree().process_frame
	return main


func test_all_camera_rig_presets_inside_lawn_after_presentation() -> void:
	var main := await _boot_generated()
	var world: Node = main.get_node("World")
	var bounds: Dictionary = world.get_village_lawn_camera_bounds()
	assert_false(bounds.is_empty(), "generated mode must expose lawn bounds")
	var centre: Vector2 = bounds["centre_xz"]
	var radius: float = bounds["radius"]
	var margin: float = bounds["margin"]
	var allowed := maxf(radius - margin, 0.0) + 0.05
	var rig: CameraRig = world.get_node("CameraRig") as CameraRig
	var names := ["CamSun", "CamShade", "CamTop", "CamSilhouette"]
	for i in range(mini(names.size(), rig.get_child_count())):
		rig.select(i)
		await get_tree().process_frame
		var cam := rig.get_child(i) as Camera3D
		var eye := cam.global_position
		var dist := Vector2(eye.x, eye.z).distance_to(centre)
		assert_lte(dist, allowed,
			"%s eye dist %.2f > allowed %.2f (centre %s)" % [names[i], dist, allowed, centre])


func test_debug_glide_completes_with_eye_inside_lawn() -> void:
	var main := await _boot_generated()
	var world: Node = main.get_node("World")
	var bounds: Dictionary = world.get_village_lawn_camera_bounds()
	var dc := world.get_node("DebugCamera")
	dc.set("script_driven", false)
	dc.call("setup", load("res://src/world/tower_spec_default.tres"))
	dc.call("set_lawn_camera_bounds", bounds["centre_xz"], bounds["radius"], bounds["margin"])
	var far_target := Vector3(bounds["centre_xz"].x + 40.0, 0.0, bounds["centre_xz"].y + 40.0)
	dc.call("_begin_glide_to", far_target)
	dc.call("_apply_orbit_view")
	for _f in range(120):
		dc.call("_process", 0.05)
		await get_tree().process_frame
	var eye: Vector3 = dc.global_transform.origin
	var allowed := maxf(bounds["radius"] - bounds["margin"], 0.0) + 0.05
	assert_lte(Vector2(eye.x, eye.z).distance_to(bounds["centre_xz"]), allowed,
		"orbit eye must be inside lawn after glide + enforce")


## AC-VT11 — CameraBounds floor_y arg: CameraRig preset eyes are >= terrain floor (WP7).
func test_camera_rig_preset_eyes_above_terrain_floor() -> void:
	var main := await _boot_generated()
	var world: Node = main.get_node("World")
	var backdrop: Node = world.get_node_or_null("VillageBackdrop")
	if backdrop == null or not backdrop.has_method("sample_terrain_y"):
		pending("no generated backdrop with sample_terrain_y — skip")
		return
	var terrain_params = backdrop.get("_terrain_params")
	var clearance: float = 0.35
	if terrain_params != null and terrain_params.get("camera_ground_clearance_m") != null:
		clearance = float(terrain_params.get("camera_ground_clearance_m"))
	var rig: CameraRig = world.get_node("CameraRig") as CameraRig
	if rig == null:
		pending("no CameraRig in World — skip")
		return
	var names := ["CamSun", "CamShade", "CamTop", "CamSilhouette"]
	for i in range(mini(names.size(), rig.get_child_count())):
		rig.select(i)
		await get_tree().process_frame
		var cam := rig.get_child(i) as Camera3D
		var eye := cam.global_position
		var terrain_y: float = backdrop.call("sample_terrain_y", Vector2(eye.x, eye.z))
		var floor_y := terrain_y + clearance
		# Preset cameras sit high (authored > 5 m) — they should always be above terrain floor.
		assert_gte(eye.y, floor_y - 0.05,
			"%s eye.y %.2f must be >= terrain_floor %.2f" % [names[i], eye.y, floor_y])
