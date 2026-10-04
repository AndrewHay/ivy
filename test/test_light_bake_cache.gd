extends GutTest

const IvyParams = preload("res://src/params/ivy_params.gd")
const Solar = preload("res://src/env/solar.gd")
const LightBake = preload("res://src/env/light_bake.gd")
const LightBakeCache = preload("res://src/env/light_bake_cache.gd")
const IvyEnvironment = preload("res://src/env/environment.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")
const WallSdf = preload("res://src/world/wall_sdf.gd")

## Header layout, for the byte-level tamper test: magic, version, then the three key hashes.
const CODE_HASH_OFFSET := 7 + 4 + 2 * LightBakeCache.HASH_BYTES


func _fake_identity(byte: int) -> PackedByteArray:
	var p := PackedByteArray()
	for _i in LightBakeCache.HASH_BYTES:
		p.append(byte)
	return p


## Deliberately not the shipped `wall_spec_default.tres` dimensions: these tests write real
## cache entries into the shared `res://.tmp` directory, and a distinct spec keeps their keys
## clear of the buildings the game loads. `length` also separates one test's entries from
## another's, so a file a tamper test leaves behind cannot reach the test next door.
func _tiny_wall_surface(length: float = 1.2) -> SurfaceQuery:
	var spec := WallSpec.new()
	spec.length = length
	spec.height = 0.8
	spec.thickness = 0.35
	var sq := SurfaceQuery.new()
	sq.setup(null, null, WallSdf.new(spec), PackedByteArray(), IvyParams.new())
	return sq


## Cache entries outlive the process, which is the whole point of them — so any test asserting a
## *miss* has to clear the entry a previous run left behind or it will see that run's hit.
func _forget_cache_entry(identity: PackedByteArray, params: IvyParams) -> void:
	var path := LightBakeCache.cache_path(identity, LightBakeCache.params_hash(params))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _single_cell_bake(params: IvyParams) -> LightBake:
	var bake := LightBake.new(params, Solar.new(params))
	bake._slot_of[CellGrid.pack_key(Vector3i.ZERO)] = 0
	bake._svf = PackedFloat32Array([0.5])
	bake._vis = PackedInt32Array([0x00FFFFFF])
	bake._leak = PackedFloat32Array([0.0])
	bake._bake_normal = PackedVector3Array([Vector3.UP])
	return bake


func test_save_load_roundtrip_preserves_coarse_grid() -> void:
	var params := IvyParams.new()
	var bake := LightBake.new(params, Solar.new(params))
	var bounds := AABB(Vector3(-1, 0, -1), Vector3(2, 3, 2))
	var key := CellGrid.pack_key(Vector3i(7, -3, 12))
	bake._slot_of[key] = 0
	bake._svf = PackedFloat32Array([0.42])
	bake._vis = PackedInt32Array([0x00FF00FF])
	bake._leak = PackedFloat32Array([0.25])
	bake._bake_normal = PackedVector3Array([Vector3(0.0, 0.0, 1.0)])
	var identity := _fake_identity(0xAB)
	var ph := LightBakeCache.params_hash(params)
	LightBakeCache.save(bake, bounds, identity, ph)
	var bake2 := LightBake.new(params, Solar.new(params))
	assert_true(LightBakeCache.try_load(bake2, bounds, identity, ph))
	assert_eq(bake2._svf.size(), 1)
	assert_almost_eq(bake2._svf[0], 0.42, 1e-6)
	assert_eq(bake2._vis[0], 0x00FF00FF)
	assert_almost_eq(bake2._leak[0], 0.25, 1e-6)
	assert_true(bake2._slot_of.has(key))


func test_mismatch_identity_is_miss_not_stale_read() -> void:
	var params := IvyParams.new()
	var bounds := AABB(Vector3.ZERO, Vector3.ONE)
	var identity := _fake_identity(1)
	var ph := LightBakeCache.params_hash(params)
	LightBakeCache.save(_single_cell_bake(params), bounds, identity, ph)
	var bake2 := LightBake.new(params, Solar.new(params))
	assert_false(LightBakeCache.try_load(bake2, bounds, _fake_identity(2), ph))
	assert_eq(bake2._svf.size(), 0)


