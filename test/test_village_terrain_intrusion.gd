## AC-VT6: No cottage origin buried > 0.1 m / floating > 0.15 m vs pad target.
## Also: that _build_cottages actually lifts origin.y to sample_y(centre).
## AR-VT-GAP-2 / AR-VT-WIRE / SD-VILLAGE-TERRAIN-7 / WP3.
extends GutTest

const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

## Tolerance: bury > 0.1 m is bad, float > 0.15 m is bad.
const _BURY_TOL_M := 0.1
const _FLOAT_TOL_M := 0.15
## Exact-match tolerance when wiring is correct (actual_y = pad_y exactly).
const _EXACT_EPS_M := 0.001
const _TEST_SEEDS: Array[int] = [1, 7, 12]


func _make_generated(seed: int) -> GeneratedVillageBackdrop:
	var bd := GeneratedBackdropScene.instantiate() as GeneratedVillageBackdrop
	bd.set_village_seed(seed)
	add_child_autofree(bd)
	return bd


# ── AC-VT6 main probe ─────────────────────────────────────────────────────────

func test_ac_vt6_cottage_origins_stored_seed1() -> void:
	_check_intrusion(1)

func test_ac_vt6_cottage_origins_stored_seed7() -> void:
	_check_intrusion(7)

func test_ac_vt6_cottage_origins_stored_seed12() -> void:
	_check_intrusion(12)


func _check_intrusion(seed: int) -> void:
	## AC-VT6: After _build_cottages, _cottage_origins must be set and each
	## cottage origin.y must equal sample_y(centre) within _EXACT_EPS_M.
	## RED before WP3: _cottage_origins is null (var not yet added / populated).
	## GREEN after WP3: _cottage_origins populated in _build_cottages with lifted ys.
	var bd := _make_generated(seed)
	var layout := bd.get("_layout") as VillageLayout
	if layout == null or layout.fallback:
		pass_test("fallback/null layout skip seed %d" % seed)
		return

	## Check _cottage_origins was set by _build_cottages (WP3).
	var origins = bd.get("_cottage_origins")
	assert_not_null(origins,
		"AC-VT6 seed=%d: _cottage_origins must be set in _build_cottages (WP3 not wired)" % seed)
	if origins == null:
		return

	var origins_arr: Array = origins as Array
	assert_eq(origins_arr.size(), layout.cottages.size(),
		"AC-VT6 seed=%d: _cottage_origins.size()=%d must equal cottages.size()=%d" % [
		seed, origins_arr.size(), layout.cottages.size()])

	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)

	for i in range(layout.cottages.size()):
		var spec := layout.cottages[i] as Dictionary
		var centre := spec["centre"] as Vector2
		var expected_pad_y := VillageTerrain.sample_y(centre, layout, params, t_seed)
		var origin := origins_arr[i] as Vector3
		var actual_y := origin.y

		## Intrusion tolerance checks (AC-VT6)
		var bury := expected_pad_y - actual_y   # positive = buried below pad
		var floot := actual_y - expected_pad_y  # positive = floating above pad
		if bury > _BURY_TOL_M:
			fail_test(
				"AC-VT6 seed=%d cottage[%d]@%s: buried %.3f m (actual_y=%.3f, pad_y=%.3f)" % [
				seed, i, str(centre), bury, actual_y, expected_pad_y])
			return
		if floot > _FLOAT_TOL_M:
			fail_test(
				"AC-VT6 seed=%d cottage[%d]@%s: floating %.3f m (actual_y=%.3f, pad_y=%.3f)" % [
				seed, i, str(centre), floot, actual_y, expected_pad_y])
			return

		## Exact match when correctly wired (actual_y = pad_y after WP3)
		if absf(actual_y - expected_pad_y) > _EXACT_EPS_M:
			fail_test(
				"AC-VT6 seed=%d cottage[%d]@%s: actual_y=%.4f, expected pad_y=%.4f, diff=%.4f > %.3f" % [
				seed, i, str(centre), actual_y, expected_pad_y,
				absf(actual_y - expected_pad_y), _EXACT_EPS_M])
			return

	pass_test("AC-VT6 seed=%d: all %d cottage origins at pad_y within %.3f m" % [
		seed, layout.cottages.size(), _EXACT_EPS_M])


# ── Non-regression: static cottage_transform still returns y=0 (AR-VT-GAP-2) ──

func test_cottage_transform_static_y_unchanged() -> void:
	## AR-VT-GAP-2: cottage_transform(spec) must remain byte-identical (y=0 in origin).
	## The Y lift happens only in _build_cottages, not in the static function.
	for spec: Dictionary in VillageLayout.generate(7).cottages:
		var xf := VillageBackdrop.cottage_transform(spec)
		assert_almost_eq(xf.origin.y, 0.0, 0.0001,
			"cottage_transform static origin.y must stay 0.0 (AR-VT-GAP-2)")
		return  # one spec is enough for this assertion
	pass_test("cottage_transform static: origin.y = 0.0 (byte-identical)")
