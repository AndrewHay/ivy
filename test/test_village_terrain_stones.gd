## Path stones Y bake (AC-VT4) and the path slope metric (AC-LT-PATH, SD-VILLAGE-TERRAIN-20).
## Stone origin.y follows the field within ±0.08 m; classic byte-identical (INV-15).
## ivy-82zn.14.14: paths drape on the landform with no corridor stamp; the 14° cap (with the 25°
## door-approach exemption) is enforced by the generator retry in WP2 (ivy-82zn.14.16). WP1 measures
## it with VillageTerrainField.max_path_slope and asserts it once WP2 lands.
extends GutTest

const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")
const ClassicBackdropScene = preload("res://src/world/village_backdrop.tscn")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _TEST_SEED := 7
## AC-VT4: stone origins ±0.08m of sample_y.
const _STONE_EPS := 0.08
const _STONE_PREFIXES := ["Scatter_Path_0", "Scatter_Path_1", "Scatter_Path_2"]


func _make_generated(seed: int) -> GeneratedVillageBackdrop:
	var bd := GeneratedBackdropScene.instantiate() as GeneratedVillageBackdrop
	bd.set_village_seed(seed)
	add_child_autofree(bd)
	return bd


func _make_classic() -> VillageBackdrop:
	var bd := ClassicBackdropScene.instantiate() as VillageBackdrop
	add_child_autofree(bd)
	return bd


static func _parse_origin_ys(mm: MultiMesh) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if mm == null or mm.instance_count == 0:
		return out
	var buf := mm.buffer
	var stride := 16 if mm.use_colors else 12
	out.resize(mm.instance_count)
	for i in range(mm.instance_count):
		out[i] = buf[i * stride + 7]
	return out


static func _parse_origin_xzs(mm: MultiMesh) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if mm == null or mm.instance_count == 0:
		return out
	var buf := mm.buffer
	var stride := 16 if mm.use_colors else 12
	for i in range(mm.instance_count):
		var b := i * stride
		out.append(Vector2(buf[b + 3], buf[b + 11]))
	return out


static func _is_stone(mmi: MultiMeshInstance3D) -> bool:
	for prefix: String in _STONE_PREFIXES:
		if mmi.name.begins_with(prefix):
			return true
	return false


func test_path_stone_y_baked_generated() -> void:
	## AC-VT4: path stone origin.y within ±0.08 m of sample_y(xz).
	var bd := _make_generated(_TEST_SEED)
	var layout := bd.get_layout()
	var params := bd.get("_terrain_params") as VillageTerrainParams
	if layout == null or not layout.is_generated or params == null:
		fail_test("not generated")
		return
	var checked := 0
	var max_err := 0.0
	for child in bd.get_children():
		if not (child is MultiMeshInstance3D) or not _is_stone(child):
			continue
		var mm := (child as MultiMeshInstance3D).multimesh
		var ys := _parse_origin_ys(mm)
		var xzs := _parse_origin_xzs(mm)
		for i in range(ys.size()):
			var err := absf(ys[i] - VillageTerrain.sample_y(xzs[i], layout, params, 0))
			max_err = maxf(max_err, err)
		checked += ys.size()
	assert_gt(checked, 0, "found path stones (%d)" % checked)
	assert_lte(max_err, _STONE_EPS, "stone y follows the field (max err %.4f m)" % max_err)


func test_path_stones_ride_the_landform() -> void:
	## The paths drape over metres of relief (no corridor stamp): stone heights span > 1 m.
	var bd := _make_generated(_TEST_SEED)
	var lo := INF
	var hi := -INF
	for child in bd.get_children():
		if child is MultiMeshInstance3D and _is_stone(child):
			for y in _parse_origin_ys((child as MultiMeshInstance3D).multimesh):
				lo = minf(lo, y)
				hi = maxf(hi, y)
	assert_gt(hi - lo, 1.0, "path stones span %.2f m of height" % (hi - lo))


func test_path_stone_y_zero_in_classic() -> void:
	## INV-15: classic backdrop path stones stay at y = 0 (byte-identical).
	var bd := _make_classic()
	for child in bd.get_children():
		if not (child is MultiMeshInstance3D) or not _is_stone(child):
			continue
		for y in _parse_origin_ys((child as MultiMeshInstance3D).multimesh):
			if not is_zero_approx(y):
				fail_test("classic %s y=%.6f expected 0 (INV-15)" % [child.name, y])
				return
	pass_test("classic path stones: all y=0 (INV-15)")


