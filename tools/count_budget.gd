## Budget verification: count MI3D surfaces + tri + MultiMesh surfaces.
extends SceneTree

const VillageBackdropScene = preload("res://src/world/village_backdrop.tscn")

var _backdrop: Node3D


func _initialize() -> void:
	_backdrop = VillageBackdropScene.instantiate() as Node3D
	get_root().add_child(_backdrop)


func _process(_delta: float) -> bool:
	var backdrop := _backdrop
	var mi3d := [0]   # [surfaces, tris]
	var mi3d_tris := [0]
	var mm_surfs := [0]
	var mm_tris := [0]
	_count_mi3d(backdrop, mi3d, mi3d_tris)
	_count_mm(backdrop, mm_surfs, mm_tris)
	print("MI3D surfaces: ", mi3d[0])
	print("MultiMesh surfaces: ", mm_surfs[0])
	print("Total draw surface count: ", mi3d[0] + mm_surfs[0])
	print("MI3D triangles: ", mi3d_tris[0])
	print("MultiMesh triangles (×1, not ×instances): ", mm_tris[0])
	print("Total triangles: ", mi3d_tris[0] + mm_tris[0])
	return true

func _count_mi3d(node: Node, surfs: Array, tris: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			surfs[0] += mi.mesh.get_surface_count()
			for s in range(mi.mesh.get_surface_count()):
				var a := mi.mesh.surface_get_arrays(s)
				if a and a[Mesh.ARRAY_INDEX]:
					tris[0] += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				elif a and a[Mesh.ARRAY_VERTEX]:
					tris[0] += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for child in node.get_children():
		_count_mi3d(child, surfs, tris)

func _count_mm(node: Node, surfs: Array, tris: Array) -> void:
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh and mmi.multimesh.mesh:
			surfs[0] += mmi.multimesh.mesh.get_surface_count()
			for s in range(mmi.multimesh.mesh.get_surface_count()):
				var a := mmi.multimesh.mesh.surface_get_arrays(s)
				if a and a[Mesh.ARRAY_INDEX]:
					tris[0] += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				elif a and a[Mesh.ARRAY_VERTEX]:
					tris[0] += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for child in node.get_children():
		_count_mm(child, surfs, tris)