func test_mismatch_params_hash_is_miss() -> void:
	var params := IvyParams.new()
	var bounds := AABB(Vector3.ZERO, Vector3.ONE)
	var identity := _fake_identity(3)
	LightBakeCache.save(
		_single_cell_bake(params), bounds, identity, LightBakeCache.params_hash(params)
	)
	var other := IvyParams.new()
	other.svf_rays = params.svf_rays + 1
	var bake2 := LightBake.new(other, Solar.new(other))
	assert_false(
		LightBakeCache.try_load(bake2, bounds, identity, LightBakeCache.params_hash(other))
	)
	assert_eq(bake2._svf.size(), 0)


func test_corrupt_magic_fails_load() -> void:
	var params := IvyParams.new()
	var identity := _fake_identity(4)
	var ph := LightBakeCache.params_hash(params)
	var path := LightBakeCache.cache_path(identity, ph)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LightBakeCache.CACHE_DIR))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("BADMAGIC")
	f.close()
	var bake := LightBake.new(params, Solar.new(params))
	assert_false(LightBakeCache.try_load(bake, AABB(Vector3.ZERO, Vector3.ONE), identity, ph))


# --- Key totality (ivy-9xp layers 2 and 3) ---


## Every declared bake-affecting parameter must actually move the hash. A name listed in
## BAKE_AFFECTING but not read would advertise protection the cache does not have.
func test_params_hash_responds_to_every_bake_affecting_parameter() -> void:
	var base_hash := LightBakeCache.params_hash(IvyParams.new())
	assert_gt(IvyParams.BAKE_AFFECTING.size(), 5, "the bake-affecting list must be non-trivial")
	for name in IvyParams.BAKE_AFFECTING:
		var perturbed := IvyParams.new()
		var value: Variant = perturbed.get(name)
		match typeof(value):
			TYPE_INT:
				perturbed.set(name, int(value) + 1)
			TYPE_FLOAT:
				perturbed.set(name, float(value) + 1.0)
			TYPE_BOOL:
				perturbed.set(name, not bool(value))
			_:
				fail_test("unhandled parameter type for %s" % name)
				continue
		assert_ne(
			LightBakeCache.params_hash(perturbed), base_hash,
			"changing %s must change the cache key, or a cached bake outlives it" % name
		)


## The mirror of the above: parameters that only scale the uncached fine grid must not
## invalidate bakes, or every light-tuning tweak costs a full re-bake for nothing.
func test_params_hash_ignores_parameters_the_coarse_bake_cannot_see() -> void:
	var base := IvyParams.new()
	var base_hash := LightBakeCache.params_hash(base)
	var other := IvyParams.new()
	other.light_p_max = base.light_p_max * 2.0
	other.leaf_cap = base.leaf_cap + 1
	other.branch_rate = base.branch_rate + 0.5
	assert_eq(LightBakeCache.params_hash(other), base_hash)


## Pre-ivy-9xp the key covered ray counts and cell sizes but not the sun path, so moving the
## site or changing the date reused another location's shadow mask.
func test_params_hash_covers_the_sun_path() -> void:
	var base_hash := LightBakeCache.params_hash(IvyParams.new())
	for name in ["latitude", "longitude", "day_of_year"]:
		var moved := IvyParams.new()
		var value: Variant = moved.get(name)
		moved.set(name, int(value) + 1 if typeof(value) == TYPE_INT else float(value) + 1.0)
		assert_ne(
			LightBakeCache.params_hash(moved), base_hash,
			"%s changes the baked visibility mask and must change the key" % name
		)


func test_code_hash_is_a_stable_digest() -> void:
	var first := LightBakeCache.code_hash()
	assert_eq(first.size(), LightBakeCache.HASH_BYTES)
	assert_eq(LightBakeCache.code_hash(), first, "code hash must be stable within a run")


## A file written by a build whose bake code differed must not be read back, even when the
## geometry and the parameters match.
func test_file_from_different_bake_code_is_a_miss() -> void:
	var params := IvyParams.new()
	var bounds := AABB(Vector3.ZERO, Vector3.ONE)
	var identity := _fake_identity(5)
	var ph := LightBakeCache.params_hash(params)
	LightBakeCache.save(_single_cell_bake(params), bounds, identity, ph)
	var f := FileAccess.open(LightBakeCache.cache_path(identity, ph), FileAccess.READ_WRITE)
	f.seek(CODE_HASH_OFFSET)
	f.store_buffer(_fake_identity(0x7E))
	f.close()
	var bake2 := LightBake.new(params, Solar.new(params))
	assert_false(
		LightBakeCache.try_load(bake2, bounds, identity, ph),
		"a cache written by different bake code must not be loaded"
	)


