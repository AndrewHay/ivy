## AS-4 (simulation half), SD-RNG-5 — Two independent runs from the same seed must
## produce bit-identical simulation outputs.
##
## Written for W-042 as one of the two guards M3 stresses.  The dev tuning overlay
## mutates parameters at runtime, and any parameter edit that accidentally introduces
## a stray random call (e.g. by bypassing the per-tip RngStream) would silently break
## determinism.  This test locks that invariant before M3 lands.
##
## Two completely independent simulation objects are constructed from the same seed,
## run for TICKS_5_DAYS ticks each, and compared for: segment count, leaf count,
## bit-identical total stem length, total tip count, and per-tip **growth-step**
## stream draw count for the root tip (branch + correlated-random draws only —
## LeafPlacer is hash-based per SD-RNG-6 and consumes no stream).  Exact equality
## only — not assert_almost_eq.  A tolerance here would
## turn this into a Lyapunov divergence meter, which is the class defect that
## invalidated the W-049 AS-3(b) instrument and is explicitly forbidden by the
## standing rule in the AS-4 row (DESIGN.md § SD-OPEN-12).
##
## Mutation evidence (determinism test must be able to fail):
##   Mutation applied:  In src/sim/growth_step.gd, line ~78, replaced
##     `if tip.stream.randf() < p_b * branch_q:`
##   with
##     `if randf() < p_b * branch_q:`
##   The stray `randf()` draws from the process-global RNG, which is in a different
##   state when run_b begins (run_a advanced it by several hundred draws).  At least
##   one branch check fires differently → tip counts diverge → test fails.
##   Failure seen: "segment count must be identical … expected <N>, got <M> (SD-RNG-5)"
##   Mutation reverted before shipping.
extends GutTest

const IvyParams = preload("res://src/params/ivy_params.gd")
const SimClock = preload("res://src/core/sim_clock.gd")
const Solar = preload("res://src/env/solar.gd")
const IvyEnvironment = preload("res://src/env/environment.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const TipManager = preload("res://src/sim/tip_manager.gd")
const SimContext = preload("res://src/sim/sim_context.gd")
const Physiology = preload("res://src/sim/physiology.gd")
const GrowthStep = preload("res://src/sim/growth_step.gd")

## The fixed seed used by SimRoot._seed_m1() and by this test.  The test does not
## pick a special seed — it uses the same south-anchor seed the acceptance harness
## will use, so a determinism failure here is a real harness failure.
const SEED := 12345

## Five game-days = 120 ticks.  Short enough to finish in < 2 s on a laptop;
## long enough for several branch events (branching probability ~0.05/segment
## gives ~24 expected events in 480 segments), which makes the growth-step
## stream draw-count comparison meaningful rather than vacuous.
const TICKS_5_DAYS := 5 * 24


## Builds one completely independent simulation from scratch.
## Uses a null PhysicsDirectSpaceState3D (no raycasts; SurfaceQuery falls back to
## the analytic SDF) so the environment bake and every tick run purely in GDScript
## without the physics server — the same pattern used in test_leaf_placement.gd.
func _build_sim() -> Dictionary:
	var params := IvyParams.new()
	var clock := SimClock.new(params)
	var solar := Solar.new(params)
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), params)
	var env := IvyEnvironment.new()
	env.build(params, surface, solar)
	var plant := PlantData.new()
	var tips := TipManager.new()
	var ctx := SimContext.new(params, env, surface, plant, tips, clock)
	# Mirror SimRoot._seed_m1(): probe outward from the south face (SD-AGENCY-1)
	# and stand the seed 0.01 m proud of the wall (SD-AGENCY-4).
	var probe := Vector3(0.0, params.ground_y_min, 0.0) + Conv.SOUTH * 8.0
	var anchor := surface.nearest(probe)
	var pos := anchor.position + anchor.normal * 0.01
	tips.add_seed(pos, anchor.normal, SEED, params)
	return {
		"params": params, "clock": clock, "solar": solar,
		"env": env, "plant": plant, "tips": tips, "ctx": ctx,
	}


