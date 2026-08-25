extends GutTest

const IvyParams = preload("res://src/params/ivy_params.gd")
const Solar = preload("res://src/env/solar.gd")
const LightBake = preload("res://src/env/light_bake.gd")
const LightBakeCache = preload("res://src/env/light_bake_cache.gd")


func _fake_provenance(byte: int) -> PackedByteArray:
	var p := PackedByteArray()
	for i in 32:
		p.append(byte)
	return p


func test_save_load_roundtrip_preserves_coarse_grid() -> void:
	var params := IvyParams.new()
	var bake := LightBake.new(params, Solar.new(params))
	var bounds := AABB(Vector3(-1, 0, -1), Vector3(2, 3, 2))
	var key := CellGrid.pack_key(Vector3i(7, -3, 12))
	bake._slot_of[key] = 0
	bake._svf = PackedFloat32Array([0.42])
	bake._vis = PackedInt32Array([0x00FF00FF])
	var prov := _fake_provenance(0xAB)
	var ph := LightBakeCache.params_hash(params)
	LightBakeCache.save(bake, bounds, prov, ph)
	var bake2 := LightBake.new(params, Solar.new(params))
	assert_true(LightBakeCache.try_load(bake2, bounds, prov, ph))
	assert_eq(bake2._svf.size(), 1)
	assert_almost_eq(bake2._svf[0], 0.42, 1e-6)
	assert_eq(bake2._vis[0], 0x00FF00FF)
	assert_true(bake2._slot_of.has(key))


func test_mismatch_provenance_is_miss_not_stale_read() -> void:
	var params := IvyParams.new()
	var bake := LightBake.new(params, Solar.new(params))
	var bounds := AABB(Vector3.ZERO, Vector3.ONE)
	var prov := _fake_provenance(1)
	var ph := LightBakeCache.params_hash(params)
	bake._slot_of[CellGrid.pack_key(Vector3i.ZERO)] = 0
	bake._svf = PackedFloat32Array([0.5])
	bake._vis = PackedInt32Array([0xFFFFFF])
	LightBakeCache.save(bake, bounds, prov, ph)
	var bake2 := LightBake.new(params, Solar.new(params))
	assert_false(LightBakeCache.try_load(bake2, bounds, _fake_provenance(2), ph))
	assert_eq(bake2._svf.size(), 0)


func test_mismatch_params_hash_is_miss() -> void:
	var params := IvyParams.new()
	var bake := LightBake.new(params, Solar.new(params))
	var bounds := AABB(Vector3.ZERO, Vector3.ONE)
	var prov := _fake_provenance(3)
	var ph := LightBakeCache.params_hash(params)
	bake._slot_of[CellGrid.pack_key(Vector3i.ZERO)] = 0
	bake._svf = PackedFloat32Array([0.5])
	bake._vis = PackedInt32Array([0xFFFFFF])
	LightBakeCache.save(bake, bounds, prov, ph)
	var other := IvyParams.new()
	other.svf_rays = params.svf_rays + 1
	var bake2 := LightBake.new(other, Solar.new(other))
	assert_false(LightBakeCache.try_load(bake2, bounds, prov, LightBakeCache.params_hash(other)))
	assert_eq(bake2._svf.size(), 0)


func test_corrupt_magic_fails_load() -> void:
	var params := IvyParams.new()
	var prov := _fake_provenance(4)
	var ph := LightBakeCache.params_hash(params)
	var path := LightBakeCache.cache_path(prov, ph)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LightBakeCache.CACHE_DIR))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("BADMAGIC")
	f.close()
	var bake := LightBake.new(params, Solar.new(params))
	assert_false(LightBakeCache.try_load(bake, AABB(Vector3.ZERO, Vector3.ONE), prov, ph))