# --- Verification probe (ivy-9xp layer 4) ---


func test_probe_accepts_a_cache_this_build_produced() -> void:
	var params := IvyParams.new()
	var surface := _tiny_wall_surface()
	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)
	var bake := LightBake.new(params, Solar.new(params))
	bake.bake(surface, bounds)
	assert_gt(bake.coarse_count(), 0, "the wall must bake cells for this test to mean anything")
	var identity := surface.bake_identity()
	assert_eq(identity.size(), LightBakeCache.HASH_BYTES, "WallSdf must supply a cache identity")
	var ph := LightBakeCache.params_hash(params)
	LightBakeCache.save(bake, bounds, identity, ph)
	var loaded := LightBake.new(params, Solar.new(params))
	assert_true(LightBakeCache.try_load(loaded, bounds, identity, ph))
	assert_eq(loaded.coarse_count(), bake.coarse_count())
	assert_true(
		LightBakeCache.verify_against_surface(loaded, surface),
		"a cache written from this surface must verify against it"
	)


## The hazard SD-OPEN-24 named: a file whose key matches but whose contents belong to another
## bake. The load succeeds and nothing about the key is wrong, so only recomputing catches it —
## without the probe this file would be used and every test would still pass.
func test_probe_rejects_svf_values_this_build_would_not_produce() -> void:
	var params := IvyParams.new()
	var surface := _tiny_wall_surface()
	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)
	var bake := LightBake.new(params, Solar.new(params))
	bake.bake(surface, bounds)
	# Every cell wrong, as a file belonging to another building would be, so the sampled probe
	# rather than an exhaustive one has to catch it.
	for slot in bake.coarse_count():
		bake._svf[slot] = 1.0 - bake._svf[slot]
	var identity := surface.bake_identity()
	var ph := LightBakeCache.params_hash(params)
	LightBakeCache.save(bake, bounds, identity, ph)
	var loaded := LightBake.new(params, Solar.new(params))
	assert_true(LightBakeCache.try_load(loaded, bounds, identity, ph), "the key still matches")
	assert_false(
		LightBakeCache.verify_against_surface(loaded, surface),
		"recomputing must catch SVF the live surface cannot produce"
	)


## One wrong cell, verified exhaustively: proves the mask is compared at all, independently of
## which cells the default sampling happens to visit.
func test_probe_rejects_a_wrong_visibility_mask() -> void:
	var params := IvyParams.new()
	var surface := _tiny_wall_surface()
	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)
	var bake := LightBake.new(params, Solar.new(params))
	bake.bake(surface, bounds)
	bake._vis[0] = ~bake._vis[0] & 0x00FFFFFF
	var identity := surface.bake_identity()
	var ph := LightBakeCache.params_hash(params)
	LightBakeCache.save(bake, bounds, identity, ph)
	var loaded := LightBake.new(params, Solar.new(params))
	assert_true(LightBakeCache.try_load(loaded, bounds, identity, ph))
	assert_false(
		LightBakeCache.verify_against_surface(loaded, surface, loaded.coarse_count()),
		"recomputing must catch an inverted direct-sun mask"
	)


## Normals are stored alongside the ray products and feed the trilerp face filter, so a file with
## correct SVF, mask and leak but rotated normals still reads wrong.
func test_probe_rejects_wrong_surface_normals() -> void:
	var params := IvyParams.new()
	var surface := _tiny_wall_surface(1.5)
	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)
	var bake := LightBake.new(params, Solar.new(params))
	bake.bake(surface, bounds)
	bake._bake_normal[0] = -bake._bake_normal[0]
	var identity := surface.bake_identity()
	var ph := LightBakeCache.params_hash(params)
	LightBakeCache.save(bake, bounds, identity, ph)
	var loaded := LightBake.new(params, Solar.new(params))
	assert_true(LightBakeCache.try_load(loaded, bounds, identity, ph))
	assert_false(
		LightBakeCache.verify_against_surface(loaded, surface, loaded.coarse_count()),
		"an inverted surface normal must be caught even when the ray products match"
	)


