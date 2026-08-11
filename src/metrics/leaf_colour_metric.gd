class_name LeafColourMetric
extends RefCounted

## LG-2 sun/shade leaf-colour separation metric (SD-METRIC-7, W-061).
##
## This is a read-only observer: consumes no RNG, reads no environment field,
## writes nothing to the simulation.  Two identical calls with the same PlantData
## return identical numbers (INV-7 not threatened).
##
## LG-2a and LG-2b are WITHDRAWN (SD-OPEN-10, ratified 2026-08-11).  They are still
## computed, and still reported, but they are **report-only diagnostics** and gate nothing.
## Do not write new code that branches on lg2a_passes or lg2b_passes.
##
## LG-2a: area-weighted mean instance Color.g, sun-facing 180° minus shaded 180°.
## LG-2b: area-weighted healthy-tier area-fraction delta, same hemispheres.
##
## Why they were withdrawn, since the numbers below look like a failure and are not:
## both average a light-derived property over the leaves that exist, and shade suppresses
## growth, so the darkest cells hold almost no leaf area to average.  The measured 180°
## split is therefore dominated by the brightest cells in each hemisphere — leaf-weighted
## f_L came out at 0.9986 sun-facing against 0.9522 shaded, where ratification had assumed
## the shaded *surface* value of 0.736.  Inverting SD-LEAF-7's linear tint reproduced the
## measurement to five figures (predicted Δg 0.00835, measured 0.00834), which is what
## proved the gate's premise wrong rather than its implementation.  Causation in this
## simulation shows up as *absent* leaves, which AS-1 and AS-2 already measure.
##
## The thresholds are retained only so the reported PASS/FAIL keeps a stable meaning for
## anyone reading historical logs; expect FAIL on every canonical run.
##
## LG-2' layer (b) (W-075, AR-METRIC-2): decile_measure() ranks eligible leaves
## by PlantData.leaf_light (the experienced f_L stored at placement — independent of
## the tint under test) and computes top-vs-bottom-decile separation in mean Color.g
## and healthy-tier area fraction.  Threshold deferred to W-077 (report-only).

const _CoverageMetric = preload("res://src/metrics/coverage.gd")
const _LeafAtlas = preload("res://src/render/leaf_atlas.gd")

## Withdrawn thresholds (SD-OPEN-10). Retained so historical logs stay readable; the
## derived lg2a_passes / lg2b_passes fields are diagnostics and gate nothing.
const LG2A_THRESHOLD_WITHDRAWN: float = 0.03
const LG2B_THRESHOLD_WITHDRAWN: float = 0.08

## SD-LEAF-7 tint formula constants used for the cross-check in decile_measure().
## recovered_f_L = (Color.g - SHADE_G) / TINT_SPAN must match leaf_light within ε.
const SHADE_G: float = 0.86
const TINT_SPAN: float = 0.18

var _spec: TowerSpec
var _eligible: PackedByteArray


func setup(spec: TowerSpec, params: IvyParams) -> void:
	_spec = spec
	# Reuse CoverageMetric's opening-exclusion mask verbatim (SD-METRIC-7a).
	var cm := _CoverageMetric.new()
	cm.setup(spec, params)
	_eligible = cm._eligible


