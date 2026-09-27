class_name LightBakeCache
extends RefCounted

## W-097 / SD-OPEN-24: disk cache for LightBake coarse-grid ray products (SVF + V_hours).
## Content-addressed on the geometry's identity plus bake-affecting IvyParams plus the bake
## code itself. Hard error on corrupt files; any mismatch is a miss (re-bake).
##
## ivy-9xp widened this from mesh-only to every backend and closed the stale-pairing hazard
## SD-OPEN-24 warned about ("pairing a correct volume with the wrong cache would leave every
## test passing"). The hazard came from keys that were *proxies* for the bake's inputs, so the
## key is now total over three things, and a load-path probe catches whatever totality misses:
##
##   1. geometry — `SurfaceQuery.bake_identity()`: GLB hash for MeshSdf, spec hash otherwise
##   2. parameters — every field in `IvyParams.BAKE_AFFECTING`, guarded by a conformance test
##   3. code — the source of the scripts that compute the bake (`_CODE_FILES`)
##   4. verification — `verify_against_surface()` recomputes sampled cells and rejects on
##      mismatch, so a wrong pairing fails loudly on load instead of passing silently
##
## The asymmetry is deliberate: a miss and a rejection both just re-bake, so being too strict
## costs time while being too lax costs correctness. When in doubt, be strict.

const MAGIC := "IVYLBC1"
## 4: key widened to any backend identity + code hash; params hash now reads BAKE_AFFECTING.
const VERSION := 4
const CACHE_DIR := "res://.tmp/light_bake_cache/"
const HASH_BYTES := 32

## Scripts whose contents change what a bake produces. Editing any of them invalidates every
## cached bake, which is the point: nothing else notices that the ray math moved.
##
## `MeshSdf.BAKER_VERSION` is the hand-bumped version of this idea and shows the weakness —
## it only protects you when someone remembers. All three backends are listed unconditionally
## rather than just the active one, so the hash is a constant per build.
##
## The line this list draws: code that *computes* the bake belongs here — the ray math, the sun
## path, the surface oracle it queries, the conventions and cell arithmetic they are built on.
## Code that merely *populates the physics space* the rays are cast against (`structure_body.gd`,
## the scene composition) does not, because it also carries visual and material concerns that
## would cause constant needless invalidation. That half is covered by the verification probe
## instead, and its one known discrepancy is tracked as ivy-2ey.
const _CODE_FILES: Array[String] = [
	"res://src/env/light_bake.gd",
	"res://src/env/solar.gd",
	"res://src/world/surface_query.gd",
	"res://src/world/mesh_sdf.gd",
	"res://src/world/tower_sdf.gd",
	"res://src/world/wall_sdf.gd",
	# Reached through `SurfaceQuery.project_to_shell`, which decides where on the shell each
	# coarse cell's rays start — for TowerSdf that includes the opening-footprint snap.
	"res://src/world/opening_footprint.gd",
	"res://src/core/cell_grid.gd",
	# `Conv.tangent_basis` orients every SVF hemisphere sample and every horizon-escape ray, and
	# `Conv.sun_direction` places the sun, so a convention change moves every baked value.
	"res://src/core/conv.gd",
]

## Cells recomputed on load by `verify_against_surface`. Each costs the same ~136 rays the bake
## spent on it, so 64 cells is a fraction of a percent of a bake over tens of thousands of
## cells — cheap enough to run on every load, which is the only way a probe catches anything.
const VERIFY_SAMPLES := 64

static var _code_hash_cache: PackedByteArray = PackedByteArray()


static func params_hash(params: IvyParams) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(params_digest(params).to_utf8_buffer())
	return ctx.finish()


## Text form of the bake-affecting parameters, sorted. Public so a mismatch can be diffed.
static func params_digest(params: IvyParams) -> String:
	var parts: PackedStringArray = []
	for name in IvyParams.BAKE_AFFECTING:
		parts.append("%s=%s" % [name, SpecHash.format_value(params.get(name))])
	parts.sort()
	return "|".join(parts)


## Hash of the bake implementation. Computed once per process — the files cannot change while
## the game is running, and reading seven scripts on every building load would be wasteful.
static func code_hash() -> PackedByteArray:
	if _code_hash_cache.size() == HASH_BYTES:
		return _code_hash_cache
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for path in _CODE_FILES:
		ctx.update(path.to_utf8_buffer())
		if FileAccess.file_exists(path):
			ctx.update(FileAccess.get_file_as_bytes(path))
		else:
			# Exported builds may ship compiled scripts rather than .gd sources. Degrading to a
			# marker keeps the key well-defined; the verification probe is the backstop there.
			ctx.update("<unreadable>".to_utf8_buffer())
	_code_hash_cache = ctx.finish()
	return _code_hash_cache


