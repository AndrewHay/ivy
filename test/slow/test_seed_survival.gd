## ivy-p73 — start seeds on the canonical tower must not die in the first days.
##
## Before the fix, 10 of 17 seeds on the south anchor ended with 18-600 segments. These three
## were among the fatal ones (777 and 2024 died by day 10); each must now still be growing and
## have built a real plant by day 30. Only the tip stream seed differs from AS-1.
extends GutTest

const Tower = preload("res://src/world/tower.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const SeedAnchors = preload("res://src/world/seed_anchors.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const SimClock = preload("res://src/core/sim_clock.gd")

const SOUTH := 2
const FORMERLY_FATAL_SEEDS := [777, 2024, 101]
const MIN_SEGMENTS_DAY_30 := 500

var _tower: Node
var _sq: SurfaceQuery
var _anchors: SeedAnchors


func before_all() -> void:
	_tower = Tower.new()
	add_child(_tower)
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	_tower.build_from_spec(spec, true)
	await get_tree().physics_frame
	var params := load("res://src/params/ivy_params_default.tres") as IvyParams
	_sq = SurfaceQuery.new()
	_sq.setup(
		_tower.get_world_3d().direct_space_state, _tower, TowerSdf.new(spec), _tower.face_material, params
	)
	_anchors = SeedAnchors.new()
	_anchors.build(_sq, spec)


func after_all() -> void:
	_tower.queue_free()


func _grow(stream_seed: int) -> SimRoot:
	var params := load("res://src/params/ivy_params_default.tres") as IvyParams
	var sim := SimRoot.new()
	add_child_autofree(sim)
	sim.setup(params, _sq, null, SOUTH, _anchors, false)
	var anchor = _anchors.get_anchors()[SOUTH]
	sim.tips.add_seed(anchor.position, anchor.normal, stream_seed, params)
	sim.advance_ticks(SimClock.ticks_for_game_days(30.0, SimClock.Speed.NORMAL))
	return sim


## ivy-0bn: these two stayed on the wall but wandered down it and struck out on the ground
## (DORMANT at day 8-9, 29-35 segments). They are slow starters, so the bar is "alive and
## visibly growing", not the 500 segments the others reach.
func test_seeds_that_wandered_into_the_ground_survive_day_30() -> void:
	for stream_seed in [100, 42]:
		var sim := _grow(stream_seed)
		var live := 0
		for tip in sim.tips.tips:
			if tip.is_live():
				live += 1
		assert_gt(live, 0, "seed %d: no live tips at day 30" % stream_seed)
		assert_gt(
			sim.plant.segment_count(), 100,
			"seed %d: only %d segments at day 30" % [stream_seed, sim.plant.segment_count()]
		)


func test_formerly_fatal_seeds_are_alive_and_growing_at_day_30() -> void:
	for stream_seed in FORMERLY_FATAL_SEEDS:
		var sim := _grow(stream_seed)
		var live := 0
		for tip in sim.tips.tips:
			if tip.is_live():
				live += 1
		assert_gt(live, 0, "seed %d: no live tips at day 30" % stream_seed)
		assert_gt(
			sim.plant.segment_count(), MIN_SEGMENTS_DAY_30,
			"seed %d: only %d segments at day 30" % [stream_seed, sim.plant.segment_count()]
		)
