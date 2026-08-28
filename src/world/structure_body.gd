class_name StructureBody
extends StaticBody3D

## Collision proxy (+ optional hero visual) for an imported M2.6 structure (SD-MESH-12).

const _BRICK_MAT := preload("res://assets/materials/brick/Bricks094/Bricks094_2K-JPG.tres")

var face_material: PackedByteArray = PackedByteArray()


func build(collision_glb: String, hero_glb: String = "") -> void:
	collision_layer = 1
	collision_mask = 0
	_clear_generated()
	face_material = PackedByteArray()
	if not collision_glb.is_empty():
		_add_collision_from_glb(collision_glb)
	if not hero_glb.is_empty():
		_add_visual_from_glb(hero_glb)


func bounds_aabb() -> AABB:
	var merged := AABB()
	var first := true
	for child in get_children():
		if child is CollisionShape3D:
			var shape_aabb := _shape_aabb(child as CollisionShape3D)
			if shape_aabb.size.length_squared() < 1e-8:
				continue
			if first:
				merged = shape_aabb
				first = false
			else:
				merged = merged.merge(shape_aabb)
	return merged


func _clear_generated() -> void:
	for child in get_children():
		child.queue_free()


func _load_gltf_scene(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("StructureBody: failed to load %s (%s)" % [path, err])
		return null
	var scene := doc.generate_scene(state) as Node3D
	if scene == null:
		push_error("StructureBody: no scene root in %s" % path)
	return scene


func _add_collision_from_glb(path: String) -> void:
	var root := _load_gltf_scene(path)
	if root == null:
		return
	add_child(root)
	var pieces: Array[Dictionary] = []
	_collect_mesh_pieces(root, Transform3D.IDENTITY, pieces)
	root.free()
	var idx := 0
	for piece in pieces:
		var col := CollisionShape3D.new()
		col.name = "StructureCol_%d" % idx
		col.shape = piece.mesh.create_trimesh_shape()
		add_child(col)
		col.transform = piece.transform
		idx += 1
		face_material.append(_material_for_object_name(piece.name))


static func _material_for_object_name(name: String) -> int:
	if "Interior_" in name:
		return MaterialRegistry.INTERIOR
	if "_Panel_" in name:
		if "_door" in name:
			return MaterialRegistry.WOOD
		if "_win" in name or "_wide_win" in name or "_thin_win" in name:
			return MaterialRegistry.GLASS
		return MaterialRegistry.BRICK_WALL
	if "_Seal_" in name:
		if "_glass" in name:
			return MaterialRegistry.GLASS
		if "_frame" in name:
			return MaterialRegistry.OPENING_REVEAL
		if "_door" in name:
			return MaterialRegistry.WOOD
	return MaterialRegistry.BRICK_WALL


func _add_visual_from_glb(path: String) -> void:
	var root := _load_gltf_scene(path)
	if root == null:
		return
	root.name = "StructureVisual"
	add_child(root)
	_strip_physics(root)
	_apply_hero_materials(root)


static func _apply_hero_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var name_lower := node.name.to_lower()
		if "glass" in name_lower:
			mi.material_override = _glass_material()
		elif "_door" in name_lower or "door_2" in name_lower:
			mi.material_override = _wood_material()
		elif "reveal" in name_lower and "floor" in name_lower:
			mi.material_override = _interior_floor_material()
		elif "reveal" in name_lower:
			mi.material_override = _interior_wall_material()
		elif mi.material_override == null:
			mi.material_override = _BRICK_MAT
	for child in node.get_children():
		_apply_hero_materials(child)


static func _glass_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.72, 0.82, 0.88, 0.82)
	m.roughness = 0.06
	m.metallic = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _wood_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.28, 0.18, 1.0)
	m.roughness = 0.75
	return m


static func _interior_wall_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.16, 0.14, 1.0)
	m.roughness = 0.92
	return m


static func _interior_floor_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.11, 0.10, 0.09, 1.0)
	m.roughness = 0.95
	return m


func _collect_mesh_pieces(
	node: Node,
	parent_xform: Transform3D,
	out: Array[Dictionary]
) -> void:
	var xform: Transform3D = parent_xform * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append({
			"name": node.name,
			"mesh": (node as MeshInstance3D).mesh,
			"transform": xform,
		})
	for child in node.get_children():
		_collect_mesh_pieces(child, xform, out)


func _strip_physics(node: Node) -> void:
	if node is PhysicsBody3D or node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		_strip_physics(child)


func _shape_aabb(col: CollisionShape3D) -> AABB:
	if col.shape == null:
		return AABB()
	return col.transform * col.shape.get_aabb()
