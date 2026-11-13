## AC-VT-HERO: |sample_y| ≤ 0.02 for r < hero_flat_r_m from HERO_DOOR_STOOP.
## Also: caps, mesh tri budget, sample_normal unit length, rim taper.
## SD-VILLAGE-TERRAIN-3/4 / AR-VT-DECIDE-2/3 / AR-VT-TESTS.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillagePondSite = preload("res://src/world/village_pond_site.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")


func test_hero_stoop_exact_zero() -> void:
	# AC-VT-HERO: exact stoop position must be flat = 0.0
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var y := VillageTerrain.sample_y(VillageLayout.HERO_DOOR_STOOP, layout, params, t_seed)
	assert_almost_eq(y, 0.0, 0.001, "hero stoop exact: |y| ≤ 0.001")


func test_hero_sanctum_flat_within_disc() -> void:
	# AC-VT-HERO: |sample_y| ≤ 0.02 for r < hero_flat_r_m − 0.5 m
	for seed: int in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			pass_test("fallback skip seed %d" % seed)
			continue
		var params := VillageTerrainParams.production()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var stoop := VillageLayout.HERO_DOOR_STOOP
		var test_r := params.hero_flat_r_m - 0.5
		var angles := 16
		for i in range(angles):
			var phi := (float(i) / angles) * TAU
			var xz := stoop + Vector2(sin(phi), cos(phi)) * test_r
			var y := VillageTerrain.sample_y(xz, layout, params, t_seed)
			if absf(y) > 0.02:
				fail_test("seed=%d: hero sanctum at r=%.1f phi=%.2f: |y|=%.4f > 0.02" % [
					seed, test_r, phi, absf(y)])
				return
	pass_test("hero sanctum flat for all seeds")


func test_caps_respected_for_all_seeds() -> void:
	# SD-VILLAGE-TERRAIN-3: h = clamp(h, -max_depression_m, max_rise_m) + 0.05 safety margin
	for seed: int in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			pass_test("fallback skip seed %d" % seed)
			continue
		var params := VillageTerrainParams.production()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var g := layout.hamlet_centre_xz
		var step := 5.0
		var half := 40.0
		var x := -half
		while x <= half:
			var z := -half
			while z <= half:
				var xz := g + Vector2(x, z)
				var y := VillageTerrain.sample_y(xz, layout, params, t_seed)
				if y < -(params.max_depression_m + 0.06):
					fail_test("seed=%d xz=%s: y=%.4f below -max_depression-0.06" % [seed, str(xz), y])
					return
				if y > params.max_rise_m + 0.06:
					fail_test("seed=%d xz=%s: y=%.4f above max_rise+0.06" % [seed, str(xz), y])
					return
				z += step
			x += step
	pass_test("caps respected for all seeds")


func test_build_mesh_seed_12345_under_15s() -> void:
	## Regression: full displaced mesh must not re-sample every vertex (was ~130s hang).
	var layout := VillageLayout.generate(12345)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t0 := Time.get_ticks_msec()
	var mesh := VillageTerrain.build_mesh(layout, params)
	var ms := Time.get_ticks_msec() - t0
	assert_not_null(mesh, "build_mesh returns mesh")
	assert_lt(ms, 15000, "build_mesh seed 12345 must finish <15s (got %d ms)" % ms)


func test_build_mesh_tris_target_budget() -> void:
	# AR-VT-DECIDE-3: ≤ 8k tris target (hard cap 16k)
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var mesh := VillageTerrain.build_mesh(layout, params)
	assert_not_null(mesh, "build_mesh returns non-null ArrayMesh")
	assert_gt(mesh.get_surface_count(), 0, "mesh has at least one surface")
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tris := verts.size() / 3
	assert_lte(tris, 8000, "mesh tris ≤ 8k target (got %d)" % tris)


func test_build_mesh_tris_hard_cap() -> void:
	# Hard cap 16k — even at 1 m cell size
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	params.terrain_mesh_step_m = 1.0
	var mesh := VillageTerrain.build_mesh(layout, params)
	assert_not_null(mesh, "build_mesh returns non-null at 1m step")
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tris := verts.size() / 3
	assert_lte(tris, 16000, "mesh tris ≤ 16k hard cap at 1m step (got %d)" % tris)


func test_sample_normal_is_unit_vector() -> void:
	# sample_normal returns normalized Vector3
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var probes: Array[Vector2] = [g, g + Vector2(10, 5), g + Vector2(-15, 20), g + Vector2(0, -25)]
	for xz: Vector2 in probes:
		var n := VillageTerrain.sample_normal(xz, layout, params, t_seed)
		assert_almost_eq(n.length(), 1.0, 0.001, "normal is unit at %s" % str(xz))
		assert_gt(n.y, 0.0, "normal.y > 0 (upward-facing) at %s" % str(xz))


func test_rim_taper_near_boundary() -> void:
	# SD-VILLAGE-TERRAIN-3: rim_taper(r) → 0 at r = lawn_radius; sample_y ≈ 0 near rim
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var angles := 16
	# Just inside the rim blend zone: r = lawn_radius - 0.2
	for i in range(angles):
		var phi := (float(i) / angles) * TAU
		var xz := g + Vector2(sin(phi), cos(phi)) * (layout.lawn_radius - 0.2)
		var y := VillageTerrain.sample_y(xz, layout, params, t_seed)
		assert_almost_eq(y, 0.0, 0.08, "near rim taper: |y| ≤ 0.08 at phi=%.1f" % phi)


