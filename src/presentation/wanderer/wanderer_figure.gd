class_name WandererFigure
extends RefCounted

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")

const COL_SHIRT := Color(0x5b / 255.0, 0x72 / 255.0, 0x90 / 255.0)
const COL_TEE := Color(0x2f / 255.0, 0x30 / 255.0, 0x34 / 255.0)
const COL_JEANS := Color(0x1f / 255.0, 0x23 / 255.0, 0x33 / 255.0)
const COL_HAIR := Color(0x3b / 255.0, 0x2a / 255.0, 0x20 / 255.0)
const COL_SKIN := Color(0xd9 / 255.0, 0xa6 / 255.0, 0x8c / 255.0)
const COL_SHOE := Color(0.08, 0.09, 0.12)
const COL_POCKET := Color(0x4d / 255.0, 0x62 / 255.0, 0x7e / 255.0)

const FACE_TEX := "res://assets/wanderer/figure_face.png"


static func build(params: WandererParams) -> Node3D:
	var root := Node3D.new()
	root.name = "WandererFigure"
	var mat_shirt := _mat(COL_SHIRT)
	var mat_tee := _mat(COL_TEE)
	var mat_jeans := _mat(COL_JEANS)
	var mat_skin := _mat(COL_SKIN)
	var mat_hair := _mat(COL_HAIR)
	var mat_shoe := _mat(COL_SHOE)
	var mat_pocket := _mat(COL_POCKET)

	var leg_l := _limb_pivot("LegL", Vector3(0.20, 0.84, 0.22), Vector3(-0.12, 0.86, 0.0), mat_jeans)
	var leg_r := _limb_pivot("LegR", Vector3(0.20, 0.84, 0.22), Vector3(0.12, 0.86, 0.0), mat_jeans)
	_add_child_box(leg_l.get_node("LimbMesh"), "Shoe", Vector3(0.22, 0.10, 0.28), Vector3(0.0, -0.37, 0.04), mat_shoe)
	_add_child_box(leg_r.get_node("LimbMesh"), "Shoe", Vector3(0.22, 0.10, 0.28), Vector3(0.0, -0.37, 0.04), mat_shoe)

	var torso := _box("Torso", Vector3(0.46, 0.65, 0.26), Vector3(0.0, 1.275, 0.0), mat_shirt)
	_add_child_box(torso, "TeeStrip", Vector3(0.08, 0.48, 0.02), Vector3(0.0, 0.04, 0.14), mat_tee)
	_add_child_box(torso, "PocketL", Vector3(0.12, 0.06, 0.02), Vector3(-0.14, 0.14, 0.14), mat_pocket)
	_add_child_box(torso, "PocketR", Vector3(0.12, 0.06, 0.02), Vector3(0.14, 0.14, 0.14), mat_pocket)

	var arm_l := _limb_pivot("ArmL", Vector3(0.12, 0.56, 0.12), Vector3(-0.29, 1.56, 0.0), mat_shirt)
	var arm_r := _limb_pivot("ArmR", Vector3(0.12, 0.56, 0.12), Vector3(0.29, 1.56, 0.0), mat_shirt)
	_add_child_box(arm_l.get_node("LimbMesh"), "HandL", Vector3(0.10, 0.10, 0.10), Vector3(0.0, -0.33, 0.0), mat_skin)
	_add_child_box(arm_r.get_node("LimbMesh"), "HandR", Vector3(0.10, 0.10, 0.10), Vector3(0.0, -0.33, 0.0), mat_skin)

	var head := _box("Head", Vector3(0.20, 0.25, 0.22), Vector3(0.0, 1.875, 0.0), mat_skin)
	_add_child_box(head, "HairCap", Vector3(0.24, 0.06, 0.24), Vector3(0.0, 0.13, 0.0), mat_hair)
	_add_child_box(head, "HairBack", Vector3(0.22, 0.14, 0.04), Vector3(0.0, 0.05, -0.13), mat_hair)
	var face := _face_plate(head)

	root.add_child(leg_l)
	root.add_child(leg_r)
	root.add_child(torso)
	root.add_child(arm_l)
	root.add_child(arm_r)
	root.add_child(head)
	return root


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


