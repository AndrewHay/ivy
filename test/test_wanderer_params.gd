extends GutTest

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")


func test_production_pins_sd_numbers() -> void:
	var p := WandererParams.production()
	assert_almost_eq(p.figure_height_m, 2.0, 1e-6)
	assert_almost_eq(p.walk_speed_mps, 2.0, 1e-6)
	assert_almost_eq(p.speed_ease_m, 0.3, 1e-6)
	assert_almost_eq(p.turn_rate_deg_s, 270.0, 1e-6)
	assert_almost_eq(p.stride_length_m, 1.8, 1e-6)
	assert_almost_eq(p.leg_swing_deg, 24.0, 1e-6)
	assert_almost_eq(p.arm_swing_deg, 18.0, 1e-6)
	assert_almost_eq(p.torso_roll_deg, 2.5, 1e-6)
	assert_almost_eq(p.torso_lean_deg, 4.0, 1e-6)
	assert_almost_eq(p.bob_m, 0.04, 1e-6)
	assert_almost_eq(p.idle_blend_s, 0.2, 1e-6)
	assert_eq(p.walk_variant, 0)
	assert_almost_eq(p.door_pause_s, 1.0, 1e-6)
	assert_almost_eq(p.inside_s, 10.0, 1e-6)
	assert_almost_eq(p.exit_pause_s, 1.0, 1e-6)
	assert_almost_eq(p.present_standoff_m, 2.5, 1e-6)
	assert_almost_eq(p.leg_turn_gate_deg, 90.0, 1e-6)
	assert_almost_eq(p.image_s, 5.0, 1e-6)
	assert_almost_eq(p.image_fade_s, 0.3, 1e-6)
	assert_almost_eq(p.quote_interval_s, 20.0, 1e-6)
	assert_almost_eq(p.quote_min_walk_s, 3.0, 1e-6)
	assert_almost_eq(p.bubble_base_s, 2.0, 1e-6)
	assert_almost_eq(p.bubble_s_per_char, 0.06, 1e-6)
	assert_almost_eq(p.bubble_min_s, 3.0, 1e-6)
	assert_almost_eq(p.bubble_max_s, 6.0, 1e-6)
	assert_almost_eq(p.snap_m, 0.35, 1e-6)
	assert_almost_eq(p.door_snap_m, 1.0, 1e-6)
	assert_almost_eq(p.door_stoop_m, 0.5, 1e-6)
	assert_almost_eq(p.door_stand_off_m, 0.3, 1e-6)
	assert_almost_eq(p.bridge_max_m, 12.0, 1e-6)
	assert_eq(p.image_max_px, 1024)
	assert_eq(p.content_dir, "res://wanderer_content/")
	assert_false(p.pause_with_sim)


func test_bubble_duration_formula() -> void:
	var p := WandererParams.production()
	assert_almost_eq(p.bubble_duration(""), 3.0, 1e-6)
	assert_almost_eq(p.bubble_duration("0123456789"), 3.0, 1e-6)
	assert_almost_eq(p.bubble_duration("x".repeat(50)), 5.0, 1e-6)
	var long := "x".repeat(200)
	assert_almost_eq(p.bubble_duration(long), 6.0, 1e-6)


func test_variant_alias() -> void:
	var p := WandererParams.production()
	assert_eq(p.variant, 0)
	p.variant = 2
	assert_eq(p.walk_variant, 2)
	assert_eq(p.variant, 2)


func test_dict_round_trip() -> void:
	var p := WandererParams.production()
	p.walk_speed_mps = 1.2
	p.variant = 1
	p.pause_with_sim = true
	var d := p.to_dict()
	var q := WandererParams.production()
	q.from_dict(d)
	assert_almost_eq(q.walk_speed_mps, 1.2, 1e-6)
	assert_eq(q.walk_variant, 1)
	assert_true(q.pause_with_sim)


func test_present_standoff_floor() -> void:
	var p := WandererParams.production()
	p.present_standoff_m = 0.3
	assert_almost_eq(p.present_standoff(), 1.0, 1e-6)
	p.present_standoff_m = 1.0
	assert_almost_eq(p.present_standoff(), 1.0, 1e-6)
	p.present_standoff_m = 2.5
	assert_almost_eq(p.present_standoff(), 2.5, 1e-6)
	p.present_standoff_m = 6.0
	assert_almost_eq(p.present_standoff(), 6.0, 1e-6)


func test_reset_to_production() -> void:
	var p := WandererParams.production()
	p.walk_speed_mps = 9.0
	p.rng_seed = 42
	p.reset_to_production()
	assert_almost_eq(p.walk_speed_mps, 2.0, 1e-6)
	assert_eq(p.rng_seed, 42)
