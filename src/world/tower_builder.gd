class_name TowerBuilder
extends RefCounted

const ConvScript = preload("res://src/core/conv.gd")
const TowerSdfScript = preload("res://src/world/tower_sdf.gd")
const TowerBuildResultScript = preload("res://src/world/tower_build_result.gd")


static func build(spec: TowerSpec, dev_build: bool = true) -> TowerBuildResult:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_material := PackedByteArray()
	var sdf := TowerSdfScript.new(spec)
	var segs := spec.ring_segments
	for ring in range(segs):
		var a0 := TAU * float(ring) / float(segs)
		var a1 := TAU * float(ring + 1) / float(segs)
		if _spans_doorway(spec, a0, a1):
			continue
		if _spans_window(spec, a0, a1):
			# The window is bounded vertically, so we split the ring into a below-sill
			# strip and an above-window strip, skipping the opening height band.
			# A naive full-height quad would contradict the SDF and saturate the light
			# gradient for any tip growing near the east face (W-028).
			var sill := spec.window_sill
			var win_top := spec.window_sill + spec.window_size
			if sill > 0.0:
				_add_wall_quad(st, face_material, spec, a0, a1, 0.0, sill, MaterialRegistry.BRICK_WALL)
			if win_top < spec.height:
				_add_wall_quad(st, face_material, spec, a0, a1, win_top, spec.height, MaterialRegistry.BRICK_WALL)
		else:
			_add_wall_quad(st, face_material, spec, a0, a1, 0.0, spec.height, MaterialRegistry.BRICK_WALL)
	_build_lip(st, face_material, spec)
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


static func _spans_window(spec: TowerSpec, a0: float, a1: float) -> bool:
	var win_a := deg_to_rad(spec.window_azimuth)
	var half := asin(clampf(spec.window_size * 0.5 / spec.radius_outer, -1.0, 1.0)) + 0.05
	var ring_half := absf(a1 - a0) * 0.5
	return _angular_delta((a0 + a1) * 0.5, win_a) < half + ring_half


static func _spans_doorway(spec: TowerSpec, a0: float, a1: float) -> bool:
	var door_a := deg_to_rad(spec.door_azimuth)
	# Arc subtended by the flat door opening on the cylinder, plus a small margin so
	# the mesh never keeps a sliver the SDF has already carved away.
	var half := asin(clampf(spec.door_width * 0.5 / spec.radius_outer, -1.0, 1.0)) + 0.05
	var ring_half := absf(a1 - a0) * 0.5
	return _angular_delta((a0 + a1) * 0.5, door_a) < half + ring_half


## Smallest absolute angle between two azimuths, correct across the 0/TAU seam.
## Comparing raw intervals fails for a door at azimuth 0, whose span straddles the
## seam and so cannot be expressed as a single ascending range.
static func _angular_delta(x: float, y: float) -> float:
	return absf(fposmod(x - y + PI, TAU) - PI)


static func _add_wall_quad(
	st: SurfaceTool, face_material: PackedByteArray, spec: TowerSpec,
	a0: float, a1: float, y0: float, y1: float, mat_id: int
) -> void:
	var r := spec.radius_outer
	# Cylindrical UV: U wraps the circumference, V runs up the height.
	# Each axis uses the material's real-world physical dimension independently
	# (AR-TOWER-1). The horizontal repeat count is rounded to an integer so U
	# at a=TAU is a whole number and the wrap seam is invisible.
	# Bricks094: 1.80 m wide × 0.90 m tall → roundi(TAU*2.0/1.8)=7 repeats.
	var int_repeats := float(roundi(TAU * r / spec.brick_physical_size.x))
	var u0 := (a0 / TAU) * int_repeats
	var u1 := (a1 / TAU) * int_repeats
	var v0 := y0 / spec.brick_physical_size.y
	var v1 := y1 / spec.brick_physical_size.y
	var p00 := Vector3(r * sin(a0), y0, -r * cos(a0))
	var p01 := Vector3(r * sin(a0), y1, -r * cos(a0))
	var p10 := Vector3(r * sin(a1), y0, -r * cos(a1))
	var p11 := Vector3(r * sin(a1), y1, -r * cos(a1))
	# Outward radial normal taken analytically from the mid-azimuth, matching the
	# azimuth->position mapping above. Deriving it from the winding instead gives an
	# inward normal, because Godot winds front faces clockwise as seen from outside
	# and the right-hand rule then points the other way (SD-CONV-3).
	var am := (a0 + a1) * 0.5
	var n := Vector3(sin(am), 0.0, -cos(am)).normalized()
	_add_tri(st, face_material, p00, p10, p11,
		Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), n, mat_id)
	_add_tri(st, face_material, p00, p11, p01,
		Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1), n, mat_id)


static func _build_lip(st: SurfaceTool, face_material: PackedByteArray, spec: TowerSpec) -> void:
	var segs := spec.ring_segments
	var r0 := spec.radius_outer
	var r1 := spec.lip_radius()
	var y0 := spec.height
	var y1 := spec.height + spec.lip_thickness
	# Lip UV: U follows the same integer-rounded azimuth repeat count as the wall
	# so the brick pattern is consistent at the crown.  V treats the horizontal
	# annulus as a continuation of the wall face: inner edge (r0) picks up where
	# the wall top ends (v = height / brick_physical_size.y) and V increases
	# radially outward as if the brick surface wraps over the top (AR-TOWER-1).
	var int_repeats := float(roundi(TAU * r0 / spec.brick_physical_size.x))
	var v_inner := y0 / spec.brick_physical_size.y
	var v_outer := (y0 + spec.lip_overhang) / spec.brick_physical_size.y
	for ring in range(segs):
		var a0 := TAU * float(ring) / float(segs)
		var a1 := TAU * float(ring + 1) / float(segs)
		var p01 := Vector3(r0 * sin(a0), y1, -r0 * cos(a0))
		var p11 := Vector3(r0 * sin(a1), y1, -r0 * cos(a1))
		var q00 := Vector3(r1 * sin(a0), y1, -r1 * cos(a0))
		var q10 := Vector3(r1 * sin(a1), y1, -r1 * cos(a1))
		var u0 := (a0 / TAU) * int_repeats
		var u1 := (a1 / TAU) * int_repeats
		var n_top := ConvScript.UP
		_add_tri(st, face_material, q00, q10, p11,
			Vector2(u0, v_outer), Vector2(u1, v_outer), Vector2(u1, v_inner),
			n_top, MaterialRegistry.BRICK_LIP)
		_add_tri(st, face_material, q00, p11, p01,
			Vector2(u0, v_outer), Vector2(u1, v_inner), Vector2(u0, v_inner),
			n_top, MaterialRegistry.BRICK_LIP)


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
	tris: PackedVector3Array, face_material: PackedByteArray, spec: TowerSpec, sdf: TowerSdf
) -> void:
	var tri_idx := 0
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		# Negated because Godot winds front faces clockwise as seen from the front,
		# so the raw right-hand rule over the winding yields the inward direction.
		var n_geo := -(b - a).cross(c - a).normalized()
		var centroid := (a + b + c) / 3.0
		var axis_point := Vector3(0.0, centroid.y, 0.0)
		if face_material[tri_idx] == MaterialRegistry.BRICK_LIP:
			assert(n_geo.dot(ConvScript.UP) > 0.9)
		else:
			assert(n_geo.dot(centroid - axis_point) > 0.0)
		assert(sdf.signed_distance(centroid + n_geo * 0.01) > 0.0)
		assert(sdf.signed_distance(centroid - n_geo * 0.01) < 0.0)
		tri_idx += 1