func test_path_scan_skips_fit_zones_and_door_approaches() -> void:
	## SD-20 restated (ivy-82zn.14.23): open land = sdf_j ≥ w_j + 0.4 for every fit site and more
	## than door_approach_m from every door; only open samples are read by the open-land slope fn.
	var p := VillageTerrainParams.production()
	var layout := VillageLayout.new()
	layout.paths = [[Vector2(-40.0, 0.0), Vector2(40.0, 0.0)]]
	var hero := {"kind": "hero", "centre": Vector2.ZERO, "r_c": 7.0, "w": 4.0, "bound_c": Vector2.ZERO, "bound_r": 11.0}
	var fn := func(xz: Vector2) -> float: return 99.0 if absf(xz.x) < 11.4 else 5.0
	var m := VillageTerrainField.path_scan(layout, p, [hero], fn, fn)
	assert_eq(float(m["deg"]), 5.0, "zone samples excluded from the open-land max")
	assert_eq(float(m["zone_deg"]), 99.0, "zone samples reported separately")
	assert_gt(int(m["n_open"]), 40, "open samples counted")


func test_ac_lt_path_sweep_seeds_1_20() -> void:
	## AC-LT-PATH sweep (counts restated 2026-11-18, SD-VILLAGE-TERRAIN-28 §1, ivy-82zn.14.28):
	## open-land max ≤ path_steep_accept_deg (18°) on every seed, ≤ 8 / 20 flagged, fit zone ≤ 25° on
	## every seed, no seed uses 12 attempts, mean attempts_used ≤ 4.0. (Was ≤ 2 flagged, mean ≤ 3.)
	var p := VillageTerrainParams.production()
	var flagged := PackedStringArray()
	var attempts_sum := 0
	var n := 0
	var all_twelve := PackedStringArray()
	for seed in range(1, 21):
		var layout := VillageLayout.generate(seed)
		var used := int(VillageGeneratorV3.last_diag.get("attempts_used", 0))
		attempts_sum += used
		n += 1
		assert_lte(used, 12, "seed %d within the 12-attempt budget" % seed)
		if used >= 12:
			all_twelve.append(str(seed))
		if layout.fallback:
			continue
		var m: Dictionary = VillageTerrain.field(layout, p).max_path_slope(layout)
		assert_lte(float(m["zone_deg"]), p.ring_max_slope_deg + 3.0, "seed %d fit zone ≤ 25° (%.1f°)" % [seed, m["zone_deg"]])
		if bool(layout.terrain_diag.get("path_cap_fallback", false)):
			flagged.append("%d (%.2f°)" % [seed, m["deg"]])
			assert_lte(float(m["deg"]), p.path_steep_accept_deg, "seed %d flagged open max ≤ 18°" % seed)
		else:
			assert_lte(float(m["deg"]), p.max_path_slope_deg, "seed %d open path ≤ 14°" % seed)
	gut.p("flagged: %s; mean attempts %.2f" % [", ".join(flagged), float(attempts_sum) / float(n)])
	## Human decision 2026-11-18 (option A, stopgap; proper fix ivy-82zn.14.29): <= 9 / 20 flagged as
	## measured with the SD-28 storey rule (was <= 8). Open-land max <= 18° on every seed unchanged.
	assert_lte(flagged.size(), 9, "≤ 9 / 20 flagged seeds (option A 2026-11-18)")
	assert_lte(float(attempts_sum) / float(n), 4.0, "mean attempts ≤ 4.0 (SD-28)")
	## Human decision 2026-11-18 (option A, stopgap; proper fix ivy-82zn.14.29): at most ONE of seeds
	## 1-20 may use all 12 attempts (measured: seed 10; was "no seed uses 12"). The 3.7 s mean timing
	## limit was accepted knowing it comes from this seed.
	gut.p("seeds using all 12 attempts: [%s]" % ", ".join(all_twelve))
	assert_lte(all_twelve.size(), 1, "at most one seed uses all 12 attempts (option A 2026-11-18)")


func test_ac_lt_path_metric() -> void:
	## AC-LT-PATH (restated ivy-82zn.14.23; counts restated 2026-11-18 SD-28 §1): on the probe seeds
	## 1/7/12 the open-land max is ≤ 18° (path_steep_accept_deg; a flag is allowed), fit zone ≤ 25°,
	## and the generator's open-land value equals the field's within 0.01°. (Was: unflagged, ≤ 14°.)
	var p := VillageTerrainParams.production()
	for seed in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		assert_false(layout.fallback, "seed %d generated" % seed)
		var m: Dictionary = VillageTerrain.field(layout, p).max_path_slope(layout)
		gut.p("seed %d open path %.2f° zone %.1f° flagged %s" % [seed, m["deg"], m["zone_deg"],
			str(layout.terrain_diag.get("path_cap_fallback", false))])
		assert_lte(float(m["deg"]), p.path_steep_accept_deg, "seed %d open path ≤ 18°" % seed)
		assert_lte(float(m["zone_deg"]), p.ring_max_slope_deg + 3.0, "seed %d fit zone ≤ 25°" % seed)
		assert_almost_eq(float(layout.terrain_diag.get("max_path_slope_open_deg", -1.0)), float(m["deg"]), 0.01,
			"seed %d generator open-land value = field" % seed)
		assert_eq(layout.terrain_diag.get("max_path_slope_deg"), layout.terrain_diag.get("max_path_slope_open_deg"),
			"alias kept")
