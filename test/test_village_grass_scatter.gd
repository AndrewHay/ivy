## SD-GRASS-2 mechanical tests for VillageScatterPositions.grass_positions(ctx).
extends GutTest

const GRASS_MAX := VillageScatterPositions.GRASS_MAX_INSTANCES
const GRASS_INNER := VillageScatterPositions.GRASS_RING_INNER_M
const GRASS_FRINGE_INNER := VillageScatterPositions.GRASS_HERO_FRINGE_INNER_M
const GRASS_FOOTPRINT_R := VillageScatterPositions.GRASS_HERO_FOOTPRINT_R
const GRASS_STEP := VillageScatterPositions.GRASS_GRID_STEP_M
const GRASS_CORE := VillageScatterPositions.GRASS_DENSITY_CORE_PER_M2
const GRASS_EDGE := VillageScatterPositions.GRASS_DENSITY_EDGE_PER_M2
const R_EDGE_C := VillageScatterPositions.GRASS_RADIAL_EDGE_CLASSIC_M
const R_EDGE_G := VillageScatterPositions.GRASS_RADIAL_EDGE_GENERATED_M
## ivy-82zn.14.18 (WP3, SD-21): today's radial profile ends at 56 m (full density zone); blades fade
## smoothly to 0 between 56 and the 64 m lawn edge.
const R_FULL_G := VillageScatterPositions.GRASS_FULL_EDGE_GENERATED_M
const R_FLAT_FRAC := VillageScatterPositions.GRASS_DENSITY_FLAT_FRACTION
const GEN_SCALE := VillageScatterPositions.GRASS_GENERATED_DENSITY_SCALE
const GRASS_STEP_G := VillageScatterPositions.GRASS_GRID_STEP_GENERATED_M
const COTTAGE_MARGIN := VillageScatterPositions.COTTAGE_MARGIN
const PATH_CLEAR := VillageScatterPositions.PATH_CLEARANCE_M
const PLANT_CLEAR := VillageScatterPositions.PLANT_CLEARANCE_M
const GENERATED_GRASS_BUDGET_MS := 15000


func _make_ctx() -> VillageGrassExclusionContext:
	var path_stones := VillageScatterPositions.path_stone_transforms(
		VillageBackdrop.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).length() < 4.5 \
				or VillageBackdrop.inside_any_cottage(Vector2(cx, cz), 0.2))
	var bushes := VillageScatterPositions.bush_common_positions()
	return VillageGrassExclusionContext.for_village(path_stones, bushes)


func _grass_transforms() -> Array[Transform3D]:
	return VillageScatterPositions.grass_positions(_make_ctx())


func _scatter_anchors(ctx: VillageGrassExclusionContext) -> Array[Vector2]:
	return VillageScatterPositions.collect_scatter_anchor_xz(ctx)


func _annulus_density(grass: Array, centre: Vector2, r0: float, r1: float) -> float:
	var n := 0
	for t in grass:
		var r := Vector2(t.origin.x, t.origin.z).distance_to(centre)
		if r >= r0 and r < r1:
			n += 1
	var area := PI * (r1 * r1 - r0 * r0)
	return float(n) / area if area > 0.0 else 0.0


func _max_radius(grass: Array, centre: Vector2) -> float:
	var max_r := 0.0
	for t in grass:
		max_r = maxf(max_r, Vector2(t.origin.x, t.origin.z).distance_to(centre))
	return max_r


func test_grass_deterministic() -> void:
	var ctx := _make_ctx()
	var a := VillageScatterPositions.grass_positions(ctx)
	var b := VillageScatterPositions.grass_positions(ctx)
	assert_eq(a.size(), b.size(), "Determinism: equal count")
	for i in range(a.size()):
		assert_eq(a[i].origin, b[i].origin, "Determinism: origin[%d]" % i)
		assert_eq(a[i].basis, b[i].basis, "Determinism: basis[%d]" % i)


