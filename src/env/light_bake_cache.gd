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

## Caps `CACHE_DIR`'s total size (ivy-1or): every edit to a hashed source file, spec, or
## bake-affecting parameter orphans the previous generation of entries, and nothing deleted
## them before this, so a long edit history grows the directory without bound. Bounded by
## total bytes rather than entry count because entries vary over two orders of magnitude —
## coarse grids run tens of KB, fine grids run tens of MB (see the ivy-k99 section below) — so
## a count cap would starve whichever kind writes last while a byte cap bounds the thing that
## actually costs disk space. Safe to evict anything: the directory is gitignored and every
## entry is reconstructible from source, so losing one just costs a re-bake, never correctness.
const MAX_CACHE_BYTES := 512 * 1024 * 1024  # 512 MiB

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
	f.close()
	_evict_lru(path)


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


# --- Fine-grid disk cache (ivy-k99). ---
##
## Same content-addressing discipline as the coarse cache above (geometry + params + code +
## a verification probe), kept as an entirely separate file and key rather than folded into
## the coarse format. Two reasons: the coarse format is load-bearing for ten existing tests
## and every session that has ever cached a building, so extending it in place would force a
## version bump that invalidates every one of them for a change that does not touch what they
## cover; and the key itself must differ (`fine_params_hash` below, not `params_hash`) so a
## light-tuning change to `IvyParams.FINE_BAKE_AFFECTING` invalidates only this file, not the
## far more expensive coarse ray bake.
##
## What this fixes: `IvyEnvironment.build()`'s residual warm-load stall after ivy-9xp made the
## coarse ray bake cacheable — measured 2026-09-27 (ivy-k99) at 12.6s (test_wall, analytic
## `WallSdf`) and 27.9s (`square` mesh scenario, `MeshSdf`), of which `fill_field`'s per-cell
## `surface_normal`/`project_to_shell` geometry queries are 90% and 73% respectively, and
## `allocate_shell`'s per-candidate `signed_distance` queries are the rest — expensive for
## `MeshSdf` because both walk the narrow-band volume and, for `nearest()`, cast physics rays;
## cheap for the analytic backends' closed-form math. Caching the fine grid's shell membership
## and its `P(cell, hour)` table together skips both loops entirely on a hit, the same way the
## coarse cache skips the ray bake.
##
## Measured fine-to-coarse cell ratio is 2.2–4.0x on the two buildings measured, not the ~8x
## this was estimated at before measuring (`tools/measure_light_bake.gd`'s
## `_time_build_phases`) — `field_shell_halfwidth` (0.09 m) is a narrower band than the
## coarse grid's `vis_cell·√3` in-band threshold (~0.21 m), so the fine shell is not simply
## the coarse shell subdivided. File size lands at 9.8 MB (square, 93,910 cells) to 36.5 MB
## (test_wall, 351,045 cells) — one `u64` key plus one `f32` SVF plus 24 `f32` hours per cell.

const FINE_MAGIC := "IVYLBF1"
const FINE_VERSION := 1
const FINE_HOURS := 24

## Text form of `BAKE_AFFECTING` plus `FINE_BAKE_AFFECTING`, sorted. Public so a mismatch can
## be diffed, mirroring `params_digest`.
static func fine_params_digest(params: IvyParams) -> String:
	var parts: PackedStringArray = []
	for name in IvyParams.BAKE_AFFECTING:
		parts.append("%s=%s" % [name, SpecHash.format_value(params.get(name))])
	for name in IvyParams.FINE_BAKE_AFFECTING:
		parts.append("%s=%s" % [name, SpecHash.format_value(params.get(name))])
	parts.sort()
	return "|".join(parts)


static func fine_params_hash(params: IvyParams) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(fine_params_digest(params).to_utf8_buffer())
	return ctx.finish()


