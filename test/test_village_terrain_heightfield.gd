## AC-VT-HERO: |sample_y| ≤ 0.02 for r < hero_flat_r_m from HERO_DOOR_STOOP.
## Also: caps, mesh tri budget, sample_normal unit length, rim taper.
## SD-VILLAGE-TERRAIN-3/4 / AR-VT-DECIDE-2/3 / AR-VT-TESTS.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillagePondSite = preload("res://src/world/village_pond_site.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")
const VillageViewRelief = preload("res://tools/village_view_relief.gd")


func test_hero_stoop_exact_zero() -> void:
	# AC-VT-HERO: exact stoop position is the hero datum (ivy-82zn.14.10: the hill crest,
	# hero_datum_y; World lowers the village by it so the stoop is at world y 0).
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var y := VillageTerrain.sample_y(VillageLayout.HERO_DOOR_STOOP, layout, params, t_seed)
	assert_almost_eq(y, VillageTerrain.hero_datum_y(layout, params), 0.001, "hero stoop at the datum")


func test_hero_sanctum_flat_within_disc() -> void:
	# AC-VT-HERO: |sample_y − hero datum| ≤ 0.02 for r < hero_flat_r_m − 0.5 m
	for seed: int in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			pass_test("fallback skip seed %d" % seed)
			continue
		var params := VillageTerrainParams.production()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var datum := VillageTerrain.hero_datum_y(layout, params)
		var stoop := VillageLayout.HERO_DOOR_STOOP
		var test_r := params.hero_flat_r_m - 0.5
		var angles := 16
		for i in range(angles):
			var phi := (float(i) / angles) * TAU
			var xz := stoop + Vector2(sin(phi), cos(phi)) * test_r
			var y := VillageTerrain.sample_y(xz, layout, params, t_seed)
			if absf(y - datum) > 0.02:
				fail_test("seed=%d: hero sanctum at r=%.1f phi=%.2f: |y − datum|=%.4f > 0.02" % [
					seed, test_r, phi, absf(y - datum)])
				return
	pass_test("hero sanctum flat for all seeds")


func test_caps_respected_for_all_seeds() -> void:
	# SD-VILLAGE-TERRAIN-3: h = clamp(h, -max_depression_m, max_rise_m) + 0.05 safety margin.
	# ivy-82zn.14.10: the caps clamp the detail layer only (never the hill) — measured on detail_y.
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
				var y := VillageTerrain.detail_y(xz, layout, params, t_seed)
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