func test_build_mesh_variant1_is_not_null() -> void:
	# Flat variant still returns a mesh (LawnGround fan; byte-parity)
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	params.variant = 1
	var mesh := VillageTerrain.build_mesh(layout, params)
	assert_not_null(mesh, "variant=1 build_mesh returns non-null")


func test_knoll_centres_count_within_requested() -> void:
	# knoll_centres returns at most knoll_count entries
	for seed: int in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			pass_test("fallback skip seed %d" % seed)
			continue
		var params := VillageTerrainParams.production()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var centres := VillageTerrain.knoll_centres(layout, params, t_seed)
		assert_lte(centres.size(), params.knoll_count,
			"seed=%d: knoll_centres size ≤ knoll_count" % seed)


func test_knoll_centres_hero_clearance() -> void:
	# SD-VILLAGE-TERRAIN-4: no mound centre within knoll_hero_clear_m of HERO_DOOR_STOOP
	for seed: int in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			pass_test("fallback skip seed %d" % seed)
			continue
		var params := VillageTerrainParams.production()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var centres := VillageTerrain.knoll_centres(layout, params, t_seed)
		var stoop := VillageLayout.HERO_DOOR_STOOP
		for c: Vector2 in centres:
			var dist := c.distance_to(stoop)
			assert_gte(dist, params.knoll_hero_clear_m - 0.01,
				"seed=%d: knoll at %s too close to hero stoop (dist=%.2f)" % [seed, str(c), dist])


func test_knoll_centres_sun_corridor_respected() -> void:
	# SD-VILLAGE-TERRAIN-4: no mound centre within knoll_sun_corridor_half_deg of sun E/W azimuths
	for seed: int in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			pass_test("fallback skip seed %d" % seed)
			continue
		var params := VillageTerrainParams.production()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var centres := VillageTerrain.knoll_centres(layout, params, t_seed)
		var g := layout.hamlet_centre_xz
		for c: Vector2 in centres:
			var dx := c.x - g.x
			var dz := c.y - g.y
			# azimuth: 0=north(−Z/−dz), 90=east(+X/+dx)
			var az := rad_to_deg(atan2(dx, -dz))
			if az < 0.0:
				az += 360.0
			# Check not within half_deg of east (90°) or west (270°)
			var d_east := minf(absf(az - 90.0), 360.0 - absf(az - 90.0))
			var d_west := minf(absf(az - 270.0), 360.0 - absf(az - 270.0))
			var half := params.knoll_sun_corridor_half_deg
			assert_gte(d_east, half - 0.01,
				"seed=%d knoll az=%.1f within %.0f° of east" % [seed, az, half])
			assert_gte(d_west, half - 0.01,
				"seed=%d knoll az=%.1f within %.0f° of west" % [seed, az, half])


func test_production_open_lawn_relief_floor_seed7() -> void:
	## Regression: open-lawn envelope must keep seed-7 relief visible (anti timid defaults).
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	var min_h := INF
	var max_h := -INF
	var min_open := INF
	var max_open_h := -INF
	var max_open_slope := 0.0
	var step := 2.0
	var x := g.x - r
	while x <= g.x + r:
		var z := g.y - r
		while z <= g.y + r:
			var xz := Vector2(x, z)
			if xz.distance_to(g) < r:
				var h := VillageTerrain.sample_y(xz, layout, params, t_seed)
				min_h = minf(min_h, h)
				max_h = maxf(max_h, h)
				if _open_lawn_probe_point(xz, layout, params, t_seed, false):
					min_open = minf(min_open, h)
					max_open_h = maxf(max_open_h, h)
				if _open_lawn_probe_point(xz, layout, params, t_seed, true):
					max_open_slope = maxf(max_open_slope, VillageTerrain.sample_slope_deg(
						xz, layout, params, t_seed))
			z += step
		x += step
	var open_span := max_open_h - min_open if min_open < INF else 0.0
	assert_gte(open_span, 0.48, "seed7 open-lawn h span ≥ 0.48 m")
	assert_gte(max_h - min_h, 0.30, "seed7 production h span ≥ 0.30 m")
	assert_gte(max_open_slope, 2.0, "seed7 open-lawn slope ≥ 2°")
	assert_lte(max_open_slope, 8.01, "seed7 open-lawn slope ≤ 8° cap")


static func _open_lawn_probe_point(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		for_slope: bool) -> bool:
	var g := layout.hamlet_centre_xz
	if xz.distance_to(g) > layout.lawn_radius - params.rim_blend_m - 1.0:
		return false
	if for_slope:
		var pond_r := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m + params.pond_skirt_m + 1.0
		if xz.distance_to(layout.pond_center) < pond_r:
			return false
	for polyline: Variant in layout.path_polylines():
		var pts: Array = polyline
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var ab := b - a
			var t := clampf((xz - a).dot(ab) / maxf(ab.dot(ab), 1e-6), 0.0, 1.0)
			if for_slope and xz.distance_to(a + ab * t) < 5.0:
				return false
	var skirt_outer := VillageTerrain.pad_skirt_outer_m(params, layout, t_seed) + 1.0
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var c := rect.get_center()
		var half := rect.size * 0.5
		var sdf := maxf(absf(xz.x - c.x) - half.x, absf(xz.y - c.y) - half.y)
		if sdf <= skirt_outer:
			return false
	return true
