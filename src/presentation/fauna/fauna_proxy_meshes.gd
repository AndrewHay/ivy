class_name FaunaProxyMeshes
extends RefCounted

## Low-poly ambient insect meshes sized against ivy leaf width (presentation only).


static func make_mesh_instance(species: FaunaConstants.Species) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match species:
		FaunaConstants.Species.BEE:
			mi.mesh = _build_bee_mesh()
			mi.set_surface_override_material(0, _mat_unshaded(Color(0.95, 0.88, 0.25)))
			mi.set_surface_override_material(1, _mat_unshaded(Color(0.12, 0.10, 0.08)))
			mi.set_surface_override_material(2, _mat_wing())
			var s := FaunaConstants.BEE_VISUAL_SCALE
			mi.scale = Vector3(s, s, s)
		FaunaConstants.Species.BUTTERFLY:
			mi.mesh = _build_butterfly_mesh()
			mi.set_surface_override_material(0, _mat_unshaded(Color(0.92, 0.48, 0.14)))
			mi.set_surface_override_material(1, _mat_unshaded(Color(0.22, 0.14, 0.08)))
			mi.set_surface_override_material(2, _mat_unshaded(Color(0.98, 0.94, 0.82)))
		FaunaConstants.Species.LADYBIRD:
			mi.mesh = _build_ladybird_mesh()
			mi.set_surface_override_material(0, _mat_unshaded(Color(0.85, 0.15, 0.12)))
	return mi


## Returns `{ "root": Node3D, "wing_left": MeshInstance3D?, "wing_right": MeshInstance3D? }`.
static func make_visual_rig(species: FaunaConstants.Species) -> Dictionary:
	match species:
		FaunaConstants.Species.BEE:
			var mi := MeshInstance3D.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.mesh = _build_bee_mesh()
			mi.set_surface_override_material(0, _mat_unshaded(Color(0.95, 0.88, 0.25)))
			mi.set_surface_override_material(1, _mat_unshaded(Color(0.12, 0.10, 0.08)))
			mi.set_surface_override_material(2, _mat_wing())
			var s := FaunaConstants.BEE_VISUAL_SCALE
			mi.scale = Vector3(s, s, s)
			return {"root": mi}
		FaunaConstants.Species.BUTTERFLY:
			return _make_butterfly_rig()
		FaunaConstants.Species.LADYBIRD:
			var mi := MeshInstance3D.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.mesh = _build_ladybird_mesh()
			mi.set_surface_override_material(0, _mat_unshaded(Color(0.85, 0.15, 0.12)))
			return {"root": mi}
	return {"root": Node3D.new()}


static func _make_butterfly_rig() -> Dictionary:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.mesh = _build_butterfly_body_mesh()
	body.set_surface_override_material(0, _mat_unshaded(Color(0.22, 0.14, 0.08)))
	var wing_l := _make_butterfly_wing_instance(true)
	var wing_r := _make_butterfly_wing_instance(false)
	root.add_child(body)
	root.add_child(wing_l)
	root.add_child(wing_r)
	return {"root": root, "wing_left": wing_l, "wing_right": wing_r}


