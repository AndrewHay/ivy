## Logs hill terrain + forest budget for generated seed 7 (builders only — fast).
extends Node

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")


func _ready() -> void:
	var seed := 7
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
	var layout := VillageLayout.generate(seed)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var mesh := HillsHeightfield.build_mesh(layout, params)
	var tris := 0
	for si in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		tris += verts.size() / 3
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var backdrop := ForestPlacement.forest_tree_xz(layout, ForestParams.production())
	var xforms := HillsForestPlacement.hill_forest_transforms(layout, params, t_seed, backdrop)
	print("=== hills budget seed=%d ===" % seed)
	print("HillTerrain triangles (builder): %d" % tris)
	print("HillForest instance_count (builder): %d" % xforms.size())
	print("Hill terrain MeshInstance3D: 1")
	print("Hill forest MultiMeshInstance3D: 1")
	print("New draw surfaces (incremental): +2")
	get_tree().quit(0)
