## Tests for LeafColourMetric (SD-METRIC-7, W-061).
##
## LG-2a: area-weighted mean instance Color.g, sun-facing 180° − shaded 180°.
## LG-2b: area-weighted healthy-tier area-fraction delta, same hemispheres.
##
## Flat-plant invariant (the W-053/W-058 safeguard):
##   With all leaves Color.WHITE and equal tier mix, both deltas must collapse to ~0.
##   If these tests pass on a flat synthetic plant the metric is correctly sensitive to
##   the W-060 tint and tier changes — and will fail on the pre-W-060 code.
##
## W-075: LG-2' layer (b) decile_measure() instrument tests.
extends GutTest

const LeafColourMetric = preload("res://src/metrics/leaf_colour_metric.gd")
const CoverageMetric = preload("res://src/metrics/coverage.gd")
const LeafAtlas = preload("res://src/render/leaf_atlas.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const LeafPlacer = preload("res://src/sim/leaf_placer.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const Tip = preload("res://src/sim/tip.gd")
const SimContext = preload("res://src/sim/sim_context.gd")


## Build a LeafColourMetric set up with the default TowerSpec and IvyParams.
func _make_metric() -> LeafColourMetric:
	var m := LeafColourMetric.new()
	m.setup(TowerSpec.new(), IvyParams.new())
	return m


## Add a leaf to the plant at a given world position with a given Color.g and atlas id.
## Position is placed on the outer wall at the given azimuth bin / height bin so that
## CoverageMetric eligibility criteria are met.
## n_leaf (basis.z) = outward radial normal → |dot(n_leaf, n_bucket)| = 1.
func _add_leaf(
	plant: PlantData,
	az_bin: int,
	h_bin: int,
	g_value: float,
	rect: Vector4
) -> void:
	var az_rad := deg_to_rad(float(az_bin) * 5.0 + 2.5)
	var y := float(h_bin) * 0.10 + 0.05
	var nx := sin(az_rad)
	var nz := -cos(az_rad)
	var pos := Vector3(nx * 2.0, y, nz * 2.0)
	var n := Vector3(nx, 0.0, nz)
	var tangent := Vector3(cos(az_rad), 0.0, sin(az_rad))
	var xform := Transform3D(Basis(tangent, Vector3.UP, n), pos)
	# width=0.1, height=0.1 → area = alpha_fill * 0.01 ≈ 0.006
	var col := Color(1.0, g_value, 1.0, 1.0)
	plant.append_leaf(xform, col, rect, 0, 0.0, 0.006, 0.5)


## Sun-side bin: az=180° (south), h=17 (y=1.75m). Seed_az=180° → diff=0 → sun half.
const AZ_SUN := 36    # south
## Shade-side bin: az=315° (northwest), h=17. Seed_az=180° → diff=135° > 90° → shade half.
const AZ_SHADE := 63  # northwest
const H_MID := 17     # y ≈ 1.75 m


# ---------------------------------------------------------------------------
# LG-2a: area-weighted mean Color.g delta
# ---------------------------------------------------------------------------

func test_lg2a_flat_white_plant_delta_is_near_zero() -> void:
	# Both hemispheres with Color.g = 1.0 (white) → delta ≈ 0.
	# This is the flat-plant invariant: the metric MUST distinguish a real plant from this.
	var plant := PlantData.new()
	var atlas := LeafAtlas.new()
	var rect_a := atlas.rect_for("a")
	for _i in range(5):
		_add_leaf(plant, AZ_SUN,   H_MID, 1.0, rect_a)
		_add_leaf(plant, AZ_SHADE, H_MID, 1.0, rect_a)

	var result := _make_metric().measure(plant, 180.0)
	assert_almost_eq(result.lg2a_delta, 0.0, 1e-4,
		"flat white plant: LG-2a delta must be ≈ 0 (metric fails if this does not hold)")


func test_lg2a_positive_when_sun_leaves_are_brighter() -> void:
	# Sun g=1.04 (leaf_sun_tint.g), shade g=0.86 (leaf_shade_tint.g).
	# Expected delta ≈ 0.18 >> 0.03 threshold.
	var plant := PlantData.new()
	var atlas := LeafAtlas.new()
	var rect_a := atlas.rect_for("a")
	for _i in range(5):
		_add_leaf(plant, AZ_SUN,   H_MID, 1.04, rect_a)
		_add_leaf(plant, AZ_SHADE, H_MID, 0.86, rect_a)

	var result := _make_metric().measure(plant, 180.0)
	assert_gt(result.lg2a_delta, 0.0, "sun-brighter plant: LG-2a delta must be positive")
	assert_gt(result.lg2a_delta, 0.03, "sun-brighter plant: LG-2a delta must exceed 0.03 threshold")


func test_lg2a_passes_flag_set_correctly() -> void:
	# With sun_g > shade_g and Δ ≥ 0.03, lg2a_passes must be true.
	var plant := PlantData.new()
	var atlas := LeafAtlas.new()
	var rect_a := atlas.rect_for("a")
	for _i in range(5):
		_add_leaf(plant, AZ_SUN,   H_MID, 1.04, rect_a)
		_add_leaf(plant, AZ_SHADE, H_MID, 0.86, rect_a)

	var result := _make_metric().measure(plant, 180.0)
	assert_true(result.lg2a_passes, "lg2a_passes must be true when delta ≥ 0.03")


# ---------------------------------------------------------------------------
# LG-2b: healthy-tier area-fraction delta
# ---------------------------------------------------------------------------

func test_lg2b_equal_tier_mix_delta_is_near_zero() -> void:
	# Both hemispheres with 50% H and 50% W leaves → delta ≈ 0.
	# Flat-tier invariant.
	var plant := PlantData.new()
	var atlas := LeafAtlas.new()
	var rect_a := atlas.rect_for("a")  # tier H
	var rect_b := atlas.rect_for("b")  # tier W
	for _i in range(4):
		_add_leaf(plant, AZ_SUN,   H_MID, 1.0, rect_a)  # H on sun
		_add_leaf(plant, AZ_SUN,   H_MID, 1.0, rect_b)  # W on sun
		_add_leaf(plant, AZ_SHADE, H_MID, 1.0, rect_a)  # H on shade
		_add_leaf(plant, AZ_SHADE, H_MID, 1.0, rect_b)  # W on shade

	var result := _make_metric().measure(plant, 180.0)
	assert_almost_eq(result.lg2b_delta, 0.0, 1e-4,
		"equal tier mix: LG-2b delta must be ≈ 0")


func test_lg2b_positive_when_sun_is_more_healthy() -> void:
	# Sun: all tier H (healthy), shade: all tier W (weathered).
	# Expected delta = 1.0 - 0.0 = 1.0 >> 0.08 threshold.
	var plant := PlantData.new()
	var atlas := LeafAtlas.new()
	var rect_a := atlas.rect_for("a")  # tier H
	var rect_b := atlas.rect_for("b")  # tier W
	for _i in range(5):
		_add_leaf(plant, AZ_SUN,   H_MID, 1.0, rect_a)  # H on sun
		_add_leaf(plant, AZ_SHADE, H_MID, 1.0, rect_b)  # W on shade

	var result := _make_metric().measure(plant, 180.0)
	assert_gt(result.lg2b_delta, 0.0, "sun=all-healthy plant: LG-2b delta must be positive")
	assert_gt(result.lg2b_delta, 0.08, "sun=all-healthy plant: LG-2b delta must exceed 0.08")


func test_lg2b_passes_flag_set_correctly() -> void:
	var plant := PlantData.new()
	var atlas := LeafAtlas.new()
	var rect_a := atlas.rect_for("a")
	var rect_b := atlas.rect_for("b")
	for _i in range(5):
		_add_leaf(plant, AZ_SUN,   H_MID, 1.0, rect_a)
		_add_leaf(plant, AZ_SHADE, H_MID, 1.0, rect_b)

	var result := _make_metric().measure(plant, 180.0)
	assert_true(result.lg2b_passes, "lg2b_passes must be true when delta ≥ 0.08")


# ---------------------------------------------------------------------------
# LeafAtlas.id_for_rect round-trip (SD-METRIC-7f prerequisite)
# ---------------------------------------------------------------------------

func test_leaf_atlas_id_for_rect_round_trips_for_all_six_ids() -> void:
	# For each atlas id, id_for_rect(rect_for(id)) must return the same id.
	# This is the reverse-lookup used by LG-2b to recover tier from PlantData.leaf_custom.
	var atlas := LeafAtlas.new()
	for id in ["a", "b", "c", "d", "e", "f"]:
		var rect := atlas.rect_for(id)
		var recovered := atlas.id_for_rect(rect)
		assert_eq(recovered, id, "id_for_rect(rect_for('%s')) must return '%s'" % [id, id])


# ---------------------------------------------------------------------------
# W-075 / AR-METRIC-2: LG-2' layer (b) decile_measure() instrument
# ---------------------------------------------------------------------------

## Helper: place N leaves via LeafPlacer at positions that map to eligible buckets.
## Alternates between sun-half and shade-half azimuths using distinct f_L values
## to create a realistic light distribution for the decile instrument.
func _build_decile_plant(n_per_fl: int) -> PlantData:
	var params := IvyParams.new()
	var plant := PlantData.new()
	var ctx := SimContext.new(params, null, null, plant, null, null)
	var f_l_values: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
	for f_l: float in f_l_values:
		for j in range(n_per_fl):
			var tip := Tip.new()
			tip.id = int(f_l * 100.0) + j
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
			# Place leaf at south wall (az=180°, h=17) — eligible bucket, sun half.
			var seg_a := Vector3(0.0, 1.7, 1.9)
			var seg_b := Vector3(0.0, 1.73, 2.0)
			tip.last_contact_normal = Vector3(0.0, 0.0, 1.0)
			LeafPlacer.advance(tip, ctx, seg_a, seg_b, f_l, Basis.IDENTITY)
	return plant


func test_w075_decile_measure_returns_positive_delta_g() -> void:
	## LG-2' layer (b) — decile_measure() must return positive delta_g when
	## leaves with different f_L are present (top-decile leaves are brighter).
	var plant := _build_decile_plant(20)
	var m := _make_metric()
	var result := m.decile_measure(plant, 180.0)
	assert_gt(result["eligible_leaf_count"], 0, "plant must have eligible leaves")
	assert_gt(result["decile_delta_g"], 0.0,
		"decile_delta_g must be positive when top-decile leaves have higher f_L (W-075)")


func test_w075_decile_measure_returns_positive_delta_healthy_frac() -> void:
	## LG-2' layer (b) — top-decile leaves (high f_L) must have higher healthy fraction.
	var plant := _build_decile_plant(20)
	var m := _make_metric()
	var result := m.decile_measure(plant, 180.0)
	assert_gt(result["decile_delta_healthy_frac"], 0.0,
		"top-decile healthy fraction must exceed bottom-decile (SD-LEAF-6, W-075)")


func test_w075_cross_check_residual_is_small_on_real_plant() -> void:
	## AR-METRIC-2 cross-check: recovered f_L' = (Color.g − 0.86) / 0.18 must match
	## PlantData.leaf_light within ε = 1e-4.  A large residual means the tint does not
	## honestly encode the experienced light, making the ranking key non-independent.
	var plant := _build_decile_plant(20)
	var m := _make_metric()
	var result := m.decile_measure(plant, 180.0)
	assert_gt(result["eligible_leaf_count"], 0, "plant must have eligible leaves for cross-check")
	assert_lt(result["max_cross_check_residual"], 1e-4,
		"cross-check residual must be < 1e-4: tint must encode experienced f_L (AR-METRIC-2)")


func test_w075_decile_measure_reports_decile_counts_and_areas() -> void:
	## decile_measure() must report non-zero decile counts and areas.
	var plant := _build_decile_plant(20)
	var m := _make_metric()
	var result := m.decile_measure(plant, 180.0)
	assert_gt(result["bottom_decile_count"], 0, "bottom decile count must be > 0")
	assert_gt(result["top_decile_count"], 0, "top decile count must be > 0")
	assert_gt(result["bottom_decile_area"], 0.0, "bottom decile area must be > 0")
	assert_gt(result["top_decile_area"], 0.0, "top decile area must be > 0")


func test_w075_decile_measure_empty_plant_returns_zero_deltas() -> void:
	## Edge case: an empty plant must return zero deltas and not crash.
	var plant := PlantData.new()
	var m := _make_metric()
	var result := m.decile_measure(plant, 180.0)
	assert_eq(result["eligible_leaf_count"], 0, "empty plant: no eligible leaves")
	assert_almost_eq(result["decile_delta_g"], 0.0, 1e-9, "empty plant: delta_g = 0")
	assert_almost_eq(result["decile_delta_healthy_frac"], 0.0, 1e-9,
		"empty plant: delta_healthy_frac = 0")