static func fine_cache_path(identity: PackedByteArray, fine_ph: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(identity)
	ctx.update(fine_ph)
	ctx.update(code_hash())
	ctx.update("fine".to_utf8_buffer())  # namespaced so a hash collision can't alias the coarse file
	var hex := ""
	for b in ctx.finish():
		hex += "%02x" % b
	return CACHE_DIR + "fine_" + hex + ".bin"


## Loads the fine shell + `P(cell, hour)` table directly into `field` (via `ensure_cell`,
## bypassing `SparseHashField.allocate_shell`'s per-candidate `signed_distance` queries and
## `LightBake.fill_field`'s per-cell geometry queries entirely) and returns whether it was a
## hit. Like `try_load`, a true return means the file matched the key, not that its contents
## are trustworthy — callers must follow with `verify_fine_against_surface`.
static func try_load_fine(
	field: SparseHashField,
	bounds: AABB,
	identity: PackedByteArray,
	fine_ph: PackedByteArray,
	field_cell: float,
	field_shell_halfwidth: float
) -> bool:
	if identity.size() != HASH_BYTES or fine_ph.size() != HASH_BYTES:
		return false
	var path := fine_cache_path(identity, fine_ph)
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LightBakeCache: cannot open %s" % path)
		return false
	var magic := f.get_buffer(7).get_string_from_ascii()
	if magic != FINE_MAGIC:
		push_error("LightBakeCache: bad magic in %s" % path)
		return false
	var ver := f.get_32()
	if ver != FINE_VERSION:
		push_error("LightBakeCache: unsupported fine version %d in %s" % [ver, path])
		return false
	var file_identity := f.get_buffer(HASH_BYTES)
	var file_ph := f.get_buffer(HASH_BYTES)
	var file_code := f.get_buffer(HASH_BYTES)
	if file_identity != identity or file_ph != fine_ph or file_code != code_hash():
		return false
	var file_cell := f.get_float()
	var file_halfwidth := f.get_float()
	if absf(file_cell - field_cell) > 1e-6 or absf(file_halfwidth - field_shell_halfwidth) > 1e-6:
		return false
	var bx := Vector3(f.get_float(), f.get_float(), f.get_float())
	var bs := Vector3(f.get_float(), f.get_float(), f.get_float())
	if not _bounds_match(AABB(bx, bs), bounds):
		return false
	var n := f.get_32()
	# Read every record before touching `field`. `SparseHashField.ensure_cell` only grows
	# `_p_hour` once it is already non-empty (a lazy-allocation optimisation for callers who
	# never bake at all, e.g. `debug_field_cells` fixtures) — calling `ensure_cell` then
	# `set_p_hour` cell-by-cell on a fresh field writes past the end of an unresized array.
	# Registering every cell first and calling `ensure_p_hour()` exactly once, sized against
	# the final cell count, avoids both that and `n` redundant array resizes.
	var keys := PackedInt64Array()
	var svfs := PackedFloat32Array()
	var p_hours := PackedFloat32Array()
	keys.resize(n)
	svfs.resize(n)
	p_hours.resize(n * FINE_HOURS)
	for i in n:
		keys[i] = f.get_64()
		svfs[i] = f.get_float()
		var base := i * FINE_HOURS
		for hour in FINE_HOURS:
			p_hours[base + hour] = f.get_float()
	if f.get_position() != f.get_length():
		push_error("LightBakeCache: truncated fine file %s" % path)
		return false
	var slots := PackedInt32Array()
	slots.resize(n)
	for i in n:
		slots[i] = field.ensure_cell(CellGrid.unpack_key(keys[i]))
	field.ensure_p_hour()
	for i in n:
		var slot := slots[i]
		field.write_slot(SparseHashField.Channel.SVF, slot, svfs[i])
		field.write_slot(SparseHashField.Channel.F_M, slot, 1.0)
		var base := i * FINE_HOURS
		for hour in FINE_HOURS:
			field.set_p_hour(slot, hour, p_hours[base + hour])
	return true


static func save_fine(
	field: SparseHashField,
	bounds: AABB,
	identity: PackedByteArray,
	fine_ph: PackedByteArray,
	field_cell: float,
	field_shell_halfwidth: float
) -> void:
	if identity.size() != HASH_BYTES or fine_ph.size() != HASH_BYTES:
		return
	_ensure_cache_dir()
	var path := fine_cache_path(identity, fine_ph)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("LightBakeCache: cannot write %s" % path)
		return
	f.store_buffer(FINE_MAGIC.to_ascii_buffer())
	f.store_32(FINE_VERSION)
	f.store_buffer(identity)
	f.store_buffer(fine_ph)
	f.store_buffer(code_hash())
	f.store_float(field_cell)
	f.store_float(field_shell_halfwidth)
	f.store_float(bounds.position.x)
	f.store_float(bounds.position.y)
	f.store_float(bounds.position.z)
	f.store_float(bounds.size.x)
	f.store_float(bounds.size.y)
	f.store_float(bounds.size.z)
	# Sorted for the same reason the coarse writer sorts: a stable byte-for-byte file for
	# unchanged input, so two bakes of the same building are diffable and version control
	# of a committed cache (if that is ever done) does not thrash on ordering alone.
	var keys: Array = []
	for slot in field.slot_count():
		keys.append(field.cell_key(slot))
	keys.sort()
	f.store_32(keys.size())
	for key in keys:
		var slot := field.slot_of_cell(CellGrid.unpack_key(key))
		f.store_64(key)
		f.store_float(field.read_slot(SparseHashField.Channel.SVF, slot))
		for hour in FINE_HOURS:
			f.store_float(field.p_hour(slot, hour))
	f.close()
	_evict_lru(path)


## Recomputes a deterministic sample of the loaded fine cells against the live surface and
## reports whether the cache still describes this build's fill (ivy-k99, mirroring
## `verify_against_surface`). Calls `LightBake.compute_fine_cell` — the same code
## `fill_field`/`fill_field_interactive` call — so this can only disagree with a genuine
## mismatch, never with its own reimplementation of the arithmetic.
static func verify_fine_against_surface(
	field: SparseHashField,
	bake: LightBake,
	grid: CellGrid,
	surface: SurfaceQuery,
	samples: int = VERIFY_SAMPLES
) -> bool:
	if surface == null:
		push_error("LightBakeCache: fine verification needs a surface; refusing to trust the cache")
		return false
	var slot_count := field.slot_count()
	if slot_count == 0:
		push_error("LightBakeCache: cached fine grid has no cells, so it cannot be verified; re-filling")
		return false
	var count: int = mini(samples, slot_count)
	var stride: int = maxi(1, slot_count / count)
	var slot := 0
	while slot < slot_count:
		var cell := CellGrid.unpack_key(field.cell_key(slot))
		var p := grid.cell_point(cell)
		if absf(surface.signed_distance(p)) > bake.params.field_shell_halfwidth + 1e-4:
			push_error(
				"LightBakeCache: cached fine cell %s is out of band for this surface" % str(cell)
			)
			return false
		var fresh := bake.compute_fine_cell(surface, p)
		var fresh_svf: float = fresh["svf"]
		if absf(fresh_svf - field.read_slot(SparseHashField.Channel.SVF, slot)) > 1e-5:
			push_error(
				"LightBakeCache: fine SVF mismatch at %s (cached %f, recomputed %f)"
				% [str(cell), field.read_slot(SparseHashField.Channel.SVF, slot), fresh_svf]
			)
			return false
		var fresh_p_hour: PackedFloat32Array = fresh["p_hour"]
		for hour in FINE_HOURS:
			if absf(fresh_p_hour[hour] - field.p_hour(slot, hour)) > 1e-4:
				push_error(
					"LightBakeCache: fine P(cell,hour=%d) mismatch at %s (cached %f, recomputed %f)"
					% [hour, str(cell), field.p_hour(slot, hour), fresh_p_hour[hour]]
				)
				return false
		slot += stride
	return true


static func _ensure_cache_dir() -> void:
	var abs := ProjectSettings.globalize_path(CACHE_DIR)
	if not DirAccess.dir_exists_absolute(abs):
		DirAccess.make_dir_recursive_absolute(abs)


## Deletes the oldest-by-mtime entries in `dir_path` until it is at or under `max_bytes`,
## skipping `keep_path` so a save can never evict the entry it just wrote even if the
## directory was already over the cap before this save. Called after every `save()` /
## `save_fine()` — the only places that create new entries — so growth is bounded at the
## point it happens rather than needing a separate sweep or a background task. mtime
## approximates least-recently-*used* (nothing records reads), which is enough for
## housekeeping: an entry nothing has resaved recently is also one nothing has hit recently,
## since every hit happens on the same building+params pairing that would resave it anyway if
## it were a miss.
##
## `max_bytes`/`dir_path` default to the real cap and directory; tests override both so they
## can exercise this against an isolated scratch directory with a cap small enough to write by
## hand, rather than needing hundreds of megabytes of fixtures or risking real cache entries
## other tests and tools depend on within the same run.
static func _evict_lru(
	keep_path: String, max_bytes: int = MAX_CACHE_BYTES, dir_path: String = CACHE_DIR
) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entries: Array[Dictionary] = []
	var total := 0
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var path := dir_path + name
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var size := f.get_length()
				f.close()
				total += size
				if path != keep_path:
					entries.append(
						{"path": path, "size": size, "mtime": FileAccess.get_modified_time(path)}
					)
		name = dir.get_next()
	dir.list_dir_end()
	if total <= max_bytes:
		return
	# `mtime` alone ties constantly: it has one-second resolution on at least one filesystem
	# this project runs tests on, and a bake session can easily write several entries within
	# the same second. Breaking ties by path makes eviction order a pure function of
	# (mtime, path) instead of directory-listing order, which filesystems do not guarantee —
	# deterministic either way, but only one of them is also reproducible for a test to assert.
	entries.sort_custom(
		func(a, b):
			if a["mtime"] != b["mtime"]:
				return a["mtime"] < b["mtime"]
			return a["path"] < b["path"]
	)
	for entry in entries:
		if total <= max_bytes:
			break
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(entry["path"])) == OK:
			total -= entry["size"]


static func _bounds_match(a: AABB, b: AABB) -> bool:
	const EPS := 1e-4
	return (
		a.position.distance_to(b.position) < EPS
		and a.size.distance_to(b.size) < EPS
	)
