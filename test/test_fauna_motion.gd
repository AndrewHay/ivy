extends GutTest

const FaunaAgentStateScript = preload("res://src/presentation/fauna/fauna_agent_state.gd")


func before_each() -> void:
	FaunaIntegration.set_gut_fauna_test_active(true)


func after_each() -> void:
	FaunaIntegration.set_gut_fauna_test_active(false)

const FaunaMotionScript = preload("res://src/presentation/fauna/fauna_motion.gd")


func _make_two_flower_env() -> FaunaEnvironment:
	var env := FaunaEnvironment.new()
	for pos in [Vector3(6.0, 0.0, 0.0), Vector3(9.0, 0.0, 2.0)]:
		var anchor := FaunaAnchor.new()
		anchor.kind = FaunaConstants.AnchorKind.FLOWER
		anchor.local_transform = Transform3D(Basis.IDENTITY, pos)
		anchor.hero_weight = 1.0
		env.anchors.append(anchor)
	return env


func test_bee_flies_between_flower_anchors() -> void:
	var env := _make_two_flower_env()
	var ctx := FaunaPresentationContext.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var agent = FaunaAgentStateScript.new()
	agent.species = FaunaConstants.Species.BEE
	agent.mesh = MeshInstance3D.new()
	FaunaMotionScript.init_agent(agent, FaunaConstants.Species.BEE, rng)
	FaunaMotionScript.begin_bee_at_flower(agent, 0, env, ctx.backdrop_global_transform, rng)
	agent.bee_linger_sec = 0.0
	agent.path_segment_u = 1.0
	var start: Vector3 = agent.mesh.position
	for _i in range(180):
		FaunaMotionScript.advance(
			agent, env, ctx, Vector3.ZERO, 1.0 / 60.0, rng, false, 8.0)
	var moved := start.distance_to(agent.mesh.position)
	assert_true(moved > 0.4, "bee should leave first flower toward another anchor")


func test_bee_cruise_speed_is_slow() -> void:
	var agent = FaunaAgentStateScript.new()
	agent.mesh = MeshInstance3D.new()
	var rng := RandomNumberGenerator.new()
	FaunaMotionScript.init_agent(agent, FaunaConstants.Species.BEE, rng)
	assert_true(agent.cruise_speed_mps <= FaunaConstants.BEE_CRUISE_SPEED_MPS + 0.1)
	assert_true(agent.cruise_speed_mps >= 0.25)


func test_butterfly_wing_flap_four_hz_with_twenty_percent() -> void:
	var fly = FaunaAgentStateScript.new()
	fly.species = FaunaConstants.Species.BUTTERFLY
	fly.mesh = MeshInstance3D.new()
	fly.wing_left = MeshInstance3D.new()
	fly.wing_right = MeshInstance3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	FaunaMotionScript.init_agent(fly, FaunaConstants.Species.BUTTERFLY, rng)
	assert_almost_eq(fly.wing_beat_hz, FaunaConstants.BUTTERFLY_WING_FLAP_HZ, 0.01)
	var env := _make_two_flower_env()
	var ctx := FaunaPresentationContext.new()
	var base := Vector3(7.0, 0.5, 1.0)
	var min_x := INF
	var max_x := -INF
	for _i in range(120):
		FaunaMotionScript.advance(fly, env, ctx, base, 1.0 / 60.0, rng, false, 8.0)
		var sx: float = absf(fly.wing_left.scale.x)
		min_x = minf(min_x, sx)
		max_x = maxf(max_x, sx)
	var expected_min := 1.0 - FaunaConstants.BUTTERFLY_WING_FLAP_AMPLITUDE
	var expected_max := 1.0 + FaunaConstants.BUTTERFLY_WING_FLAP_AMPLITUDE
	assert_true(min_x <= expected_min + 0.05)
	assert_true(max_x >= expected_max - 0.05)


func test_anchor_hover_y_above_ground_band() -> void:
	assert_true(FaunaMotionScript.anchor_hover_y(FaunaConstants.Species.BEE) > 0.45)
	assert_true(FaunaMotionScript.anchor_hover_y(FaunaConstants.Species.BUTTERFLY) > 0.45)


func test_butterfly_begin_at_flower_starts_flit_mode() -> void:
	var env := _make_two_flower_env()
	var ctx := FaunaPresentationContext.new()
	var rng := RandomNumberGenerator.new()
	var fly = FaunaAgentStateScript.new()
	fly.species = FaunaConstants.Species.BUTTERFLY
	fly.mesh = MeshInstance3D.new()
	FaunaMotionScript.init_agent(fly, FaunaConstants.Species.BUTTERFLY, rng)
	FaunaMotionScript.begin_butterfly_at_flower(fly, 0, env, ctx.backdrop_global_transform, rng)
	assert_eq(fly.butterfly_mode, FaunaAgentState.ButterflyMode.FLIT_AT_FLOWER)
	assert_true(fly.butterfly_linger_sec > 0.0)


