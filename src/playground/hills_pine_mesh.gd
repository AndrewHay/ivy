class_name HillsPineMesh
extends RefCounted

## Pine_2 MultiMesh prep: fog off + instance-color tint, leaf alpha scissor (FarTreeline parity).


static func prepare(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var dup := mesh.duplicate() as Mesh
	if dup == null:
		return null
	for si in range(dup.get_surface_count()):
		var src := dup.surface_get_material(si)
		if src is StandardMaterial3D:
			var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.disable_fog = true
			mat.vertex_color_use_as_albedo = false
			if si == 1:
				mat.alpha_scissor_threshold = minf(mat.alpha_scissor_threshold, 0.1)
			dup.surface_set_material(si, mat)
	return dup


static func leaf_material_luminance(mesh: Mesh) -> float:
	if mesh == null or mesh.get_surface_count() < 2:
		return 0.0
	var mat := mesh.surface_get_material(1) as StandardMaterial3D
	if mat == null:
		return 0.0
	var c := mat.albedo_color
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114
