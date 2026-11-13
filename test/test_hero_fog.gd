extends GutTest

const HeroFog = preload("res://src/world/hero_fog.gd")
const WorldFogParams = preload("res://src/world/world_fog_params.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")


func test_volumetric_fog_fallback_when_not_forward_plus() -> void:
	var m := HeroFog.effective_fog_model(HeroFog.FogModel.WORLD_AROUND_HERO, "gl_compatibility")
	assert_eq(m, HeroFog.FogModel.HERO_SHIFTED_DEPTH)
	var keep := HeroFog.effective_fog_model(HeroFog.FogModel.WORLD_AROUND_HERO, "forward_plus")
	assert_eq(keep, HeroFog.FogModel.WORLD_AROUND_HERO)


func test_fog_amount_linear_ramp() -> void:
	assert_almost_eq(HeroFog.fog_amount(20.0, 20.0, 95.0), 0.0, 1e-5)
	assert_almost_eq(HeroFog.fog_amount(95.0, 20.0, 95.0), 1.0, 1e-5)
	assert_almost_eq(HeroFog.fog_amount(57.5, 20.0, 95.0), 0.5, 1e-5)


func test_world_density_monotonic() -> void:
	var p: WorldFogParams = WorldFogParams.production()
	assert_eq(HeroFog.world_density_at_distance(10.0, p), 0.0, "clear zone")
	var at_peak := HeroFog.world_density_at_distance(
		(p.clear_radius_m + p.thick_radius_m) * 0.55, p)
	assert_gt(at_peak, p.max_density * 0.35, "mid-rise band should build noticeable density")
	var mid := (p.clear_radius_m + p.thick_radius_m) * 0.5
	var hi := mid + 8.0
	assert_gt(
		HeroFog.world_density_at_distance(hi, p),
		HeroFog.world_density_at_distance(mid, p))


func test_world_density_soft_onset_past_clear_radius() -> void:
	var p: WorldFogParams = WorldFogParams.production()
	var at_clear := HeroFog.world_density_at_distance(p.clear_radius_m, p)
	var just_out := HeroFog.world_density_at_distance(p.clear_radius_m + 4.0, p)
	var mid_onset := HeroFog.world_density_at_distance(
		p.clear_radius_m + p.clear_onset_pad_m * 0.5, p)
	assert_eq(at_clear, 0.0, "interior clear disk stays fog-free")
	assert_gt(just_out, 0.0, "density should ramp smoothly past clear (no hard step)")
	assert_gt(mid_onset, just_out, "onset ramp monotonic inside pad band")


func test_world_density_fades_to_zero_at_outer_radius() -> void:
	var p: WorldFogParams = WorldFogParams.production()
	var mid := (p.thick_radius_m + p.outer_radius_m) * 0.5
	assert_gt(
		HeroFog.world_density_at_distance(mid, p),
		HeroFog.world_density_at_distance(p.outer_radius_m + 10.0, p),
		"density should decay between thick and outer radii")
	assert_lt(HeroFog.world_density_at_distance(p.outer_radius_m + 20.0, p), 0.001,
		"beyond outer_radius density ~0 (no froxel hard ring)")
	var peak := HeroFog.world_density_at_distance(p.thick_radius_m, p)
	assert_gt(peak, 0.0, "peak band exists")
	assert_lt(peak, p.max_density + 0.001, "no density plateau above max")


func test_density_at_point_independent_of_camera() -> void:
	var anchor := Vector3(-7.0, 1.0, -15.0)
	var point := Vector3(-7.0, 1.0, -50.0)
	var p: WorldFogParams = WorldFogParams.production()
	var d := HeroFog.world_density_at_xz(point, anchor, p)
	assert_gt(d, 0.0)
	assert_almost_eq(d, HeroFog.world_density_at_xz(point, anchor, p), 1e-8)


func test_haze_at_hero_low_from_edge_and_camsun() -> void:
	var anchor := ForestPlaygroundCamera.hero_fog_anchor_world()
	var params: WorldFogParams = WorldFogParams.production()
	var hero_pt := anchor
	var lawn_edge := anchor + Vector3(0.0, 0.0, 54.0)
	var camsun := ForestPlaygroundCamera.camsun_position()
	var edge_cam := anchor + Vector3(52.0, 5.0, 0.0)
	var haze_hero_camsun := HeroFog.haze_along_view_ray(camsun, hero_pt, anchor, params)
	var haze_hero_edge := HeroFog.haze_along_view_ray(edge_cam, hero_pt, anchor, params)
	var haze_lawn_camsun := HeroFog.haze_along_view_ray(camsun, lawn_edge, anchor, params)
	var haze_lawn_edge := HeroFog.haze_along_view_ray(edge_cam, lawn_edge, anchor, params)
	assert_lt(haze_hero_camsun, 0.35, "CamSun view of hero stays fairly clear")
	assert_gt(haze_hero_edge, haze_hero_camsun,
		"disc edge camera integrates more haze along ray to hero")
	assert_gt(haze_lawn_camsun, haze_hero_camsun + 0.08)
	assert_gt(haze_lawn_edge, haze_lawn_camsun * 0.85)


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
		"legacy hero-shifted depth offset")
	assert_almost_eq(env.fog_depth_end, 95.0 + d_anchor, 0.05)
