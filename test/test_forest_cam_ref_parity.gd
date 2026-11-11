extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")
const ForestCamRef = preload("res://src/world/forest_cam_ref.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const VillagePresentationScale = preload("res://src/world/village_presentation_scale.gd")


func test_playground_camsun_matches_live_orbit_pivot() -> void:
	var main := MainScene.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", SquareScenario)
	add_child_autofree(main)
	for _i in range(30):
		await get_tree().process_frame
	var world := main.get_node("World")
	world.call("set_village_mode", GameModes.GENERATED, 7)
	world.call("rebuild_backdrop")
	await get_tree().process_frame
	var pivot: Vector3 = world.get_orbit_pivot()
	var scale := VillagePresentationScale.camera_rig_scale_for_mode(GameModes.GENERATED)
	var live := ForestCamRef.camsun_eye(pivot, scale)
	var playground := ForestPlaygroundCamera.camsun_position()
	assert_almost_eq(live.x, playground.x, 1e-3)
	assert_almost_eq(live.y, playground.y, 1e-3)
	assert_almost_eq(live.z, playground.z, 1e-3)
	var rig_cam: Camera3D = world.get_node("CameraRig/CamSun") as Camera3D
	assert_almost_eq(rig_cam.global_position.x, live.x, 0.15,
		"scene CamSun should match ForestCamRef after presentation")