## Refusing to verify is the safe answer when there is nothing to verify against: a caller that
## cannot supply a surface must re-bake rather than trust the file.
func test_probe_refuses_without_a_surface() -> void:
	var params := IvyParams.new()
	assert_false(LightBakeCache.verify_against_surface(_single_cell_bake(params), null))


## A grid with no cells would otherwise pass by vacuum — nothing recomputed, nothing to disagree
## with. Re-baking nothing is free, so there is no reason to accept it.
func test_probe_refuses_an_empty_grid() -> void:
	var params := IvyParams.new()
	var empty := LightBake.new(params, Solar.new(params))
	assert_eq(empty.coarse_count(), 0, "this test needs a genuinely empty bake")
	assert_false(LightBakeCache.verify_against_surface(empty, _tiny_wall_surface()))


# --- End to end (ivy-9xp: the reason any of this exists) ---


## The headline change: a procedural building takes part in the cache at all. `build()` used to
## gate it on `backend_tag() == "MeshSdf"`, so the wall and the cylinder re-ran the whole ray
## bake on every load, for every test, forever.
func test_environment_build_caches_a_procedural_building() -> void:
	var params := IvyParams.new()
	var surface := _tiny_wall_surface(1.3)
	var identity := surface.bake_identity()
	var path := LightBakeCache.cache_path(identity, LightBakeCache.params_hash(params))
	_forget_cache_entry(identity, params)
	assert_false(FileAccess.file_exists(path), "this test must start from a cold cache")

	var cold := IvyEnvironment.new()
	cold.build(params, surface, Solar.new(params))
	assert_false(cold.loaded_coarse_from_cache, "a cold build has nothing to load")
	assert_true(FileAccess.file_exists(path), "a procedural build must write a cache entry")

	var warm := IvyEnvironment.new()
	warm.build(params, surface, Solar.new(params))
	assert_true(
		warm.loaded_coarse_from_cache,
		"the second build must load and verify the entry the first one wrote"
	)


## Same building, one bake-affecting parameter moved: a miss, so nothing stale is read. The warm
## build in the middle is what gives the final assertion its teeth — it proves a hit is available
## for this surface, so the miss that follows is caused by the parameter and not by a cache that
## never worked.
func test_environment_rebakes_when_a_bake_affecting_parameter_changes() -> void:
	var params := IvyParams.new()
	var moved := IvyParams.new()
	moved.latitude = params.latitude + 10.0
	var surface := _tiny_wall_surface(1.4)
	var identity := surface.bake_identity()
	_forget_cache_entry(identity, params)
	_forget_cache_entry(identity, moved)

	var cold := IvyEnvironment.new()
	cold.build(params, surface, Solar.new(params))
	assert_false(cold.loaded_coarse_from_cache, "a cold build has nothing to load")

	var warm := IvyEnvironment.new()
	warm.build(params, surface, Solar.new(params))
	assert_true(warm.loaded_coarse_from_cache, "an unchanged rebuild must hit")

	var relocated := IvyEnvironment.new()
	relocated.build(moved, surface, Solar.new(moved))
	assert_false(
		relocated.loaded_coarse_from_cache,
		"moving the site changes the sun path, so the previous bake must not be reused"
	)


# --- Fine-grid disk cache (ivy-k99) ---


func _forget_fine_cache_entry(identity: PackedByteArray, params: IvyParams) -> void:
	var path := LightBakeCache.fine_cache_path(identity, LightBakeCache.fine_params_hash(params))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _single_cell_fine_field(params: IvyParams, svf: float = 0.6, p_hour_base: float = 3.0) -> SparseHashField:
	var field := SparseHashField.new(params.field_cell)
	var slot := field.ensure_cell(Vector3i(2, -1, 5))
	field.write_slot(SparseHashField.Channel.SVF, slot, svf)
	field.ensure_p_hour()
	for hour in LightBake.HOURS:
		field.set_p_hour(slot, hour, p_hour_base + float(hour))
	return field