func test_grass_radial_density_constants() -> void:
	assert_almost_eq(GRASS_CORE, 40.0, 1e-6)
	assert_almost_eq(GRASS_EDGE, 15.0, 1e-6)
	assert_almost_eq(R_FLAT_FRAC, 0.7, 1e-6)
	assert_almost_eq(GRASS_STEP, 1.0 / sqrt(GRASS_CORE), 1e-4)
	assert_almost_eq(R_EDGE_C, 19.0, 1e-6)
	assert_almost_eq(R_EDGE_G, VillageLayout.GENERATED_LAWN_RADIUS, 1e-6)
	assert_almost_eq(R_EDGE_G, 64.0, 1e-6, "WP3 lawn edge 64")
	assert_almost_eq(R_FULL_G, 56.0, 1e-6, "WP3 full-density edge 56")
	var cap_c := int(roundi(PI * R_EDGE_C * R_EDGE_C * GRASS_CORE * 1.15))
	assert_almost_eq(GEN_SCALE, 0.5, 1e-6)
	assert_almost_eq(GRASS_STEP_G, 1.0 / sqrt(GRASS_CORE * GEN_SCALE), 1e-4)
	## Faded area integral: core over the 56 m disc + half the edge density over the 56-64 fade ring.
	var cap_g := int(roundi((PI * R_FULL_G * R_FULL_G * GRASS_CORE
		+ PI * (R_EDGE_G * R_EDGE_G - R_FULL_G * R_FULL_G) * GRASS_EDGE * 0.5) * GEN_SCALE * 1.15))
	assert_eq(GRASS_MAX, cap_c)
	assert_eq(VillageScatterPositions.GRASS_MAX_INSTANCES_GENERATED, cap_g)


func test_grass_count_bounds() -> void:
	var grass := _grass_transforms()
	assert_lte(grass.size(), GRASS_MAX, "Cap GRASS_MAX_INSTANCES")
	assert_gte(grass.size(), 12000, "Radial fill should populate classic disk")


func test_grass_classic_reaches_treeline() -> void:
	var centre := Vector2.ZERO
	var max_r := _max_radius(_grass_transforms(), centre)
	assert_between(max_r, R_EDGE_C - 1.0, R_EDGE_C + GRASS_STEP,
		"Classic grass must reach inner pine ring (~%.1f m)" % R_EDGE_C)


func test_grass_open_patch_density_classic() -> void:
	var ctx := _make_ctx()
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var centre := Vector2.ZERO
	var r_flat := R_FLAT_FRAC * R_EDGE_C
	var p_core := VillageScatterPositions.find_open_grass_patch_centre(ctx, centre, 11.0, 11)
	assert_false(is_inf(p_core.x), "Need open flat-zone patch")
	var d_core := VillageScatterPositions.measure_patch_density_m2(grass, p_core)
	assert_between(d_core, GRASS_CORE * 0.78, GRASS_CORE * 1.15,
		"Open patch flat zone %.1f/m²" % d_core)
	var p_fall := VillageScatterPositions.find_open_grass_patch_centre(
		ctx, centre, r_flat + (R_EDGE_C - r_flat) * 0.5, 22)
	assert_false(is_inf(p_fall.x))
	var d_fall := VillageScatterPositions.measure_patch_density_m2(grass, p_fall)
	var t_mid := VillageScatterPositions.grass_target_density_m2(p_fall.distance_to(centre), R_EDGE_C)
	assert_between(d_fall, t_mid * 0.85, t_mid * 1.15, "Open patch mid-falloff %.1f/m²" % d_fall)
	var p_edge := VillageScatterPositions.find_open_grass_patch_centre(ctx, centre, R_EDGE_C - 0.8, 33)
	assert_false(is_inf(p_edge.x))
	var d_edge := VillageScatterPositions.measure_patch_density_m2(grass, p_edge)
	var t_edge := VillageScatterPositions.grass_target_density_m2(p_edge.distance_to(centre), R_EDGE_C)
	assert_between(d_edge, t_edge * 0.72, t_edge * 1.15,
		"Open patch edge %.1f/m² target ~%.1f" % [d_edge, t_edge])


