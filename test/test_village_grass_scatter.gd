## SD-GRASS-2 mechanical tests for VillageScatterPositions.grass_positions(ctx).
extends GutTest

const GRASS_MAX := VillageScatterPositions.GRASS_MAX_INSTANCES
const GRASS_INNER := VillageScatterPositions.GRASS_RING_INNER_M
const GRASS_OUTER := VillageScatterPositions.GRASS_RING_OUTER_M
const GRASS_FULL := VillageScatterPositions.GRASS_FULL_DENSITY_OUTER_M
const GRASS_STEP := VillageScatterPositions.GRASS_GRID_STEP_M
const COTTAGE_MARGIN := VillageScatterPositions.COTTAGE_MARGIN
const PATH_CLEAR := VillageScatterPositions.PATH_CLEARANCE_M
const PLANT_CLEAR := VillageScatterPositions.PLANT_CLEARANCE_M


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


func test_grass_deterministic() -> void:
	var ctx := _make_ctx()
	var a := VillageScatterPositions.grass_positions(ctx)
	var b := VillageScatterPositions.grass_positions(ctx)
	assert_eq(a.size(), b.size(), "Determinism: equal count")
	for i in range(a.size()):
		assert_eq(a[i].origin, b[i].origin, "Determinism: origin[%d]" % i)
		assert_eq(a[i].basis, b[i].basis, "Determinism: basis[%d]" % i)


func test_grass_count_bounds() -> void:
	var grass := _grass_transforms()
	assert_lte(grass.size(), GRASS_MAX, "Cap GRASS_MAX_INSTANCES")
	assert_gte(grass.size(), 6000, "Blade lawn should be densely populated")
	assert_lte(grass.size(), 18000, "Cap expected tuft range")


func test_grass_generation_under_400ms() -> void:
	var ctx := _make_ctx()
	var t0 := Time.get_ticks_msec()
	var grass := VillageScatterPositions.grass_blade_positions(ctx)
	var elapsed := Time.get_ticks_msec() - t0
	assert_gte(grass.size(), 1, "Generated tufts")
	assert_lt(elapsed, 400, "Generation must stay under 400 ms headless; got %d ms" % elapsed)


func test_grass_wispy_accent_count() -> void:
	var ctx := _make_ctx()
	var accents := VillageScatterPositions.grass_wispy_accent_positions(ctx)
	assert_eq(accents.size(), VillageScatterPositions.GRASS_ACCENT_COUNT)


func test_grass_hero_annulus() -> void:
	for t in _grass_transforms():
		var r := Vector2(t.origin.x, t.origin.z).length()
		assert_gte(r, GRASS_INNER, "Hero disk inner bound")
		assert_lte(r, GRASS_OUTER + GRASS_STEP, "Outer bound with grid slack")


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


func test_grass_fade_band_sparser_than_full() -> void:
	var grass := _grass_transforms()
	var full := 0
	var fade := 0
	for t in grass:
		var r := Vector2(t.origin.x, t.origin.z).length()
		if r >= GRASS_FULL and r <= GRASS_OUTER:
			fade += 1
		elif r >= GRASS_INNER and r < GRASS_FULL:
			full += 1
	assert_gt(full, 0, "Full-density band populated")
	assert_gt(fade, 0, "Fade band populated")
	var full_area := PI * (GRASS_FULL * GRASS_FULL - GRASS_INNER * GRASS_INNER)
	var fade_area := PI * (GRASS_OUTER * GRASS_OUTER - GRASS_FULL * GRASS_FULL)
	var full_density := float(full) / full_area
	var fade_density := float(fade) / fade_area
	assert_lt(fade_density, full_density * 0.85,
		"Fade band area density lower than full band (prob + height fade)")


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
