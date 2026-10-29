class_name MeshSdf
extends RefCounted

## Baked discrete signed-distance volume (SD-MESH-2…8).
## Pitch, band, and pad live in the asset header — not IvyParams (SD-MESH-16).

const MAGIC := "IVYSDF1"
const BAKER_VERSION := 3

var h: float = 0.05
var band: float = 0.55
var origin: Vector3 = Vector3.ZERO
var dims: Vector3i = Vector3i.ZERO
var mesh_aabb: AABB = AABB()
var provenance: PackedByteArray = PackedByteArray()
var _data: PackedFloat32Array = PackedFloat32Array()


func signed_distance(p: Vector3) -> float:
	return _read_trilinear(p)


func bounds() -> AABB:
	return mesh_aabb


func gradient(p: Vector3) -> Vector3:
	# Always interpolate for differences — the W-087 uniform-neighbourhood read
	# shortcut returns flat Φ and would zero out ∇Φ near band edges (SD-MESH-5).
	var eps := h
	return Vector3(
		_read_trilinear_interp(p + Vector3(eps, 0.0, 0.0)) - _read_trilinear_interp(p - Vector3(eps, 0.0, 0.0)),
		_read_trilinear_interp(p + Vector3(0.0, eps, 0.0)) - _read_trilinear_interp(p - Vector3(0.0, eps, 0.0)),
		_read_trilinear_interp(p + Vector3(0.0, 0.0, eps)) - _read_trilinear_interp(p - Vector3(0.0, 0.0, eps))
	) / (2.0 * eps)


func gradient_normalized(p: Vector3) -> Vector3:
	var g := gradient(p)
	if g.length_squared() < 1e-10:
		return Conv.UP
	return g.normalized()


func load_from_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MeshSdf: cannot open %s" % path)
		return
	var magic := f.get_buffer(7).get_string_from_ascii()
	if magic != MAGIC:
		push_error("MeshSdf: bad magic in %s (got %s)" % [path, magic])
		return
	h = f.get_float()
	band = f.get_float()
	origin = Vector3(f.get_float(), f.get_float(), f.get_float())
	dims = Vector3i(f.get_32(), f.get_32(), f.get_32())
	var aabb_pos := Vector3(f.get_float(), f.get_float(), f.get_float())
	var aabb_size := Vector3(f.get_float(), f.get_float(), f.get_float())
	mesh_aabb = AABB(aabb_pos, aabb_size)
	var baker_ver := f.get_32()
	if baker_ver != BAKER_VERSION:
		push_error("MeshSdf: unsupported baker version %d in %s" % [baker_ver, path])
		return
	provenance = f.get_buffer(32)
	var count := dims.x * dims.y * dims.z
	_data = f.get_buffer(count * 4).to_float32_array()
	if _data.size() != count:
		push_error("MeshSdf: truncated data in %s (expected %d floats)" % [path, count])
		return


## Cache identity (ivy-9xp). The baked volume already carries a hash of the collision GLB's
## bytes (SD-MESH-9), which is exactly the content identity a cache key needs.
func bake_identity() -> PackedByteArray:
	return provenance


func verify_provenance(collision_glb_path: String) -> bool:
	if provenance.size() != 32:
		push_error("MeshSdf: missing provenance header")
		return false
	if collision_glb_path.is_empty():
		push_error("MeshSdf: collision_glb_path is required for provenance check")
		return false
	if not FileAccess.file_exists(collision_glb_path):
		push_error("MeshSdf: collision glb missing: %s" % collision_glb_path)
		return false
	var expected := _compute_provenance(collision_glb_path, h, band)
	if expected != provenance:
		push_error(
			"MeshSdf: provenance mismatch for %s (sdf volume does not match collision glb)"
			% collision_glb_path
		)
		return false
	return true