static func _make_butterfly_wing_instance(left: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.mesh = _build_butterfly_wing_mesh(left)
	mi.set_surface_override_material(0, _mat_unshaded(Color(0.92, 0.48, 0.14)))
	mi.set_surface_override_material(1, _mat_unshaded(Color(0.98, 0.94, 0.82)))
	if left:
		mi.scale.x = -1.0
	return mi


static func _build_bee_mesh() -> ArrayMesh:
	var l := FaunaConstants.bee_body_length_m()
	var st_yellow := _st_begin()
	var st_black := _st_begin()
	var st_wing := _st_begin()
	_add_ellipsoid(st_yellow, Vector3(0, 0, -l * 0.38), Vector3(l * 0.11, l * 0.10, l * 0.09))
	_add_ellipsoid(st_black, Vector3(0, 0, -l * 0.14), Vector3(l * 0.13, l * 0.12, l * 0.11))
	_add_ellipsoid(st_yellow, Vector3(0, 0, l * 0.08), Vector3(l * 0.14, l * 0.13, l * 0.16))
	_add_ellipsoid(st_black, Vector3(0, 0, l * 0.22), Vector3(l * 0.12, l * 0.11, l * 0.10))
	_add_ellipsoid(st_yellow, Vector3(0, 0, l * 0.34), Vector3(l * 0.10, l * 0.09, l * 0.08))
	_add_capsule(st_yellow, Vector3(-l * 0.05, l * 0.06, -l * 0.42), Vector3(-l * 0.05, l * 0.10, -l * 0.48), l * 0.012)
	_add_capsule(st_yellow, Vector3(l * 0.05, l * 0.06, -l * 0.42), Vector3(l * 0.05, l * 0.10, -l * 0.48), l * 0.012)
	var wing_w := l * 0.42
	var wing_h := l * 0.28
	var wing_y := l * 0.02
	var wing_z := -l * 0.12
	var wt := FaunaConstants.bee_wing_half_thickness_m()
	_add_thick_quad(st_wing, Vector3(-wing_w, wing_y, wing_z), Vector3(0, wing_y, wing_z - wing_h * 0.2),
			Vector3(0, wing_y + l * 0.04, wing_z + wing_h * 0.5), Vector3(-wing_w * 0.2, wing_y + l * 0.03, wing_z + wing_h), wt)
	_add_thick_quad(st_wing, Vector3(wing_w, wing_y, wing_z), Vector3(0, wing_y, wing_z - wing_h * 0.2),
			Vector3(0, wing_y + l * 0.04, wing_z + wing_h * 0.5), Vector3(wing_w * 0.2, wing_y + l * 0.03, wing_z + wing_h), wt)
	return _merge_tools([st_yellow, st_black, st_wing])


static func _build_butterfly_mesh() -> ArrayMesh:
	var body := _build_butterfly_body_mesh()
	var wing := _build_butterfly_wing_mesh(false)
	var mesh := ArrayMesh.new()
	for i in range(body.get_surface_count()):
		mesh.add_surface_from_arrays(body.surface_get_primitive_type(i), body.surface_get_arrays(i))
	for i in range(wing.get_surface_count()):
		mesh.add_surface_from_arrays(wing.surface_get_primitive_type(i), wing.surface_get_arrays(i))
	return mesh


static func _build_butterfly_body_mesh() -> ArrayMesh:
	var span := FaunaConstants.butterfly_wingspan_m()
	var st_dark := _st_begin()
	var body_l := span * 0.22
	_add_ellipsoid(st_dark, Vector3(0, 0, 0), Vector3(span * 0.025, span * 0.025, body_l * 0.5))
	_add_capsule(st_dark, Vector3(-span * 0.02, span * 0.04, body_l * 0.45), Vector3(-span * 0.03, span * 0.08, body_l * 0.55), span * 0.008)
	_add_capsule(st_dark, Vector3(span * 0.02, span * 0.04, body_l * 0.45), Vector3(span * 0.03, span * 0.08, body_l * 0.55), span * 0.008)
	st_dark.generate_normals()
	return st_dark.commit()


static func _build_butterfly_wing_mesh(_left: bool) -> ArrayMesh:
	var span := FaunaConstants.butterfly_wingspan_m()
	var half := span * 0.5
	var st_orange := _st_begin()
	var st_cream := _st_begin()
	var body_l := span * 0.22
	var root := Vector3(0, 0, -body_l * 0.15)
	var wt := FaunaConstants.butterfly_wing_half_thickness_m()
	_add_wing(st_orange, st_cream, root, half, span * 0.38, false, wt)
	return _merge_tools([st_orange, st_cream])


static func _build_ladybird_mesh() -> ArrayMesh:
	var r := FaunaConstants.LEAF_REFERENCE_WIDTH_M * 0.08
	var st := _st_begin()
	_add_ellipsoid(st, Vector3.ZERO, Vector3(r, r * 0.6, r * 1.1))
	st.generate_normals()
	return st.commit()


static func _add_wing(
		st_orange: SurfaceTool, st_cream: SurfaceTool,
		root: Vector3, half_span: float, wing_depth: float, left: bool, half_thick: float) -> void:
	var sx := -1.0 if left else 1.0
	var camber := wing_depth * 0.12
	var tip := root + Vector3(sx * half_span, camber, -wing_depth * 0.35)
	var front := root + Vector3(sx * half_span * 0.55, camber * 0.5, wing_depth * 0.45)
	var back := root + Vector3(sx * half_span * 0.35, 0, -wing_depth * 0.55)
	var spot := root + Vector3(sx * half_span * 0.72, camber * 0.65, wing_depth * 0.05)
	var root_top := root + Vector3(0, camber * 0.15, 0)
	_add_thick_tri(st_orange, root_top, front, tip, half_thick)
	_add_thick_tri(st_orange, root_top, back, front, half_thick)
	_add_thick_tri(st_cream, front, spot, tip, half_thick * 0.85)


static func _merge_tools(tools: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for st: SurfaceTool in tools:
		st.generate_normals()
		var part: ArrayMesh = st.commit()
		for i in range(part.get_surface_count()):
			mesh.add_surface_from_arrays(
				part.surface_get_primitive_type(i),
				part.surface_get_arrays(i))
	return mesh


static func _st_begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() > 1e-10:
		n = n.normalized()
	else:
		n = Vector3.UP
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_tri(st, a, b, c)
	_add_tri(st, a, c, d)


static func _add_thick_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, half_thick: float) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var off := n * half_thick
	_add_prism(st, a - off, b - off, c - off, a + off, b + off, c + off)


static func _add_thick_quad(
		st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, half_thick: float) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-12:
		n = Vector3.UP
	else:
		n = n.normalized()
	var off := n * half_thick
	_add_prism_quad(st, a - off, b - off, c - off, d - off, a + off, b + off, c + off, d + off)


static func _add_prism(st: SurfaceTool, a0: Vector3, b0: Vector3, c0: Vector3, a1: Vector3, b1: Vector3, c1: Vector3) -> void:
	_add_tri(st, a0, b0, c0)
	_add_tri(st, a1, c1, b1)
	_add_quad(st, a0, b0, b1, a1)
	_add_quad(st, b0, c0, c1, b1)
	_add_quad(st, c0, a0, a1, c1)


static func _add_prism_quad(
		st: SurfaceTool,
		a0: Vector3, b0: Vector3, c0: Vector3, d0: Vector3,
		a1: Vector3, b1: Vector3, c1: Vector3, d1: Vector3) -> void:
	_add_tri(st, a0, b0, c0)
	_add_tri(st, a0, c0, d0)
	_add_tri(st, a1, c1, b1)
	_add_tri(st, a1, d1, c1)
	_add_quad(st, a0, b0, b1, a1)
	_add_quad(st, b0, c0, c1, b1)
	_add_quad(st, c0, d0, d1, c1)
	_add_quad(st, d0, a0, a1, d1)


static func _add_capsule(st: SurfaceTool, a: Vector3, b: Vector3, radius: float) -> void:
	var dir := (b - a).normalized()
	var perp := dir.cross(Vector3.UP)
	if perp.length_squared() < 1e-6:
		perp = dir.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var side := dir.cross(perp).normalized()
	_add_tri(st, a + perp * radius, a - perp * radius, b + perp * radius)
	_add_tri(st, a - perp * radius, b - perp * radius, b + perp * radius)
	_add_tri(st, a + side * radius, a + perp * radius, b + side * radius)
	_add_tri(st, a + perp * radius, b + perp * radius, b + side * radius)


static func _add_ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, segments: int = 6) -> void:
	var rings := maxi(segments / 2, 3)
	var sectors := segments
	var prev: Array[Vector3] = []
	for i in range(rings + 1):
		var v := float(i) / float(rings)
		var phi := lerpf(-PI * 0.5, PI * 0.5, v)
		var ring: Array[Vector3] = []
		for j in range(sectors):
			var u := float(j) / float(sectors)
			var theta := u * TAU
			var p := center + Vector3(
				cos(phi) * cos(theta) * radii.x,
				sin(phi) * radii.y,
				cos(phi) * sin(theta) * radii.z)
			ring.append(p)
		if i > 0:
			for j in range(sectors):
				var jn := (j + 1) % sectors
				_add_tri(st, prev[j], ring[j], ring[jn])
				_add_tri(st, prev[j], ring[jn], prev[jn])
		prev = ring


static func _mat_unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _mat_wing() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.90, 0.82, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
