class_name VillageGrassMesh
extends RefCounted

## Low-poly cross card for near-ring lawn geometry (SD-GRASS-1 hybrid tier).


static func cross_card_mesh() -> ArrayMesh:
	var h := 0.32
	var w := 0.11
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_vertical_quad(st, w, h, 0.0)
	_add_vertical_quad(st, w, h, PI * 0.5)
	st.generate_normals()
	return st.commit()


static func _add_vertical_quad(st: SurfaceTool, half_w: float, height: float, yaw: float) -> void:
	var c := cos(yaw)
	var s := sin(yaw)
	var right := Vector3(c, 0.0, -s) * half_w
	var up := Vector3(0.0, height, 0.0)
	var o := Vector3.ZERO
	var n := Vector3(-s, 0.0, -c).normalized()
	var verts: Array[Vector3] = [o - right, o + right, o + right + up, o - right + up]
	var uvs: Array[Vector2] = [
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])