static func _limb_pivot(n: String, size: Vector3, pivot_pos: Vector3, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = n
	pivot.position = pivot_pos
	var mesh := _box("LimbMesh", size, Vector3(0.0, -size.y * 0.5, 0.0), mat)
	pivot.add_child(mesh)
	return pivot


static func _add_child_box(parent: Node3D, n: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	parent.add_child(_box(n, size, pos, mat))


static func _box(n: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


static func _face_plate(head: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "FacePlate"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.14, 0.18)
	mi.mesh = qm
	mi.position = Vector3(0.0, 0.02, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var tex: Texture2D = null
	if ResourceLoader.exists(FACE_TEX):
		tex = load(FACE_TEX) as Texture2D
	if tex == null:
		var path := ProjectSettings.globalize_path(FACE_TEX)
		var img := Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		mat.albedo_texture = tex
	else:
		mat.albedo_color = COL_SKIN
	mi.material_override = mat
	head.add_child(mi)
	return mi


static func limb_mesh_top_y(root: Node3D, limb_name: String) -> float:
	var mi := _limb_mesh(root, limb_name)
	if mi == null:
		return 0.0
	var aabb := mi.get_aabb()
	var top_local := Vector3(0.0, aabb.position.y + aabb.size.y, 0.0)
	return mi.to_global(top_local).y


static func limb_pivot_global(root: Node3D, limb_name: String) -> Vector3:
	var pivot := root.get_node_or_null(limb_name) as Node3D
	if pivot == null:
		return Vector3.ZERO
	return pivot.global_position


static func foot_global(root: Node3D, limb_name: String) -> Vector3:
	var pivot := root.get_node_or_null(limb_name) as Node3D
	if pivot == null:
		return Vector3.ZERO
	var shoe := pivot.get_node_or_null("LimbMesh/Shoe") as MeshInstance3D
	if shoe == null:
		return pivot.global_position
	var aabb := shoe.get_aabb()
	var bot_local := Vector3(0.0, aabb.position.y, 0.04)
	return shoe.to_global(bot_local)


static func _limb_mesh(root: Node3D, limb_name: String) -> MeshInstance3D:
	var pivot := root.get_node_or_null(limb_name) as Node3D
	if pivot == null:
		return null
	return pivot.get_node_or_null("LimbMesh") as MeshInstance3D


static func pose(variant: int, params: WandererParams, phase: float, motion: float) -> Dictionary:
	var swing := params.leg_swing_deg * motion
	var arm := params.arm_swing_deg * motion
	var bob := params.bob_m * motion
	var roll := params.torso_roll_deg * motion
	var lean := params.torso_lean_deg * motion
	var s := sin(phase)
	var c := cos(phase)
	match variant:
		1:
			var tri := _triangle_ease(phase / TAU)
			s = sin(tri * TAU)
		2:
			roll *= 4.0
			swing *= 0.6
			bob *= 1.5
		3:
			arm *= 1.4
			bob = 0.0
	if motion < 1e-4:
		return {
			"leg_l_deg": 0.0,
			"leg_r_deg": 0.0,
			"arm_l_deg": 0.0,
			"arm_r_deg": 0.0,
			"bob_m": 0.0,
			"roll_deg": 0.0,
			"lean_deg": 0.0,
		}
	return {
		"leg_l_deg": swing * s,
		"leg_r_deg": -swing * s,
		"arm_l_deg": -arm * s,
		"arm_r_deg": arm * s,
		"bob_m": bob * (0.5 + 0.5 * cos(2.0 * phase)),
		"roll_deg": roll * s,
		"lean_deg": lean * motion,
	}


static func _triangle_ease(t: float) -> float:
	t = fposmod(t, 1.0)
	return 1.0 - absf(2.0 * t - 1.0)


static func apply_pose(root: Node3D, pose: Dictionary, params: WandererParams) -> void:
	root.position.y = float(pose.get("bob_m", 0.0))
	root.rotation.z = deg_to_rad(float(pose.get("roll_deg", 0.0)))
	root.rotation.x = deg_to_rad(float(pose.get("lean_deg", 0.0)))
	var leg_l := root.get_node_or_null("LegL") as Node3D
	var leg_r := root.get_node_or_null("LegR") as Node3D
	var arm_l := root.get_node_or_null("ArmL") as Node3D
	var arm_r := root.get_node_or_null("ArmR") as Node3D
	if leg_l != null:
		leg_l.rotation.x = deg_to_rad(float(pose.get("leg_l_deg", 0.0)))
	if leg_r != null:
		leg_r.rotation.x = deg_to_rad(float(pose.get("leg_r_deg", 0.0)))
	if arm_l != null:
		arm_l.rotation.x = deg_to_rad(float(pose.get("arm_l_deg", 0.0)))
	if arm_r != null:
		arm_r.rotation.x = deg_to_rad(float(pose.get("arm_r_deg", 0.0)))


static func measured_height(root: Node3D) -> float:
	var aabb := _combined_aabb(root)
	return aabb.size.y


static func count_mesh_instances(root: Node3D) -> int:
	return _count_mesh_rec(root)


static func _count_mesh_rec(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D:
		n += 1
	for c in node.get_children():
		n += _count_mesh_rec(c)
	return n


static func count_triangles(root: Node3D) -> int:
	return _acc_tris(root)


static func _acc_tris(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			total += _mesh_tris(mi.mesh)
	for c in node.get_children():
		total += _acc_tris(c)
	return total


static func _mesh_tris(mesh: Mesh) -> int:
	var tris := 0
	for i in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
			tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			var prim: int = mesh.surface_get_primitive_type(i)
			var vcount := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if prim == Mesh.PRIMITIVE_TRIANGLES:
				tris += vcount / 3
	return tris


static func face_forward_dot(root: Node3D) -> float:
	var head := root.get_node_or_null("Head")
	if head == null:
		return 0.0
	var face := head.get_node_or_null("FacePlate") as MeshInstance3D
	if face == null:
		return 0.0
	var n := face.global_transform.basis.z
	var fwd := root.global_transform.basis.z
	return n.normalized().dot(fwd.normalized())


static func _combined_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for c in root.get_children():
		var pair := _merge_mesh_aabb(c, root, merged, first)
		merged = pair[0]
		first = pair[1]
	return merged


static func _merge_mesh_aabb(node: Node, root: Node3D, merged: AABB, first: bool) -> Array:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var local := mi.get_aabb()
		var xf := mi.global_transform
		for p in _aabb_corners(local):
			var wp := root.to_local(xf * p)
			if first:
				merged = AABB(wp, Vector3.ZERO)
				first = false
			else:
				merged = merged.expand(wp)
	for c in node.get_children():
		var pair := _merge_mesh_aabb(c, root, merged, first)
		merged = pair[0]
		first = pair[1]
	return [merged, first]


static func _aabb_corners(local: AABB) -> Array[Vector3]:
	return [
		local.position,
		local.position + Vector3(local.size.x, 0, 0),
		local.position + Vector3(0, local.size.y, 0),
		local.position + Vector3(0, 0, local.size.z),
		local.position + local.size,
	]