func test_grass_open_patch_density_generated() -> void:
	var ctx := _make_generated_grass_ctx(1)
	if ctx == null:
		pending("seed=1 fell back")
		return
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var g := ctx.grid_centre_xz
	var r_flat := R_FLAT_FRAC * R_FULL_G
	var p_core := VillageScatterPositions.find_open_grass_patch_centre(ctx, g, r_flat * 0.65, 41)
	assert_false(is_inf(p_core.x))
	var d_core := VillageScatterPositions.measure_patch_density_m2(grass, p_core)
	var g_core := GRASS_CORE * GEN_SCALE
	var g_edge := GRASS_EDGE * GEN_SCALE
	assert_between(d_core, g_core * 0.78, g_core * 1.15, "G open core %.1f/m²" % d_core)
	## ivy-82zn.14.18 contract change: the first open patch near the full-density edge is at r 53.25 m
	## (inside the smoothstep tail, target 8.4/m²), not at the 7.5/m² edge value the old assert used.
	## Compare with the target at the patch radius (as the classic edge test does). Seeds 1-3 land on
	## the same open patch today, so the mean is kept only for robustness to future layouts.
	var ratio_sum := 0.0
	var n := 0
	for seed in [1, 2, 3]:
		var c2 := ctx if seed == 1 else _make_generated_grass_ctx(seed)
		if c2 == null:
			continue
		var gr2 := grass if seed == 1 else VillageScatterPositions.grass_blade_positions(c2)
		var p_edge := VillageScatterPositions.find_open_grass_patch_centre(c2, c2.grid_centre_xz, R_FULL_G - 1.0, 55)
		if is_inf(p_edge.x):
			continue
		var d_edge := VillageScatterPositions.measure_patch_density_m2(gr2, p_edge)
		var t_edge := VillageScatterPositions.grass_target_density_m2(
			p_edge.distance_to(c2.grid_centre_xz), R_FULL_G) * GEN_SCALE
		gut.p("seed %d edge patch r %.2f: %.2f/m² target %.2f" % [seed, p_edge.distance_to(c2.grid_centre_xz), d_edge, t_edge])
		ratio_sum += d_edge / t_edge
		n += 1
	assert_gt(n, 0, "edge patches found")
	assert_between(ratio_sum / maxf(n, 1), 0.8, 1.2, "G open edge / target (mean of %d seeds)" % n)
	assert_almost_eq(g_edge, 7.5, 1e-6, "edge density constant")


func test_grass_radial_density_curve() -> void:
	var edge := R_EDGE_C
	assert_almost_eq(VillageScatterPositions.grass_target_density_m2(0.0, edge), GRASS_CORE, 1e-6)
	assert_almost_eq(VillageScatterPositions.grass_target_density_m2(edge, edge), GRASS_EDGE, 1e-6)
	var r_flat := VillageScatterPositions.grass_radial_flat_m(edge)
	assert_almost_eq(VillageScatterPositions.grass_target_density_m2(r_flat - 0.05, edge), GRASS_CORE, 1e-4)
	assert_almost_eq(VillageScatterPositions.grass_target_density_slope_at_flat(edge), 0.0, 0.35)
	assert_almost_eq(
		VillageScatterPositions.grass_radial_keep_p(edge * 0.5, edge),
		VillageScatterPositions.grass_target_density_m2(edge * 0.5, edge) / GRASS_CORE,
		1e-4)


func test_generated_grass_fill_never_needs_cap_trim() -> void:
	var ctx := _make_generated_grass_ctx(1)
	if ctx == null:
		pending("seed=1 fell back")
		return
	var cap := VillageScatterPositions.GRASS_MAX_INSTANCES_GENERATED
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	assert_lt(grass.size(), int(float(cap) * 0.98), "Cap must not trim outer ring; got %d / %d" % [grass.size(), cap])