func test_save_load_roundtrip_preserves_fine_grid() -> void:
	var params := IvyParams.new()
	var field := _single_cell_fine_field(params)
	var bounds := AABB(Vector3(-1, 0, -1), Vector3(2, 3, 2))
	var identity := _fake_identity(0xCD)
	var fine_ph := LightBakeCache.fine_params_hash(params)
	LightBakeCache.save_fine(
		field, bounds, identity, fine_ph, params.field_cell, params.field_shell_halfwidth
	)
	var loaded := SparseHashField.new(params.field_cell)
	assert_true(
		LightBakeCache.try_load_fine(
			loaded, bounds, identity, fine_ph, params.field_cell, params.field_shell_halfwidth
		)
	)
	assert_eq(loaded.slot_count(), 1)
	var slot := loaded.slot_of_cell(Vector3i(2, -1, 5))
	assert_ne(slot, -1, "the cached cell key must round-trip")
	assert_almost_eq(loaded.read_slot(SparseHashField.Channel.SVF, slot), 0.6, 1e-6)
	for hour in LightBake.HOURS:
		assert_almost_eq(loaded.p_hour(slot, hour), 3.0 + float(hour), 1e-4)


func test_fine_mismatch_identity_is_miss_not_stale_read() -> void:
	var params := IvyParams.new()
	var bounds := AABB(Vector3.ZERO, Vector3.ONE)
	var identity := _fake_identity(0xCE)
	var fine_ph := LightBakeCache.fine_params_hash(params)
	LightBakeCache.save_fine(
		_single_cell_fine_field(params), bounds, identity, fine_ph,
		params.field_cell, params.field_shell_halfwidth
	)
	var loaded := SparseHashField.new(params.field_cell)
	assert_false(
		LightBakeCache.try_load_fine(
			loaded, bounds, _fake_identity(0xCF), fine_ph,
			params.field_cell, params.field_shell_halfwidth
		)
	)
	assert_eq(loaded.slot_count(), 0)


func test_fine_mismatch_params_hash_is_miss() -> void:
	var params := IvyParams.new()
	var bounds := AABB(Vector3.ZERO, Vector3.ONE)
	var identity := _fake_identity(0xD0)
	LightBakeCache.save_fine(
		_single_cell_fine_field(params), bounds, identity, LightBakeCache.fine_params_hash(params),
		params.field_cell, params.field_shell_halfwidth
	)
	var other := IvyParams.new()
	other.light_p_max = params.light_p_max * 2.0
	var loaded := SparseHashField.new(other.field_cell)
	assert_false(
		LightBakeCache.try_load_fine(
			loaded, bounds, identity, LightBakeCache.fine_params_hash(other),
			other.field_cell, other.field_shell_halfwidth
		)
	)
	assert_eq(loaded.slot_count(), 0)


func test_fine_corrupt_magic_fails_load() -> void:
	var params := IvyParams.new()
	var identity := _fake_identity(0xD1)
	var fine_ph := LightBakeCache.fine_params_hash(params)
	var path := LightBakeCache.fine_cache_path(identity, fine_ph)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LightBakeCache.CACHE_DIR))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("BADMAGIC")
	f.close()
	var loaded := SparseHashField.new(params.field_cell)
	assert_false(
		LightBakeCache.try_load_fine(
			loaded, AABB(Vector3.ZERO, Vector3.ONE), identity, fine_ph,
			params.field_cell, params.field_shell_halfwidth
		)
	)


func test_fine_probe_accepts_a_cache_this_build_produced() -> void:
	var params := IvyParams.new()
	var surface := _tiny_wall_surface(1.6)
	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)
	var bake := LightBake.new(params, Solar.new(params))
	bake.bake(surface, bounds)
	var grid := CellGrid.new(params.field_cell)
	var field := SparseHashField.new(params.field_cell)
	field.allocate_shell(surface, params.field_shell_halfwidth, bounds)
	bake.fill_field(surface, field, grid)
	assert_gt(field.slot_count(), 0, "the wall must fill fine cells for this test to mean anything")
	var identity := surface.bake_identity()
	var fine_ph := LightBakeCache.fine_params_hash(params)
	LightBakeCache.save_fine(
		field, bounds, identity, fine_ph, params.field_cell, params.field_shell_halfwidth
	)
	var loaded := SparseHashField.new(params.field_cell)
	assert_true(
		LightBakeCache.try_load_fine(
			loaded, bounds, identity, fine_ph, params.field_cell, params.field_shell_halfwidth
		)
	)
	assert_eq(loaded.slot_count(), field.slot_count())
	assert_true(
		LightBakeCache.verify_fine_against_surface(loaded, bake, grid, surface),
		"a fine cache written from this surface must verify against it"
	)


