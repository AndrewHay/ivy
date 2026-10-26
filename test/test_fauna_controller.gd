extends GutTest

const FaunaControllerScript = preload("res://src/presentation/fauna/fauna_controller.gd")


func before_each() -> void:
	FaunaIntegration.set_gut_fauna_test_active(true)


func after_each() -> void:
	FaunaIntegration.set_gut_fauna_test_active(false)

const FaunaMotionScript = preload("res://src/presentation/fauna/fauna_motion.gd")


func _garden_env() -> FaunaEnvironment:
	var env := FaunaEnvironment.new()
	for i in range(8):
		var angle := (float(i) / 8.0) * TAU
		var pos := Vector3(6.55 + cos(angle) * 0.9, 0.0, 0.05 + sin(angle) * 0.9)
		var anchor := FaunaAnchor.new()
		anchor.kind = FaunaConstants.AnchorKind.FLOWER
		anchor.local_transform = Transform3D(Basis.IDENTITY, pos)
		anchor.hero_weight = 1.0
		env.anchors.append(anchor)
	return env


func _ctx() -> FaunaPresentationContext:
	var ctx := FaunaPresentationContext.new()
	ctx.lit = 1.0
	ctx.local_solar_hour = 11.0
	ctx.backdrop_global_transform = Transform3D.IDENTITY
	return ctx


func _controller(uncapped: bool) -> FaunaController:
	var fc: FaunaController = FaunaControllerScript.new()
	fc.uncapped_population = uncapped
	fc.ambient_spawn_enabled = false
	fc.console_log = false
	add_child_autofree(fc)
	fc.bind_environment(_garden_env(), null, "test")
	return fc


func test_spawn_at_hover_increments_species_count() -> void:
	var fc := _controller(true)
	var ctx := _ctx()
	assert_eq(fc.count_species(FaunaConstants.Species.BEE), 0)
	assert_true(fc.spawn_at_hover_local(FaunaConstants.Species.BEE, ctx, Vector2(6.5, 0.0)))
	assert_eq(fc.count_species(FaunaConstants.Species.BEE), 1)


func test_despawn_one_decrements_species_count() -> void:
	var fc := _controller(true)
	var ctx := _ctx()
	fc.spawn_at_hover_local(FaunaConstants.Species.BUTTERFLY, ctx, Vector2(6.6, 0.1))
	fc.spawn_at_hover_local(FaunaConstants.Species.BUTTERFLY, ctx, Vector2(6.7, 0.2))
	assert_eq(fc.count_species(FaunaConstants.Species.BUTTERFLY), 2)
	assert_true(fc.despawn_one(FaunaConstants.Species.BUTTERFLY))
	assert_eq(fc.count_species(FaunaConstants.Species.BUTTERFLY), 1)


func test_uncapped_allows_more_than_default_butterfly_cap() -> void:
	var fc := _controller(true)
	var ctx := _ctx()
	for _i in range(FaunaConstants.MAX_BUTTERFLY + 2):
		assert_true(fc.spawn_at_hover_local(FaunaConstants.Species.BUTTERFLY, ctx, Vector2(6.5, 0.0)))
	assert_eq(fc.count_species(FaunaConstants.Species.BUTTERFLY), FaunaConstants.MAX_BUTTERFLY + 2)


func test_capped_stops_at_butterfly_max() -> void:
	var fc := _controller(false)
	var ctx := _ctx()
	var spawned := 0
	for _i in range(FaunaConstants.MAX_BUTTERFLY + 4):
		if fc.spawn_at_hover_local(FaunaConstants.Species.BUTTERFLY, ctx, Vector2(6.5, 0.0)):
			spawned += 1
	assert_eq(spawned, FaunaConstants.MAX_BUTTERFLY)
	assert_eq(fc.count_species(FaunaConstants.Species.BUTTERFLY), FaunaConstants.MAX_BUTTERFLY)


func test_prefill_respects_counts_when_uncapped() -> void:
	var fc := _controller(true)
	var ctx := _ctx()
	fc.prefill_agents(3, 5, ctx)
	assert_eq(fc.count_species(FaunaConstants.Species.BEE), 3)
	assert_eq(fc.count_species(FaunaConstants.Species.BUTTERFLY), 5)


func test_get_active_agent_count_matches_spawns() -> void:
	var fc := _controller(true)
	var ctx := _ctx()
	fc.spawn_at_hover_local(FaunaConstants.Species.BEE, ctx, Vector2(6.5, 0.0))
	fc.spawn_at_hover_local(FaunaConstants.Species.BUTTERFLY, ctx, Vector2(6.6, 0.0))
	assert_eq(fc.get_active_agent_count(), 2)
