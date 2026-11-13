extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const WorldFogParams = preload("res://src/world/world_fog_params.gd")
const WorldFogVolume = preload("res://src/world/world_fog_volume.gd")


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


## Contract changed ivy-jnee: production uses world volumetric fog (depth fog off).
func test_world_volumetric_fog_after_generated_rebuild() -> void:
	var main := await _boot_generated(7)
	var sky: SkySun = main.get_node("World").get_sky_sun()
	for _i in range(8):
		await get_tree().process_frame
	sky.sync_depth_fog_from_active_camera()
	var env := _environment(main)
	assert_true(env.fog_enabled, "world model uses fixed far depth wash (not camera-shifted)")
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_gte(env.fog_depth_begin, 180.0, "depth wash starts past hero volumetric band")
	assert_gte(env.fog_depth_end, 400.0, "depth wash reaches horizon")
	assert_true(env.volumetric_fog_enabled, "world model enables volumetric fog")
	assert_eq(sky.get_fog_model(), HeroFog.FogModel.WORLD_AROUND_HERO)
	var fv := sky.get_node_or_null("WorldHeroFog") as FogVolume
	assert_not_null(fv, "WorldHeroFog volume should exist under SkySun")
	assert_gte(env.volumetric_fog_length, 400.0, "fog must reach horizon without black cutoff")
	var albedo := env.volumetric_fog_albedo
	assert_gte(albedo.r + albedo.g + albedo.b, 0.5, "volumetric albedo must not be black")
	assert_lte(env.volumetric_fog_sky_affect, 0.35, "sky affect capped to avoid over-darkening")
	if fv.material is ShaderMaterial:
		var sm := fv.material as ShaderMaterial
		var cr: Variant = sm.get_shader_parameter("clear_radius")
		assert_almost_eq(float(cr), WorldFogParams.DEFAULT_CLEAR_RADIUS_M, 0.5)
		var contract := WorldFogVolume.validate_shader_contract(sm)
		assert_true(contract["ok"], "fog volume shader: %s" % str(contract["issues"]))


## Legacy hero-shifted depth still available for playground comparison (not production default).
func test_legacy_depth_shift_when_hero_shifted_mode() -> void:
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
	sky.set_fog_anchor(world.call("_hero_fog_anchor_world"))
	sky.set_fog_model(HeroFog.FogModel.CAMERA_DEPTH)
	sky.sync_depth_fog_from_active_camera()
	for _i in range(6):
		await get_tree().process_frame
	var env := _environment(main)
	var cam_begin := env.fog_depth_begin
	sky.set_fog_model(HeroFog.FogModel.HERO_SHIFTED_DEPTH)
	sky.sync_depth_fog_from_active_camera()
	await get_tree().process_frame
	var hero_begin := env.fog_depth_begin
	assert_gt(hero_begin, cam_begin + 40.0,
		"legacy shifted depth begin (playground compare only)")