func test_generated_radial_annulus_monotone() -> void:
	var ctx := _make_generated_grass_ctx(1)
	if ctx == null:
		pending("seed=1 fell back")
		return
	var g := ctx.grid_centre_xz
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var r0 := VillageScatterPositions.grass_radial_flat_m(R_FULL_G) + 2.0
	var prev := _annulus_density(grass, g, r0, r0 + 1.0)
	for i in range(14):
		var a := r0 + float(i)
		var b := a + 1.0
		var d := _annulus_density(grass, g, a, b)
		var target_mid := VillageScatterPositions.grass_target_density_m2(
			(a + b) * 0.5, R_FULL_G) * GEN_SCALE
		assert_between(d, target_mid * 0.75, target_mid * 1.25,
			"Annulus [%.0f,%.0f) %.1f/m² target ~%.1f" % [a, b, d, target_mid])
		assert_lte(d, prev * 1.06, "Monotone falloff annulus %d" % i)
		prev = d


func test_generated_falloff_patch_cv() -> void:
	var ctx := _make_generated_grass_ctx(1)
	if ctx == null:
		pending("seed=1 fell back")
		return
	var g := ctx.grid_centre_xz
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var r_sample := 46.0
	var cv := VillageScatterPositions.measure_patch_density_cv(grass, g, r_sample)
	var target := VillageScatterPositions.grass_target_density_m2(r_sample, R_FULL_G) * GEN_SCALE
	const PATCH_R := 1.5
	var patch_area := PI * PATCH_R * PATCH_R
	var poisson_cv := 1.0 / sqrt(target * patch_area) if target * patch_area > 1.0 else 1.0
	assert_lt(cv, maxf(poisson_cv * 2.2, 0.28), "Falloff patch CV %.3f (Poisson ref %.3f)" % [cv, poisson_cv])


func test_generated_angular_uniformity_in_annulus() -> void:
	var ctx := _make_generated_grass_ctx(1)
	if ctx == null:
		pending("seed=1 fell back")
		return
	var g := ctx.grid_centre_xz
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	## ivy-82zn.14.18 contract change: the annulus was 42-50 m, open meadow outside the old r <= 37 m
	## village. With the 46 m reach, cottages, paths and stones sit there; measure the open band
	## between the farthest cottage corner (seed 1: 43.95 m) and the 56 m full-density edge.
	var r_in := 48.0
	var r_out := 56.0
	var sectors: Array[float] = []
	for s in range(12):
		var n := 0
		var ang0 := float(s) / 12.0 * TAU
		var ang1 := float(s + 1) / 12.0 * TAU
		for t in grass:
			var p := Vector2(t.origin.x, t.origin.z) - g
			var r := p.length()
			if r < r_in or r >= r_out:
				continue
			var ang := atan2(p.x, p.y)
			if ang < 0.0:
				ang += TAU
			if ang >= ang0 and ang < ang1:
				n += 1
		var area := (PI * (r_out * r_out - r_in * r_in)) / 12.0
		sectors.append(float(n) / area)
	var mean := 0.0
	for d in sectors:
		mean += d
	mean /= 12.0
	for i in range(12):
		if mean < 1.0:
			continue
		assert_between(sectors[i], mean * 0.82, mean * 1.18, "Sector %d density spread" % i)


func test_grass_classic_core_annulus_density() -> void:
	var r_flat := R_FLAT_FRAC * R_EDGE_C
	var dens := _annulus_density(_grass_transforms(), Vector2.ZERO, 10.5, r_flat - 0.4)
	assert_between(dens, GRASS_CORE * 0.35, GRASS_CORE * 0.55,
		"Classic core (exclusions) %.1f blades/m²" % dens)


