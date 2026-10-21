## ivy-0bn — a stem that meanders down to the ground is turned back up, not retired.
##
## The ground used to be a flat clamp: a tip heading down at y = ground_y_min was held on the clamp
## plane, kept its downward heading, and struck out after five segments (DORMANT). Roughly one
## start seed in eight on the tower died this way after wandering down its own wall. The ground now
## behaves like the walls do — it deflects the heading — and a strike only counts while the tip is
## actually pinned (SD-GEO-4 says five CONSECUTIVE clamped segments; the counter was cumulative).
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
const GrowthStep = preload("res://src/sim/growth_step.gd")

var _params: IvyParams
var _surface: SurfaceQuery
var _ctx: SimContext
var _tips: TipManager
var _wall_point: Vector3
var _wall_normal: Vector3


func before_each() -> void:
	_params = IvyParams.new()
	var clock := SimClock.new(_params)
	var solar := Solar.new(_params)
	_surface = SurfaceQuery.new()
	_surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), _params)
	var env := IvyEnvironment.new()
	env.build(_params, _surface, solar)
	_tips = TipManager.new()
	_ctx = SimContext.new(_params, env, _surface, PlantData.new(), _tips, clock)
	var anchor := _surface.nearest(Vector3(0.0, 1.0, 0.0) + Conv.SOUTH * 8.0)
	_wall_point = anchor.position
	_wall_normal = anchor.normal


## A tip on the wall at `height`, pointing along `heading`.
func _tip_at(height: float, heading: Vector3) -> Tip:
	var pos := Vector3(_wall_point.x, height, _wall_point.z) + _wall_normal * 0.005
	var tip := _tips.add_seed(pos, _wall_normal, 1, _params)
	tip.direction = heading.normalized()
	tip.random_dir = heading.normalized()
	return tip


func test_tip_heading_down_at_the_ground_is_turned_upward() -> void:
	var tip := _tip_at(_params.ground_y_min, Vector3.DOWN)
	GrowthStep.step_tip(tip, _ctx)
	assert_gt(tip.position.y, _params.ground_y_min, "the step must lift off the ground, not slide along it")
	assert_gt(tip.direction.y, -0.3, "heading must no longer point into the ground, got %s" % tip.direction)


func test_ground_contact_never_puts_a_point_below_the_clamp() -> void:
	var tip := _tip_at(_params.ground_y_min + 0.01, Vector3.DOWN)
	for _i in 4:
		GrowthStep.step_tip(tip, _ctx)
		assert_gte(tip.position.y, _params.ground_y_min - 1e-6)


func test_strikes_count_only_consecutive_ground_segments() -> void:
	var tip := _tip_at(1.0, Vector3.UP)
	tip.ground_strikes = 4
	GrowthStep.step_tip(tip, _ctx)
	assert_eq(tip.ground_strikes, 0, "a step well clear of the ground resets the strike count")


func test_a_ground_hit_still_counts_as_a_strike() -> void:
	var tip := _tip_at(_params.ground_y_min, Vector3.DOWN)
	GrowthStep.step_tip(tip, _ctx)
	assert_eq(tip.ground_strikes, 1)


func test_five_consecutive_strikes_still_retire_a_tip() -> void:
	# The backstop stays: a tip that really is pinned against the ground is still retired.
	var tip := _tip_at(_params.ground_y_min, Vector3.DOWN)
	tip.ground_strikes = 5
	tip.position.y = _params.ground_y_min
	_tips.apply_lifecycle(_ctx)
	assert_eq(tip.state, Tip.State.DORMANT)