func test_fine_probe_rejects_svf_values_this_build_would_not_produce() -> void:
	var params := IvyParams.new()
	var surface := _tiny_wall_surface(1.7)
	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)
	var bake := LightBake.new(params, Solar.new(params))
	bake.bake(surface, bounds)
	var grid := CellGrid.new(params.field_cell)
	var field := SparseHashField.new(params.field_cell)
	field.allocate_shell(surface, params.field_shell_halfwidth, bounds)
	bake.fill_field(surface, field, grid)
	assert_gt(field.slot_count(), 0)
	for slot in field.slot_count():
		var svf := field.read_slot(SparseHashField.Channel.SVF, slot)
		field.write_slot(SparseHashField.Channel.SVF, slot, 1.0 - svf)
	var identity := surface.bake_identity()
	var fine_ph := LightBakeCache.fine_params_hash(params)
	LightBakeCache.save_fine(
		field, bounds, identity, fine_ph, params.field_cell, params.field_shell_halfwidth
	)
	var loaded := SparseHashField.new(params.field_cell)
	assert_true(
		LightBakeCache.try_load_fine(
			loaded, bounds, identity, fine_ph, params.field_cell, params.field_shell_halfwidth
		),
		"the key still matches"
	)
	assert_false(
		LightBakeCache.verify_fine_against_surface(loaded, bake, grid, surface),
		"recomputing must catch fine SVF the live surface cannot produce"
	)


func test_fine_probe_rejects_p_hour_values_this_build_would_not_produce() -> void:
	var params := IvyParams.new()
	var surface := _tiny_wall_surface(1.8)
	var bounds := surface.shell_bounds(params.field_shell_halfwidth + params.field_cell)
	var bake := LightBake.new(params, Solar.new(params))
	bake.bake(surface, bounds)
	var grid := CellGrid.new(params.field_cell)
	var field := SparseHashField.new(params.field_cell)
	field.allocate_shell(surface, params.field_shell_halfwidth, bounds)
	bake.fill_field(surface, field, grid)
	assert_gt(field.slot_count(), 0)
	field.set_p_hour(0, 12, field.p_hour(0, 12) + 500.0)
	var identity := surface.bake_identity()
	var fine_ph := LightBakeCache.fine_params_hash(params)
	LightBakeCache.save_fine(
		field, bounds, identity, fine_ph, params.field_cell, params.field_shell_halfwidth
	)
	var loaded := SparseHashField.new(params.field_cell)
	assert_true(
		LightBakeCache.try_load_fine(
			loaded, bounds, identity, fine_ph, params.field_cell, params.field_shell_halfwidth
		)
	)
	assert_false(
		LightBakeCache.verify_fine_against_surface(loaded, bake, grid, surface, field.slot_count()),
		"recomputing must catch a tampered P(cell,hour) entry"
	)


func test_fine_probe_refuses_an_empty_grid() -> void:
	var params := IvyParams.new()
	var empty := SparseHashField.new(params.field_cell)
	var bake := LightBake.new(params, Solar.new(params))
	var grid := CellGrid.new(params.field_cell)
	assert_false(
		LightBakeCache.verify_fine_against_surface(empty, bake, grid, _tiny_wall_surface())
	)


## End to end, mirroring test_environment_build_caches_a_procedural_building: the fine grid
## fill, not just the coarse ray bake, must be skipped on a warm build.
func test_environment_build_caches_the_fine_grid_for_a_procedural_building() -> void:
	var params := IvyParams.new()
	var surface := _tiny_wall_surface(1.9)
	var identity := surface.bake_identity()
	_forget_cache_entry(identity, params)
	_forget_fine_cache_entry(identity, params)

	var cold := IvyEnvironment.new()
	cold.build(params, surface, Solar.new(params))
	assert_false(cold.loaded_fine_from_cache, "a cold build has nothing to load")

	var warm := IvyEnvironment.new()
	warm.build(params, surface, Solar.new(params))
	assert_true(
		warm.loaded_fine_from_cache,
		"the second build must load and verify the fine entry the first one wrote"
	)


