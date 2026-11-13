## AC-VT8: Rim circle r = lawn_radius — VillageTerrain.sample_y vs HillsHeightfield.sample_y
## ≤ rim_eps_m (0.05 m) at ≥ 64 azimuths; inward radial gradient ≤ 0.12 m/m over 2 m.
## AR-VT-SEAM / SD-VILLAGE-TERRAIN-6 / WP2.
extends GutTest

const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsParams = preload("res://src/playground/hills_params.gd")

const _RIM_AZIMUTHS := 64
const _RIM_EPS_M := 0.05          # SD-VILLAGE-TERRAIN-2 rim_eps_m
const _GRAD_MAX_M_PER_M := 0.12   # SD-VILLAGE-TERRAIN-6 inward gradient cap
const _GRAD_STEP_M := 2.0         # gradient measured over 2 m inward
const _TEST_SEEDS: Array[int] = [7]  # primary seed; rim is deterministic


func _rim_points(layout: VillageLayout, azimuths: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	for i in range(azimuths):
		var phi := float(i) / float(azimuths) * TAU
		pts.append(g + Vector2(cos(phi) * r, sin(phi) * r))
	return pts


func test_rim_parity_seed7() -> void:
	## AC-VT8 part 1: |VillageTerrain.sample_y - HillsHeightfield.sample_y| ≤ 0.05 m
	## at 64 azimuths on r = lawn_radius for seed 7.
	var seed := 7
	var layout := VillageLayout.generate(seed)
	if layout.fallback:
		pass_test("fallback skip seed %d" % seed)
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var hills_params := HillsParams.production()
	var h_seed := HillsHeightfield.terrain_seed(layout, hills_params)
	var pts := _rim_points(layout, _RIM_AZIMUTHS)
	var max_delta := 0.0
	for p: Vector2 in pts:
		var y_lawn := VillageTerrain.sample_y(p, layout, params, t_seed)
		var y_hills := HillsHeightfield.sample_y(p, layout, hills_params, h_seed)
		var delta := absf(y_lawn - y_hills)
		if delta > max_delta:
			max_delta = delta
		if delta > _RIM_EPS_M:
			fail_test(
				"AC-VT8 seed=%d: rim at %s: |lawn %.4f − hills %.4f| = %.4f > rim_eps %.3f" % [
				seed, str(p), y_lawn, y_hills, delta, _RIM_EPS_M])
			return
	pass_test("AC-VT8 seed=%d: max |Δ| = %.4f m ≤ %.3f (64 azimuths)" % [seed, max_delta, _RIM_EPS_M])


func test_rim_parity_north_wedge_azimuths() -> void:
	## AC-VT8 extra: azimuths inside the north wedge (0°–45°) where hills have relief.
	## Rim must still hold ≤ 0.05 m regardless of hill azimuth weighting.
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var hills_params := HillsParams.production()
	var h_seed := HillsHeightfield.terrain_seed(layout, hills_params)
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	# North = −Z, i.e. phi = PI/2 offset (XZ plane: north = +Z direction in Vector2)
	# Sample azimuths 330°..30° (north wedge) at fine 5° steps.
	var north_azimuths: Array[float] = [-30, -20, -10, 0, 10, 20, 30]
	for az_deg: float in north_azimuths:
		var az_rad := deg_to_rad(az_deg)
		# Compass: 0=north(+Z in XZ), 90=east(+X). Vector: x=sin(az), z=cos(az)... but
		# VillageLayout uses Vector2(x, z), so north = Vector2(0, -1) in world space.
		# In Vector2 terms: north is −Y, east is +X.
		var dir := Vector2(sin(az_rad), -cos(az_rad))
		var p := g + dir * r
		var y_lawn := VillageTerrain.sample_y(p, layout, params, t_seed)
		var y_hills := HillsHeightfield.sample_y(p, layout, hills_params, h_seed)
		var delta := absf(y_lawn - y_hills)
		if delta > _RIM_EPS_M:
			fail_test(
				"AC-VT8 north-wedge az=%.0f°: |lawn %.4f − hills %.4f| = %.4f > %.3f" % [
				az_deg, y_lawn, y_hills, delta, _RIM_EPS_M])
			return
	pass_test("AC-VT8 north-wedge 7 azimuths all within rim_eps_m")


func test_inward_gradient_le_012() -> void:
	## AC-VT8 part 2: inward radial gradient ≤ 0.12 m/m over 2 m inside the rim.
	## Ensures no inward cliff at the rim join (SD-VILLAGE-TERRAIN-6).
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var r_rim := layout.lawn_radius
	var r_inner := r_rim - _GRAD_STEP_M
	var max_grad := 0.0
	for i in range(_RIM_AZIMUTHS):
		var phi := float(i) / float(_RIM_AZIMUTHS) * TAU
		var dir := Vector2(cos(phi), sin(phi))
		var p_rim := g + dir * r_rim
		var p_in := g + dir * r_inner
		var y_rim := VillageTerrain.sample_y(p_rim, layout, params, t_seed)
		var y_in := VillageTerrain.sample_y(p_in, layout, params, t_seed)
		var grad := absf(y_in - y_rim) / _GRAD_STEP_M
		if grad > max_grad:
			max_grad = grad
		if grad > _GRAD_MAX_M_PER_M:
			fail_test(
				"AC-VT8 inward gradient at azimuth %d: %.4f m/m > %.3f m/m cap" % [
				i, grad, _GRAD_MAX_M_PER_M])
			return
	pass_test("AC-VT8 inward gradient: max %.4f m/m ≤ %.3f (64 azimuths)" % [
		max_grad, _GRAD_MAX_M_PER_M])


func test_rim_y_lawn_is_zero() -> void:
	## VillageTerrain.sample_y exactly at r = lawn_radius returns Y_BASE (0.0).
	## rim_taper(lawn_radius) = 0 by definition. (SD-VILLAGE-TERRAIN-3 §rim_taper)
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip"); return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	var max_dev := 0.0
	for i in range(32):
		var phi := float(i) / 32.0 * TAU
		var p := g + Vector2(cos(phi) * r, sin(phi) * r)
		var y := VillageTerrain.sample_y(p, layout, params, t_seed)
		var dev := absf(y)
		if dev > max_dev:
			max_dev = dev
	assert_almost_eq(max_dev, 0.0, 0.001, "sample_y at rim must be Y_BASE (0.0) at all azimuths")


func test_rim_seam_numbers() -> void:
	## Documents the rim numbers for WP2 evidence.
	## AR-VT-SEAM: lawn rim = 0.0, hills rim = y_lawn (-0.03), |Δ| = 0.03 ≤ 0.05.
	## TERRAIN_BASE_LIFT (0.05) is mesh-only, not in sample_y.
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip"); return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var hills_params := HillsParams.production()
	var h_seed := HillsHeightfield.terrain_seed(layout, hills_params)
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	var p := g + Vector2(r, 0.0)
	var y_lawn_terrain := VillageTerrain.sample_y(p, layout, params, t_seed)
	var y_hills_rim := HillsHeightfield.sample_y(p, layout, hills_params, h_seed)
	var delta := absf(y_lawn_terrain - y_hills_rim)
	# Document: hill mesh vertex at rim = y_hills_rim + TERRAIN_BASE_LIFT = -0.03 + 0.05 = +0.02
	var hill_mesh_vertex_y := y_hills_rim + HillsHeightfield.TERRAIN_BASE_LIFT
	assert_almost_eq(y_lawn_terrain, 0.0, 0.001,
		"VillageTerrain.sample_y at rim = Y_BASE (0.0)")
	assert_almost_eq(y_hills_rim, -0.03, 0.001,
		"HillsHeightfield.sample_y at rim = y_lawn (-0.03)")
	assert_true(delta <= 0.05,
		"Rim delta %f ≤ 0.05 (rim_eps_m)" % delta)
	# Hill mesh surface is at +0.02 m (TERRAIN_BASE_LIFT offsets for rendering only)
	assert_almost_eq(hill_mesh_vertex_y, 0.02, 0.001,
		"Hill mesh vertex Y at rim = y_lawn + TERRAIN_BASE_LIFT = +0.02 m")
	pass_test("Rim numbers: lawn_y=%.3f, hills_y=%.3f, |Δ|=%.3f, hill_mesh_y=%.3f" % [
		y_lawn_terrain, y_hills_rim, delta, hill_mesh_vertex_y])
