extends GutTest


func test_lit_cutoff_zero_activity() -> void:
	var act := FaunaGating.combined_activity(
		0.04, 1.0, 1.0, FaunaConstants.Species.BEE, 12.0)
	assert_eq(act, 0.0)


func test_bee_active_at_noon() -> void:
	var act := FaunaGating.combined_activity(
		1.0, 1.0, 1.0, FaunaConstants.Species.BEE, 12.0)
	assert_true(act > 0.0)


func test_bee_inactive_at_dawn_before_six_thirty() -> void:
	assert_eq(FaunaGating.species_hour_gate(FaunaConstants.Species.BEE, 6.0), 0.0)


func test_bee_dawn_ramp_before_eight() -> void:
	assert_true(FaunaGating.species_hour_gate(FaunaConstants.Species.BEE, 7.0) > 0.0)


func test_bee_inactive_at_night_hour() -> void:
	var game_day := 22.0 / 24.0
	assert_eq(FaunaGating.species_hour_gate(FaunaConstants.Species.BEE, 22.0), 0.0)


func test_timelapse_density_floor() -> void:
	assert_almost_eq(FaunaGating.timelapse_density_scale(0.0), 0.25, 1e-5)
	assert_almost_eq(FaunaGating.timelapse_density_scale(1.0), 1.0, 1e-5)


func test_hero_weight_inside_hard_exclusion() -> void:
	assert_eq(FaunaGating.hero_weight_at_xz(Vector2(3.0, 0.0)), 0.0)


func test_hero_weight_outside_soft_band() -> void:
	assert_almost_eq(FaunaGating.hero_weight_at_xz(Vector2(8.0, 0.0)), 1.0, 1e-5)


func test_camera_cap_scale_close_to_pivot() -> void:
	var scale := FaunaGating.camera_cap_scale(Vector3(1.0, 2.0, 1.0), Vector3.ZERO)
	assert_almost_eq(scale, FaunaConstants.HERO_CAMERA_CAP_SCALE, 1e-5)


func test_spawn_forbidden_beyond_18m() -> void:
	var cam := Vector3.ZERO
	var far := Vector3(20.0, 0.0, 0.0)
	assert_false(FaunaGating.spawn_distance_allowed(cam, far))


func test_spawn_allowed_within_despawn_ring() -> void:
	var cam := Vector3.ZERO
	var near := Vector3(12.0, 0.0, 0.0)
	assert_true(FaunaGating.spawn_distance_allowed(cam, near))


func test_fauna_scale_vs_leaf() -> void:
	assert_almost_eq(FaunaConstants.bee_body_length_m(), FaunaConstants.LEAF_REFERENCE_WIDTH_M / 3.0, 1e-6)
	assert_almost_eq(
		FaunaConstants.butterfly_wingspan_m(),
		FaunaConstants.LEAF_REFERENCE_WIDTH_M * 0.5,
		1e-6)


func test_despawn_beyond_18m() -> void:
	var cam := Vector3.ZERO
	var agent := Vector3(20.0, 0.0, 0.0)
	assert_true(FaunaGating.should_despawn_agent(cam, agent))