## The fine-specific mirror of test_environment_rebakes_when_a_bake_affecting_parameter_changes:
## a parameter the coarse bake cannot see, but the fine fill can, must still force a re-fill.
func test_environment_refills_when_a_fine_bake_affecting_parameter_changes() -> void:
	var params := IvyParams.new()
	var tuned := IvyParams.new()
	tuned.light_p_max = params.light_p_max * 1.5
	var surface := _tiny_wall_surface(2.0)
	var identity := surface.bake_identity()
	_forget_cache_entry(identity, params)
	_forget_cache_entry(identity, tuned)
	_forget_fine_cache_entry(identity, params)
	_forget_fine_cache_entry(identity, tuned)

	var cold := IvyEnvironment.new()
	cold.build(params, surface, Solar.new(params))
	assert_false(cold.loaded_fine_from_cache, "a cold build has nothing to load")

	var warm := IvyEnvironment.new()
	warm.build(params, surface, Solar.new(params))
	assert_true(warm.loaded_fine_from_cache, "an unchanged rebuild must hit the fine cache")

	var tuned_env := IvyEnvironment.new()
	tuned_env.build(tuned, surface, Solar.new(tuned))
	assert_false(
		tuned_env.loaded_fine_from_cache,
		"light_p_max only scales the fine table, but it must still force a re-fill"
	)
	# The coarse ray bake, meanwhile, must still hit — this is the whole point of splitting
	# the two caches' keys: a fine-only tuning change must not force the expensive ray trace.
	assert_true(
		tuned_env.loaded_coarse_from_cache,
		"light_p_max cannot move a single SVF/visibility/leak value, so the coarse cache "
		+ "(and its far more expensive ray bake) must still hit"
	)


# --- Cache directory eviction (ivy-1or) ---
##
## `_evict_lru` takes an explicit `max_bytes`/`dir_path` precisely so these tests never touch
## the real `CACHE_DIR` or its 512 MiB cap — doing either would mean writing hundreds of
## megabytes of fixtures, or risking eviction of real entries other tests and tools in the
## same run depend on. Everything below runs against a scratch directory this file owns.


const _EVICT_TEST_DIR := "res://.tmp/light_bake_cache_evict_test/"


func _evict_scratch_dir_setup() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_EVICT_TEST_DIR))


## GUT does not call this automatically for every test in the file (only `before_each`/
## `after_each` do that); each eviction test calls it explicitly on the way out so a failed
## assertion in one test cannot leave fixtures for the next to trip over.
func _evict_scratch_dir_teardown() -> void:
	var dir := DirAccess.open(_EVICT_TEST_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(_EVICT_TEST_DIR + name)
			)
		name = dir.get_next()
	dir.list_dir_end()


## Writes `byte_count` zero bytes under `_EVICT_TEST_DIR` and returns the `res://` path.
func _write_fake_cache_file(name: String, byte_count: int) -> String:
	var path := _EVICT_TEST_DIR + name
	var buf := PackedByteArray()
	buf.resize(byte_count)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(buf)
	f.close()
	return path


func _total_bytes(paths: Array) -> int:
	var total := 0
	for path in paths:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			total += f.get_length()
			f.close()
	return total


func test_evict_lru_is_a_no_op_when_under_the_cap() -> void:
	_evict_scratch_dir_setup()
	var a := _write_fake_cache_file("under_cap_a.bin", 50)
	var b := _write_fake_cache_file("under_cap_b.bin", 50)

	LightBakeCache._evict_lru("", 1000, _EVICT_TEST_DIR)

	assert_true(FileAccess.file_exists(a), "nothing should be deleted while under the cap")
	assert_true(FileAccess.file_exists(b), "nothing should be deleted while under the cap")
	_evict_scratch_dir_teardown()


