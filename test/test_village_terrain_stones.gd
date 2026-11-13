## WP6: Path stones Y bake + path slope cap.
## Tests: stone origin.y follows terrain within ±0.08m (AC-VT4); classic byte-identical (INV-15);
## max path sample_slope_deg ≤ max_path_slope_deg (AC-VT7).
## AR-VT-TESTS / SD-VILLAGE-TERRAIN-7.
extends GutTest

const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")
const ClassicBackdropScene = preload("res://src/world/village_backdrop.tscn")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _TEST_SEED := 7
## AC-VT4: stone origins ±0.08m of sample_y.
const _STONE_EPS := 0.08


func _make_generated(seed: int) -> GeneratedVillageBackdrop:
	var bd := GeneratedBackdropScene.instantiate() as GeneratedVillageBackdrop
	bd.set_village_seed(seed)
	add_child_autofree(bd)
	return bd


func _make_classic() -> VillageBackdrop:
	var bd := ClassicBackdropScene.instantiate() as VillageBackdrop
	add_child_autofree(bd)
	return bd


## Parse origin.y from a MultiMesh buffer.
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


## Parse origin XZ from a MultiMesh buffer.
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


# ── 1. Path stone Y baked in generated village ────────────────────────────────

func test_path_stone_y_baked_generated() -> void:
	## AC-VT4: path stone origin.y must be within ±0.08m of sample_y(xz) in generated village.
	var bd := _make_generated(_TEST_SEED)
	var layout := bd.get_layout()
	if layout == null or not layout.is_generated:
		fail_test("not generated"); return
	var params := bd.get("_terrain_params") as VillageTerrainParams
	var t_seed := bd.get("_terrain_seed") as int
	if params == null:
		fail_test("no terrain params"); return
	var stone_prefixes := ["Scatter_Path_0", "Scatter_Path_1", "Scatter_Path_2"]
	var checked := 0
	var max_err := 0.0
	for child in bd.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		var mmi := child as MultiMeshInstance3D
		var is_stone := false
		for prefix: String in stone_prefixes:
			if mmi.name.begins_with(prefix):
				is_stone = true
				break
		if not is_stone:
			continue
		var mm := mmi.multimesh
		if mm == null or mm.instance_count == 0:
			continue
		var ys := _parse_origin_ys(mm)
		var xzs := _parse_origin_xzs(mm)
		for i in range(ys.size()):
			var expected := VillageTerrain.sample_y(xzs[i], layout, params, t_seed)
			var err := absf(ys[i] - expected)
			max_err = maxf(max_err, err)
			if err > _STONE_EPS:
				fail_test("%s[%d] y=%.4f expected≈%.4f err=%.4f > %.3f" % [
					mmi.name, i, ys[i], expected, err, _STONE_EPS])
				return
		checked += mm.instance_count
	assert_gt(checked, 0, "must have found at least 1 path stone (got %d)" % checked)
	pass_test("path stone Y baked: %d stones, max_err=%.4fm" % [checked, max_err])


func test_path_stone_y_nonzero_in_generated() -> void:
	## Generated backdrop must show terrain lift: path spine is grade-limited (AC-VT7) and may
	## sit near datum, so also check lifted cottages for visible relief.
	var bd := _make_generated(_TEST_SEED)
	var stone_prefixes := ["Scatter_Path_0", "Scatter_Path_1", "Scatter_Path_2"]
	var max_abs_y := 0.0
	for child in bd.get_children():
		if child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			var is_stone := false
			for prefix: String in stone_prefixes:
				if mmi.name.begins_with(prefix):
					is_stone = true
					break
			if not is_stone:
				continue
			var mm := mmi.multimesh
			if mm == null:
				continue
			var ys := _parse_origin_ys(mm)
			for y in ys:
				max_abs_y = maxf(max_abs_y, absf(y))
	var layout := bd.get_layout()
	var params := bd.get("_terrain_params") as VillageTerrainParams
	var t_seed := bd.get("_terrain_seed") as int
	if layout != null and params != null:
		var g := layout.hamlet_centre_xz
		var r := layout.lawn_radius - 1.0
		var x := -r
		while x <= r:
			var z := -r
			while z <= r:
				var xz := g + Vector2(x, z)
				if xz.distance_to(g) < r:
					max_abs_y = maxf(max_abs_y, absf(
						VillageTerrain.sample_y(xz, layout, params, t_seed)))
				z += 5.0
			x += 5.0
	assert_gt(max_abs_y, 0.005,
		"generated backdrop must show |y| > 5mm on grass or stones (terrain relief)")


