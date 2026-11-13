## AC-VT2: sample_y grid hash + knoll_centres deterministic across rebuild for seeds 1/7/12/240424020.
## SD-VILLAGE-TERRAIN-5 / AR-VT-DECIDE-3 determinism via _derive + VILLAGE_TERRAIN_SALT.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _PARITY_SEEDS: Array[int] = [1, 7, 12, 240424020]
const _GRID_HALF := 40.0
const _GRID_STEP := 5.0


static func _sample_y_hash(
		layout: VillageLayout,
		params: VillageTerrainParams,
		t_seed: int) -> String:
	var parts: PackedStringArray = []
	var x := -_GRID_HALF
	while x <= _GRID_HALF:
		var z := -_GRID_HALF
		while z <= _GRID_HALF:
			var xz := layout.hamlet_centre_xz + Vector2(x, z)
			var y := VillageTerrain.sample_y(xz, layout, params, t_seed)
			parts.append("%.6f" % y)
			z += _GRID_STEP
		x += _GRID_STEP
	return ",".join(parts).sha256_text()


static func _knoll_hash(centres: Array[Vector2]) -> String:
	var parts: PackedStringArray = []
	for c: Vector2 in centres:
		parts.append("%.6f,%.6f" % [c.x, c.y])
	return ",".join(parts).sha256_text()


func test_sample_y_hash_deterministic() -> void:
	# AC-VT2: identical rebuild → identical sample_y grid hash
	for seed: int in _PARITY_SEEDS:
		var layout1 := VillageLayout.generate(seed)
		if layout1.fallback:
			pass_test("fallback skip seed %d" % seed)
			continue
		var params1 := VillageTerrainParams.production()
		var ts1 := VillageTerrain.terrain_seed(layout1, params1)
		var h1 := _sample_y_hash(layout1, params1, ts1)

		var layout2 := VillageLayout.generate(seed)
		var params2 := VillageTerrainParams.production()
		var ts2 := VillageTerrain.terrain_seed(layout2, params2)
		var h2 := _sample_y_hash(layout2, params2, ts2)

		assert_eq(h1, h2, "sample_y hash deterministic for seed %d" % seed)


func test_knoll_centres_deterministic() -> void:
	# AC-VT2: knoll_centres identical across rebuilds
	for seed: int in _PARITY_SEEDS:
		var layout1 := VillageLayout.generate(seed)
		if layout1.fallback:
			pass_test("fallback skip seed %d" % seed)
			continue
		var params := VillageTerrainParams.production()
		var ts1 := VillageTerrain.terrain_seed(layout1, params)
		var c1 := VillageTerrain.knoll_centres(layout1, params, ts1)

		var layout2 := VillageLayout.generate(seed)
		var ts2 := VillageTerrain.terrain_seed(layout2, params)
		var c2 := VillageTerrain.knoll_centres(layout2, params, ts2)

		assert_eq(c1.size(), c2.size(), "knoll count deterministic seed %d" % seed)
		for i in range(c1.size()):
			assert_almost_eq(c1[i].x, c2[i].x, 0.001,
				"knoll[%d].x deterministic seed %d" % [i, seed])
			assert_almost_eq(c1[i].y, c2[i].y, 0.001,
				"knoll[%d].y deterministic seed %d" % [i, seed])


func test_terrain_seed_differs_for_different_village_seeds() -> void:
	var layout1 := VillageLayout.generate(1)
	var layout7 := VillageLayout.generate(7)
	if layout1.fallback or layout7.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var ts1 := VillageTerrain.terrain_seed(layout1, params)
	var ts7 := VillageTerrain.terrain_seed(layout7, params)
	assert_ne(ts1, ts7, "terrain_seed differs for seeds 1 vs 7")


func test_terrain_seed_uses_layout_seed_when_generation_seed_zero() -> void:
	# When layout.generation_seed == 0 (authored), uses params.layout_seed
	var layout := VillageLayout.authored()
	assert_eq(layout.generation_seed, 0, "authored layout has generation_seed=0")
	var params := VillageTerrainParams.production()
	params.layout_seed = 42
	var ts := VillageTerrain.terrain_seed(layout, params)
	assert_gt(ts, 0, "terrain_seed non-zero from params.layout_seed fallback")
	# Verify it's derived from layout_seed
	params.layout_seed = 43
	var ts2 := VillageTerrain.terrain_seed(layout, params)
	assert_ne(ts, ts2, "different layout_seed → different terrain_seed")


func test_salt_constants_exist_in_village_layout() -> void:
	# AR-VT-FILES: VILLAGE_TERRAIN_SALT and VILLAGE_TERRAIN_KNOLL_SALT must exist (SD-VILLAGE-TERRAIN-5)
	assert_eq(VillageLayout.VILLAGE_TERRAIN_SALT, 0x7E44A1,
		"VILLAGE_TERRAIN_SALT = 0x7E44A1")
	assert_eq(VillageLayout.VILLAGE_TERRAIN_KNOLL_SALT, 0x7E44A1 ^ 0x5B,
		"VILLAGE_TERRAIN_KNOLL_SALT = 0x7E44A1 ^ 0x5B")