func test_grass_classic_radial_falloff_monotonic() -> void:
	var centre := Vector2.ZERO
	var r_flat := R_FLAT_FRAC * R_EDGE_C
	var bands: Array[float] = []
	var edges := [r_flat, r_flat + (R_EDGE_C - r_flat) * 0.33, r_flat + (R_EDGE_C - r_flat) * 0.66, R_EDGE_C - 1.0]
	for i in range(edges.size() - 1):
		bands.append(_annulus_density(_grass_transforms(), centre, edges[i], edges[i + 1]))
	for i in range(bands.size() - 1):
		assert_lte(bands[i + 1], bands[i] * 1.08,
			"Falloff band %d→%d non-increasing (%.1f → %.1f/m²)" % [i, i + 1, bands[i], bands[i + 1]])


func test_grass_classic_edge_sparser_than_core() -> void:
	var centre := Vector2.ZERO
	var grass := _grass_transforms()
	var r_flat := R_FLAT_FRAC * R_EDGE_C
	var core := _annulus_density(grass, centre, 10.5, r_flat - 0.4)
	var edge := _annulus_density(grass, centre, R_EDGE_C - 1.0, R_EDGE_C - 0.05)
	assert_lt(edge, core * 0.92, "Edge %.1f < core %.1f/m²" % [edge, core])
	assert_gt(edge, 5.0, "Edge band still populated")


func test_grass_generation_under_budget() -> void:
	var ctx := _make_ctx()
	var t0 := Time.get_ticks_msec()
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var elapsed := Time.get_ticks_msec() - t0
	assert_gte(grass.size(), 1, "Generated tufts")
	assert_lt(elapsed, 2500, "Classic generation budget; got %d ms" % elapsed)


func test_grass_wispy_accent_count() -> void:
	var ctx := _make_ctx()
	var accents := VillageScatterPositions.grass_wispy_accent_positions(ctx)
	assert_eq(accents.size(), VillageScatterPositions.GRASS_ACCENT_COUNT)


func test_grass_hero_annulus() -> void:
	for t in _grass_transforms():
		var r := Vector2(t.origin.x, t.origin.z).length()
		assert_gte(r, GRASS_FRINGE_INNER, "Hero fringe inner bound")
		assert_lte(r, R_EDGE_C + GRASS_STEP, "Outer bound with grid slack")


func test_grass_no_hero_footprint_disk() -> void:
	for t in _grass_transforms():
		var r := Vector2(t.origin.x, t.origin.z).length()
		assert_gte(
			r, GRASS_FOOTPRINT_R,
			"Grass must not sit inside hero footprint disk (r < %.1f m)" % GRASS_FOOTPRINT_R)


func test_grass_hero_fringe_band() -> void:
	var fringe := 0
	for t in _grass_transforms():
		var r := Vector2(t.origin.x, t.origin.z).length()
		if r >= GRASS_FRINGE_INNER and r < GRASS_INNER:
			fringe += 1
	assert_gt(fringe, 0, "Sparse hero fringe 4.0–4.5 m should have tufts")


func test_grass_hero_density_fade() -> void:
	var grass := _grass_transforms()
	var band_45_60 := 0
	var band_60_70 := 0
	for t in grass:
		var r := Vector2(t.origin.x, t.origin.z).length()
		if r >= 4.5 and r < 6.0:
			band_45_60 += 1
		elif r >= 6.0 and r < 7.0:
			band_60_70 += 1
	assert_gt(band_45_60, 0, "Transition band 4.5–6.0 m should have tufts")
	assert_gt(band_60_70, 0, "Reference band 6.0–7.0 m should have tufts")
	var area_45_60 := PI * (6.0 * 6.0 - 4.5 * 4.5)
	var area_60_70 := PI * (7.0 * 7.0 - 6.0 * 6.0)
	var dens_45_60 := float(band_45_60) / area_45_60
	var dens_60_70 := float(band_60_70) / area_60_70
	assert_lt(
		dens_45_60, dens_60_70,
		"Hero fade: 4.5–6.0 m area density should be lower than 6.0–7.0 m")