## Replicates SimRoot._tick() exactly, advancing `n` ticks.
## Order of operations must match SimRoot._tick() because `apply_lifecycle` reads
## `ctx.clock.tick_index` before `clock.advance_ticks(1)` increments it —
## the same ordering that makes the SD-TIP stall rule (W-040) correct.
func _run_for_ticks(d: Dictionary, n: int) -> void:
	var params: IvyParams = d.params
	var clock: SimClock = d.clock
	var solar: Solar = d.solar
	var env: IvyEnvironment = d.env
	var tips: TipManager = d.tips
	var ctx: SimContext = d.ctx
	for _i in range(n):
		env.tick(clock.dt_sim(), clock.game_day)
		var g_hat := solar.diel_gate(clock.game_day)
		tips.refresh_vigour(ctx)
		for tip in tips.live_in_id_order():
			Physiology.accumulate_budget(tip, g_hat, ctx)
			var emitted := 0
			while (tip.growth_budget >= params.segment_length
					and emitted < params.max_segments_per_tick):
				GrowthStep.step_tip(tip, ctx)
				tip.growth_budget -= params.segment_length
				emitted += 1
		tips.apply_pending_branches()
		tips.apply_lifecycle(ctx)
		clock.advance_ticks(1)


func test_two_identical_seed_runs_produce_identical_outputs() -> void:
	# AS-4 (simulation half): two genuinely independent runs from the same seed must
	# converge to the same plant — bit for bit, not within a tolerance.
	#
	# The runs are independent: different params, clock, env, plant, tips objects.
	# The only shared state is the process-global RNG, which correct simulation code
	# never draws from (INV-7).  If it does, run_b gets a different global RNG state
	# (run_a advanced it), and at least one branch check fires differently, giving
	# different segment/leaf/tip counts.
	var run_a := _build_sim()
	var run_b := _build_sim()
	_run_for_ticks(run_a, TICKS_5_DAYS)
	_run_for_ticks(run_b, TICKS_5_DAYS)

	var plant_a: PlantData = run_a.plant
	var plant_b: PlantData = run_b.plant
	var tips_a: TipManager = run_a.tips
	var tips_b: TipManager = run_b.tips

	# Sanity guard: a run that produced nothing would make equality vacuous.
	assert_gt(plant_a.segment_count(), 0,
		"run_a must produce at least one segment in %d ticks" % TICKS_5_DAYS)
	assert_gt(plant_a.leaf_count(), 0,
		"run_a must produce at least one leaf in %d ticks" % TICKS_5_DAYS)

	assert_eq(plant_a.segment_count(), plant_b.segment_count(),
		"segment count must be identical across runs (SD-RNG-5)")
	assert_eq(plant_a.leaf_count(), plant_b.leaf_count(),
		"leaf count must be identical across runs (SD-RNG-5)")
	# total_length is a float64 accumulator (PlantData.total_length: float).
	# assert_eq on floats tests bit identity; any stray random draw that changes
	# WHEN a per-metre event fires will shift total_length by at least one segment_length.
	assert_eq(plant_a.total_length, plant_b.total_length,
		"total stem length must be bit-identical across runs (SD-RNG-5)")
	assert_eq(tips_a.tips.size(), tips_b.tips.size(),
		"total tip count (including dead/dormant) must be identical across runs")
	# Growth-step stream draw count for the root tip confirms GrowthStep advanced
	# each tip.stream exactly the same number of times (SD-RNG-1).  LeafPlacer
	# takes no stream draws (SD-RNG-6) — this assertion does not cover leaf hashing.
	assert_eq(
		tips_a.tips[0].stream.draw_count(),
		tips_b.tips[0].stream.draw_count(),
		"root-tip stream draw count must be identical across runs (SD-RNG-5)"
	)
