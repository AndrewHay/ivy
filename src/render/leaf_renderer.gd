class_name LeafRenderer
extends MultiMeshInstance3D

const LeafCupMeshScript = preload("res://src/render/leaf_cup_mesh.gd")

var _params: IvyParams
var _is_growing_buffer: bool = false


func setup(params: IvyParams, capacity: int, is_growing: bool) -> void:
	_params = params
	_is_growing_buffer = is_growing
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = capacity
	multimesh = mm
	multimesh.mesh = LeafCupMeshScript.build()
	material_override = load("res://src/render/materials/leaf_material.tres")
	(material_override as ShaderMaterial).set_shader_parameter(
		"weathered_tint",
		Vector3(params.leaf_weathered_tint.r, params.leaf_weathered_tint.g, params.leaf_weathered_tint.b))


## SD-LEAF-5 s_age: metres of stem grown past the node, smoothed over leaf_expand_distance.
static func s_age_for(stem_past_node: float, expand_distance: float) -> float:
	var a := maxf(0.0, stem_past_node)
	return smoothstep(0.0, 1.0, minf(1.0, a / expand_distance))


static func should_freeze(stem_past_node: float, expand_distance: float) -> bool:
	return stem_past_node >= expand_distance


func sync_static_from(plant: PlantData, from_index: int) -> void:
	assert(not _is_growing_buffer)
	multimesh.visible_instance_count = plant.leaf_frozen_count
	for i in range(from_index, plant.leaf_frozen_count):
		_write_instance(i, plant, i, 1.0)


func sync_growing_from(plant: PlantData, tip_shoot: Dictionary, frozen_count: int) -> void:
	assert(_is_growing_buffer)
	var total := plant.leaf_count()
	var growing := total - frozen_count
	multimesh.visible_instance_count = growing
	var slot := 0
	for i in range(frozen_count, total):
		var shoot: float = tip_shoot.get(plant.leaf_tip[i], plant.leaf_s_at_node[i] + _params.leaf_expand_distance)
		var past := shoot - plant.leaf_s_at_node[i]
		var age := s_age_for(past, _params.leaf_expand_distance)
		_write_instance(slot, plant, i, age)
		slot += 1


func _write_instance(slot: int, plant: PlantData, leaf_index: int, s_age: float) -> void:
	var base := leaf_index * 12
	var bx := Vector3(plant.leaf_xform[base], plant.leaf_xform[base + 1], plant.leaf_xform[base + 2])
	var by := Vector3(plant.leaf_xform[base + 4], plant.leaf_xform[base + 5], plant.leaf_xform[base + 6])
	var bz := Vector3(plant.leaf_xform[base + 8], plant.leaf_xform[base + 9], plant.leaf_xform[base + 10])
	var origin := Vector3(plant.leaf_xform[base + 3], plant.leaf_xform[base + 7], plant.leaf_xform[base + 11])
	var w := bx.length() * s_age
	var h := by.length() * s_age
	var xf := Transform3D(
		Basis(bx.normalized() * w, by.normalized() * h, bz.normalized()),
		origin)
	multimesh.set_instance_transform(slot, xf)
	var cbase := leaf_index * 4
	multimesh.set_instance_color(slot, Color(
		plant.leaf_color[cbase], plant.leaf_color[cbase + 1],
		plant.leaf_color[cbase + 2], plant.leaf_color[cbase + 3]))
	var ubase := leaf_index * 4
	multimesh.set_instance_custom_data(slot, Color(
		plant.leaf_custom[ubase], plant.leaf_custom[ubase + 1],
		plant.leaf_custom[ubase + 2], plant.leaf_custom[ubase + 3]))
