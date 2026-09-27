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
	# ivy-8so (2026-09-27): floors revised 90/50 -> 85/55 (overall unchanged at 70; see DESIGN.md
	# AS-1 for the arithmetic). SD-ENV-11's opening-footprint snap in project_to_shell (added by
	# 8e27147) is a deliberate, tested fix for degenerate D_L/gradient sampling at the tower's
	# door/window, and LightBake.compute_coarse_cell reuses that same projection for coarse-grid
	# ray origins -- the correctness fix permanently redistributes ~5pp of coverage from the
	# sun half to the shade half. Not a regression; see ivy-8so notes for the bisection.
	assert_gte(cov.sun_half_pct, 85.0, "AS-1 sun-half coverage at day 150 (ivy-bax / ivy-8so)")
	assert_gte(cov.shade_half_pct, 55.0, "AS-1 shade-half coverage at day 150 (ivy-bax / ivy-8so)")
