extends GutTest

const IvyParams = preload("res://src/params/ivy_params.gd")
const _DEFAULTS := {
	"segment_length": 0.03,
	"max_growth_rate": 0.12,
	"light_memory": 3.0,
	"light_K": 3.0,
	"reference_DLI": 12.0,
	"persistence_base": 0.50,
	"random_base": 0.20,
	"random_new_mix": 0.25,
	"light_seek_min": 0.03,
	"light_seek_max": 0.23,
	"adhesion_base": 0.10,
	"adhesion_range": 0.15,
	"max_float": 0.40,
	"gravity_exponent": 0.70,
	"crowding_base": 0.15,
	"crowding_decay": 0.80,
	"branch_rate": 1.7,
	"branch_light_exponent": 1.30,
	"branch_crowd_exponent": 1.50,
	"direction_memory": 0.50,
	"light_gradient_scale": 4.0,
	"crowding_gradient_scale": 2.0,
	"upward_base": 0.20,
	"sim_tick": 1.0 / 24.0,
	"speed_watch": 60.0,
	"speed_fast": 6.0,
	"speed_grow": 1.2,
	"render_sun_blend_lo": 10.0,
	"render_sun_blend_hi": 30.0,
	"latitude": 51.5,
	"longitude": 0.0,
	"day_of_year": 105,
	"start_hour": 6.0,
	"light_warmup_days": 12.0,
	"diel_night_floor": 0.05,
	"diel_exponent": 0.35,
	"field_cell": 0.06,
	"field_sample_jitter_ratio": 0.35,
	"gradient_epsilon_ratio": 1.5,
	"field_shell_halfwidth": 0.09,
	"contact_distance": 0.02,
	"max_segments_per_tick": 8,
	"branch_angle_min": 45.0,
	"branch_angle_max": 75.0,
	"branch_offset": 0.005,
	"ground_y_min": 0.02,
	"tip_cap_soft": 96,
	"tip_cap_hard": 160,
	"retire_margin": 1.25,
	"stall_rate": 0.01,
	"stall_days": 3,
	"internode_base": 0.040,
	"internode_shade_gain": 0.85,
	"internode_jitter": 0.25,
	"leaf_tip_suppress": 0.06,
	"phyllotaxy_divergence": 137.5,
	"phyllotaxy_flatten": 0.65,
	"leaf_out_of_plane": 0.35,
	"leaf_photo_cant": 0.45,
	"droop_base": 12.0,
	"droop_shade_gain": 18.0,
	"leaf_jitter_tilt": 22.0,
	"leaf_jitter_roll": 15.0,
	"leaf_jitter_yaw": 8.0,
	"leaf_offset_base": 0.004,
	"leaf_offset_step": 0.0015,
	"leaf_offset_ladder": 5,
	"leaf_width_base": 0.075,
	"leaf_order_falloff": 0.18,
	"leaf_expand_distance": 0.12,
	"leaf_light_scale_base": 0.80,
	"leaf_light_scale_gain": 0.30,
	"leaf_size_sigma": 0.16,
	"leaf_healthy_base": 0.18,
	"leaf_healthy_gain": 0.77,
	"leaf_crowd_suppress": 0.70,
	"leaf_crowd_floor": 0.30,
	"leaf_crowd_k": 0.5,
	"leaf_cap": 20000,
	"stem_radius_base": 0.006,
	"stem_order_falloff": 0.25,
	"stem_tip_taper": 0.15,
	"diel_gate_enabled": true,
	"tip_cap_m1": 64,
	"dev_build": true,
}


func test_defaults_present() -> void:
	var p := IvyParams.new()
	for key in _DEFAULTS:
		assert_true(key in p, "missing %s" % key)
		var got = p.get(key)
		var expected = _DEFAULTS[key]
		if typeof(expected) == TYPE_FLOAT:
			assert_almost_eq(got, expected, 1e-6, key)
		else:
			assert_eq(got, expected, key)


func test_validate_accepts_the_shipped_defaults() -> void:
	assert_eq(IvyParams.new().validate(), PackedStringArray(),
		"shipped defaults must satisfy every coupled-parameter constraint")
	assert_eq((load("res://src/params/ivy_params_default.tres") as IvyParams).validate(),
		PackedStringArray(), "the default resource must satisfy them too")


func test_validate_rejects_a_healthy_probability_above_one() -> void:
	# SD-LEAF-6: base + gain > 1 makes every tier draw healthy at full light, so the
	# weathered variants stop being placed. Nothing else catches it — the LG-2' layer (a)
	# tier tests assert the probability function's shape, not the drawn outcome.
	var p := IvyParams.new()
	p.leaf_healthy_base = 0.5
	p.leaf_healthy_gain = 0.7
	var problems := p.validate()
	assert_eq(problems.size(), 1, "base+gain=1.2 must be reported")
	assert_string_contains(problems[0], "leaf_healthy_base + leaf_healthy_gain",
		"the message must name both parameters so the reader can act on it")

	# The boundary itself is legal: P(healthy) = 1 at full light is saturation, not overflow.
	p.leaf_healthy_base = 0.3
	p.leaf_healthy_gain = 0.7
	assert_eq(p.validate(), PackedStringArray(), "base+gain == 1.0 must be accepted")


func test_content_hash_stable() -> void:
	var a := load("res://src/params/ivy_params_default.tres") as IvyParams
	var b := load("res://src/params/ivy_params_default.tres") as IvyParams
	assert_eq(a.content_hash(), b.content_hash())


func test_content_hash_changes_on_edit() -> void:
	var p := IvyParams.new()
	var h0 := p.content_hash()
	p.diel_gate_enabled = false
	assert_ne(p.content_hash(), h0)
	assert_gt(p.content_hash().length(), 0)