func test_knoll_centres_clear_cottage_pads() -> void:
	## ivy-82zn.14.1: like paths, a knoll centre sits ≥ knoll_pad_clear_m from every grown pad rect,
	## so the taller mound's flank does not ride the pad relief-fade ramp (seed 5 hit 10.8°).
	for seed: int in [1, 5, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var params := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		for c: Vector2 in VillageTerrain.knoll_centres(layout, params, t_seed):
			for spec: Dictionary in layout.cottages:
				var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
				var sdf := VillageTerrain._rect_sdf(c, rect)
				assert_gte(sdf, params.knoll_pad_clear_m - 0.01,
					"seed %d knoll %s only %.1f m from a pad" % [seed, str(c), sdf])


func test_knolls_raise_open_lawn_away_from_paths() -> void:
	## ivy-82zn.14.1 regression: knoll_shield was _fer(path_d, …) — 1 next to paths, 0 away
	## from them — so knolls only appeared beside paths and open-lawn knolls added ~0 m.
	## A knoll centre clear of paths/pads must add most of knoll_height_m.
	var checked := 0
	for seed: int in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var params := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var kc := VillageTerrain.knoll_centres(layout, params, t_seed)
		var no_knoll := params.duplicate_params()
		no_knoll.knoll_height_m = 0.0
		for c: Vector2 in kc:
			var path_d := VillageTerrain._min_dist_to_paths(c, layout)
			var open_scale := VillageTerrain._open_lawn_relief_scale(c, layout, params, path_d)
			var pad_cover := VillageTerrain._max_cottage_pad_weight(c, layout, params, t_seed)
			if path_d < params.knoll_radius_m + 1.0 or open_scale < 0.9 or pad_cover > 0.0:
				continue
			var with_k := VillageTerrain._compose_base_with_knolls(c, layout, params, t_seed, kc)
			var without_k := VillageTerrain._compose_base_with_knolls(c, layout, no_knoll, t_seed, kc)
			assert_gte(with_k - without_k, 0.5 * params.knoll_height_m,
				"seed %d knoll %s (path_d=%.1f) adds only %.3f m" % [seed, str(c), path_d, with_k - without_k])
			checked += 1
	assert_gt(checked, 0, "at least one open-lawn knoll probed")


func test_production_open_lawn_relief_floor_seed7() -> void:
	## Regression: open-lawn envelope must keep seed-7 relief visible (anti timid defaults).
	## ivy-82zn.14.10 contract change: the village-scale relief is now the hill (fall >= one cottage,
	## test_village_terrain_hill.gd). This pins the DETAIL layer (knolls + base noise on top of the
	## hill) so the hill does not replace the small-scale relief: open-lawn detail span, its peak, and
	## its slope (detail_y, FD 0.545 m) still <= 8°. Floors = measured on this tree − 5% (plan).
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	var min_open := INF
	var max_open_h := -INF
	var max_open_slope := 0.0
	var step := 2.0
	var e := 0.545
	var x := g.x - r
	while x <= g.x + r:
		var z := g.y - r
		while z <= g.y + r:
			var xz := Vector2(x, z)
			if xz.distance_to(g) < r:
				if _open_lawn_probe_point(xz, layout, params, t_seed, false):
					var h := VillageTerrain.detail_y(xz, layout, params, t_seed)
					min_open = minf(min_open, h)
					max_open_h = maxf(max_open_h, h)
				if _open_lawn_probe_point(xz, layout, params, t_seed, true):
					var dx := (VillageTerrain.detail_y(xz + Vector2(e, 0), layout, params, t_seed)
						- VillageTerrain.detail_y(xz - Vector2(e, 0), layout, params, t_seed)) / (2.0 * e)
					var dz := (VillageTerrain.detail_y(xz + Vector2(0, e), layout, params, t_seed)
						- VillageTerrain.detail_y(xz - Vector2(0, e), layout, params, t_seed)) / (2.0 * e)
					max_open_slope = maxf(max_open_slope, rad_to_deg(atan(sqrt(dx * dx + dz * dz))))
			z += step
		x += step
	var open_span := max_open_h - min_open if min_open < INF else 0.0
	gut.p("seed 7 detail layer: open span %.3f m, peak %.3f m, slope %.2f°" % [
		open_span, max_open_h, max_open_slope])
	assert_gte(open_span, _DETAIL_OPEN_SPAN_FLOOR_M, "seed7 detail open-lawn span floor")
	assert_gte(max_open_h, _DETAIL_OPEN_PEAK_FLOOR_M, "seed7 detail open-lawn peak floor")
	assert_gte(max_open_slope, 2.0, "seed7 detail open-lawn slope ≥ 2°")
	assert_lte(max_open_slope, 8.01, "seed7 detail open-lawn slope ≤ 8° cap")


## Measured on the ivy-82zn.14.10 tree, − 5% (architect plan: 'R floor, measured − 5%').
## Measured 2026-11-15: span 1.609 m, peak 1.021 m, slope 6.70° (seed 7, defaults).
const _DETAIL_OPEN_SPAN_FLOOR_M := 1.53
const _DETAIL_OPEN_PEAK_FLOOR_M := 0.97


## Rim-inclusive slope mask stops this far inside lawn_radius (same as
## tools/probe_village_relief.gd RIM_INNER_M).
const _RIM_INNER_M := 0.6


# ── Village swell (ivy-82zn.14.1, architect plan ivy-82zn.14.4) ───────────────

func test_stamp_anchors_ride_the_hill() -> void:
	## Root cause of the flat CamSun frame: every pad / plaza / pond anchor sat at exactly 0 m.
	## ivy-82zn.14.10 (was test_stamp_anchors_ride_swell): the anchors ride the village hill — the
	## outermost cottage at least one cottage ridge (6.84 m) below the hero datum on these seeds, the
	## plaza at least 1 m below it; with hill_rise_m 0 and swell_amp_m 0 they are back at datum 0.
	const RIDGE_M := 3.125 + 3.7178683280944824
	for seed: int in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var params := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var datum := VillageTerrain.hero_datum_y(layout, params)
		var far_c := Vector2.ZERO
		for spec: Dictionary in layout.cottages:
			var c := spec["centre"] as Vector2
			if c.distance_to(VillageLayout.HERO_DOOR_STOOP) > far_c.distance_to(VillageLayout.HERO_DOOR_STOOP):
				far_c = c
		assert_lte(VillageTerrain.sample_y(far_c, layout, params, t_seed), datum - RIDGE_M,
			"seed %d: outermost pad >= one cottage below the hero" % seed)
		var plaza_h := VillageTerrain.sample_y(layout.plaza_rect.get_center(), layout, params, t_seed)
		assert_lte(plaza_h, datum - 1.0, "seed %d: plaza centre >= 1 m below the hero (h=%.3f)" % [seed, plaza_h])
		var off := params.duplicate_params()
		off.swell_amp_m = 0.0
		off.hill_rise_m = 0.0
		VillageTerrain.clear_knoll_centres_cache()
		for spec: Dictionary in layout.cottages:
			assert_almost_eq(VillageTerrain.sample_y(spec["centre"] as Vector2, layout, off, t_seed), 0.0,
				0.001, "seed %d no hill, no swell: pad centre at datum" % seed)
		assert_almost_eq(VillageTerrain.sample_y(layout.plaza_rect.get_center(), layout, off, t_seed),
			0.0, 0.001, "seed %d no hill, no swell: plaza centre at datum" % seed)
	VillageTerrain.clear_knoll_centres_cache()


func test_hero_ring_slope_with_plaza_swell() -> void:
	## The plaza rect is ~11.6 m from the stoop, so the plaza's swell height must come back to
	## datum across the 3 m hero skirt. Unbounded it made 9-14.5° at (2, -4) on seeds 8, 15, 17,
	## 25, 27 (ivy-82zn.14.1 sweep v2). Open-lawn mask, 6.5-13 m from the stoop, 1 m grid.
	## ivy-82zn.14.10 contract change: the ring is hero_flat_r_m .. + hero_skirt_m (the hill flank
	## starts at the crest edge, 10 m, and is <= 30°, test_village_terrain_hill.gd); pad banks masked.
	for seed: int in [8, 15, 17, 25, 27]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var params := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var stoop := VillageLayout.HERO_DOOR_STOOP
		var worst := 0.0
		var worst_xz := Vector2.ZERO
		var x := stoop.x - 13.0
		while x <= stoop.x + 13.0:
			var z := stoop.y - 13.0
			while z <= stoop.y + 13.0:
				var xz := Vector2(x, z)
				var d := xz.distance_to(stoop)
				## The slope stencil (±0.545 m) stays inside the ring: at d = 10 m half of it would sit
				## on the hill flank, which starts at the crest edge by design (<= 30°, hill test).
				if d >= params.hero_flat_r_m and d <= params.hero_flat_r_m + params.hero_skirt_m - 0.55 \
						and not VillageTerrain.in_any_pad_terrace(xz, layout, params, t_seed):
					var s := VillageTerrain.sample_slope_deg(xz, layout, params, t_seed)
					if s > worst:
						worst = s
						worst_xz = xz
				z += 1.0
			x += 1.0
		assert_lte(worst, 8.0, "seed %d hero-ring slope %.2f° at %s <= 8°" % [seed, worst, str(worst_xz)])
	VillageTerrain.clear_knoll_centres_cache()


func test_camsun_view_relief_floor_seed7() -> void:
	## T1: the default / CamSun frame must show relief (fixer tree: span 0.158 m, mean |h| 0.008 m,
	## 0 pct of in-view ground above 0.15 m). Same sampler as tools/probe_village_relief.gd.
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var sun := VillageViewRelief.camsun(VillageTerrain, layout, params, t_seed)
	assert_gte(sun["span"], 0.60, "seed 7 CamSun in-view span %.3f >= 0.60 m" % sun["span"])
	assert_gte(sun["mean_abs"], 0.10, "seed 7 CamSun in-view mean |h| %.3f >= 0.10 m" % sun["mean_abs"])
	assert_gte(sun["frac_visible"], 0.40,
		"seed 7 CamSun ground above 0.15 m %.2f >= 0.40" % sun["frac_visible"])
	var shade := VillageViewRelief.camshade(VillageTerrain, layout, params, t_seed)
	assert_gte(shade["mean_abs"], 0.05, "seed 7 CamShade in-view mean |h| %.3f >= 0.05 m" % shade["mean_abs"])
	VillageTerrain.clear_knoll_centres_cache()


func test_sun_corridor_height_bound() -> void:
	## T5: inside the E/W sun corridors (azimuth from G within knoll_sun_corridor_half_deg of 90 / 270)
	## no knoll sits, so terrain there is base noise (pad/feature-faded) plus the swell; it stays
	## <= swell_amp_m + 0.05 m above datum over the open lawn, so the low sun is not blocked.
	## ivy-82zn.14.10: measured on the detail layer (the hill and swell are the large layer; the
	## bound pins "no knoll mound in the sun corridors", which is a detail-layer property).
	for seed: int in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var params := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var g := layout.hamlet_centre_xz
		var r := layout.lawn_radius
		## ivy-82zn.14.10: base noise only (amplitude × centre bias) + 0.1 m — no knoll-size mound. The
		## old swell_amp_m + 0.05 bound relied on the inverted path-quiet (ivy-sx7x) muting open lawn.
		var bound: float = params.base_amplitude_m * maxf(params.center_bias_gain, 1.0) \
			* (1.0 + params.dir_bias_gain) + 0.1
		var worst := -INF
		var worst_xz := Vector2.ZERO
		var x := g.x - r
		while x <= g.x + r:
			var z := g.y - r
			while z <= g.y + r:
				var xz := Vector2(x, z)
				z += 3.0
				if xz.distance_to(g) >= r or xz.distance_to(g) < 4.0:
					continue
				var az := VillageTerrain._azimuth_from_g_deg(xz, g)
				var d_sun := minf(VillageTerrain._angular_diff_deg(az, 90.0),
					VillageTerrain._angular_diff_deg(az, 270.0))
				if d_sun > params.knoll_sun_corridor_half_deg:
					continue
				var h := VillageTerrain.detail_y(xz, layout, params, t_seed)
				if h > worst:
					worst = h
					worst_xz = xz
			x += 3.0
		assert_lte(worst, bound, "seed %d sun-corridor max detail h %.3f at %s <= base noise + 0.1 (%.2f)" % [
			seed, worst, str(worst_xz), bound])
	VillageTerrain.clear_knoll_centres_cache()


func test_open_lawn_slope_with_rim_band() -> void:
	## ivy-82zn.14.5 (review ivy-82zn.14.2 MAJOR-1): the rim taper band must not hide a scarp.
	## Knoll centres out at r 37-47 m put ~1 m of mound height on the 5 m rim smoothstep, so the
	## full disc reached 14-17° on seeds 8, 11, 16, 23 (HEAD 4.1-4.6°) and 8.76° on seed 7.
	## Mask: full disc to lawn_radius - 0.6 m, minus pads/skirts, paths (5 m) and pond.
	## Seeds 10 and 28 are the closest to the limit after the fix (7.79° / 7.82°, knoll flank on
	## base noise); HEAD had them at 7.70° / 5.54°.
	## ivy-82zn.14.1 swell: + seeds 3 and 24 (prototype swell pushed them to 8.82° / 8.86°).
	## ivy-82zn.14.10 contract change: on the village hill the open lawn is a flank <= 30° (hill grade
	## up to ~26° behind the hero + detail), and the rim band (r >= lawn_radius − rim_blend_m, where
	## the hill is 0) keeps the old 8° — the scarp guard this test was written for.
	for seed: int in [3, 7, 8, 10, 11, 16, 23, 24, 28]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var params := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var g := layout.hamlet_centre_xz
		var r := layout.lawn_radius
		var worst := 0.0
		var worst_xz := Vector2.ZERO
		var worst_rim := 0.0
		var worst_rim_xz := Vector2.ZERO
		var r_band := layout.lawn_radius - params.rim_blend_m
		var x := g.x - r
		while x <= g.x + r:
			var z := g.y - r
			while z <= g.y + r:
				var xz := Vector2(x, z)
				if xz.distance_to(g) < r \
						and _open_lawn_probe_point(xz, layout, params, t_seed, true, _RIM_INNER_M):
					var s := VillageTerrain.sample_slope_deg(xz, layout, params, t_seed)
					if s > worst:
						worst = s
						worst_xz = xz
					if xz.distance_to(g) >= r_band + 0.6 and s > worst_rim:
						worst_rim = s
						worst_rim_xz = xz
				z += 2.0
			x += 2.0
		assert_lte(worst, 30.0, "seed %d open-lawn hill flank %.2f° at %s (r_g=%.1f) ≤ 30°" % [
			seed, worst, str(worst_xz), worst_xz.distance_to(g)])
		assert_lte(worst_rim, 8.0, "seed %d rim band slope %.2f° at %s (r_g=%.1f) ≤ 8°" % [
			seed, worst_rim, str(worst_rim_xz), worst_rim_xz.distance_to(g)])
	VillageTerrain.clear_knoll_centres_cache()


func test_knoll_footprint_ends_before_rim_band() -> void:
	## ivy-82zn.14.5: a knoll's whole footprint (centre + knoll_radius_m) sits inside the
	## untapered disc, so no mound flank meets the rim taper (MAJOR-1 root cause).
	var checked := 0
	for seed: int in range(1, 31):
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var params := VillageTerrainParams.production()
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var g := layout.hamlet_centre_xz
		var limit := layout.lawn_radius - params.rim_blend_m
		for c: Vector2 in VillageTerrain.knoll_centres(layout, params, t_seed):
			checked += 1
			assert_lte(c.distance_to(g) + params.knoll_radius_m, limit + 0.01,
				"seed %d knoll %s footprint reaches r=%.1f (rim band starts %.1f)" % [
					seed, str(c), c.distance_to(g) + params.knoll_radius_m, limit])
	VillageTerrain.clear_knoll_centres_cache()
	assert_gt(checked, 0, "at least one knoll placed across seeds 1-30")


## rim_inner_m < 0 → legacy interior mask (lawn_radius - rim_blend_m - 1 m).
static func _open_lawn_probe_point(
		xz: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int,
		for_slope: bool,
		rim_inner_m: float = -1.0) -> bool:
	var g := layout.hamlet_centre_xz
	var inner := rim_inner_m if rim_inner_m >= 0.0 else params.rim_blend_m + 1.0
	if xz.distance_to(g) > layout.lawn_radius - inner:
		return false
	if for_slope:
		var pond_r := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m + params.pond_skirt_m + 1.0
		if xz.distance_to(layout.pond_center) < pond_r:
			return false
		## ivy-82zn.14.10: terrace banks (pads, pond) are not open lawn (they are capped separately).
		if xz.distance_to(layout.pond_center) < VillageTerrain.pond_terrace_outer_m(layout, params, t_seed):
			return false
		if VillageTerrain.in_any_pad_terrace(xz, layout, params, t_seed):
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