func test_grass_cap_trim_keeps_innermost() -> void:
	var transforms: Array[Transform3D] = []
	for r in [5.0, 6.0, 7.0, 8.0, 9.0]:
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(r, 0.0, 0.0)))
	VillageScatterPositions.trim_grass_instances_to_cap(transforms, 3)
	assert_eq(transforms.size(), 3)
	var radii: Array[float] = []
	for t in transforms:
		radii.append(Vector2(t.origin.x, t.origin.z).length())
	radii.sort()
	assert_almost_eq(radii[0], 5.0, 1e-4)
	assert_almost_eq(radii[1], 6.0, 1e-4)
	assert_almost_eq(radii[2], 7.0, 1e-4)


func _make_generated_grass_ctx(seed: int = 1) -> VillageGrassExclusionContext:
	var layout := VillageLayout.generate(seed)
	if layout.fallback:
		return null
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var path_stones := VillageScatterPositions.path_stone_transforms(
		layout.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).distance_to(VillageLayout.HERO_DOOR_STOOP) < 4.5 \
				or layout.inside_any_cottage(Vector2(cx, cz), 0.2),
		layout.stone_seed, layout.min_stone_spacing)
	var bushes := VillageScatterPositions.bush_common_positions(
		layout.cottages, layout.bush_filler_inner, layout.bush_filler_outer,
		layout.hamlet_centre_xz)
	return VillageGrassExclusionContext.for_layout(
		layout.paths,
		func(p: Vector2) -> bool: return layout.inside_any_cottage(p, COTTAGE_MARGIN),
		path_stones, bushes, layout.hamlet_centre_xz, VillageLayout.HERO_DOOR_STOOP, true,
		layout.cottages)


func test_ac_lt_dress_grass_fade_56_to_64() -> void:
	## AC-LT-DRESS (SD-21 / -23): full density (today's profile) to 56 m, smooth monotone fade to 0 at 64.
	var prev := INF
	for i in range(0, 41):
		var r := 56.0 + 0.2 * float(i)
		var p := VillageScatterPositions.grass_generated_keep_p(r)
		assert_lte(p, prev + 1e-9, "keep_p non-increasing at %.1f" % r)
		prev = p
	assert_almost_eq(VillageScatterPositions.grass_generated_keep_p(56.0),
		VillageScatterPositions.grass_radial_keep_p(56.0, R_FULL_G), 1e-6, "continuous at 56 m")
	assert_almost_eq(VillageScatterPositions.grass_generated_keep_p(30.0),
		VillageScatterPositions.grass_radial_keep_p(30.0, R_FULL_G), 1e-6, "today's profile inside 56 m")
	assert_eq(VillageScatterPositions.grass_generated_keep_p(64.0), 0.0, "0 at the 64 m edge")
	assert_eq(VillageScatterPositions.grass_generated_keep_p(70.0), 0.0, "0 beyond")
	var ctx := _make_generated_grass_ctx(1)
	if ctx == null:
		fail_test("seed 1 fell back")
		return
	var g := ctx.grid_centre_xz
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var outside := 0
	for t in grass:
		if Vector2(t.origin.x, t.origin.z).distance_to(g) >= 64.0:
			outside += 1
	assert_eq(outside, 0, "no blade at r >= 64 m")
	var d_prev := INF
	var row := PackedStringArray()
	for k in range(4):
		var a := 56.0 + 2.0 * float(k)
		var d := _annulus_density(grass, g, a, a + 2.0)
		row.append("%.0f-%.0f: %.2f" % [a, a + 2.0, d])
		assert_lte(d, d_prev * 1.05, "measured annulus %.0f-%.0f non-increasing" % [a, a + 2.0])
		d_prev = d
	gut.p("AC-LT-DRESS grass seed 1: %d blades; fade annuli /m2 %s" % [grass.size(), ", ".join(row)])


