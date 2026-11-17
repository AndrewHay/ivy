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


func test_ac_lt_path_metric() -> void:
	## AC-LT-PATH: sample_slope_deg along every polyline at ≤ 1 m steps ≤ 14°, ≤ 25° within 3 m of
	## a door. Enforcement (attempt retry → next offset → path_cap_fallback) is WP2; until then the
	## measured values are reported and asserted only if they already hold.
	var p := VillageTerrainParams.production()
	var notes := PackedStringArray()
	var all_ok := true
	for seed in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		var m: Dictionary = VillageTerrain.field(layout, p).max_path_slope(layout)
		assert_true(is_finite(float(m["deg"])), "seed %d path metric finite" % seed)
		notes.append("%d: %.1f° (door %.1f°)" % [seed, m["deg"], m["door_exempt_deg"]])
		all_ok = all_ok and float(m["deg"]) <= p.max_path_slope_deg \
			and float(m["door_exempt_deg"]) <= p.ring_max_slope_deg + 3.0
	if all_ok:
		pass_test("AC-LT-PATH holds already: %s" % ", ".join(notes))
	else:
		pending("AC-LT-PATH cap is enforced in WP2 (ivy-82zn.14.16); WP1 measures %s" % ", ".join(notes))
