class_name OverhangWall
extends StaticBody3D

## StaticBody3D node for the procedural eave-wall fixture (ivy-9us).
## Mirrors the Wall node pattern: build_from_spec() creates MeshInstance3D +
## CollisionShape3D children and stores face_material for SurfaceQuery setup.

const OverhangBuilderScript = preload("res://src/world/overhang_builder.gd")

## spec: OverhangSpec (untyped to avoid class_name resolution order at compile time)
var spec = null
var face_material: PackedByteArray = PackedByteArray()


## overhang_spec: OverhangSpec
func build_from_spec(overhang_spec, dev_build: bool = true) -> void:
	spec = overhang_spec
	collision_layer = 1
	collision_mask = 0
	var built := OverhangBuilderScript.build(spec, dev_build)
	face_material = built.face_material
	var mesh_node := get_node_or_null("OverhangMesh") as MeshInstance3D
	if mesh_node == null:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "OverhangMesh"
		add_child(mesh_node)
	mesh_node.mesh = built.mesh
	var mat := load("res://assets/materials/brick/Bricks094/Bricks094_2K-JPG.tres") as Material
	if mat:
		mesh_node.material_override = mat
	var col := get_node_or_null("OverhangCollision") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "OverhangCollision"
		add_child(col)
	col.shape = built.shape