func test_generated_grass_count_and_perf() -> void:
	var ctx := _make_generated_grass_ctx(1)
	if ctx == null:
		pending("seed=1 fell back to authored")
		return
	var g := ctx.grid_centre_xz
	var t0 := Time.get_ticks_msec()
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var elapsed := Time.get_ticks_msec() - t0
	assert_gte(grass.size(), int(150000 * GEN_SCALE),
		"Generated radial fill should be large; got %d" % grass.size())
	assert_lte(grass.size(), VillageScatterPositions.GRASS_MAX_INSTANCES_GENERATED,
		"Must stay under cap")
	var max_r := _max_radius(grass, g)
	assert_between(max_r, R_EDGE_G - 1.0, R_EDGE_G + GRASS_STEP_G,
		"Generated grass must reach lawn edge")
	assert_lt(elapsed, GENERATED_GRASS_BUDGET_MS,
		"Generated grass generation budget %d ms; got %d ms" % [GENERATED_GRASS_BUDGET_MS, elapsed])


func test_generated_grass_core_and_edge_density() -> void:
	## Mean over seeds 1–3 (ivy-82zn.14.16): the annulus density depends on where a seed's cottages
	## and paths fall; WP2 terrain fitting re-places seed 1 (core 16.1 → 14.1/m² with the grass code
	## unchanged; seeds 1–8 span 14.1–17.2), so one layout is too noisy a sample. Bounds unchanged.
	var core := 0.0
	var edge := 0.0
	var n := 0
	for seed in [1, 2, 3]:
		var ctx := _make_generated_grass_ctx(seed)
		if ctx == null:
			continue
		var g := ctx.grid_centre_xz
		var grass := VillageScatterPositions.grass_blade_positions(ctx)
		var r_flat := R_FLAT_FRAC * R_FULL_G
		core += _annulus_density(grass, g, r_flat * 0.55, r_flat * 0.92)
		edge += _annulus_density(grass, g, R_FULL_G - 1.2, R_FULL_G - 0.05)
		n += 1
	if n == 0:
		pending("seeds 1–3 fell back to authored")
		return
	core /= n
	edge /= n
	assert_between(core, GRASS_CORE * GEN_SCALE * 0.72, GRASS_CORE * GEN_SCALE * 1.12,
		"Generated core %.1f/m² (mean of %d seeds)" % [core, n])
	assert_between(edge, GRASS_EDGE * GEN_SCALE * 0.55, GRASS_EDGE * GEN_SCALE * 1.35,
		"Generated edge %.1f/m² (mean of %d seeds)" % [edge, n])
	assert_lt(edge, core * 0.85, "Generated edge sparser than core")


func test_grass_no_cottage_footprint() -> void:
	for t in _grass_transforms():
		var p := Vector2(t.origin.x, t.origin.z)
		assert_false(
			VillageBackdrop.inside_any_cottage(p, COTTAGE_MARGIN),
			"Grass must not sit inside cottage margin at %s" % str(p))


func test_grass_path_clearance() -> void:
	var ctx := _make_ctx()
	var segments := VillageBackdrop.path_polylines()
	for t in _grass_transforms():
		var p := Vector2(t.origin.x, t.origin.z)
		var d := VillageScatterPositions.min_xz_dist_to_path_segments(p, segments)
		assert_gte(d, PATH_CLEAR, "Path corridor at %s (d=%.3f)" % [str(p), d])


func test_grass_scatter_clearance() -> void:
	var ctx := _make_ctx()
	var anchors := _scatter_anchors(ctx)
	for t in _grass_transforms():
		var p := Vector2(t.origin.x, t.origin.z)
		for a in anchors:
			assert_gte(
				p.distance_to(a), PLANT_CLEAR,
				"Scatter exclusion at %s near anchor %s" % [str(p), str(a)])
