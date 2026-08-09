class_name LeafRenderer
extends MultiMeshInstance3D

var _params: IvyParams
var _last_count: int = 0


func setup(params: IvyParams) -> void:
	_params = params
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = params.leaf_cap
	multimesh = mm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	multimesh.mesh = mesh
	material_override = load("res://src/render/materials/leaf_material.tres")


func sync_from(plant: PlantData) -> void:
	var count := plant.leaf_count()
	multimesh.visible_instance_count = count
	for i in range(_last_count, count):
		var xf := Transform3D()
		var base := i * 12
		xf.basis = Basis(
			Vector3(plant.leaf_xform[base], plant.leaf_xform[base + 1], plant.leaf_xform[base + 2]),
			Vector3(plant.leaf_xform[base + 4], plant.leaf_xform[base + 5], plant.leaf_xform[base + 6]),
			Vector3(plant.leaf_xform[base + 8], plant.leaf_xform[base + 9], plant.leaf_xform[base + 10])
		)
		xf.origin = Vector3(plant.leaf_xform[base + 3], plant.leaf_xform[base + 7], plant.leaf_xform[base + 11])
		multimesh.set_instance_transform(i, xf)
		var cbase := i * 4
		multimesh.set_instance_color(i, Color(plant.leaf_color[cbase], plant.leaf_color[cbase + 1], plant.leaf_color[cbase + 2], plant.leaf_color[cbase + 3]))
		var ubase := i * 4
		multimesh.set_instance_custom_data(i, Color(plant.leaf_custom[ubase], plant.leaf_custom[ubase + 1], plant.leaf_custom[ubase + 2], plant.leaf_custom[ubase + 3]))
	_last_count = count
