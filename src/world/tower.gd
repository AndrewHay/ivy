class_name Tower
extends StaticBody3D

const TowerBuilderScript = preload("res://src/world/tower_builder.gd")

@export var spec: TowerSpec

var face_material: PackedByteArray = PackedByteArray()


func build_from_spec(tower_spec: TowerSpec, dev_build: bool = true) -> void:
	spec = tower_spec
	collision_layer = 1
	collision_mask = 0
	var built := TowerBuilderScript.build(spec, dev_build)
	face_material = built.face_material
	var mesh_node := get_node_or_null("TowerMesh") as MeshInstance3D
	if mesh_node == null:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "TowerMesh"
		add_child(mesh_node)
	mesh_node.mesh = built.mesh
	var mat := load("res://assets/materials/brick/Bricks094/Bricks094_2K-JPG.tres") as Material
	if mat:
		mesh_node.material_override = mat
	var col := get_node_or_null("TowerCollision") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "TowerCollision"
		add_child(col)
	col.shape = built.shape
