class_name Wall
extends StaticBody3D

const WallBuilderScript = preload("res://src/world/wall_builder.gd")

@export var spec: WallSpec
var face_material: PackedByteArray = PackedByteArray()


func build_from_spec(wall_spec: WallSpec, dev_build: bool = true) -> void:
	spec = wall_spec
	collision_layer = 1
	collision_mask = 0
	var built := WallBuilderScript.build(spec, dev_build)
	face_material = built.face_material
	var mesh_node := get_node_or_null("WallMesh") as MeshInstance3D
	if mesh_node == null:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "WallMesh"
		add_child(mesh_node)
	mesh_node.mesh = built.mesh
	var mat := load("res://assets/materials/brick/Bricks094/Bricks094_2K-JPG.tres") as Material
	if mat:
		mesh_node.material_override = mat
	var col := get_node_or_null("WallCollision") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "WallCollision"
		add_child(col)
	col.shape = built.shape
