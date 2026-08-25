class_name LightBakeCache
extends RefCounted

## W-097 / SD-OPEN-24: disk cache for LightBake coarse-grid ray products (SVF + V_hours).
## Content-addressed on mesh provenance (SD-MESH-9) plus bake-affecting IvyParams.
## Hard error on corrupt files; provenance/params mismatch is a miss (re-bake).

const MAGIC := "IVYLBC1"
const VERSION := 1
const CACHE_DIR := "res://.tmp/light_bake_cache/"


static func params_hash(params: IvyParams) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedFloat32Array([
		params.vis_cell,
		params.field_shell_halfwidth,
		params.field_cell,
		params.bake_ray_length,
		params.bake_ray_offset,
	]).to_byte_array())
	ctx.update(PackedInt32Array([params.svf_rays]).to_byte_array())
	return ctx.finish()


static func cache_path(provenance: PackedByteArray, params_hash: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(provenance)
	ctx.update(params_hash)
	var hex := ""
	for b in ctx.finish():
		hex += "%02x" % b
	return CACHE_DIR + hex + ".bin"


static func try_load(
	bake: LightBake,
	bounds: AABB,
	provenance: PackedByteArray,
	params_hash: PackedByteArray
) -> bool:
	if provenance.size() != 32 or params_hash.size() != 32:
		return false
	var path := cache_path(provenance, params_hash)
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LightBakeCache: cannot open %s" % path)
		return false
	var magic := f.get_buffer(7).get_string_from_ascii()
	if magic != MAGIC:
		push_error("LightBakeCache: bad magic in %s" % path)
		return false
	var ver := f.get_32()
	if ver != VERSION:
		push_error("LightBakeCache: unsupported version %d in %s" % [ver, path])
		return false
	var file_prov := f.get_buffer(32)
	var file_ph := f.get_buffer(32)
	if file_prov != provenance or file_ph != params_hash:
		return false
	var vis_cell := f.get_float()
	if absf(vis_cell - bake.params.vis_cell) > 1e-6:
		return false
	var bx := Vector3(f.get_float(), f.get_float(), f.get_float())
	var bs := Vector3(f.get_float(), f.get_float(), f.get_float())
	var file_bounds := AABB(bx, bs)
	if not _bounds_match(file_bounds, bounds):
		return false
	var n := f.get_32()
	bake._slot_of.clear()
	bake._svf = PackedFloat32Array()
	bake._vis = PackedInt32Array()
	for _i in n:
		var key := f.get_64()
		var svf := f.get_float()
		var vis := f.get_32()
		var cell := CellGrid.unpack_key(key)
		bake._slot_of[key] = bake._svf.size()
		bake._svf.append(svf)
		bake._vis.append(vis)
	if f.get_position() != f.get_length():
		push_error("LightBakeCache: truncated file %s" % path)
		return false
	return true


static func save(
	bake: LightBake,
	bounds: AABB,
	provenance: PackedByteArray,
	params_hash: PackedByteArray
) -> void:
	if provenance.size() != 32 or params_hash.size() != 32:
		return
	_ensure_cache_dir()
	var path := cache_path(provenance, params_hash)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("LightBakeCache: cannot write %s" % path)
		return
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(VERSION)
	f.store_buffer(provenance)
	f.store_buffer(params_hash)
	f.store_float(bake.params.vis_cell)
	f.store_float(bounds.position.x)
	f.store_float(bounds.position.y)
	f.store_float(bounds.position.z)
	f.store_float(bounds.size.x)
	f.store_float(bounds.size.y)
	f.store_float(bounds.size.z)
	var keys: Array = bake._slot_of.keys()
	keys.sort()
	f.store_32(keys.size())
	for key in keys:
		var slot: int = bake._slot_of[key]
		f.store_64(key)
		f.store_float(bake._svf[slot])
		f.store_32(bake._vis[slot])


static func _ensure_cache_dir() -> void:
	var abs := ProjectSettings.globalize_path(CACHE_DIR)
	if not DirAccess.dir_exists_absolute(abs):
		DirAccess.make_dir_recursive_absolute(abs)


static func _bounds_match(a: AABB, b: AABB) -> bool:
	const EPS := 1e-4
	return (
		a.position.distance_to(b.position) < EPS
		and a.size.distance_to(b.size) < EPS
	)
