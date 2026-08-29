## ivy-bax — AS-1 south-seed coverage floors at day 150 (canonical tower).
extends GutTest

const Tower = preload("res://src/world/tower.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const SeedAnchors = preload("res://src/world/seed_anchors.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const CoverageMetric = preload("res://src/metrics/coverage.gd")

const TICKS_150_DAYS := 150 * 24
const SOUTH_AZIMUTH_DEG := 180.0


func _tower_sim_south() -> SimRoot:
	var tower := Tower.new()
	add_child_autofree(tower)
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	tower.build_from_spec(spec, true)
	await get_tree().physics_frame
	var params := load("res://src/params/ivy_params_default.tres") as IvyParams
	var sq := SurfaceQuery.new()
	sq.setup(
		tower.get_world_3d().direct_space_state,
		tower,
		TowerSdf.new(spec),
		tower.face_material,
		params
	)
	var anchors := SeedAnchors.new()
	anchors.build(sq, spec)
	var sim := SimRoot.new()
	add_child_autofree(sim)
	sim.setup(params, sq, null, 2, anchors)
	return sim


func test_as1_south_seed_day150_coverage_floors() -> void:
	var sim := await _tower_sim_south()
	sim.advance_ticks(TICKS_150_DAYS)
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var params := load("res://src/params/ivy_params_default.tres") as IvyParams
	var metric := CoverageMetric.new()
	metric.setup(spec, params)
	var cov: Dictionary = metric.measure(sim.plant, SOUTH_AZIMUTH_DEG)
	assert_gte(cov.overall_pct, 70.0, "AS-1 overall coverage at day 150 (ivy-bax)")
	assert_gte(cov.sun_half_pct, 90.0, "AS-1 sun-half coverage at day 150 (ivy-bax)")
	assert_gte(cov.shade_half_pct, 50.0, "AS-1 shade-half coverage at day 150 (ivy-bax)")