static func _compute_provenance(collision_glb_path: String, cell: float, band: float) -> PackedByteArray:
	var f := FileAccess.open(collision_glb_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var tail := PackedFloat32Array([cell, band]).to_byte_array()
	ctx.update(tail)
	ctx.update(PackedInt32Array([BAKER_VERSION]).to_byte_array())
	return ctx.finish()


func save_to_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MeshSdf: cannot write %s" % path)
		return
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_float(h)
	f.store_float(band)
	f.store_float(origin.x)
	f.store_float(origin.y)
	f.store_float(origin.z)
	f.store_32(dims.x)
	f.store_32(dims.y)
	f.store_32(dims.z)
	f.store_float(mesh_aabb.position.x)
	f.store_float(mesh_aabb.position.y)
	f.store_float(mesh_aabb.position.z)
	f.store_float(mesh_aabb.size.x)
	f.store_float(mesh_aabb.size.y)
	f.store_float(mesh_aabb.size.z)
	f.store_32(BAKER_VERSION)
	f.store_buffer(provenance)
	f.store_buffer(_data.to_byte_array())


func _cell_index(ix: int, iy: int, iz: int) -> int:
	return ix + iy * dims.x + iz * dims.x * dims.y


func _sample_cell(ix: int, iy: int, iz: int) -> float:
	ix = clampi(ix, 0, dims.x - 1)
	iy = clampi(iy, 0, dims.y - 1)
	iz = clampi(iz, 0, dims.z - 1)
	return _data[_cell_index(ix, iy, iz)]


## Both trilinear reads are unrolled by hand: they dominate growth-step cost on mesh
## buildings. The weight products and the left-to-right sums keep the loop's evaluation
## order exactly, so results are bit-identical to `_sample_cell`/`_tri_weight` loops.
func _read_trilinear(p: Vector3) -> float:
	if _data.is_empty():
		return band
	var q := (p - origin) / h
	var bx := int(floor(q.x))
	var by := int(floor(q.y))
	var bz := int(floor(q.z))
	var fx := q.x - float(bx)
	var fy := q.y - float(by)
	var fz := q.z - float(bz)
	var sy := dims.x
	var sz := dims.x * dims.y
	var x0 := clampi(bx, 0, dims.x - 1)
	var x1 := clampi(bx + 1, 0, dims.x - 1)
	var y0 := clampi(by, 0, dims.y - 1) * sy
	var y1 := clampi(by + 1, 0, dims.y - 1) * sy
	var z0 := clampi(bz, 0, dims.z - 1) * sz
	var z1 := clampi(bz + 1, 0, dims.z - 1) * sz
	var v000 := _data[x0 + y0 + z0]
	var v001 := _data[x0 + y0 + z1]
	var v010 := _data[x0 + y1 + z0]
	var v011 := _data[x0 + y1 + z1]
	var v100 := _data[x1 + y0 + z0]
	var v101 := _data[x1 + y0 + z1]
	var v110 := _data[x1 + y1 + z0]
	var v111 := _data[x1 + y1 + z1]
	var gx := 1.0 - fx
	var gy := 1.0 - fy
	var gz := 1.0 - fz
	var w000 := gx * gy * gz
	var w001 := gx * gy * fz
	var w010 := gx * fy * gz
	var w011 := gx * fy * fz
	var w100 := fx * gy * gz
	var w101 := fx * gy * fz
	var w110 := fx * fy * gz
	var w111 := fx * fy * fz
	var weight_sum := 0.0 + w000 + w001 + w010 + w011 + w100 + w101 + w110 + w111
	if weight_sum < 1e-6:
		return band if p.y >= mesh_aabb.position.y else -band
	if v001 == v000 and v010 == v000 and v011 == v000 and v100 == v000 \
			and v101 == v000 and v110 == v000 and v111 == v000:
		return v000
	var sum := 0.0 + w000 * v000 + w001 * v001 + w010 * v010 + w011 * v011 \
		+ w100 * v100 + w101 * v101 + w110 * v110 + w111 * v111
	return sum / weight_sum


static func _tri_weight(f: float, corner: int) -> float:
	return 1.0 - f if corner == 0 else f


func _read_trilinear_interp(p: Vector3) -> float:
	if _data.is_empty():
		return band
	var q := (p - origin) / h
	var bx := int(floor(q.x))
	var by := int(floor(q.y))
	var bz := int(floor(q.z))
	var fx := q.x - float(bx)
	var fy := q.y - float(by)
	var fz := q.z - float(bz)
	var sy := dims.x
	var sz := dims.x * dims.y
	var x0 := clampi(bx, 0, dims.x - 1)
	var x1 := clampi(bx + 1, 0, dims.x - 1)
	var y0 := clampi(by, 0, dims.y - 1) * sy
	var y1 := clampi(by + 1, 0, dims.y - 1) * sy
	var z0 := clampi(bz, 0, dims.z - 1) * sz
	var z1 := clampi(bz + 1, 0, dims.z - 1) * sz
	var gx := 1.0 - fx
	var gy := 1.0 - fy
	var gz := 1.0 - fz
	var w000 := gx * gy * gz
	var w001 := gx * gy * fz
	var w010 := gx * fy * gz
	var w011 := gx * fy * fz
	var w100 := fx * gy * gz
	var w101 := fx * gy * fz
	var w110 := fx * fy * gz
	var w111 := fx * fy * fz
	var weight_sum := 0.0 + w000 + w001 + w010 + w011 + w100 + w101 + w110 + w111
	if weight_sum < 1e-6:
		return band if p.y >= mesh_aabb.position.y else -band
	var sum := 0.0 + w000 * _data[x0 + y0 + z0] + w001 * _data[x0 + y0 + z1] \
		+ w010 * _data[x0 + y1 + z0] + w011 * _data[x0 + y1 + z1] \
		+ w100 * _data[x1 + y0 + z0] + w101 * _data[x1 + y0 + z1] \
		+ w110 * _data[x1 + y1 + z0] + w111 * _data[x1 + y1 + z1]
	return sum / weight_sum
