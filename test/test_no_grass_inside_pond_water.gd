## AC-VT3: Pond water_y is correctly computed (AR-VT-GAP-1 fix); water is below
## lip crest and above floor; bank vertices follow sample_y per-vertex (WP4).
## Also: no grass XZ inside water radius (XZ exclusion, always enforced).
## AR-VT-WIRE / AR-VT-GAP-1 / SD-VILLAGE-TERRAIN-7 / WP4.
extends GutTest

const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")
const VillageGrassExclusionContext = preload("res://src/world/village_grass_exclusion_context.gd")

const _TEST_SEEDS: Array[int] = [1, 7, 12]
## Tolerance for water_y exact match with AR-VT-GAP-1 formula.
const _WATER_Y_EPS := 0.002
## Tolerance for bank vertex vs sample_y.
const _BANK_VERTEX_EPS := 0.005


func _make_generated(seed: int) -> GeneratedVillageBackdrop:
	var bd := GeneratedBackdropScene.instantiate() as GeneratedVillageBackdrop
	bd.set_village_seed(seed)
	add_child_autofree(bd)
	return bd


## ivy-82zn.14.14 contract change (SD-VILLAGE-TERRAIN-19, AR-LF-GAP-7): the water level is the
## lowest point of the capped field on the bank circle (r = BANK_OUTER_M) − pond_freeboard_m, never
## above the lowest bank outline point − 2 cm (VillageTerrain.pond_water_y).
static func _expected_water_y(
		pond_center: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	return VillageTerrain.pond_water_y(layout, params, t_seed)


## Basin floor: the ground at the pond centre (anchor + pond_depth_m).
static func _expected_floor_y(
		pond_center: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	return VillageTerrain.sample_y(pond_center, layout, params, t_seed)


## Lip height: pond_lip_rise_m above the basin anchor (floor − pond_depth_m).
static func _expected_lip_y(
		pond_center: Vector2,
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> float:
	return _expected_floor_y(pond_center, layout, params, t_seed) - params.pond_depth_m \
		+ params.pond_lip_rise_m


# ── AC-VT3 part 1: water_y wiring matches AR-VT-GAP-1 formula ─────────────────

func test_ac_vt3_water_y_formula_seed1() -> void:
	_check_water_y_formula(1)

func test_ac_vt3_water_y_formula_seed7() -> void:
	_check_water_y_formula(7)

func test_ac_vt3_water_y_formula_seed12() -> void:
	_check_water_y_formula(12)


func _check_water_y_formula(seed: int) -> void:
	## Reads actual water_y from PondWater mesh vertex (all vertices at same y).
	## RED before WP4: actual = POND_WATER_Y_OFFSET (fixed ~0.012), differs from expected.
	## GREEN after WP4: actual = AR-VT-GAP-1 formula output.
	var bd := _make_generated(seed)
	var layout := bd.get("_layout") as VillageLayout
	if layout == null or layout.fallback or not layout.pond_placed:
		pass_test("skip seed %d (fallback or no pond)" % seed)
		return

	var pond_node := bd.get_node_or_null("PondWater") as MeshInstance3D
	assert_not_null(pond_node, "AC-VT3 seed=%d: PondWater node must exist" % seed)
	if pond_node == null:
		return
	var mesh := pond_node.mesh as ArrayMesh
	assert_not_null(mesh, "AC-VT3 seed=%d: PondWater must have ArrayMesh" % seed)
	if mesh == null:
		return
	var arrays := mesh.surface_get_arrays(0)
	if arrays == null or arrays.size() == 0:
		fail_test("AC-VT3 seed=%d: PondWater mesh has no surface arrays" % seed)
		return
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if verts.size() == 0:
		fail_test("AC-VT3 seed=%d: PondWater mesh has 0 vertices" % seed)
		return

	var actual_water_y := verts[0].y  # all water mesh vertices at same y

	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var pond_center := layout.pond_center
	var expected_water_y := _expected_water_y(pond_center, layout, params, t_seed)
	var floor_y := _expected_floor_y(pond_center, layout, params, t_seed)
	var lip_y := _expected_lip_y(pond_center, layout, params, t_seed)

	## Exact match with formula (AR-VT-GAP-1 wiring check)
	assert_almost_eq(actual_water_y, expected_water_y, _WATER_Y_EPS,
		"AC-VT3 seed=%d: actual water_y=%.4f should match expected=%.4f (AR-VT-GAP-1 formula)" % [
		seed, actual_water_y, expected_water_y])

	## Water strictly below lip (AR-VT-GAP-1 intent)
	assert_true(actual_water_y < lip_y,
		"AC-VT3 seed=%d: water_y=%.4f must be below lip_y=%.4f" % [seed, actual_water_y, lip_y])

	## Water strictly above floor (AR-VT-GAP-1 intent)
	assert_true(actual_water_y > floor_y,
		"AC-VT3 seed=%d: water_y=%.4f must be above floor_y=%.4f" % [seed, actual_water_y, floor_y])

	pass_test("AC-VT3 seed=%d: water_y=%.4f (expected=%.4f, floor=%.4f, lip=%.4f)" % [
		seed, actual_water_y, expected_water_y, floor_y, lip_y])


func test_ac_lt_pond_water_from_the_lowest_bank_point() -> void:
	## AC-LT-POND (WP1 part): y_w = min(capped field on r = BANK_OUTER_M) − freeboard; the water
	## stays ≤ the lowest rendered bank-outline point − 0.02 m; the pond is ≥ 20 m inside the join
	## circle, so the drape never meets a clipped boundary cell (AR-LF-RISK-7).
	var params := VillageTerrainParams.production()
	for seed: int in _TEST_SEEDS:
		var layout := VillageLayout.generate(seed)
		var f = VillageTerrain.field(layout, params)
		var lo := INF
		for i in range(360):
			var a := TAU * float(i) / 360.0
			lo = minf(lo, f.sample_unfit_y(layout.pond_center + Vector2(cos(a), sin(a)) * VillagePondSite.BANK_OUTER_M))
		var water := VillageTerrain.pond_water_y(layout, params)
		assert_lte(water, lo - params.pond_freeboard_m + 0.01,
			"seed %d water %.3f from the lowest bank point %.3f − freeboard" % [seed, water, lo])
		var lut := VillageTerrain.mesh_surface_lut(layout, params)
		var bank_min := INF
		for xz in VillagePondShape.at(layout.pond_center).bank_outer_outline_world_xz():
			bank_min = minf(bank_min, VillageTerrain.mesh_surface_y_from_lut(xz, layout, params, lut))
		assert_lte(water, bank_min - 0.02 + 0.005, "seed %d water ≤ bank-mesh min − 0.02" % seed)
		var r_pond := layout.pond_center.distance_to(layout.hamlet_centre_xz) + VillagePondSite.BANK_OUTER_M
		assert_lte(r_pond, layout.lawn_radius - 4.0, "seed %d pond well inside the join circle" % seed)


# ── AC-VT3 part 2: bank vertices follow sample_y per-vertex ──────────────────

func test_ac_vt3_bank_vertices_follow_sample_y_seed7() -> void:
	_check_bank_vertices(7)


func _check_bank_vertices(seed: int) -> void:
	## Each PondBank mesh vertex follows the terrain per vertex (WP4).
	## RED before WP4: all vertices at POND_BANK_Y_OFFSET (fixed ~0.008).
	## ivy-82zn.14.10 contract change: on the RENDERED lawn (VillageTerrain.mesh_surface_y, the 2 m
	## triangle mesh) + POND_BANK_DRAPE_M, not the exact sample_y — vertices on sample_y left the
	## bank under the coarse lawn in places and above it in others (the dark pond shards).
	var bd := _make_generated(seed)
	var layout := bd.get("_layout") as VillageLayout
	if layout == null or layout.fallback or not layout.pond_placed:
		pass_test("skip seed %d (fallback or no pond)" % seed)
		return

	var bank_node := bd.get_node_or_null("PondBank") as MeshInstance3D
	if bank_node == null:
		pass_test("no PondBank node (classic layout?), skip")
		return
	var mesh := bank_node.mesh as ArrayMesh
	if mesh == null:
		fail_test("AC-VT3 bank seed=%d: PondBank has no mesh" % seed)
		return
	var arrays := mesh.surface_get_arrays(0)
	if arrays == null or arrays.size() == 0:
		fail_test("AC-VT3 bank seed=%d: PondBank mesh empty" % seed)
		return
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if verts.size() == 0:
		pass_test("PondBank mesh has 0 vertices, skip")
		return

	var params := VillageTerrainParams.production()
	var lut := VillageTerrain.mesh_surface_lut(layout, params)

	var max_dev := 0.0
	var num_checked := 0
	for v: Vector3 in verts:
		var xz := Vector2(v.x, v.z)
		var expected_y := VillageTerrain.mesh_surface_y_from_lut(xz, layout, params, lut) \
			+ VillageBackdrop.POND_BANK_DRAPE_M
		var dev := absf(v.y - expected_y)
		if dev > max_dev:
			max_dev = dev
		if dev > _BANK_VERTEX_EPS:
			fail_test(
				"AC-VT3 bank seed=%d: vertex at xz=%s has y=%.4f, expected sample_y=%.4f dev=%.4f" % [
				seed, str(xz), v.y, expected_y, dev])
			return
		num_checked += 1
	pass_test("AC-VT3 bank seed=%d: %d vertices all within %.3f m of sample_y (max_dev=%.4f)" % [
		seed, num_checked, _BANK_VERTEX_EPS, max_dev])


# ── AC-VT3 part 3: no grass XZ inside water outline (XZ exclusion) ───────────

func test_ac_vt3_no_grass_xz_inside_water_seed7() -> void:
	_check_no_grass_in_water_xz(7)


func _check_no_grass_in_water_xz(seed: int) -> void:
	## No grass blade XZ position should fall inside the water outline (XZ exclusion).
	## This is enforced by VillageGrassExclusionContext regardless of Y baking.
	var layout := VillageLayout.generate(seed)
	if layout.fallback or not layout.pond_placed:
		pass_test("skip seed %d (fallback or no pond)" % seed)
		return
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
	var ctx := VillageGrassExclusionContext.for_layout(
		layout.paths,
		func(p: Vector2) -> bool: return layout.inside_any_cottage(p, 0.35),
		path_stones, bushes, layout.hamlet_centre_xz, VillageLayout.HERO_DOOR_STOOP, true,
		layout.cottages)
	var positions := VillageScatterPositions.grass_positions(ctx)
	var water_outline := VillagePondShape.water_render_outline_xz()
	var violation_count := 0
	for xf: Transform3D in positions:
		var p := Vector2(xf.origin.x, xf.origin.z)
		# ivy-5anf: vertex-robust test (Geometry2D.is_point_in_polygon gave false positives far outside).
		if VillagePondShape.point_in_outline(p, water_outline):
			violation_count += 1
	assert_eq(violation_count, 0,
		"AC-VT3 seed=%d: %d grass blades inside water outline" % [seed, violation_count])
	pass_test("AC-VT3 XZ exclusion seed=%d: 0 grass inside water outline (%d total)" % [
		seed, positions.size()])