## The core contract: once over the cap, the entry nothing has touched since it was written
## goes first, and recently-written entries survive as long as the cap allows room for them.
##
## `FileAccess.get_modified_time` only has one-second resolution on at least one filesystem
## this project tests on, so writing three files milliseconds apart is not enough to separate
## their mtimes — `_evict_lru` breaks mtime ties by path (see its doc comment), which is what
## makes "oldest" assertable here without a real multi-second sleep per test.
func test_evict_lru_deletes_oldest_entry_first_when_over_the_cap() -> void:
	_evict_scratch_dir_setup()
	var oldest := _write_fake_cache_file("ordered_a.bin", 100)
	var middle := _write_fake_cache_file("ordered_b.bin", 100)
	var newest := _write_fake_cache_file("ordered_c.bin", 100)

	# 300 bytes on disk, cap of 200: exactly one entry (the oldest) must go.
	LightBakeCache._evict_lru("", 200, _EVICT_TEST_DIR)

	assert_false(FileAccess.file_exists(oldest), "the oldest entry must be evicted first")
	assert_true(FileAccess.file_exists(middle), "the middle entry fits under the cap and must survive")
	assert_true(FileAccess.file_exists(newest), "the newest entry fits under the cap and must survive")
	_evict_scratch_dir_teardown()


## A save's own entry must never be evicted by that same save's cleanup, even if the directory
## was already over the cap before this save ran — otherwise every save-while-over-cap would
## write a file only to immediately delete it, re-baking forever without ever caching anything.
func test_evict_lru_never_deletes_the_keep_path_even_if_it_is_the_oldest() -> void:
	_evict_scratch_dir_setup()
	# "a" sorts before "e", so without the keep_path exemption this would be the first
	# candidate evicted on an mtime tie.
	var kept := _write_fake_cache_file("a_kept.bin", 500)
	var newer_but_expendable := _write_fake_cache_file("e_expendable.bin", 100)

	# Cap smaller than even the kept entry alone: everything else must go, but `kept` survives.
	LightBakeCache._evict_lru(kept, 10, _EVICT_TEST_DIR)

	assert_true(FileAccess.file_exists(kept), "keep_path must never be evicted by its own save")
	assert_false(
		FileAccess.file_exists(newer_but_expendable),
		"a non-keep entry must still be evicted even though it is newer than keep_path"
	)
	_evict_scratch_dir_teardown()


## Eviction continues past the first deletion when a single entry is not enough to clear the
## cap — the loop must re-check the running total, not just fire once.
func test_evict_lru_deletes_multiple_entries_until_under_the_cap() -> void:
	_evict_scratch_dir_setup()
	var paths: Array[String] = []
	for i in 5:
		# Zero-padded so lexicographic order matches numeric/creation order.
		paths.append(_write_fake_cache_file("many_%02d.bin" % i, 100))

	# 500 bytes on disk, cap of 150: four of the five oldest entries must go, leaving the one
	# newest entry (100 bytes), which is under the cap on its own.
	LightBakeCache._evict_lru("", 150, _EVICT_TEST_DIR)

	assert_eq(
		_total_bytes(paths), 100, "eviction must keep deleting until the total is under the cap"
	)
	assert_true(FileAccess.file_exists(paths[4]), "the single newest entry must be the survivor")
	_evict_scratch_dir_teardown()


## End-to-end: `save()` on the real cache path must trigger eviction against the real
## `CACHE_DIR`/`MAX_CACHE_BYTES`, not just the test-only parameters exercised above. This test
## only has to prove the wiring runs without starving the just-written entry — it is not
## expected to fill 512 MiB, so this is really asserting `save()` still leaves its own entry
## readable afterward.
func test_save_still_leaves_its_own_entry_readable_after_eviction_runs() -> void:
	var params := IvyParams.new()
	var bake := LightBake.new(params, Solar.new(params))
	var bounds := AABB(Vector3(-1, 0, -1), Vector3(2, 3, 2))
	bake._slot_of[CellGrid.pack_key(Vector3i.ZERO)] = 0
	bake._svf = PackedFloat32Array([0.5])
	bake._vis = PackedInt32Array([0x00FFFFFF])
	bake._leak = PackedFloat32Array([0.0])
	bake._bake_normal = PackedVector3Array([Vector3.UP])
	var identity := _fake_identity(201)
	var ph := LightBakeCache.params_hash(params)
	_forget_cache_entry(identity, params)

	LightBakeCache.save(bake, bounds, identity, ph)

	var path := LightBakeCache.cache_path(identity, ph)
	assert_true(
		FileAccess.file_exists(path),
		"the entry save() just wrote must still exist once its own eviction call returns"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
