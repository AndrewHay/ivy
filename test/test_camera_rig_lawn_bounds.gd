## ivy-7h1f: CameraRig preset eyes stay inside generated village lawn disc.
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")
const CameraBounds = preload("res://src/world/camera_bounds.gd")
const CameraRig = preload("res://src/world/camera_rig.gd")

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
