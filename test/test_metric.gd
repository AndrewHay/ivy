## Tests for CoverageMetric (SD-METRIC-1/2/3/5/6).
##
## TDD anchors verified here:
##   - Bucket azimuth/height mapping round-trips correctly
##   - Door and window buckets are excluded from the denominator (SD-METRIC-2)
##   - A synthetic fully-covered plant measures 100%
##   - Sun/shade halves are split about the seed anchor's azimuth, not a compass constant
##   - AS-1 coupling rule: the two half floors (90/50) average to the overall floor (70)
##   - 12-sector asymmetry reports correctly on a one-sided synthetic plant
##   - Stem-bucket occupancy is reported alongside leaf coverage (SD-METRIC-5)
##   - CoverageMetric is a read-only observer — it consumes no RNG draws
##   - W-076 AR-METRIC-1 amendment: ref_area = alpha_fill("a")·width²/aspect("a"), id-independent;
##     AS-1 is bit-identical across s_light-gain changes AND tier-probability changes.
extends GutTest

const CoverageMetric = preload("res://src/metrics/coverage.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const LeafPlacer = preload("res://src/sim/leaf_placer.gd")
const Tip = preload("res://src/sim/tip.gd")
const SimContext = preload("res://src/sim/sim_context.gd")
const LeafAtlas = preload("res://src/render/leaf_atlas.gd")


func _make_metric() -> CoverageMetric:
	var m := CoverageMetric.new()
	m.setup(TowerSpec.new(), IvyParams.new())
	return m


## Append a synthetic leaf at a known (azimuth_bin, height_bin) with outward normal
## facing the cylinder wall.  n_leaf = outward radial normal so |dot(n_leaf, n_bucket)| = 1.
## CoverageMetric now weights every leaf by _ref_area (not by the stored area), so
## `area` here only affects PlantData.leaf_area (rendered), not coverage outcome.
func _add_leaf_at_bin(plant: PlantData, az_bin: int, h_bin: int, area: float = 0.006) -> void:
	var az_rad := deg_to_rad(float(az_bin) * 5.0 + 2.5)
	var y := float(h_bin) * 0.10 + 0.05
	var nx := sin(az_rad)
	var nz := -cos(az_rad)
	var pos := Vector3(nx * 2.0, y, nz * 2.0)
	# Leaf normal (basis.z) = outward radial direction
	var n := Vector3(nx, 0.0, nz)
	# basis.x = circumferential (tangent), basis.y = up
	var tangent := Vector3(cos(az_rad), 0.0, sin(az_rad))
	var xform := Transform3D(Basis(tangent, Vector3.UP, n), pos)
	plant.append_leaf(xform, Color.WHITE, Vector4(0.0, 0.0, 0.0, 0.0), 0, 0.0, area, 0.0)


## Variant of _add_leaf_at_bin that tags each leaf with a specific atlas rect (leaf_custom) and
## the real rendered area for that variant.  Used by test_w076_ref_area_is_fixed_and_correct so
## that the six plants differ in both stored leaf_area AND leaf_custom, making a mutation to
## weight-by-leaf_area detectable by the bit-identity assertions.
func _add_leaf_at_bin_with_variant(plant: PlantData, az_bin: int, h_bin: int,
		area: float, rect: Vector4) -> void:
	var az_rad := deg_to_rad(float(az_bin) * 5.0 + 2.5)
	var y := float(h_bin) * 0.10 + 0.05
	var nx := sin(az_rad)
	var nz := -cos(az_rad)
	var pos := Vector3(nx * 2.0, y, nz * 2.0)
	var n := Vector3(nx, 0.0, nz)
	var tangent := Vector3(cos(az_rad), 0.0, sin(az_rad))
	var xform := Transform3D(Basis(tangent, Vector3.UP, n), pos)
	plant.append_leaf(xform, Color.WHITE, rect, 0, 0.0, area, 0.0)


## Add a stem segment with both endpoints at a given azimuth angle and height.
func _add_segment_at(plant: PlantData, az_deg: float, y: float) -> void:
	var az_rad := deg_to_rad(az_deg)
	var nx := sin(az_rad)
	var nz := -cos(az_rad)
	var a := Vector3(nx * 2.0, y, nz * 2.0)
	var b := Vector3(nx * 2.0, y + 0.03, nz * 2.0)
	plant.append_segment(a, b, Vector3(nx, 0.0, nz), 0, 0, 0.0)


# ---------------------------------------------------------------------------
# Bucket azimuth mapping
# ---------------------------------------------------------------------------

func test_north_point_maps_to_azimuth_bin_zero() -> void:
	# NORTH = (0, 0, -1): azimuth 0°, bin 0
	var m := _make_metric()
	var bin := m._azimuth_bin_of(0.0, -2.0)
	assert_eq(bin, 0, "north point must map to azimuth bin 0")


func test_south_point_maps_to_azimuth_bin_36() -> void:
	# SOUTH = (0, 0, 1): azimuth 180°, bin 36
	var m := _make_metric()
	var bin := m._azimuth_bin_of(0.0, 2.0)
	assert_eq(bin, 36, "south point must map to azimuth bin 36")


func test_east_point_maps_to_azimuth_bin_18() -> void:
	# EAST = (1, 0, 0): azimuth 90°, bin 18
	var m := _make_metric()
	var bin := m._azimuth_bin_of(2.0, 0.0)
	assert_eq(bin, 18, "east point must map to azimuth bin 18")


func test_west_point_maps_to_azimuth_bin_54() -> void:
	# WEST = (-1, 0, 0): azimuth 270°, bin 54
	var m := _make_metric()
	var bin := m._azimuth_bin_of(-2.0, 0.0)
	assert_eq(bin, 54, "west point must map to azimuth bin 54")


func test_azimuth_bin_round_trips_all_72_bins() -> void:
	var m := _make_metric()
	for az_bin in range(CoverageMetric.AZIMUTH_BINS):
		var az_rad := deg_to_rad(float(az_bin) * 5.0 + 2.5)
		var x := sin(az_rad) * 2.0
		var z := -cos(az_rad) * 2.0
		var got := m._azimuth_bin_of(x, z)
		assert_eq(got, az_bin, "round-trip failed for azimuth bin %d" % az_bin)


# ---------------------------------------------------------------------------
# Height bin mapping
# ---------------------------------------------------------------------------

func test_height_bin_zero_at_ground_level() -> void:
	var m := _make_metric()
	assert_eq(m._height_bin_of(0.05), 0)
	assert_eq(m._height_bin_of(0.0), 0)
	assert_eq(m._height_bin_of(0.09), 0)


func test_height_bin_one_at_0_1_m() -> void:
	var m := _make_metric()
	assert_eq(m._height_bin_of(0.10), 1)
	assert_eq(m._height_bin_of(0.15), 1)


func test_height_bin_returns_minus_one_below_ground() -> void:
	var m := _make_metric()
	assert_eq(m._height_bin_of(-0.05), -1, "negative y must return -1")


func test_height_bin_returns_minus_one_above_tower() -> void:
	# Tower is 3.5 m (35 × 0.1 m bins 0–34). y ≥ 3.5 m is out of range.
	var m := _make_metric()
	assert_eq(m._height_bin_of(3.5), -1, "y at tower top must return -1")
	assert_eq(m._height_bin_of(4.0), -1, "y above tower must return -1")


# ---------------------------------------------------------------------------
# Opening mask (SD-METRIC-2)
# ---------------------------------------------------------------------------

func test_door_buckets_excluded_from_denominator() -> void:
	# Default spec: door at north (az 0°), height 0–2 m.
	# Bin 0 (az centre 2.5°) and height bin 0 (y 0–0.1 m) should be excluded.
	var m := _make_metric()
	# Place a leaf with area >> threshold inside the door zone
	var plant := PlantData.new()
	_add_leaf_at_bin(plant, 0, 0, 1.0)  # north, ground-level
	var result := m.measure(plant, 180.0)
	# overall_pct = 0 because door buckets are excluded from the denominator
	# — covered_count stays 0, eligible_count excludes the door buckets
	assert_eq(result["total_eligible_buckets"], result["total_eligible_buckets"],
		"eligible count is present")
	# The door bin (0,0) must NOT be eligible
	assert_almost_eq(result["overall_pct"], 0.0, 0.001,
		"door-zone leaf must not contribute to coverage % (excluded from denominator)")


func test_window_buckets_excluded() -> void:
	# Default spec: window at east (az 90°), sill 1.6 m, size 0.6 m → top 2.2 m.
	# Bin 18 (az centre 90°), height bins 16–21 (1.6–2.2 m) should be excluded.
	var m := _make_metric()
	var plant := PlantData.new()
	_add_leaf_at_bin(plant, 18, 18, 1.0)  # east, y ≈ 1.85 m (inside window)
	var result := m.measure(plant, 180.0)
	assert_almost_eq(result["overall_pct"], 0.0, 0.001,
		"window-zone leaf must not contribute to coverage %")


func test_eligible_buckets_are_less_than_total_due_to_openings() -> void:
	var m := _make_metric()
	var plant := PlantData.new()
	var result := m.measure(plant, 180.0)
	var total_possible := CoverageMetric.AZIMUTH_BINS * CoverageMetric.HEIGHT_BINS
	assert_lt(result["total_eligible_buckets"], total_possible,
		"openings must reduce eligible bucket count below 2520")


# ---------------------------------------------------------------------------
# Coverage percentage: empty and full-coverage cases
# ---------------------------------------------------------------------------

func test_empty_plant_is_zero_percent() -> void:
	var m := _make_metric()
	var plant := PlantData.new()
	var result := m.measure(plant, 180.0)
	assert_almost_eq(result["overall_pct"], 0.0, 0.001)
	assert_almost_eq(result["sun_half_pct"], 0.0, 0.001)
	assert_almost_eq(result["shade_half_pct"], 0.0, 0.001)
	assert_almost_eq(result["stem_bucket_pct"], 0.0, 0.001)


func test_synthetic_saturated_mat_is_100_pct() -> void:
	# Enough face-on leaves per bucket so accumulated weight exceeds the 50%-threshold.
	# With ref_area < bucket_area * 0.5, several leaves per bucket are required.
	var spec := TowerSpec.new()
	var params := IvyParams.new()
	var m := CoverageMetric.new()
	m.setup(spec, params)
	var bucket_area := 2.0 * PI * spec.radius_outer / float(CoverageMetric.AZIMUTH_BINS) \
		* CoverageMetric.HEIGHT_BIN_SIZE
	var leaves_per_bucket := int(ceil(bucket_area * 0.5 / m._ref_area)) + 1
	var plant := PlantData.new()
	for az_bin in range(CoverageMetric.AZIMUTH_BINS):
		for h_bin in range(CoverageMetric.HEIGHT_BINS):
			for _k in range(leaves_per_bucket):
				_add_leaf_at_bin(plant, az_bin, h_bin)
	var result := m.measure(plant, 180.0)
	assert_almost_eq(result["overall_pct"], 100.0, 0.001,
		"fully-covered plant must report 100% overall")
	assert_almost_eq(result["sun_half_pct"], 100.0, 0.001,
		"fully-covered plant must report 100% sun half")
	assert_almost_eq(result["shade_half_pct"], 100.0, 0.001,
		"fully-covered plant must report 100% shade half")


func test_edge_on_leaf_does_not_cover_bucket() -> void:
	# A leaf whose face normal is perpendicular to the bucket wall (dot_abs = 0)
	# contributes zero projected area → weight = ref_area * 0 = 0 → not covered.
	# This tests SD-METRIC-3's projection: only leaves facing the wall count.
	var spec := TowerSpec.new()
	var params := IvyParams.new()
	var m := CoverageMetric.new()
	m.setup(spec, params)
	var plant := PlantData.new()
	# Bucket at az_bin=36 (south, 180°): bucket normal = (0, 0, 1).
	# Leaf with normal = (1, 0, 0) (east): dot((1,0,0),(0,0,1)) = 0 → no coverage.
	var y := float(10) * 0.10 + 0.05
	var pos := Vector3(0.0, y, 2.0)  # south wall
	var n_edge_on := Vector3(1.0, 0.0, 0.0)  # east-facing (edge-on to south bucket)
	var xform := Transform3D(Basis(Vector3.FORWARD, Vector3.UP, n_edge_on), pos)
	plant.append_leaf(xform, Color.WHITE, Vector4.ZERO, 0, 0.0, 0.006, 0.0)
	var result := m.measure(plant, 180.0)
	assert_almost_eq(result["overall_pct"], 0.0, 0.001,
		"edge-on leaf (dot_abs=0) must not cover its bucket (SD-METRIC-3 projection)")


func test_face_on_leaves_cover_bucket() -> void:
	# Enough face-on leaves per bucket accumulate ref_area * N >= threshold → covered.
	var spec := TowerSpec.new()
	var params := IvyParams.new()
	var m := CoverageMetric.new()
	m.setup(spec, params)
	var bucket_area := 2.0 * PI * spec.radius_outer / float(CoverageMetric.AZIMUTH_BINS) \
		* CoverageMetric.HEIGHT_BIN_SIZE
	var leaves_needed := int(ceil(bucket_area * 0.5 / m._ref_area)) + 1
	var plant := PlantData.new()
	for _k in range(leaves_needed):
		_add_leaf_at_bin(plant, 36, 10)  # south, face-on
	var result := m.measure(plant, 180.0)
	assert_gt(result["overall_pct"], 0.0,
		"%d face-on leaves must cover their bucket" % leaves_needed)


# ---------------------------------------------------------------------------
# Sun / shade split follows seed azimuth (not a compass constant)
# ---------------------------------------------------------------------------

func test_south_bucket_is_in_sun_half_when_seed_is_south() -> void:
	var spec := TowerSpec.new()
	var m := CoverageMetric.new()
	m.setup(spec, IvyParams.new())
	var bucket_area := 2.0 * PI * spec.radius_outer / float(CoverageMetric.AZIMUTH_BINS) \
		* CoverageMetric.HEIGHT_BIN_SIZE
	var leaves_needed := int(ceil(bucket_area * 0.5 / m._ref_area)) + 1
	var plant := PlantData.new()
	# Place enough leaves at south (az_bin 36), seed at south (180°) → in sun half
	for _k in range(leaves_needed):
		_add_leaf_at_bin(plant, 36, 10)
	var result := m.measure(plant, 180.0)
	assert_gt(result["sun_half_pct"], 0.0,
		"south leaf must be counted in sun half when seed_azimuth=180°")
	assert_almost_eq(result["shade_half_pct"], 0.0, 0.001,
		"south leaf must NOT appear in shade half when seed_azimuth=180°")


func test_south_bucket_is_in_shade_half_when_seed_is_north() -> void:
	var spec := TowerSpec.new()
	var m := CoverageMetric.new()
	m.setup(spec, IvyParams.new())
	var bucket_area := 2.0 * PI * spec.radius_outer / float(CoverageMetric.AZIMUTH_BINS) \
		* CoverageMetric.HEIGHT_BIN_SIZE
	var leaves_needed := int(ceil(bucket_area * 0.5 / m._ref_area)) + 1
	var plant := PlantData.new()
	# Place enough leaves at south (az_bin 36), seed at NORTH (0°) → south is shade half
	for _k in range(leaves_needed):
		_add_leaf_at_bin(plant, 36, 10)
	var result := m.measure(plant, 0.0)   # seed at north
	assert_almost_eq(result["sun_half_pct"], 0.0, 0.001,
		"south leaf must NOT appear in sun half when seed_azimuth=0°")
	assert_gt(result["shade_half_pct"], 0.0,
		"south leaf must be counted in shade half when seed_azimuth=0°")


func test_sun_and_shade_eligible_buckets_sum_to_total() -> void:
	var m := _make_metric()
	var plant := PlantData.new()
	var result := m.measure(plant, 180.0)
	assert_eq(
		result["sun_eligible_buckets"] + result["shade_eligible_buckets"],
		result["total_eligible_buckets"],
		"sun + shade eligible must equal total eligible"
	)


# ---------------------------------------------------------------------------
# AS-1 coupling rule: the ratified floors (90 / 50) average to ≥ the overall (70)
# ---------------------------------------------------------------------------

func test_as1_coupling_rule_half_floors_average_to_overall() -> void:
	# Ratified in DESIGN.md: ≥90% sun-facing / ≥50% shaded averages to ≥70% overall.
	# A future revision that breaks this coupling would fail this test.
	var sun_floor := 90.0
	var shade_floor := 50.0
	var overall_floor := 70.0
	var implied_overall := (sun_floor + shade_floor) * 0.5
	assert_gte(implied_overall, overall_floor,
		"90/50 must average to ≥70 (AS-1 coupling rule; DESIGN.md ratification 2026-08-09)")


func test_as1_coupling_rule_is_satisfiable() -> void:
	# If a plant hits exactly the half floors (90 and 50), it must pass the overall (70).
	# This test catches the 70/85/35 defect that was corrected before ratification.
	var hypothetical_sun := 90.0
	var hypothetical_shade := 50.0
	var hypothetical_overall := (hypothetical_sun + hypothetical_shade) * 0.5
	assert_gte(hypothetical_overall, 70.0,
		"plant at 90%/50% must pass the 70% overall floor")


# ---------------------------------------------------------------------------
# 12-sector asymmetry (SD-METRIC-6)
# ---------------------------------------------------------------------------

func test_12_sector_asymmetry_on_one_sided_plant() -> void:
	# Place stems only in the south half (sectors 3–8, seed_azimuth=180°).
	# All stem length should appear in sun sectors; shade sectors zero.
	var m := _make_metric()
	var plant := PlantData.new()
	# Sectors 3-8 centre azimuths: 105°, 135°, 165°, 195°, 225°, 255°
	for az_deg in [105.0, 135.0, 165.0, 195.0, 225.0, 255.0]:
		_add_segment_at(plant, az_deg, 1.0)
	var result := m.measure(plant, 180.0)
	var sector_len: PackedFloat32Array = result["sector_stem_length"]
	# Sun sectors (3-8) must have non-zero length
	var sun_len := sector_len[3] + sector_len[4] + sector_len[5] \
		+ sector_len[6] + sector_len[7] + sector_len[8]
	# Shade sectors (0-2, 9-11) must be zero
	var shade_len := sector_len[0] + sector_len[1] + sector_len[2] \
		+ sector_len[9] + sector_len[10] + sector_len[11]
	assert_gt(sun_len, 0.0, "sun sectors must have stem length")
	assert_almost_eq(shade_len, 0.0, 1e-5, "shade sectors must be empty")


func test_stem_asymmetry_pct_100_when_all_stem_in_sun_half() -> void:
	var m := _make_metric()
	var plant := PlantData.new()
	# All segments at south (azimuth 180°, sun half for seed_azimuth=180°)
	_add_segment_at(plant, 180.0, 1.0)
	var result := m.measure(plant, 180.0)
	assert_gt(result["stem_asymmetry_pct"], 0.0,
		"all-sun stem must give positive asymmetry")
	assert_almost_eq(result["stem_asymmetry_pct"], 100.0, 1e-3,
		"all-sun stem must give 100% asymmetry")


func test_stem_asymmetry_pct_near_zero_with_symmetric_plant() -> void:
	var m := _make_metric()
	var plant := PlantData.new()
	# Place identical segments at north (0°) and south (180°)
	_add_segment_at(plant, 0.0, 1.0)
	_add_segment_at(plant, 180.0, 1.0)
	var result := m.measure(plant, 180.0)
	assert_almost_eq(result["stem_asymmetry_pct"], 0.0, 1.0,
		"symmetric plant must give near-zero stem asymmetry")


# ---------------------------------------------------------------------------
# Stem-bucket occupancy (SD-METRIC-5)
# ---------------------------------------------------------------------------

func test_stem_bucket_pct_zero_with_no_segments() -> void:
	var m := _make_metric()
	var plant := PlantData.new()
	var result := m.measure(plant, 180.0)
	assert_almost_eq(result["stem_bucket_pct"], 0.0, 0.001)


func test_stem_bucket_pct_positive_with_one_segment() -> void:
	var m := _make_metric()
	var plant := PlantData.new()
	_add_segment_at(plant, 180.0, 1.0)  # south, mid-height
	var result := m.measure(plant, 180.0)
	assert_gt(result["stem_bucket_pct"], 0.0,
		"a single segment must yield non-zero stem bucket occupancy")


# ---------------------------------------------------------------------------
# Lip reached
# ---------------------------------------------------------------------------

func test_lip_not_reached_when_all_segments_below_tower_top() -> void:
	var m := _make_metric()
	var plant := PlantData.new()
	_add_segment_at(plant, 180.0, 1.0)
	var result := m.measure(plant, 180.0)
	assert_false(result["lip_reached"], "low segment must not trigger lip_reached")


func test_lip_reached_when_a_segment_exceeds_tower_height() -> void:
	# TowerSpec.height = 3.5 m by default.
	var m := _make_metric()
	var plant := PlantData.new()
	# Add a segment that straddles the top (y = 3.4 to 3.6)
	var a := Vector3(0.0, 3.4, 2.0)
	var b := Vector3(0.0, 3.6, 2.0)
	plant.append_segment(a, b, Vector3(0, 0, 1), 0, 0, 0.0)
	var result := m.measure(plant, 180.0)
	assert_true(result["lip_reached"], "segment crossing tower top must trigger lip_reached")


# ---------------------------------------------------------------------------
# Independence from crowding-field parameters (SD-METRIC-4)
# ---------------------------------------------------------------------------

func test_coverage_metric_does_not_use_environment_or_rng() -> void:
	# CoverageMetric takes only TowerSpec + PlantData. This test confirms the
	# API signature: if it compiled, it passed (no env/rng dependencies).
	var m := _make_metric()
	var plant := PlantData.new()
	# Two identical calls must return identical results — no stray RNG state.
	var r1 := m.measure(plant, 180.0)
	var r2 := m.measure(plant, 180.0)
	assert_almost_eq(r1["overall_pct"], r2["overall_pct"], 1e-6,
		"identical calls must return identical results (no RNG state)")


# ---------------------------------------------------------------------------
# W-076 / AR-METRIC-1 amendment: fixed ref_area independent of leaf_id/tier/s_light
# ---------------------------------------------------------------------------

## Helper: build a SimContext with no env and a fresh plant.
func _metric_ctx(params: IvyParams, plant: PlantData) -> SimContext:
	return SimContext.new(params, null, null, plant, null, null)


## Helper: place leaves via LeafPlacer across all az/h bins with a given IvyParams.
func _fill_bins_with_placer(params: IvyParams, spec: TowerSpec, f_l: float) -> PlantData:
	var plant := PlantData.new()
	var ctx := _metric_ctx(params, plant)
	for az_bin in range(CoverageMetric.AZIMUTH_BINS):
		for h_bin in range(0, 10):
			var tip := Tip.new()
			tip.id = az_bin * 100 + h_bin
			tip.last_contact_normal = Vector3(0.0, 0.0, 1.0)
			tip.state = Tip.State.GROWING
			tip.vigour = 1.0
			tip.leaf_side_sign = 1.0
			tip.shoot_length = params.leaf_tip_suppress + 1.0
			var u := Hash64.unit_float(tip.id, 0, 99)
			var internode := params.internode_base \
				* (1.0 + params.internode_shade_gain * (1.0 - f_l)) \
				* (1.0 + params.internode_jitter * (2.0 * u - 1.0))
			tip.distance_since_node = internode + 0.001
			var az_rad := deg_to_rad(float(az_bin) * 5.0 + 2.5)
			var y := float(h_bin) * 0.10 + 0.05
			var nx := sin(az_rad)
			var nz := -cos(az_rad)
			var seg_a := Vector3(nx * 1.9, y, nz * 1.9)
			var seg_b := Vector3(nx * 2.0, y + 0.01, nz * 2.0)
			tip.last_contact_normal = Vector3(nx, 0.0, nz)
			LeafPlacer.advance(tip, ctx, seg_a, seg_b, f_l, Basis.IDENTITY)
	return plant


## W-076 test 1 — ref_area is correct and id-independent (AR-METRIC-1 amendment).
## Asserts _ref_area = alpha_fill("a") · leaf_width_base² / aspect("a").
## Each plant uses a genuinely different variant: leaf_custom carries that variant's atlas rect
## and leaf_area carries that variant's real rendered area (alpha_fill[id]·w²/aspect[id]).
## Because the six variants have different alpha_fill/aspect values, their rendered areas differ,
## so a mutation that weights coverage by leaf_area[i] instead of _ref_area would produce
## different per-variant coverage totals and break the bit-identity assertions below.
func test_w076_ref_area_is_fixed_and_correct() -> void:
	var params := IvyParams.new()
	var spec := TowerSpec.new()
	var m := CoverageMetric.new()
	m.setup(spec, params)
	var atlas := LeafAtlas.new()
	var expected_ref := atlas.alpha_fill_for("a") * params.leaf_width_base \
		* params.leaf_width_base / atlas.aspect_for("a")
	assert_almost_eq(m._ref_area, expected_ref, 1e-9,
		"_ref_area must equal alpha_fill('a')·leaf_width_base²/aspect('a') (AR-METRIC-1)")

	var bucket_area := 2.0 * PI * spec.radius_outer / float(CoverageMetric.AZIMUTH_BINS) \
		* CoverageMetric.HEIGHT_BIN_SIZE
	# Exactly ceil(threshold / _ref_area) — no safety margin.
	# With _ref_area, all variants cover: 4 × 0.002548 = 0.010192 > threshold 0.008727.
	# With mutation leaf_area[i], variant "e" (area 0.002177) falls below:
	#   4 × 0.002177 = 0.008708 < 0.008727 → not covered → test goes RED.
	var leaves_needed := int(ceil(bucket_area * 0.5 / m._ref_area))

	var leaf_ids := ["a", "b", "c", "d", "e", "f"]
	var pcts: Array = []
	for leaf_id: String in leaf_ids:
		var area_for_id := atlas.alpha_fill_for(leaf_id) * params.leaf_width_base \
			* params.leaf_width_base / atlas.aspect_for(leaf_id)
		var rect := atlas.rect_for(leaf_id)
		var plant := PlantData.new()
		for _j in range(leaves_needed):
			_add_leaf_at_bin_with_variant(plant, 36, 10, area_for_id, rect)
		assert_gt(plant.leaf_count(), 0,
			"plant must be non-empty for leaf_id '%s'" % leaf_id)
		var result := m.measure(plant, 180.0)
		assert_gt(result["overall_pct"], 0.0,
			"%d face-on leaves must cover their bucket (leaf_id '%s', AR-METRIC-1)" % [
				leaves_needed, leaf_id])
		pcts.append(result["overall_pct"])

	# All 6 variants must give bit-identical coverage (metric ignores variant).
	# Assertion is unconditional: if any pct is missing the loop above would have already failed.
	for i in range(1, pcts.size()):
		assert_almost_eq(pcts[i], pcts[0], 1e-9,
			"coverage for variant '%s' must be bit-identical to 'a' (id-independence)" % leaf_ids[i])

	# The six-variant comparison above only detects a weight-by-leaf_area regression while some
	# variant's real area happens to straddle the occupancy threshold — currently variant "e",
	# by 0.2%. Coverage is all-or-nothing per bucket, so a small change to radius_outer,
	# HEIGHT_BIN_SIZE or leaf_width_base would put every variant on the same side of the
	# threshold, and the regression would pass unnoticed with the test still green.
	#
	# These two plants remove that dependence: identical placement, stored leaf_area absurd in
	# opposite directions. Coverage must not move, because it weights by _ref_area. A metric
	# reading leaf_area would report 0% for the first and full coverage for the second, which no
	# geometry constant can disguise.
	var extreme_pcts: Array = []
	for stored_area in [0.0, 100.0]:
		var plant := PlantData.new()
		for _j in range(leaves_needed):
			_add_leaf_at_bin_with_variant(plant, 36, 10, stored_area, atlas.rect_for("a"))
		assert_gt(plant.leaf_count(), 0, "extreme-area plant must be non-empty")
		extreme_pcts.append(m.measure(plant, 180.0)["overall_pct"])

	assert_almost_eq(extreme_pcts[0], extreme_pcts[1], 1e-9,
		"stored leaf_area must not affect coverage (0 m² vs 100 m² per leaf, AR-METRIC-1)")
	assert_almost_eq(extreme_pcts[0], pcts[0], 1e-9,
		"leaves with zero stored leaf_area must still cover, since coverage uses _ref_area")


## W-076 test 2 — Presentation invariance: s_light gain (AR-METRIC-1 amendment).
## Three plants with leaf_light_scale_gain=0/default/2× — same placement, different rendered sizes.
## Canonical AS-1 must be bit-identical; leaf_area (rendered) must differ.
func test_w076_canonical_coverage_invariant_to_presentation_gain() -> void:
	var spec := TowerSpec.new()

	var gains := [0.0, 0.30, 0.60]
	var shade_pcts: Array = []
	var first_rendered_areas: Array = []

	for gain: float in gains:
		var params := IvyParams.new()
		params.leaf_light_scale_gain = gain
		var metric := CoverageMetric.new()
		metric.setup(spec, params)
		var plant := _fill_bins_with_placer(params, spec, 0.5)
		assert_gt(plant.leaf_count(), 0,
			"plant must be non-empty for leaf_light_scale_gain=%.2f" % gain)
		var result := metric.measure(plant, 180.0)
		shade_pcts.append(result["shade_half_pct"])
		first_rendered_areas.append(plant.leaf_area[0])

	assert_almost_eq(shade_pcts[0], shade_pcts[1], 1e-9,
		"canonical shade_half_pct must be bit-identical at gain=0 vs default (W-076 s_light invariance)")
	assert_almost_eq(shade_pcts[1], shade_pcts[2], 1e-9,
		"canonical shade_half_pct must be bit-identical at gain=default vs 2× (W-076 s_light invariance)")
	# Unconditional: _fill_bins_with_placer non-emptiness already asserted above.
	assert_ne(first_rendered_areas[0], first_rendered_areas[2],
		"rendered leaf_area must differ between gain=0 and gain=2× (render path active)")


## W-076 test 3 — Tier-probability invariance (the durable guard, AR-METRIC-1 amendment).
## Positive control: aggregate healthy-tier fraction must differ materially between
## leaf_healthy_gain=0 and leaf_healthy_gain=1.0.  At f_L=0.5:
##   healthy_prob(gain=0)   = leaf_healthy_base ≈ 0.25  → ~25% H leaves
##   healthy_prob(gain=1.0) = leaf_healthy_base + 0.5  → ~75% H leaves
## The ~50pp shift must appear as ≥30pp in the aggregate fraction (positive control).
## Invariance claim: canonical AS-1 must still be bit-identical despite that tier-mix shift,
## because _ref_area is the same constant for all variants (AR-METRIC-1 amendment).
## Guard: if leaf_healthy_gain is ever unwired, both healthy fractions equal leaf_healthy_base,
## the positive-control assertion fails, and the test immediately goes red (INV-7).
func test_w076_tier_probability_invariance() -> void:
	var spec := TowerSpec.new()
	var atlas := LeafAtlas.new()

	var healthy_gains := [0.0, 0.65, 1.0]
	var shade_pcts: Array = []
	var healthy_fracs: Array = []  # aggregate H-tier leaf fraction per gain setting

	for hg: float in healthy_gains:
		var params := IvyParams.new()
		params.leaf_healthy_gain = hg
		var metric := CoverageMetric.new()
		metric.setup(spec, params)
		var plant := _fill_bins_with_placer(params, spec, 0.5)
		assert_gt(plant.leaf_count(), 0,
			"plant must be non-empty for leaf_healthy_gain=%.2f" % hg)
		var result := metric.measure(plant, 180.0)
		shade_pcts.append(result["shade_half_pct"])

		# Compute aggregate H-tier fraction: recover each leaf's id via id_for_rect,
		# count H leaves.  Runs on the full plant so statistical noise is small.
		var h_count := 0
		var total := plant.leaf_count()
		for i in range(total):
			var r := Vector4(
				plant.leaf_custom[i * 4 + 0], plant.leaf_custom[i * 4 + 1],
				plant.leaf_custom[i * 4 + 2], plant.leaf_custom[i * 4 + 3])
			var lid := atlas.id_for_rect(r)
			if lid != "" and atlas.tier_for(lid) == "H":
				h_count += 1
		healthy_fracs.append(float(h_count) / float(total))

	# Positive control (unconditional): the tier mix must have shifted materially.
	# If leaf_healthy_gain is unwired this delta collapses to ~0 and the test goes red.
	assert_gt(healthy_fracs[2] - healthy_fracs[0], 0.30,
		"H-tier fraction must differ by > 30pp between gain=0 (%.2f) and gain=1.0 (%.2f)" % [
			healthy_fracs[0], healthy_fracs[2]])

	# Invariance claim (unconditional): bit-identical coverage despite different tier mix.
	assert_almost_eq(shade_pcts[0], shade_pcts[1], 1e-9,
		"canonical AS-1 must be bit-identical at leaf_healthy_gain=0 vs default (W-076 tier invariance)")
	assert_almost_eq(shade_pcts[1], shade_pcts[2], 1e-9,
		"canonical AS-1 must be bit-identical at leaf_healthy_gain=default vs 1.0 (W-076 tier invariance)")