# ── 2. Classic path stones: y must be 0 (INV-15) ────────────────────────────

func test_path_stone_y_zero_in_classic() -> void:
	## INV-15: classic backdrop path stones must remain at y=0 (byte-identical).
	var bd := _make_classic()
	var stone_prefixes := ["Scatter_Path_0", "Scatter_Path_1", "Scatter_Path_2"]
	for child in bd.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		var mmi := child as MultiMeshInstance3D
		var is_stone := false
		for prefix: String in stone_prefixes:
			if mmi.name.begins_with(prefix):
				is_stone = true
				break
		if not is_stone:
			continue
		var mm := mmi.multimesh
		if mm == null:
			continue
		var ys := _parse_origin_ys(mm)
		for i in range(ys.size()):
			if not is_zero_approx(ys[i]):
				fail_test("classic %s[%d] y=%.6f expected 0 (INV-15)" % [mmi.name, i, ys[i]])
				return
	pass_test("classic path stones: all y=0 (INV-15)")


# ── 3. Path slope cap (AC-VT7) ────────────────────────────────────────────────

const _PATH_SLOPE_STEP_M := 0.5


static func _max_path_slope_deg(seed: int) -> float:
	var layout := VillageLayout.generate(seed)
	if layout.fallback:
		return 0.0
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var cap := params.max_path_slope_deg
	var max_slope := 0.0
	for polyline: Variant in layout.path_polylines():
		var pts: Array = polyline as Array
		if pts.size() < 2:
			continue
		var seg_lens: Array[float] = []
		var total := 0.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i] as Vector2
			var b: Vector2 = pts[i + 1] as Vector2
			var len := a.distance_to(b)
			seg_lens.append(len)
			total += len
		var dist := 0.0
		while dist <= total + 0.001:
			var p := _point_along_polyline(pts, seg_lens, dist)
			var slope := VillageTerrain.sample_slope_deg(p, layout, params, t_seed)
			max_slope = maxf(max_slope, slope)
			dist += _PATH_SLOPE_STEP_M
	return max_slope


static func _point_along_polyline(pts: Array, seg_lens: Array[float], dist: float) -> Vector2:
	var remaining := dist
	for i in range(seg_lens.size()):
		var seg_len: float = seg_lens[i]
		if remaining <= seg_len or i == seg_lens.size() - 1:
			var t := clampf(remaining / maxf(seg_len, 1e-6), 0.0, 1.0)
			var a: Vector2 = pts[i] as Vector2
			var b: Vector2 = pts[i + 1] as Vector2
			return a.lerp(b, t)
		remaining -= seg_len
	return pts[pts.size() - 1] as Vector2


func test_path_slope_cap() -> void:
	## AC-VT7: max terrain slope along any path ≤ max_path_slope_deg (8.0°).
	var params := VillageTerrainParams.production()
	var max_slope := _max_path_slope_deg(_TEST_SEED)
	assert_lte(max_slope, params.max_path_slope_deg + 0.02,
		"AC-VT7 seed %d: max path slope %.2f° must be ≤ %.1f°" % [
			_TEST_SEED, max_slope, params.max_path_slope_deg])


func test_path_slope_cap_multiple_seeds() -> void:
	## AC-VT7: slope cap holds for seeds 1, 3, 5, 7, 12, 240424020.
	var params := VillageTerrainParams.production()
	for seed: int in [1, 3, 5, 7, 12, 240424020]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var max_slope := _max_path_slope_deg(seed)
		assert_lte(max_slope, params.max_path_slope_deg + 0.02,
			"AC-VT7 seed %d: max path slope %.2f° must be ≤ %.1f°" % [
				seed, max_slope, params.max_path_slope_deg])
