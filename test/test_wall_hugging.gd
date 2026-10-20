## ivy-p73 — a stem that is touching the tower must stay touching it.
##
## On the analytic tower, a tip's outward wander (initial 0.15 outward lean, correlated random
## draws, and direction memory feeding the drift back in) outran the weak adhesion pull. Once the
## tip was a hair past `contact_distance` it was FLOATING, gravity took over, and it fell to the
## ground and died: about half of all start seeds never grew. The fix is the same post-placement
## snap the mesh backend already had (SD-MESH-7), extended to the tower.
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
	# Null physics space: no raycasts, so this isolates the adhesion/snap logic.
	_surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), _params)
	var env := IvyEnvironment.new()
	env.build(_params, _surface, solar)
	_tips = TipManager.new()
	_ctx = SimContext.new(_params, env, _surface, PlantData.new(), _tips, clock)
	var anchor := _surface.nearest(Vector3(0.0, 1.0, 0.0) + Conv.SOUTH * 8.0)
	_wall_point = anchor.position
	_wall_normal = anchor.normal


## A tip standing `gap` metres off the wall, heading straight out into the air.
func _tip_off_wall(gap: float) -> Tip:
	var tip := _tips.add_seed(_wall_point + _wall_normal * gap, _wall_normal, 1, _params)
	tip.direction = _wall_normal
	tip.random_dir = _wall_normal
	return tip


func test_attached_tip_heading_outward_stays_attached() -> void:
	var tip := _tip_off_wall(0.015)
	GrowthStep.step_tip(tip, _ctx)
	assert_eq(tip.state, Tip.State.GROWING, "a stem that was touching the wall must not detach in one segment")
	assert_eq(tip.floating_length, 0.0)
	var gap := _surface.nearest(tip.position).distance
	assert_lte(gap, _params.contact_distance, "new endpoint must be within contact distance, got %.4f m" % gap)


func test_snapped_tip_is_a_skin_off_the_wall_not_on_the_plane() -> void:
	# A tip left exactly on the face plane casts its next collision ray from behind the face,
	# which back-face culling misses (ivy-2d6).
	var tip := _tip_off_wall(0.015)
	GrowthStep.step_tip(tip, _ctx)
	var gap := _surface.nearest(tip.position).distance
	assert_lte(gap, _params.contact_distance, "tip must still be attached after the step")
	assert_gt(gap, 1e-4, "snap must leave a skin between the tip and the face")
	var outward := (tip.position - _wall_point).dot(_wall_normal)
	assert_gt(outward, 0.0, "snapped tip must be on the outside of the wall")


func test_tip_far_from_wall_is_not_pulled_back() -> void:
	# Beyond the adhesion range there is nothing to cling to; the float counter must run.
	var tip := _tip_off_wall(_params.adhesion_range + 0.1)
	GrowthStep.step_tip(tip, _ctx)
	assert_eq(tip.state, Tip.State.FLOATING)
	assert_gt(tip.floating_length, 0.0)


func test_floating_tip_is_not_snapped_back_by_a_single_step() -> void:
	# Only a tip that WAS attached is rescued. One that already floated keeps floating, so
	# eave danglers and feelers still behave as before.
	var tip := _tip_off_wall(0.06)
	GrowthStep.step_tip(tip, _ctx)
	assert_eq(tip.state, Tip.State.FLOATING)
