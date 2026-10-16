class_name OverhangBuilder
extends RefCounted

## Builds a 10-face ArrayMesh + ConcavePolygonShape3D for the eave-wall fixture (ivy-9us).
##
## Geometry = wall body (4 exterior faces) + slab (6 faces):
##   Wall faces  : SOUTH, NORTH, EAST, WEST  (no top — covered by slab interior)
##   Slab faces  : SOUTH eave-lip, NORTH back, UP roof, DOWN soffit, EAST end, WEST end
##
## Dev-build: asserts every triangle's outward normal points away from the union SDF
## (same pattern as WallBuilder).  Pass dev_build=false in pure headless unit tests that
## lack a physics frame (though geometry assertions run without physics).

const ConvScript = preload("res://src/core/conv.gd")
const OverhangSdfScript = preload("res://src/world/overhang_sdf.gd")
const TowerBuildResultScript = preload("res://src/world/tower_build_result.gd")


## spec: OverhangSpec (untyped to avoid class_name resolution order issues at compile time).
static func build(spec, dev_build: bool = true) -> TowerBuildResult:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_material := PackedByteArray()
	var sdf := OverhangSdfScript.new(spec)

	var hl: float = spec.wall_length * 0.5   # half-length (x)
	var h: float  = spec.wall_height          # soffit height (y=5.0)
	var t: float  = spec.wall_thickness       # z depth of wall body (0.4)
	var p: float  = spec.slab_projection      # z extent of eave beyond face (1.0)
	var st_: float = spec.slab_thickness      # slab y thickness (0.3)
	var bpx: float = spec.brick_physical_size.x
	var bpy: float = spec.brick_physical_size.y
	var mat := MaterialRegistry.BRICK_WALL

	# ── Wall body (4 faces, no top) ────────────────────────────────────────

	# SOUTH: front climb face z=0, y=[0,h]
	_add_face_quad(
		st, face_material,
		Vector3(-hl, 0.0, 0.0), Vector3(-hl, h, 0.0),
		Vector3(hl,  0.0, 0.0), Vector3(hl,  h, 0.0),
		Vector2(0.0, 0.0), Vector2(0.0, h / bpy),
		Vector2(spec.wall_length / bpx, 0.0), Vector2(spec.wall_length / bpx, h / bpy),
		ConvScript.SOUTH, mat, true
	)
	# NORTH: back face z=-t, y=[0,h]
	_add_face_quad(
		st, face_material,
		Vector3(-hl, 0.0, -t), Vector3(-hl, h, -t),
		Vector3(hl,  0.0, -t), Vector3(hl,  h, -t),
		Vector2(0.0, 0.0), Vector2(0.0, h / bpy),
		Vector2(spec.wall_length / bpx, 0.0), Vector2(spec.wall_length / bpx, h / bpy),
		-ConvScript.SOUTH, mat, false
	)
	# EAST: right end x=+hl, y=[0,h], z=[-t,0]
	_add_face_quad(
		st, face_material,
		Vector3(hl, 0.0, 0.0), Vector3(hl, h, 0.0),
		Vector3(hl, 0.0, -t),  Vector3(hl, h, -t),
		Vector2(0.0, 0.0), Vector2(0.0, h / bpy),
		Vector2(t / bpx, 0.0), Vector2(t / bpx, h / bpy),
		ConvScript.EAST, mat, true
	)
	# WEST: left end x=-hl, y=[0,h], z=[-t,0]
	_add_face_quad(
		st, face_material,
		Vector3(-hl, 0.0, 0.0), Vector3(-hl, h, 0.0),
		Vector3(-hl, 0.0, -t),  Vector3(-hl, h, -t),
		Vector2(0.0, 0.0), Vector2(0.0, h / bpy),
		Vector2(t / bpx, 0.0), Vector2(t / bpx, h / bpy),
		ConvScript.WEST, mat, false
	)

	# ── Slab (6 faces) ────────────────────────────────────────────────────

	# SOUTH eave lip: z=+p, y=[h, h+st_]
	_add_face_quad(
		st, face_material,
		Vector3(-hl, h,       p), Vector3(-hl, h + st_, p),
		Vector3(hl,  h,       p), Vector3(hl,  h + st_, p),
		Vector2(0.0, 0.0), Vector2(0.0, st_ / bpy),
		Vector2(spec.wall_length / bpx, 0.0), Vector2(spec.wall_length / bpx, st_ / bpy),
		ConvScript.SOUTH, mat, true
	)
	# NORTH slab back: z=-t, y=[h, h+st_]
	_add_face_quad(
		st, face_material,
		Vector3(-hl, h,       -t), Vector3(-hl, h + st_, -t),
		Vector3(hl,  h,       -t), Vector3(hl,  h + st_, -t),
		Vector2(0.0, 0.0), Vector2(0.0, st_ / bpy),
		Vector2(spec.wall_length / bpx, 0.0), Vector2(spec.wall_length / bpx, st_ / bpy),
		-ConvScript.SOUTH, mat, false
	)
	# UP roof top: y=h+st_, z=[-t, p]
	## flip=false gives n_geo=UP (z increases from -t→0→p, p01 at z=+p → cross → DOWN → n_geo=UP)
	_add_face_quad(
		st, face_material,
		Vector3(-hl, h + st_, 0.0), Vector3(-hl, h + st_, p),
		Vector3(hl,  h + st_, 0.0), Vector3(hl,  h + st_, p),
		Vector2(0.0, 0.0), Vector2(0.0, p / bpy),
		Vector2(spec.wall_length / bpx, 0.0), Vector2(spec.wall_length / bpx, p / bpy),
		ConvScript.UP, mat, false
	)
	# DOWN soffit underside: y=h, z=[0, p]
	## flip=true gives n_geo=DOWN (p01 at z=+p → cross → UP → n_geo=DOWN)
	_add_face_quad(
		st, face_material,
		Vector3(-hl, h, 0.0), Vector3(-hl, h, p),
		Vector3(hl,  h, 0.0), Vector3(hl,  h, p),
		Vector2(0.0, 0.0), Vector2(0.0, p / bpy),
		Vector2(spec.wall_length / bpx, 0.0), Vector2(spec.wall_length / bpx, p / bpy),
		-ConvScript.UP, mat, true
	)
	# EAST slab end: x=+hl, y=[h, h+st_], z=[-t, p]
	_add_face_quad(
		st, face_material,
		Vector3(hl, h,       p),  Vector3(hl, h + st_, p),
		Vector3(hl, h,       -t), Vector3(hl, h + st_, -t),
		Vector2(0.0, 0.0), Vector2(0.0, st_ / bpy),
		Vector2((p + t) / bpx, 0.0), Vector2((p + t) / bpx, st_ / bpy),
		ConvScript.EAST, mat, true
	)
	# WEST slab end: x=-hl, y=[h, h+st_], z=[-t, p]
	_add_face_quad(
		st, face_material,
		Vector3(-hl, h,       p),  Vector3(-hl, h + st_, p),
		Vector3(-hl, h,       -t), Vector3(-hl, h + st_, -t),
		Vector2(0.0, 0.0), Vector2(0.0, st_ / bpy),
		Vector2((p + t) / bpx, 0.0), Vector2((p + t) / bpx, st_ / bpy),
		ConvScript.WEST, mat, false
	)

	# ── Build mesh + shape ────────────────────────────────────────────────

	var mesh := st.commit()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tris := PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.size() > 0:
		for i in range(0, indices.size(), 3):
			tris.append(verts[indices[i]])
			tris.append(verts[indices[i + 1]])
			tris.append(verts[indices[i + 2]])
	else:
		for i in range(0, verts.size(), 3):
			tris.append(verts[i])
			tris.append(verts[i + 1])
			tris.append(verts[i + 2])
	var shape := ConcavePolygonShape3D.new()
	shape.data = tris

	var result := TowerBuildResultScript.new()
	result.mesh = mesh
	result.shape = shape
	result.face_material = face_material
	result.triangle_count = face_material.size()
	if dev_build:
		_assert_outward_normals(tris, face_material, sdf)
	return result