## Compute LG-2a and LG-2b from PlantData.
##
## seed_azimuth_deg: seed anchor azimuth (same convention as CoverageMetric;
##   180.0 for the default south seed).
##
## Returns a Dictionary with:
##   lg2a_sun_mean_g, lg2a_shade_mean_g, lg2a_delta, lg2a_passes
##   lg2b_sun_healthy_frac, lg2b_shade_healthy_frac, lg2b_delta, lg2b_passes
##   lg2a_threshold, lg2b_threshold
##   sun_leaf_area, shade_leaf_area
##
## The *_passes fields compare against thresholds withdrawn by SD-OPEN-10 and are
## report-only — they will read false on a healthy plant. Use decile_measure() for the
## live LG-2' layer (b) instrument, and AS-1 / AS-2 for causation.
func measure(plant: PlantData, seed_azimuth_deg: float) -> Dictionary:
	var atlas := _LeafAtlas.new()

	var sun_g_sum: float = 0.0
	var sun_area_sum: float = 0.0
	var sun_healthy_area: float = 0.0

	var shade_g_sum: float = 0.0
	var shade_area_sum: float = 0.0
	var shade_healthy_area: float = 0.0

	var n_leaves := plant.leaf_count()
	for i in range(n_leaves):
		var base := i * 12
		# PlantData leaf_xform: [bx.x, bx.y, bx.z, origin.x,
		#                        by.x, by.y, by.z, origin.y,
		#                        bz.x, bz.y, bz.z, origin.z]
		var ox: float = plant.leaf_xform[base + 3]
		var oy: float = plant.leaf_xform[base + 7]
		var oz: float = plant.leaf_xform[base + 11]

		var az_bin := _CoverageMetric._azimuth_bin_of(ox, oz)
		var h_bin  := _CoverageMetric._height_bin_of(oy)

		if az_bin < 0 or h_bin < 0:
			continue
		if _eligible[az_bin * _CoverageMetric.HEIGHT_BINS + h_bin] == 0:
			continue

		var az_center := float(az_bin) * 5.0 + 2.5
		var in_sun := _CoverageMetric._in_sun_half(az_center, seed_azimuth_deg)

		# SD-METRIC-7c: area-weight on rendered leaf_area so the colour metric reflects
		# the real leaf material present, not the structural coverage basis.
		var area: float = plant.leaf_area[i]
		# leaf_color stores (r, g, b, a) per leaf.
		var g: float = plant.leaf_color[i * 4 + 1]

		# LG-2b: recover tier from the atlas rect stored in leaf_custom.
		# leaf_custom stores (rect.x, rect.y, rect.z, rect.w) per leaf.
		var cx: float = plant.leaf_custom[i * 4 + 0]
		var cy: float = plant.leaf_custom[i * 4 + 1]
		var cz: float = plant.leaf_custom[i * 4 + 2]
		var cw: float = plant.leaf_custom[i * 4 + 3]
		var rect := Vector4(cx, cy, cz, cw)
		var leaf_id := atlas.id_for_rect(rect)
		var is_healthy := (leaf_id != "" and atlas.tier_for(leaf_id) == "H")

		if in_sun:
			sun_g_sum      += area * g
			sun_area_sum   += area
			if is_healthy:
				sun_healthy_area += area
		else:
			shade_g_sum    += area * g
			shade_area_sum += area
			if is_healthy:
				shade_healthy_area += area

	var sun_g_mean   := sun_g_sum   / maxf(sun_area_sum,   1e-9)
	var shade_g_mean := shade_g_sum / maxf(shade_area_sum, 1e-9)
	var lg2a_delta   := sun_g_mean - shade_g_mean

	var sun_h_frac   := sun_healthy_area   / maxf(sun_area_sum,   1e-9)
	var shade_h_frac := shade_healthy_area / maxf(shade_area_sum, 1e-9)
	var lg2b_delta   := sun_h_frac - shade_h_frac

	return {
		"lg2a_sun_mean_g":      sun_g_mean,
		"lg2a_shade_mean_g":    shade_g_mean,
		"lg2a_delta":           lg2a_delta,
		"lg2a_passes":          lg2a_delta >= LG2A_THRESHOLD_WITHDRAWN,
		"lg2b_sun_healthy_frac":   sun_h_frac,
		"lg2b_shade_healthy_frac": shade_h_frac,
		"lg2b_delta":           lg2b_delta,
		"lg2b_passes":          lg2b_delta >= LG2B_THRESHOLD_WITHDRAWN,
		"lg2a_threshold":       LG2A_THRESHOLD_WITHDRAWN,
		"lg2b_threshold":       LG2B_THRESHOLD_WITHDRAWN,
		"thresholds_withdrawn": true,
		"sun_leaf_area":        sun_area_sum,
		"shade_leaf_area":      shade_area_sum,
	}


