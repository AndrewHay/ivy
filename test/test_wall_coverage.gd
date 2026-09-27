## Fast unit tests for WallCoverageMetric (ivy-agc).
## Uses synthetic PlantData to avoid a real simulation run.
extends GutTest

const WallCoverageMetric = preload("res://src/metrics/wall_coverage.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")


# ── Helpers ────────────────────────────────────────────────────────────────

## Add a leaf whose XY origin is at (ox, oy).
func _add_leaf_at(plant: PlantData, ox: float, oy: float) -> void:
	var xform := Transform3D(Basis.IDENTITY, Vector3(ox, oy, 0.01))
	plant.append_leaf(xform, Color.WHITE, Vector4.ZERO, 0, 0.0, 0.0, 0.0)


## Add a segment whose midpoint is at (mx, my).
func _add_seg_at(plant: PlantData, mx: float, my: float) -> void:
	var a := Vector3(mx - 0.01, my, 0.01)
	var b := Vector3(mx + 0.01, my, 0.01)
	plant.append_segment(a, b, Vector3.BACK, 0, 0, 0.0)


# ── ref_leaf_area() ────────────────────────────────────────────────────────

func test_ref_leaf_area_approx_0_003392() -> void:
	var area := WallCoverageMetric.ref_leaf_area()
	assert_almost_eq(area, 0.003392, 1e-5,
		"ref_leaf_area() should be ~0.003392 m² (alpha_fill*0.075²/aspect for 'a')")


# ── Empty plant ────────────────────────────────────────────────────────────

func test_empty_plant_returns_zero_pct() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var plant := PlantData.new()
	var m := WallCoverageMetric.new().measure(plant, spec)
	assert_almost_eq(m["overall_pct"], 0.0, 1e-9,
		"empty plant must return 0% coverage")


# ── total_buckets ──────────────────────────────────────────────────────────

func test_total_buckets_matches_grid_for_default_spec() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var plant := PlantData.new()
	var m := WallCoverageMetric.new().measure(plant, spec)
	var nx := ceili(spec.length / WallCoverageMetric.CELL)
	var ny := ceili(spec.height / WallCoverageMetric.CELL)
	assert_eq(m["total_buckets"], nx * ny,
		"total_buckets must equal nx*ny (200*100=20000 for 20x10 wall)")


# ── Single leaf in a bucket — uncovered ───────────────────────────────────

func test_single_leaf_bucket_uncovered() -> void:
	# ref_leaf_area ≈ 0.003392 < threshold 0.005 => should NOT be covered
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var plant := PlantData.new()
	_add_leaf_at(plant, 0.0, 0.05)  # bucket (100, 0) — well within bounds
	var m := WallCoverageMetric.new().measure(plant, spec)
	assert_eq(m["covered_buckets"], 0,
		"one leaf (area %.6f) < threshold 0.005 — bucket must be uncovered" \
		% WallCoverageMetric.ref_leaf_area())


# ── Two leaves in the same bucket — covered ───────────────────────────────

func test_two_leaves_same_bucket_covered() -> void:
	# 2 × 0.003392 = 0.006784 >= threshold 0.005 => covered
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var plant := PlantData.new()
	_add_leaf_at(plant, 0.0, 0.05)
	_add_leaf_at(plant, 0.02, 0.05)  # same bucket (100, 0)
	var m := WallCoverageMetric.new().measure(plant, spec)
	assert_eq(m["covered_buckets"], 1,
		"two leaves in the same bucket must cover it")
	assert_almost_eq(m["overall_pct"], 100.0 / float(m["total_buckets"]), 1e-6,
		"overall_pct should be exactly 1/total_buckets * 100")


# ── Out-of-bounds leaves are dropped ──────────────────────────────────────

func test_out_of_bounds_leaves_dropped() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var plant := PlantData.new()
	# x > half_len (10.0) — outside wall
	_add_leaf_at(plant, 25.0, 5.0)
	# y < 0 — below wall
	_add_leaf_at(plant, 0.0, -1.0)
	# y > height (10.0) — above wall
	_add_leaf_at(plant, 0.0, 15.0)
	var m := WallCoverageMetric.new().measure(plant, spec)
	assert_eq(m["covered_buckets"], 0,
		"out-of-bounds leaves must not contribute to coverage")
	assert_almost_eq(m["overall_pct"], 0.0, 1e-9)


# ── Stem diagnostic ────────────────────────────────────────────────────────

func test_stem_bucket_pct_reflects_segment_midpoints() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var plant := PlantData.new()
	# Midpoint at (0.0, 0.05) → bucket (100, 0)
	_add_seg_at(plant, 0.0, 0.05)
	var m := WallCoverageMetric.new().measure(plant, spec)
	var expected_stem_pct := 100.0 / float(m["total_buckets"])
	assert_almost_eq(m["stem_bucket_pct"], expected_stem_pct, 1e-6,
		"one segment midpoint should mark exactly one bucket")


func test_out_of_bounds_segment_midpoint_dropped() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var plant := PlantData.new()
	_add_seg_at(plant, 50.0, 5.0)  # outside wall
	var m := WallCoverageMetric.new().measure(plant, spec)
	assert_almost_eq(m["stem_bucket_pct"], 0.0, 1e-9,
		"out-of-bounds segment midpoint must not contribute to stem_bucket_pct")


# ── Leaves in separate buckets ─────────────────────────────────────────────

func test_two_leaves_in_different_buckets_each_uncovered() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var plant := PlantData.new()
	# Different buckets: bucket (100, 0) and bucket (101, 0)
	_add_leaf_at(plant, 0.0, 0.05)   # bucket x=100 (centred in [10.0, 10.1))
	_add_leaf_at(plant, 0.15, 0.05)  # bucket x=101
	var m := WallCoverageMetric.new().measure(plant, spec)
	assert_eq(m["covered_buckets"], 0,
		"one leaf per bucket — neither should be covered")