static func _add_face_quad(
	st: SurfaceTool, face_material: PackedByteArray,
	p00: Vector3, p01: Vector3, p10: Vector3, p11: Vector3,
	uv00: Vector2, uv01: Vector2, uv10: Vector2, uv11: Vector2,
	n: Vector3, mat_id: int, flip: bool = false
) -> void:
	if flip:
		_add_tri(st, face_material, p00, p11, p10, uv00, uv11, uv10, n, mat_id)
		_add_tri(st, face_material, p00, p01, p11, uv00, uv01, uv11, n, mat_id)
	else:
		_add_tri(st, face_material, p00, p10, p11, uv00, uv10, uv11, n, mat_id)
		_add_tri(st, face_material, p00, p11, p01, uv00, uv11, uv01, n, mat_id)


static func _add_tri(
	st: SurfaceTool, face_material: PackedByteArray,
	a: Vector3, b: Vector3, c: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2,
	n: Vector3, mat_id: int
) -> void:
	st.set_normal(n)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(uv_c)
	st.add_vertex(c)
	face_material.append(mat_id)


## sdf: OverhangSdf (untyped to avoid class_name resolution order at compile time)
static func _assert_outward_normals(
	tris: PackedVector3Array, face_material: PackedByteArray, sdf
) -> void:
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n_geo := -(b - a).cross(c - a).normalized()
		var centroid := (a + b + c) / 3.0
		assert(sdf.signed_distance(centroid + n_geo * 0.01) > 0.0)
		assert(sdf.signed_distance(centroid - n_geo * 0.01) < 0.0)
