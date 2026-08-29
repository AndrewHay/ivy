class_name LeafCupMesh
extends RefCounted

## SD-LEAF-1: 3×3 vertex patch cupped ~10° along the blade long axis (8–12° spec).
## Local space: x = width (−0.5…0.5), y = petiole→tip (1…0), z = outward cup.
const CUP_DEGREES := 10.0


static func build() -> ArrayMesh:
	var cup_amp := tan(deg_to_rad(CUP_DEGREES)) * 0.5
	var positions: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for j in range(3):
		for i in range(3):
			var u := float(i) / 2.0
			var v := float(j) / 2.0
			var x := u - 0.5
			var y := 1.0 - v
			positions.append(Vector3(x, y, _cup_offset(x, y, cup_amp)))
			uvs.append(Vector2(u, v))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vi in range(positions.size()):
		st.set_uv(uvs[vi])
		st.add_vertex(positions[vi])
	for j in range(2):
		for i in range(2):
			var i00 := j * 3 + i
			var i10 := i00 + 1
			var i01 := i00 + 3
			var i11 := i01 + 1
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i00)
			st.add_index(i11)
			st.add_index(i01)
	return st.commit()


static func _cup_offset(x: float, y: float, amp: float) -> float:
	var along := sin(PI * y)
	var across := 1.0 - (2.0 * x) * (2.0 * x)
	return amp * along * across
