class_name VillageGrassMesh
extends RefCounted

## Blade tuft for near-ring lawn geometry (SD-GRASS-2): 7 blades, 35 tris per tuft.

const BLADE_COUNT := 7
const MESH_LCG_SEED := 88001


static func blade_tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var state := MESH_LCG_SEED
	for _b in range(BLADE_COUNT):
		state = VillageScatterPositions.lcg_step(state)
		var blade_hash := VillageScatterPositions.lcg_f01(state)
		state = VillageScatterPositions.lcg_step(state)
		var root_x := (VillageScatterPositions.lcg_f01(state) - 0.5) * 0.1
		state = VillageScatterPositions.lcg_step(state)
		var root_z := (VillageScatterPositions.lcg_f01(state) - 0.5) * 0.1
		state = VillageScatterPositions.lcg_step(state)
		var yaw := VillageScatterPositions.lcg_f01(state) * TAU
		state = VillageScatterPositions.lcg_step(state)
		var height := lerpf(0.16, 0.26, VillageScatterPositions.lcg_f01(state))
		state = VillageScatterPositions.lcg_step(state)
		var base_half_w := lerpf(0.012, 0.018, VillageScatterPositions.lcg_f01(state))
		state = VillageScatterPositions.lcg_step(state)
		var arch_frac := lerpf(0.15, 0.35, VillageScatterPositions.lcg_f01(state))
		_add_blade(st, Vector3(root_x, 0.0, root_z), yaw, height, base_half_w, arch_frac, blade_hash)
	st.generate_normals()
	return st.commit()


static func _add_blade(
		st: SurfaceTool,
		root: Vector3,
		yaw: float,
		height: float,
		base_half_w: float,
		arch_frac: float,
		blade_hash: float) -> void:
	var c := cos(yaw)
	var s := sin(yaw)
	var right := Vector3(c, 0.0, -s)
	var forward := Vector3(s, 0.0, c)
	var ts: Array[float] = [0.0, 0.35, 0.7, 1.0]
	var left_pts: Array[Vector3] = []
	var right_pts: Array[Vector3] = []
	var tip_pt := Vector3.ZERO
	var uvs_left: Array[Vector2] = []
	var uvs_right: Array[Vector2] = []
	for t in ts:
		var y := height * t
		var half_w := base_half_w * (1.0 - t)
		var arch := arch_frac * height * t * t
		var center := root + forward * arch + Vector3(0.0, y, 0.0)
		if t >= 1.0 - 1e-6:
			tip_pt = center
		else:
			left_pts.append(center - right * half_w)
			right_pts.append(center + right * half_w)
			uvs_left.append(Vector2(0.0, 1.0 - t))
			uvs_right.append(Vector2(1.0, 1.0 - t))
	var col := Color(blade_hash, 0.0, 0.0, 1.0)
	for seg in range(2):
		_add_blade_tri(st, left_pts[seg], right_pts[seg], right_pts[seg + 1], col,
			uvs_left[seg], uvs_right[seg], uvs_right[seg + 1])
		_add_blade_tri(st, left_pts[seg], right_pts[seg + 1], left_pts[seg + 1], col,
			uvs_left[seg], uvs_right[seg + 1], uvs_left[seg + 1])
	_add_blade_tri(st, left_pts[2], right_pts[2], tip_pt, col,
		uvs_left[2], uvs_right[2], Vector2(0.5, 0.0))


static func _add_blade_tri(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		col: Color,
		uv_a: Vector2,
		uv_b: Vector2,
		uv_c: Vector2) -> void:
	var n := (b - a).cross(c - a).normalized()
	for pair in [[a, uv_a], [b, uv_b], [c, uv_c]]:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(pair[1] as Vector2)
		st.add_vertex(pair[0] as Vector3)
