class_name WallBuilder
extends RefCounted

const ConvScript = preload("res://src/core/conv.gd")
const WallSdfScript = preload("res://src/world/wall_sdf.gd")
const TowerBuildResultScript = preload("res://src/world/tower_build_result.gd")


static func build(spec: WallSpec, dev_build: bool = true) -> TowerBuildResult:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_material := PackedByteArray()
	var sdf := WallSdfScript.new(spec)
	var hl := spec.length * 0.5
	var h := spec.height
	var t := spec.thickness
	var bpx := spec.brick_physical_size.x
	var bpy := spec.brick_physical_size.y
	var mat := MaterialRegistry.BRICK_WALL

	_add_face_quad(
		st, face_material, spec,
		Vector3(-hl, 0.0, 0.0), Vector3(-hl, h, 0.0),
		Vector3(hl, 0.0, 0.0), Vector3(hl, h, 0.0),
		Vector2(0.0, 0.0), Vector2(0.0, h / bpy),
		Vector2(spec.length / bpx, 0.0), Vector2(spec.length / bpx, h / bpy),
		ConvScript.SOUTH, mat, true
	)
	_add_face_quad(
		st, face_material, spec,
		Vector3(-hl, 0.0, -t), Vector3(-hl, h, -t),
		Vector3(hl, 0.0, -t), Vector3(hl, h, -t),
		Vector2(0.0, 0.0), Vector2(0.0, h / bpy),
		Vector2(spec.length / bpx, 0.0), Vector2(spec.length / bpx, h / bpy),
		-ConvScript.SOUTH, mat, false
	)
	_add_face_quad(
		st, face_material, spec,
		Vector3(-hl, h, 0.0), Vector3(-hl, h, -t),
		Vector3(hl, h, 0.0), Vector3(hl, h, -t),
		Vector2(0.0, 0.0), Vector2(0.0, t / bpy),
		Vector2(spec.length / bpx, 0.0), Vector2(spec.length / bpx, t / bpy),
		ConvScript.UP, mat, true
	)
	_add_face_quad(
		st, face_material, spec,
		Vector3(hl, 0.0, 0.0), Vector3(hl, h, 0.0),
		Vector3(hl, 0.0, -t), Vector3(hl, h, -t),
		Vector2(0.0, 0.0), Vector2(0.0, h / bpy),
		Vector2(t / bpx, 0.0), Vector2(t / bpx, h / bpy),
		ConvScript.EAST, mat, true
	)
	_add_face_quad(
		st, face_material, spec,
		Vector3(-hl, 0.0, 0.0), Vector3(-hl, h, 0.0),
		Vector3(-hl, 0.0, -t), Vector3(-hl, h, -t),
		Vector2(0.0, 0.0), Vector2(0.0, h / bpy),
		Vector2(t / bpx, 0.0), Vector2(t / bpx, h / bpy),
		ConvScript.WEST, mat, false
	)
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
	var result := TowerBuildResult.new()
	result.mesh = mesh
	result.shape = shape
	result.face_material = face_material
	result.triangle_count = face_material.size()
	if dev_build:
		_assert_outward_normals(tris, face_material, spec, sdf)
	return result


static func _add_face_quad(
	st: SurfaceTool, face_material: PackedByteArray, spec: WallSpec,
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


static func _assert_outward_normals(
	tris: PackedVector3Array, face_material: PackedByteArray, spec: WallSpec, sdf: WallSdf
) -> void:
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n_geo := -(b - a).cross(c - a).normalized()
		var centroid := (a + b + c) / 3.0
		assert(sdf.signed_distance(centroid + n_geo * 0.01) > 0.0)
		assert(sdf.signed_distance(centroid - n_geo * 0.01) < 0.0)