static func cache_path(identity: PackedByteArray, params_hash: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(identity)
	ctx.update(params_hash)
	ctx.update(code_hash())
	var hex := ""
	for b in ctx.finish():
		hex += "%02x" % b
	return CACHE_DIR + hex + ".bin"


## Loads the coarse grid into `bake`, or returns false for any miss. A true return means the
## file matched the key; it does **not** yet mean the contents are trustworthy — callers must
## follow with `verify_against_surface()`, which is what makes a mispairing loud. Kept separate
## so this stays a pure file-format concern with no surface to supply.
static func try_load(
	bake: LightBake,
	bounds: AABB,
	identity: PackedByteArray,
	params_hash: PackedByteArray
) -> bool:
	if identity.size() != HASH_BYTES or params_hash.size() != HASH_BYTES:
		return false
	var path := cache_path(identity, params_hash)
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
	var file_identity := f.get_buffer(HASH_BYTES)
	var file_ph := f.get_buffer(HASH_BYTES)
	var file_code := f.get_buffer(HASH_BYTES)
	if file_identity != identity or file_ph != params_hash or file_code != code_hash():
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
	bake._leak = PackedFloat32Array()
	bake._bake_normal = PackedVector3Array()
	for _i in n:
		var key := f.get_64()
		var svf := f.get_float()
		var vis := f.get_32()
		var leak := f.get_float()
		var nx := f.get_float()
		var ny := f.get_float()
		var nz := f.get_float()
		bake._slot_of[key] = bake._svf.size()
		bake._svf.append(svf)
		bake._vis.append(vis)
		bake._leak.append(leak)
		bake._bake_normal.append(Vector3(nx, ny, nz))
	if f.get_position() != f.get_length():
		push_error("LightBakeCache: truncated file %s" % path)
		return false
	return true


static func save(
	bake: LightBake,
	bounds: AABB,
	identity: PackedByteArray,
	params_hash: PackedByteArray
) -> void:
	if identity.size() != HASH_BYTES or params_hash.size() != HASH_BYTES:
		return
	_ensure_cache_dir()
	var path := cache_path(identity, params_hash)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("LightBakeCache: cannot write %s" % path)
		return
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(VERSION)
	f.store_buffer(identity)
	f.store_buffer(params_hash)
	f.store_buffer(code_hash())
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
		f.store_float(bake._leak[slot])
		var bn: Vector3 = bake._bake_normal[slot]
		f.store_float(bn.x)
		f.store_float(bn.y)
		f.store_float(bn.z)


## Recomputes a deterministic sample of the loaded cells against the live surface and reports
## whether the cache still describes this build's bake (ivy-9xp).
##
## This is the layer that lets the key be "good enough" rather than provably total. The key
## covers geometry, parameters and the listed source files; the probe catches everything it
## cannot — an unlisted code path, a Godot upgrade changing float or physics behaviour, a file
## corrupt in a way that still parses, or a hash collision. SD-OPEN-24 rejected an earlier
## cache because a wrong pairing "would leave every test passing"; with this on the load path
## it fails in every test and every session that loads it instead.
##
## No expected values are stored: the file already holds a value for every cell, so verifying
## means recomputing some of them, not duplicating them.
static func verify_against_surface(
	bake: LightBake, surface: SurfaceQuery, samples: int = VERIFY_SAMPLES
) -> bool:
	if surface == null:
		push_error("LightBakeCache: verification needs a surface; refusing to trust the cache")
		return false
	var keys: Array = bake._slot_of.keys()
	if keys.is_empty():
		# Nothing to recompute means nothing verified, so this cannot be called a pass. Re-baking
		# an empty grid costs nothing, and a building that bakes zero cells is worth hearing about.
		push_error("LightBakeCache: cached bake has no cells, so it cannot be verified; re-baking")
		return false
	keys.sort()
	# Stride rather than RNG: reproducible across runs, and spread over the whole grid so a
	# corrupt region cannot hide between samples the way a clustered sample would allow.
	var count: int = mini(samples, keys.size())
	var stride: int = maxi(1, keys.size() / count)
	var index := 0
	while index < keys.size():
		var key: int = keys[index]
		var slot: int = bake._slot_of[key]
		var cell := CellGrid.unpack_key(key)
		var fresh := bake.compute_coarse_cell(surface, cell)
		if not fresh["in_band"]:
			push_error(
				"LightBakeCache: cached cell %s is out of band for this surface" % str(cell)
			)
			return false
		# SVF and leak are float32 on disk and in the packed arrays, so compare at float32
		# precision. The mask is an integer and must match exactly.
		if absf(float(fresh["svf"]) - bake._svf[slot]) > 1e-5:
			push_error(
				"LightBakeCache: SVF mismatch at %s (cached %f, recomputed %f)"
				% [str(cell), bake._svf[slot], fresh["svf"]]
			)
			return false
		if int(fresh["mask"]) != bake._vis[slot]:
			push_error(
				"LightBakeCache: visibility mask mismatch at %s (cached %d, recomputed %d)"
				% [str(cell), bake._vis[slot], fresh["mask"]]
			)
			return false
		if absf(float(fresh["leak"]) - bake._leak[slot]) > 1e-5:
			push_error(
				"LightBakeCache: leak mismatch at %s (cached %f, recomputed %f)"
				% [str(cell), bake._leak[slot], fresh["leak"]]
			)
			return false
		# Normals feed `_gather_corners`'s face filter, so a file with the right ray products and
		# the wrong normals still reads wrong. Compared by direction: both sides are unit vectors,
		# and 0.9999 allows the float32 narrowing of the stored copy without allowing a real tilt.
		if (fresh["normal"] as Vector3).dot(bake._bake_normal[slot]) < 0.9999:
			push_error(
				"LightBakeCache: normal mismatch at %s (cached %s, recomputed %s)"
				% [str(cell), str(bake._bake_normal[slot]), str(fresh["normal"])]
			)
			return false
		index += stride
	return true


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