## LG-2' layer (b) decile instrument (W-075, AR-METRIC-2).
##
## Collects eligible sampled leaves (same eligibility as measure()), sorts them
## ascending by PlantData.leaf_light (the experienced f_L stored at placement —
## the authoritative ranking key, independent of the tint under test).
## Takes the bottom and top decile by leaf count (floor(n × 0.1)).
## Within each decile, computes area-weighted (rendered leaf_area, SD-METRIC-7c)
## mean Color.g and healthy-tier fraction.
##
## Also computes the cross-check residual: recovered_f_L = (Color.g − SHADE_G) / TINT_SPAN
## versus the stored leaf_light.  A large residual means the shipped tint does not encode
## the experienced light — the ranking key is then independent of the metric, and the
## decile separation is a genuine test.
##
## az_sector_center_deg: optional azimuth sector filter centre (0–360, same convention
##   as CoverageMetric).  Pass -1 (default) to include all eligible leaves.
## az_sector_half_deg:   sector half-width in degrees (default 60°).  Ignored when
##   az_sector_center_deg < 0.
##
## Returns a Dictionary with:
##   decile_delta_g            — top_mean_g − bottom_mean_g  (report-only; threshold deferred W-077)
##   decile_delta_healthy_frac — top_healthy_frac − bottom_healthy_frac  (report-only)
##   bottom_decile_boundary    — leaf_light of the highest leaf in the bottom decile
##   top_decile_boundary       — leaf_light of the lowest leaf in the top decile
##   bottom_decile_count       — number of leaves in the bottom decile
##   top_decile_count          — number of leaves in the top decile
##   bottom_decile_area        — total canonical area in the bottom decile
##   top_decile_area           — total canonical area in the top decile
##   max_cross_check_residual  — max |recovered_f_L − leaf_light| over all eligible leaves
##   eligible_leaf_count       — total eligible leaves before decile selection
func decile_measure(
	plant: PlantData, seed_azimuth_deg: float,
	az_sector_center_deg: float = -1.0, az_sector_half_deg: float = 60.0
) -> Dictionary:
	var atlas := _LeafAtlas.new()

	# Collect eligible leaves — same eligibility as measure().
	var elig_lights: PackedFloat32Array = PackedFloat32Array()
	var elig_g: PackedFloat32Array = PackedFloat32Array()
	var elig_areas: PackedFloat32Array = PackedFloat32Array()
	var elig_healthy: PackedByteArray = PackedByteArray()

	var n_leaves := plant.leaf_count()
	for i in range(n_leaves):
		var base := i * 12
		var ox: float = plant.leaf_xform[base + 3]
		var oy: float = plant.leaf_xform[base + 7]
		var oz: float = plant.leaf_xform[base + 11]

		var az_bin := _CoverageMetric._azimuth_bin_of(ox, oz)
		var h_bin := _CoverageMetric._height_bin_of(oy)
		if az_bin < 0 or h_bin < 0:
			continue
		if _eligible[az_bin * _CoverageMetric.HEIGHT_BINS + h_bin] == 0:
			continue

		# Optional azimuth sector filter (for W-077 sector cross-check).
		if az_sector_center_deg >= 0.0:
			var az_center_deg := float(az_bin) * 5.0 + 2.5
			var diff := fposmod(az_center_deg - az_sector_center_deg, 360.0)
			if diff > 180.0:
				diff = 360.0 - diff
			if diff > az_sector_half_deg:
				continue

		var cx: float = plant.leaf_custom[i * 4 + 0]
		var cy: float = plant.leaf_custom[i * 4 + 1]
		var cz: float = plant.leaf_custom[i * 4 + 2]
		var cw: float = plant.leaf_custom[i * 4 + 3]
		var leaf_id := atlas.id_for_rect(Vector4(cx, cy, cz, cw))
		var is_healthy: bool = leaf_id != "" and atlas.tier_for(leaf_id) == "H"

		elig_lights.append(plant.leaf_light[i])
		elig_g.append(plant.leaf_color[i * 4 + 1])
		elig_areas.append(plant.leaf_area[i])  # rendered area (SD-METRIC-7c)
		elig_healthy.append(1 if is_healthy else 0)

	var n_elig := elig_lights.size()
	var empty_result := {
		"decile_delta_g": 0.0,
		"decile_delta_healthy_frac": 0.0,
		"bottom_decile_boundary": 0.0,
		"top_decile_boundary": 1.0,
		"bottom_decile_count": 0,
		"top_decile_count": 0,
		"bottom_decile_area": 0.0,
		"top_decile_area": 0.0,
		"max_cross_check_residual": 0.0,
		"eligible_leaf_count": 0,
	}
	if n_elig == 0:
		return empty_result

	# Sort eligible indices ascending by leaf_light.
	var order: Array = []
	for j in range(n_elig):
		order.append(j)
	order.sort_custom(func(a: int, b: int) -> bool: return elig_lights[a] < elig_lights[b])

	var decile_count := maxi(1, int(floor(float(n_elig) * 0.1)))

	# Bottom decile (lowest leaf_light).
	var bot_g_sum := 0.0
	var bot_area_sum := 0.0
	var bot_healthy_area := 0.0
	for j in range(decile_count):
		var idx: int = order[j]
		var a: float = elig_areas[idx]
		bot_g_sum += a * elig_g[idx]
		bot_area_sum += a
		if elig_healthy[idx] != 0:
			bot_healthy_area += a

	# Top decile (highest leaf_light).
	var top_g_sum := 0.0
	var top_area_sum := 0.0
	var top_healthy_area := 0.0
	for j in range(decile_count):
		var idx: int = order[n_elig - 1 - j]
		var a: float = elig_areas[idx]
		top_g_sum += a * elig_g[idx]
		top_area_sum += a
		if elig_healthy[idx] != 0:
			top_healthy_area += a

	var bot_g_mean := bot_g_sum / maxf(bot_area_sum, 1e-9)
	var top_g_mean := top_g_sum / maxf(top_area_sum, 1e-9)
	var bot_healthy_frac := bot_healthy_area / maxf(bot_area_sum, 1e-9)
	var top_healthy_frac := top_healthy_area / maxf(top_area_sum, 1e-9)

	# Decile light boundaries (leaf_light of the boundary leaf in each decile).
	var bot_boundary: float = elig_lights[order[decile_count - 1]]
	var top_boundary: float = elig_lights[order[n_elig - decile_count]]

	# Cross-check: recovered_f_L = (Color.g − SHADE_G) / TINT_SPAN vs leaf_light.
	# A small residual confirms the shipped tint encodes the experienced light honestly.
	# See AR-METRIC-2 for why ranking by recovery alone would be circular.
	var max_residual := 0.0
	for j in range(n_elig):
		var recovered_f := (elig_g[j] - SHADE_G) / TINT_SPAN
		var residual := absf(recovered_f - float(elig_lights[j]))
		if residual > max_residual:
			max_residual = residual

	return {
		"decile_delta_g":            top_g_mean - bot_g_mean,
		"decile_delta_healthy_frac": top_healthy_frac - bot_healthy_frac,
		"bottom_decile_boundary":    bot_boundary,
		"top_decile_boundary":       top_boundary,
		"bottom_decile_count":       decile_count,
		"top_decile_count":          decile_count,
		"bottom_decile_area":        bot_area_sum,
		"top_decile_area":           top_area_sum,
		"max_cross_check_residual":  max_residual,
		"eligible_leaf_count":       n_elig,
	}
