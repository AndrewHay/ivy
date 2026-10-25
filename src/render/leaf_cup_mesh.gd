class_name LeafCupMesh
extends RefCounted

## SD-LEAF-1: 3×3 vertex blade patch cupped ~10° along the long axis (8–12° spec), plus a
## full-length midrib crease and a thin petiole strip (LEAF_STANDARD.md).
## Local space: x = width (−0.5…0.5), y = node→tip, z = outward. Units of x/y/z are blade
## width/height/width — the instance basis must scale z by width (LeafRenderer does).
## The blade occupies y ∈ [PETIOLE_LEN, PETIOLE_LEN + 1]; atlas v=1 (petiole end) is nearest the node.
## Petiole vertices carry UV v ∈ [1.5, 2.5] so the shader can paint them as stalk, not atlas. The gap
## above 1.0 keeps MSAA-extrapolated blade-edge UVs (v ≈ 1.0+ε) out of the petiole branch.
const CUP_DEGREES := 10.0
const CREASE_DEGREES := 9.0
const PETIOLE_LEN := 0.30
const PETIOLE_WIDTH := 0.028
## Petiole overlaps under the blade base so there is no gap at the junction.
const PETIOLE_OVERLAP := 0.06


static func build_flat(subdiv: int = 4) -> ArrayMesh:
	return _build_mesh(subdiv, 0.0, 0.0, false)


static func build() -> ArrayMesh:
	return _build_mesh(2, CUP_DEGREES, CREASE_DEGREES, true)


static func _build_mesh(grid: int, cup_degrees: float, crease_degrees: float, petiole: bool) -> ArrayMesh:
	var cup_amp := tan(deg_to_rad(cup_degrees)) * 0.5
	var crease_amp := tan(deg_to_rad(crease_degrees)) * 0.5
	var y_base := PETIOLE_LEN if petiole else 0.0
	var n := maxi(grid, 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(n + 1):
		for i in range(n + 1):
			var u := float(i) / float(n)
			var v := float(j) / float(n)
			var x := u - 0.5
			var y := 1.0 - v
			var z := _cup_offset(x, y, cup_amp) + _crease_offset(x, crease_amp)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(x, y_base + y, z))
	var row_stride := n + 1
	for j in range(n):
		for i in range(n):
			var i00 := j * row_stride + i
			var i10 := i00 + 1
			var i01 := i00 + row_stride
			var i11 := i01 + 1
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i00)
			st.add_index(i11)
			st.add_index(i01)
	if petiole:
		var base_i := (n + 1) * (n + 1)
		var hw := PETIOLE_WIDTH * 0.5
		var y_top := y_base + PETIOLE_OVERLAP
		var z_top := _crease_offset(0.0, crease_amp)
		var corners := [
			[Vector3(-hw, y_top, z_top), Vector2(0.0, 1.5)],
			[Vector3(hw, y_top, z_top), Vector2(1.0, 1.5)],
			[Vector3(-hw, 0.0, 0.0), Vector2(0.0, 2.5)],
			[Vector3(hw, 0.0, 0.0), Vector2(1.0, 2.5)],
		]
		for c: Array in corners:
			st.set_uv(c[1])
			st.add_vertex(c[0])
		st.add_index(base_i)
		st.add_index(base_i + 1)
		st.add_index(base_i + 3)
		st.add_index(base_i)
		st.add_index(base_i + 3)
		st.add_index(base_i + 2)
	st.generate_normals(true)
	st.generate_tangents()
	return st.commit()


static func _cup_offset(x: float, y: float, amp: float) -> float:
	var along := sin(PI * y)
	var across := 1.0 - (2.0 * x) * (2.0 * x)
	return amp * along * across


## Midrib ridge: halves fall away linearly from x=0, constant along the blade.
static func _crease_offset(x: float, amp: float) -> float:
	return amp * (1.0 - absf(2.0 * x))
