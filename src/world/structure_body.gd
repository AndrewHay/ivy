class_name StructureBody
extends StaticBody3D

## Collision proxy (+ optional hero visual) for an imported M2.6 structure (SD-MESH-12).

var face_material: PackedByteArray = PackedByteArray()


func build(collision_glb: String, hero_glb: String = "") -> void:
	collision_layer = 1
	collision_mask = 0
	_clear_generated()
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
		face_material.append(MaterialRegistry.BRICK_WALL)


func _add_visual_from_glb(path: String) -> void:
	var root := _load_gltf_scene(path)
	if root == null:
		return
	root.name = "StructureVisual"
	add_child(root)
	_strip_physics(root)


func _collect_mesh_pieces(
	node: Node,
	parent_xform: Transform3D,
	out: Array[Dictionary]
) -> void:
	var xform: Transform3D = parent_xform * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append({"mesh": (node as MeshInstance3D).mesh, "transform": xform})
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
