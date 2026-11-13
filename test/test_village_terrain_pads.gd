## AC-VT5: Cottage pad interior flatness and skirt slope probe.
## Each pad interior |sample_y(p) − sample_y(centre)| ≤ 0.05 m (hard assertion).
## Skirt slope ≤ tan(pad_edge_slope_max_deg) per SD AC-VT5 (8° default → 0.1405 m/m).
## SD-VILLAGE-TERRAIN-4 §Cottage pads / AR-VT-TESTS / WP3.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _PAD_INTERIOR_EPS_M := 0.05    # AC-VT5 flatness tolerance
const _SLOPE_STEP_M := 0.25          # measurement step for skirt slope
const _TEST_SEEDS: Array[int] = [1, 7, 12]


# ── helpers ───────────────────────────────────────────────────────────────────

## Signed distance from p to the INSIDE of rect (negative = inside, positive = outside).
static func _rect_sdf(p: Vector2, rect: Rect2) -> float:
	var c := rect.get_center()
	var half := rect.size * 0.5
	var dx := absf(p.x - c.x) - half.x
	var dz := absf(p.y - c.y) - half.y
	return maxf(dx, dz)


# ── AC-VT5 part 1: interior flatness ─────────────────────────────────────────

func test_pad_interior_flat_seed1() -> void:
	_check_interior_flat(1)

func test_pad_interior_flat_seed7() -> void:
	_check_interior_flat(7)

func test_pad_interior_flat_seed12() -> void:
	_check_interior_flat(12)


func _check_interior_flat(seed: int) -> void:
	## For every cottage: sample a 3×3 grid inside the grown pad rect.
	## |h − h_centre| must be ≤ 0.05 m at each interior point (AC-VT5).
	var layout := VillageLayout.generate(seed)
	if layout.fallback:
		pass_test("fallback skip seed %d" % seed)
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)

	for spec: Dictionary in layout.cottages:
		var centre := spec["centre"] as Vector2
		var h_centre := VillageTerrain.sample_y(centre, layout, params, t_seed)
		var grown := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)

		# 3×3 interior grid, 40% of half-size inward so we're well inside any skirt
		var half := grown.size * 0.5 * 0.4
		var offsets := [
			Vector2(-half.x, -half.y), Vector2(0, -half.y), Vector2(half.x, -half.y),
			Vector2(-half.x, 0),       Vector2(0, 0),        Vector2(half.x, 0),
			Vector2(-half.x, half.y),  Vector2(0, half.y),   Vector2(half.x, half.y),
		]

		for off: Vector2 in offsets:
			var p := centre + off
			var h := VillageTerrain.sample_y(p, layout, params, t_seed)
			var dev := absf(h - h_centre)
			if dev > _PAD_INTERIOR_EPS_M:
				fail_test(
					"AC-VT5 seed=%d cottage@%s: interior p=%s h=%.4f vs h_centre=%.4f dev=%.4f > %.3f" % [
					seed, str(centre), str(p), h, h_centre, dev, _PAD_INTERIOR_EPS_M])
				return
	pass_test("AC-VT5 pad interior flat: seed=%d, all cottages ≤ %.3f m dev" % [
		seed, _PAD_INTERIOR_EPS_M])


# ── AC-VT5 part 2: skirt slope ───────────────────────────────────────────────

func test_pad_skirt_slope_seed1() -> void:
	_check_pad_skirt_slope(1)

func test_pad_skirt_slope_seed7() -> void:
	_check_pad_skirt_slope(7)

func test_pad_skirt_slope_seed12() -> void:
	_check_pad_skirt_slope(12)


func test_cottage_pad_heights_relaxation_limits_neighbor_delta_seed1() -> void:
	## Regression (bold relief): neighbour pad datums stay within gap*tan(8°) after relaxation.
	var layout := VillageLayout.generate(1)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	VillageTerrain.clear_knoll_centres_cache()
	var grade_cap := tan(deg_to_rad(params.pad_edge_slope_max_deg)) * 0.90
	for i in layout.cottages.size():
		var ci: Vector2 = layout.cottages[i]["centre"]
		for j in range(i + 1, layout.cottages.size()):
			var cj: Vector2 = layout.cottages[j]["centre"]
			var gap := maxf(ci.distance_to(cj) - 5.5, 2.0)
			var hi := VillageTerrain.sample_y(ci, layout, params, t_seed)
			var hj := VillageTerrain.sample_y(cj, layout, params, t_seed)
			var allowed := grade_cap * gap + 0.05
			assert_lte(absf(hi - hj), allowed,
				"seed1 pads %d↔%d Δh=%.3f > gap*tan(8°)=%.3f" % [i, j, absf(hi - hj), allowed])


func test_pad_skirt_multi_pad_tail_reset_seed1() -> void:
	## Regression ivy-82zn.8: sequential pad lerps let a later w≈0 cottage erase a
	## high-weight neighbour; 0.25 m steps saw cliffs at this west-skirt probe pair.
	var layout := VillageLayout.generate(1)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var slope_max := tan(deg_to_rad(params.pad_edge_slope_max_deg))
	var p0 := Vector2(-23.90287, -21.1129)
	var p1 := Vector2(-24.15287, -21.1129)
	var grade := absf(
		VillageTerrain.sample_y(p1, layout, params, t_seed)
		- VillageTerrain.sample_y(p0, layout, params, t_seed)) / _SLOPE_STEP_M
	assert_lte(grade, slope_max + 0.001,
		"seed1 multi-pad tail-reset grade=%.4f" % grade)


func _check_pad_skirt_slope(seed: int) -> void:
	## Sample pairs across each pad skirt (just outside grown rect → skirt boundary).
	var layout := VillageLayout.generate(seed)
	if layout.fallback:
		pass_test("fallback skip seed %d" % seed)
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	# SD AC-VT5: measure grade across the widened fer skirt (≥ pad_skirt_m per edge-slope guarantee).
	var skirt_m := VillageTerrain.pad_skirt_outer_m(params, layout, t_seed)
	var slope_max := tan(deg_to_rad(params.pad_edge_slope_max_deg))
	var worst := 0.0

	for spec: Dictionary in layout.cottages:
		var centre := spec["centre"] as Vector2
		var grown := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var cardinals := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
		for dir: Vector2 in cardinals:
			var prev_p := centre
			var prev_y := VillageTerrain.sample_y(centre, layout, params, t_seed)
			var prev_sdf := _rect_sdf(centre, grown)
			var guard := 0
			var p := centre
			while prev_sdf <= skirt_m + _SLOPE_STEP_M and guard < 400:
				guard += 1
				p += dir * _SLOPE_STEP_M
				var sdf := _rect_sdf(p, grown)
				if sdf < -_SLOPE_STEP_M:
					prev_y = VillageTerrain.sample_y(p, layout, params, t_seed)
					prev_p = p
					prev_sdf = sdf
					continue
				if sdf > skirt_m + _SLOPE_STEP_M:
					break
				var h := VillageTerrain.sample_y(p, layout, params, t_seed)
				var ds := sdf - prev_sdf
				if ds < _SLOPE_STEP_M * 0.45:
					prev_y = h
					prev_p = p
					prev_sdf = sdf
					continue
				var grade := absf(h - prev_y) / ds
				worst = maxf(worst, grade)
				prev_y = h
				prev_p = p
				prev_sdf = sdf
	assert_lte(
		worst, slope_max + 0.001,
		"AC-VT5 seed=%d: worst pad-skirt grade=%.4f > tan(%.1f°)=%.4f" % [
			seed, worst, params.pad_edge_slope_max_deg, slope_max])