func test_butterfly_to_flower_trip_advances_along_path() -> void:
	var env := _make_two_flower_env()
	var ctx := FaunaPresentationContext.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fly = FaunaAgentStateScript.new()
	fly.species = FaunaConstants.Species.BUTTERFLY
	fly.mesh = MeshInstance3D.new()
	add_child_autofree(fly.mesh)
	FaunaMotionScript.init_agent(fly, FaunaConstants.Species.BUTTERFLY, rng)
	FaunaMotionScript.begin_butterfly_at_flower(fly, 0, env, ctx.backdrop_global_transform, rng)
	fly.butterfly_linger_sec = 0.0
	fly.butterfly_mode = FaunaAgentState.ButterflyMode.TO_FLOWER
	fly.path_from = Vector3(6.0, 0.5, 0.0)
	fly.path_to = Vector3(9.0, 0.5, 2.0)
	fly.path_segment_u = 0.0
	var start: Vector3 = fly.path_from
	for _i in range(240):
		FaunaMotionScript.advance(
			fly, env, ctx, start, 1.0 / 60.0, rng, false, 8.0, [])
	assert_true(fly.path_segment_u >= 1.0 or fly.mesh.global_position.distance_to(start) > 0.5)


func test_butterfly_race_leader_moves_quickly() -> void:
	var env := _make_two_flower_env()
	var ctx := FaunaPresentationContext.new()
	var rng := RandomNumberGenerator.new()
	var fly = FaunaAgentStateScript.new()
	fly.species = FaunaConstants.Species.BUTTERFLY
	fly.mesh = MeshInstance3D.new()
	add_child_autofree(fly.mesh)
	FaunaMotionScript.init_agent(fly, FaunaConstants.Species.BUTTERFLY, rng)
	fly.mesh.global_position = Vector3(6.5, 0.5, 0.0)
	fly.butterfly_mode = FaunaAgentState.ButterflyMode.RACING
	fly.butterfly_race_dir_xz = Vector2(1.0, 0.0)
	fly.butterfly_race_sec = FaunaConstants.BUTTERFLY_RACE_DURATION_SEC
	var start: Vector3 = fly.mesh.global_position
	for _i in range(120):
		FaunaMotionScript.advance(
			fly, env, ctx, start, 1.0 / 60.0, rng, false, 8.0, [])
	assert_true(fly.mesh.global_position.distance_to(start) > 0.6)


func test_butterfly_race_end_schedules_flower_trip() -> void:
	var env := _make_two_flower_env()
	var ctx := FaunaPresentationContext.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var fly = FaunaAgentStateScript.new()
	fly.species = FaunaConstants.Species.BUTTERFLY
	fly.mesh = MeshInstance3D.new()
	add_child_autofree(fly.mesh)
	FaunaMotionScript.init_agent(fly, FaunaConstants.Species.BUTTERFLY, rng)
	FaunaMotionScript.begin_butterfly_at_flower(fly, 0, env, ctx.backdrop_global_transform, rng)
	fly.mesh.global_position = Vector3(6.5, 0.5, 0.0)
	fly.butterfly_mode = FaunaAgentState.ButterflyMode.RACING
	fly.butterfly_race_dir_xz = Vector2(0.0, 1.0)
	fly.butterfly_race_sec = 0.05
	for _i in range(30):
		FaunaMotionScript.advance(
			fly, env, ctx, Vector3(6.5, 0.5, 0.0), 1.0 / 60.0, rng, false, 8.0, [])
	assert_eq(fly.butterfly_mode, FaunaAgentState.ButterflyMode.TO_FLOWER)
	assert_true(fly.path_segment_u < 1.0)


func test_unlink_butterfly_partner_clears_both_sides() -> void:
	var a = FaunaAgentStateScript.new()
	var b = FaunaAgentStateScript.new()
	a.butterfly_partner = b
	b.butterfly_partner = a
	FaunaMotionScript.unlink_butterfly_partner(a)
	assert_null(a.butterfly_partner)
	assert_null(b.butterfly_partner)


func test_butterfly_chase_constants_match_design() -> void:
	assert_almost_eq(FaunaConstants.BUTTERFLY_CHASE_PROB, 0.25, 0.001)
	assert_almost_eq(FaunaConstants.BUTTERFLY_RACE_DURATION_SEC, 10.0, 0.001)
