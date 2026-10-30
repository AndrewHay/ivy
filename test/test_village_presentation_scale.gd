## ivy-0ka — generated-mode camera dolly-back + fauna ring scale; classic unchanged.
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")
const VillagePresentationScale = preload("res://src/world/village_presentation_scale.gd")
const FaunaGating = preload("res://src/presentation/fauna/fauna_gating.gd")


func after_each() -> void:
	VillagePresentationScale.fauna_world_scale = 1.0


func _boot_main() -> Node:
	var main := MainScene.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", SquareScenario)
	add_child_autofree(main)
	for _i in range(35):
		await get_tree().process_frame
	return main


func test_classic_camera_rig_scale_is_unity() -> void:
	var main := await _boot_main()
	var world: Node = main.get_node("World")
	world.call("set_village_mode", GameModes.CLASSIC, 0)
	var rig: Node3D = world.get_node("CameraRig") as Node3D
	assert_almost_eq(rig.scale.x, 1.0, 1e-5, "Classic CameraRig.scale must stay 1.0")
	assert_almost_eq(VillagePresentationScale.fauna_world_scale, 1.0, 1e-5)


func test_generated_camera_rig_and_fauna_scale() -> void:
	var main := await _boot_main()
	var world: Node = main.get_node("World")
	world.call("set_village_mode", GameModes.GENERATED, 1)
	var rig: Node3D = world.get_node("CameraRig") as Node3D
	assert_almost_eq(
		rig.scale.x, VillagePresentationScale.GENERATED_CAMERA_RIG_SCALE, 1e-5,
		"Generated CameraRig must dolly back")
	assert_almost_eq(
		VillagePresentationScale.fauna_world_scale,
		VillagePresentationScale.GENERATED_FAUNA_WORLD_SCALE, 1e-5)
	var fc := world.get_node("FaunaController")
	assert_almost_eq(
		float(fc.get("debug_spawn_max_dist_from_pivot_m")),
		VillagePresentationScale.spawn_near_pivot_max_m(), 0.01)


func test_fauna_gating_uses_scaled_garden_outer_in_generated() -> void:
	VillagePresentationScale.fauna_world_scale = VillagePresentationScale.GENERATED_FAUNA_WORLD_SCALE
	var anchor := FaunaAnchor.new()
	anchor.kind = FaunaConstants.AnchorKind.FLOWER
	anchor.local_transform = Transform3D(Basis.IDENTITY, Vector3(13.5, 0, 0))
	assert_true(
		FaunaGating.anchor_in_species_ring(FaunaConstants.Species.BEE, anchor),
		"13.5 m flower must be in scaled garden outer (12×1.2=14.4)")
	VillagePresentationScale.fauna_world_scale = 1.0
	anchor.local_transform = Transform3D(Basis.IDENTITY, Vector3(13.5, 0, 0))
	assert_false(
		FaunaGating.anchor_in_species_ring(FaunaConstants.Species.BEE, anchor),
		"13.5 m must stay outside classic garden outer 12 m")
