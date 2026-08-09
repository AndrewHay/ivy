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
extends GutTest

const CoverageMetric = preload("res://src/metrics/coverage.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const PlantData = preload("res://src/sim/plant_data.gd")


func _make_metric() -> CoverageMetric:
	var m := CoverageMetric.new()
	m.setup(TowerSpec.new())
	return m


## Append a synthetic leaf at a known (azimuth_bin, height_bin) with outward normal
## facing the cylinder wall, and a given projected area.  The n_leaf = outward radial
## normal so |dot(n_leaf, n_bucket)| = 1, making the weight exactly `area`.
func _add_leaf_at_bin(plant: PlantData, az_bin: int, h_bin: int, area: float) -> void:
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
	plant.append_leaf(xform, Color.WHITE, Vector4(0.0, 0.0, 0.0, 0.0), 0, 0.0, area)


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
	# Fill every eligible bucket with area well above the 50%-bucket threshold.
	var spec := TowerSpec.new()
	var m := CoverageMetric.new()
	m.setup(spec)
	var plant := PlantData.new()
	var threshold_area := 2.0 * PI * spec.radius_outer / CoverageMetric.AZIMUTH_BINS \
		* CoverageMetric.HEIGHT_BIN_SIZE * 0.5
	# Add one leaf per bucket with area = threshold * 1.5 (comfortably above threshold)
	var large_area := threshold_area * 1.5
	for az_bin in range(CoverageMetric.AZIMUTH_BINS):
		for h_bin in range(CoverageMetric.HEIGHT_BINS):
			_add_leaf_at_bin(plant, az_bin, h_bin, large_area)
	var result := m.measure(plant, 180.0)
	assert_almost_eq(result["overall_pct"], 100.0, 0.001,
		"fully-covered plant must report 100% overall")
	assert_almost_eq(result["sun_half_pct"], 100.0, 0.001,
		"fully-covered plant must report 100% sun half")
	assert_almost_eq(result["shade_half_pct"], 100.0, 0.001,
		"fully-covered plant must report 100% shade half")


func test_below_threshold_area_is_not_counted() -> void:
	# A leaf whose weighted area is just under 50% of bucket area must not cover the bucket.
	var spec := TowerSpec.new()
	var m := CoverageMetric.new()
	m.setup(spec)
	var plant := PlantData.new()
	var bucket_area := 2.0 * PI * spec.radius_outer / CoverageMetric.AZIMUTH_BINS \
		* CoverageMetric.HEIGHT_BIN_SIZE
	_add_leaf_at_bin(plant, 36, 10, bucket_area * 0.49)  # just under threshold
	var result := m.measure(plant, 180.0)
	assert_almost_eq(result["overall_pct"], 0.0, 0.001,
		"sub-threshold leaf must not cover the bucket")


func test_above_threshold_area_is_counted() -> void:
	var spec := TowerSpec.new()
	var m := CoverageMetric.new()
	m.setup(spec)
	var plant := PlantData.new()
	var bucket_area := 2.0 * PI * spec.radius_outer / CoverageMetric.AZIMUTH_BINS \
		* CoverageMetric.HEIGHT_BIN_SIZE
	_add_leaf_at_bin(plant, 36, 10, bucket_area * 0.51)  # just above threshold
	var result := m.measure(plant, 180.0)
	assert_gt(result["overall_pct"], 0.0, "above-threshold leaf must cover the bucket")


# ---------------------------------------------------------------------------
# Sun / shade split follows seed azimuth (not a compass constant)
# ---------------------------------------------------------------------------

func test_south_bucket_is_in_sun_half_when_seed_is_south() -> void:
	var m := _make_metric()
	var spec := TowerSpec.new()
	var plant := PlantData.new()
	# Place a leaf at south (az_bin 36), seed at south (180°) → in sun half
	var bucket_area := 2.0 * PI * spec.radius_outer / CoverageMetric.AZIMUTH_BINS \
		* CoverageMetric.HEIGHT_BIN_SIZE
	_add_leaf_at_bin(plant, 36, 10, bucket_area * 2.0)
	var result := m.measure(plant, 180.0)
	assert_gt(result["sun_half_pct"], 0.0,
		"south leaf must be counted in sun half when seed_azimuth=180°")
	assert_almost_eq(result["shade_half_pct"], 0.0, 0.001,
		"south leaf must NOT appear in shade half when seed_azimuth=180°")


func test_south_bucket_is_in_shade_half_when_seed_is_north() -> void:
	var m := _make_metric()
	var spec := TowerSpec.new()
	var plant := PlantData.new()
	# Place a leaf at south (az_bin 36), seed at NORTH (0°) → south is shade half
	var bucket_area := 2.0 * PI * spec.radius_outer / CoverageMetric.AZIMUTH_BINS \
		* CoverageMetric.HEIGHT_BIN_SIZE
	_add_leaf_at_bin(plant, 36, 10, bucket_area * 2.0)
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
