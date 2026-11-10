extends GutTest

const HeroFog = preload("res://src/world/hero_fog.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")


func test_fog_amount_linear_ramp() -> void:
	assert_almost_eq(HeroFog.fog_amount(20.0, 20.0, 95.0), 0.0, 1e-5)
	assert_almost_eq(HeroFog.fog_amount(95.0, 20.0, 95.0), 1.0, 1e-5)
	assert_almost_eq(HeroFog.fog_amount(57.5, 20.0, 95.0), 0.5, 1e-5)


func test_hero_mode_uses_anchor_distance_not_camera() -> void:
	var anchor := Vector3(-7.0, 1.0, -15.0)
	var cam_pos := ForestPlaygroundCamera.camsun_position()
	var tree := Vector3(-10.0, 0.0, -62.0)
	var hero_amt := HeroFog.fog_amount_at_world_point(
		cam_pos, tree, anchor, 20.0, 95.0, HeroFog.CentreMode.HERO)
	var cam_amt := HeroFog.fog_amount_at_world_point(
		cam_pos, tree, anchor, 20.0, 95.0, HeroFog.CentreMode.CAMERA)
	assert_lt(hero_amt, cam_amt,
		"hero-centred fog should be lighter than camera fog for distant trees behind hero")
	assert_lte(hero_amt, 0.7, "hero haze at tree should be <= 70%% for tuned band")


func test_depth_offset_exact_on_view_axis() -> void:
	var cam := Transform3D(Basis.IDENTITY, ForestPlaygroundCamera.camsun_position())
	cam = cam.looking_at(ForestPlaygroundCamera.aim_point(), Vector3.UP)
	var anchor := ForestPlaygroundCamera.aim_point()
	var offset := HeroFog.view_ray_depth_offset(cam, anchor)
	var env := Environment.new()
	env.fog_mode = Environment.FOG_MODE_DEPTH
	HeroFog.apply_depth_fog_to_environment(
		env, cam, anchor, 20.0, 95.0, HeroFog.CentreMode.HERO)
	var d_anchor := anchor.distance_to(cam.origin)
	assert_almost_eq(env.fog_depth_begin, 20.0 + d_anchor, 0.05,
		"along view axis begin offset should match anchor depth")
	assert_almost_eq(env.fog_depth_end, 95.0 + d_anchor, 0.05)
