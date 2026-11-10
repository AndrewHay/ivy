extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")


func _boot_generated(seed: int) -> Node:
	var main := MainScene.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", SquareScenario)
	add_child_autofree(main)
	for _i in range(30):
		await get_tree().process_frame
	main.call("apply_village_mode_live", GameModes.GENERATED, seed)
	for _i in range(20):
		await get_tree().process_frame
	return main


func _environment(main: Node) -> Environment:
	var world: Node = main.get_node("World")
	var sky: SkySun = world.get_sky_sun()
	var we := sky.get_node("WorldEnvironment") as WorldEnvironment
	return we.environment


func test_fog_enabled_after_generated_rebuild() -> void:
	var main := await _boot_generated(7)
	var env := _environment(main)
	assert_true(env.fog_enabled, "generated village must enable depth fog on Environment")
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH)


func test_applied_depth_begin_differs_camera_vs_hero_at_80m() -> void:
	var main := await _boot_generated(7)
	var world: Node3D = main.get_node("World")
	var sky: SkySun = world.get_sky_sun()
	var pivot: Vector3 = world.get_orbit_pivot()
	var hero := Vector2(pivot.x, pivot.z) + VillageLayout.HERO_DOOR_STOOP
	var cam := Camera3D.new()
	world.add_child(cam)
	var dir := Vector2(0.92, 0.38).normalized()
	var dist := 80.0
	var eye := Vector3(hero.x + dir.x * dist, pivot.y + 5.0, hero.y + dir.y * dist)
	cam.global_transform = Transform3D(
		Basis.looking_at(Vector3(hero.x, 1.2, hero.y) - eye, Vector3.UP), eye)
	cam.make_current()
	for _i in range(8):
		await get_tree().process_frame

	sky.set_fog_anchor(world.call("_hero_fog_anchor_world"))
	sky.set_fog_centre_mode(HeroFog.CentreMode.CAMERA)
	sky.sync_depth_fog_from_active_camera()
	var env := _environment(main)
	var cam_begin := env.fog_depth_begin
	var cam_end := env.fog_depth_end

	sky.set_fog_centre_mode(HeroFog.CentreMode.HERO)
	sky.sync_depth_fog_from_active_camera()
	await get_tree().process_frame
	var hero_begin := env.fog_depth_begin
	var hero_end := env.fog_depth_end

	var cam_dist := cam.global_position.distance_to(
		Vector3(hero.x, pivot.y + 1.0, hero.y))
	assert_gt(cam_dist, 70.0, "probe camera distance to hero")
	assert_gt(hero_begin, cam_begin + 40.0,
		"hero mode must shift fog_depth_begin by ~camera→hero depth (cam=%.2f hero=%.2f)"
		% [cam_begin, hero_begin])
	assert_gt(hero_end, cam_end + 40.0,
		"hero mode must shift fog_depth_end (cam=%.2f hero=%.2f)" % [cam_end, hero_end])
