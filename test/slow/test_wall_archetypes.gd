## Per-archetype scalar metric band regression tests (ivy-agc / ivy-68j).
##
## Runs the full three-pole simulation (dense≈400 days, mid+sparse≈150 days)
## headlessly and asserts measured bands from ivy-v4a / ivy-50f. A failure here
## means a parameter or mechanic change shifted a preset outside its allowed range.
##
## SLOW — dense alone is ~9–13 minutes wall-clock (day-400, ~320k segments).
## Excluded from the fast suite by living in test/slow/.
##
## Band values: copied exactly from ivy-v4a notes — do not approximate or widen.
##
## Sparse tip_live note: sparse legitimately reaches 0–8 live tips (near-terminal
## survival at raised seed height); we assert [0, 30] — do NOT assert live > 0.
extends GutTest

const Wall = preload("res://src/world/wall.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")
const WallSdf = preload("res://src/world/wall_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const Conv = preload("res://src/core/conv.gd")
const ArchetypePreset = preload("res://src/params/archetype_preset.gd")
const WallCoverageMetric = preload("res://src/metrics/wall_coverage.gd")

const TICKS_PER_DAY := 24


# ── Shared helper ──────────────────────────────────────────────────────────

## Build a headless Wall+SurfaceQuery+SimRoot for the given preset.
## auto_seed=false so we use preset.seed_positions() deterministically.
func _make_sim_for(preset: ArchetypePreset, spec: WallSpec) -> SimRoot:
	var wall := Wall.new()
	add_child_autofree(wall)
	wall.build_from_spec(spec, true)

	var params := preset.build_params()
	var sq := SurfaceQuery.new()
	sq.setup(
		wall.get_world_3d().direct_space_state,
		wall,
		WallSdf.new(spec),
		wall.face_material,
		params
	)
	var sim := SimRoot.new()
	sim.setup(params, sq, null, 0, null, false)  # auto_seed=false
	return sim


## Seed the sim from preset positions and advance to preset.day.
## Returns the populated sim; caller owns it and must free if needed.
func _run_preset(preset: ArchetypePreset, spec: WallSpec) -> SimRoot:
	# _make_sim_for is a plain function (no coroutine / await inside it).
	# M-2 fix (ivy-6bq): removed the redundant `await` that was a lint smell.
	var sim := _make_sim_for(preset, spec)
	await get_tree().physics_frame

	for pos: Vector3 in preset.seed_positions(spec):
		sim.plant_at(pos, Conv.SOUTH)

	var t0 := Time.get_ticks_msec()
	sim.advance_ticks(TICKS_PER_DAY * preset.day)
	var elapsed := Time.get_ticks_msec() - t0
	print("[test_wall_archetypes] %s: day=%d elapsed_ms=%d segs=%d leaves=%d"
		% [preset.label, preset.day, elapsed,
		   sim.plant.segment_count(), sim.plant.leaf_count()])
	return sim


## Max branch_order across all tips.
func _max_branch_order(sim: SimRoot) -> int:
	var mx := 0
	for t in sim.tips.tips:
		if t.branch_order > mx:
			mx = t.branch_order
	return mx


## Fraction of tips (all, live and dormant) with branch_order == 0.
func _frac_order0(sim: SimRoot) -> float:
	var total := sim.tips.tips.size()
	if total == 0:
		return 0.0
	var n0 := 0
	for t in sim.tips.tips:
		if t.branch_order == 0:
			n0 += 1
	return float(n0) / float(total)


# ── Sparse (seed_y=1.5, day=150) ──────────────────────────────────────────
# Bands from ivy-v4a (measured on deterministic run):
#   coverage_pct [0.5, 6.0]
#   total_length [80, 400] m
#   leaf_count   [700, 5000]
#   tips_live    [0, 30]      — do NOT assert > 0 (sparse may reach 0–8)
#   max_branch_order <= 10
#   frac_order0  >= 8%
func test_sparse_bands() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var preset := ArchetypePreset.for_name("sparse")
	var sim := await _run_preset(preset, spec)
	var params := preset.build_params()
	var m := WallCoverageMetric.new().measure(sim.plant, spec)

	var cov:    float = m["overall_pct"]
	var length: float = sim.plant.total_length
	var leaves: int   = sim.plant.leaf_count()
	var live:   int   = sim.tips.live_count()
	var mbo:    int   = _max_branch_order(sim)
	var fo0:    float = _frac_order0(sim)

	print("[test_wall_archetypes] sparse: cov=%.2f%% length=%.1f leaves=%d live=%d max_order=%d frac_order0=%.1f%%"
		% [cov, length, leaves, live, mbo, fo0 * 100.0])

	assert_true(cov >= 0.5  and cov <= 6.0,
		"sparse coverage_pct=%.3f must be in [0.5, 6.0]" % cov)
	assert_true(length >= 80.0 and length <= 400.0,
		"sparse total_length=%.1f must be in [80, 400]" % length)
	assert_true(leaves >= 700 and leaves <= 5000,
		"sparse leaf_count=%d must be in [700, 5000]" % leaves)
	assert_true(live >= 0 and live <= 30,
		"sparse tips_live=%d must be in [0, 30]" % live)
	assert_true(mbo <= 10,
		"sparse max_branch_order=%d must be <= 10" % mbo)
	assert_true(fo0 >= 0.08,
		"sparse frac_order0=%.3f must be >= 0.08 (8%%)" % fo0)
	assert_true(leaves < params.leaf_cap,
		"sparse leaf_count=%d must be < leaf_cap=%d (no MultiMesh overflow)" % [leaves, params.leaf_cap])


# ── Mid (seed_y=0.02, day=150) ────────────────────────────────────────────
# Bands from ivy-v4a (measured on deterministic run):
#   coverage_pct    [12, 50]
#   total_length    [700, 2800] m
#   leaf_count      [9000, 40000]
#   tips_live       [60, 200]
#   max_branch_order [10, 24]
#   stem_bucket_pct [22, 65]
func test_mid_bands() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var preset := ArchetypePreset.for_name("mid")
	var sim := await _run_preset(preset, spec)
	var params := preset.build_params()
	var m := WallCoverageMetric.new().measure(sim.plant, spec)

	var cov:    float = m["overall_pct"]
	var stem:   float = m["stem_bucket_pct"]
	var length: float = sim.plant.total_length
	var leaves: int   = sim.plant.leaf_count()
	var live:   int   = sim.tips.live_count()
	var mbo:    int   = _max_branch_order(sim)

	print("[test_wall_archetypes] mid: cov=%.2f%% stem=%.2f%% length=%.1f leaves=%d live=%d max_order=%d"
		% [cov, stem, length, leaves, live, mbo])

	assert_true(cov >= 12.0 and cov <= 50.0,
		"mid coverage_pct=%.3f must be in [12, 50]" % cov)
	assert_true(length >= 700.0 and length <= 2800.0,
		"mid total_length=%.1f must be in [700, 2800]" % length)
	assert_true(leaves >= 9000 and leaves <= 40000,
		"mid leaf_count=%d must be in [9000, 40000]" % leaves)
	assert_true(live >= 60 and live <= 200,
		"mid tips_live=%d must be in [60, 200]" % live)
	assert_true(mbo >= 10 and mbo <= 24,
		"mid max_branch_order=%d must be in [10, 24]" % mbo)
	assert_true(stem >= 22.0 and stem <= 65.0,
		"mid stem_bucket_pct=%.3f must be in [22, 65]" % stem)
	assert_true(leaves < params.leaf_cap,
		"mid leaf_count=%d must be < leaf_cap=%d (no MultiMesh overflow)" % [leaves, params.leaf_cap])


# ── Dense (seed_y=0.02, day=400 — FROZEN preset) ─────────────────────────
# Bands from ivy-v4a (measured on deterministic run):
#   coverage_pct     [80, 100]
#   total_length     [6500, 12000] m
#   leaf_count       [130000, 260000]
#   tips_live        [150, 400]
#   max_branch_order >= 22
#   stem_bucket_pct  [90, 100]
func test_dense_bands() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var preset := ArchetypePreset.for_name("dense")
	var sim := await _run_preset(preset, spec)
	var params := preset.build_params()
	var m := WallCoverageMetric.new().measure(sim.plant, spec)

	var cov:    float = m["overall_pct"]
	var stem:   float = m["stem_bucket_pct"]
	var length: float = sim.plant.total_length
	var leaves: int   = sim.plant.leaf_count()
	var live:   int   = sim.tips.live_count()
	var mbo:    int   = _max_branch_order(sim)

	print("[test_wall_archetypes] dense: cov=%.2f%% stem=%.2f%% length=%.1f leaves=%d live=%d max_order=%d"
		% [cov, stem, length, leaves, live, mbo])

	assert_true(cov >= 80.0 and cov <= 100.0,
		"dense coverage_pct=%.3f must be in [80, 100]" % cov)
	assert_true(length >= 6500.0 and length <= 12000.0,
		"dense total_length=%.1f must be in [6500, 12000]" % length)
	assert_true(leaves >= 130000 and leaves <= 260000,
		"dense leaf_count=%d must be in [130000, 260000]" % leaves)
	assert_true(live >= 150 and live <= 400,
		"dense tips_live=%d must be in [150, 400]" % live)
	assert_true(mbo >= 22,
		"dense max_branch_order=%d must be >= 22" % mbo)
	assert_true(stem >= 90.0 and stem <= 100.0,
		"dense stem_bucket_pct=%.3f must be in [90, 100]" % stem)
	assert_true(leaves < params.leaf_cap,
		"dense leaf_count=%d must be < leaf_cap=%d (no MultiMesh overflow)" % [leaves, params.leaf_cap])
