extends GutTest

const HillsPineMesh = preload("res://src/playground/hills_pine_mesh.gd")
const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsFogTint = preload("res://src/playground/hills_fog_tint.gd")
const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

const _PINE := "res://assets/backdrop/pieces/Pine_2.gltf"


static func _raw_pine_mesh() -> Mesh:
	var ps := load(_PINE) as PackedScene
	var inst := ps.instantiate()
	var mesh: Mesh = null
	for c in inst.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			mesh = (c as MeshInstance3D).mesh
			break
	inst.queue_free()
	return mesh


func test_prepare_pine_has_two_surfaces_fog_off_leaves() -> void:
	var raw := _raw_pine_mesh()
	assert_not_null(raw)
	var prep := HillsPineMesh.prepare(raw)
	assert_gte(prep.get_surface_count(), 2)
	var leaf := prep.surface_get_material(1) as StandardMaterial3D
	assert_not_null(leaf)
	assert_true(leaf.disable_fog)
	assert_lte(leaf.alpha_scissor_threshold, 0.11)
	assert_gt(HillsPineMesh.leaf_material_luminance(prep), 0.12)


func test_hill_forest_scale_and_tint_floor() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var backdrop := VillageScatterPositions.forest_tree_xz(layout)
	var xforms := HillsForestPlacement.hill_forest_transforms(layout, params, t_seed, backdrop)
	assert_gte(xforms.size(), 50)
	var min_scale := 99.0
	var max_scale := 0.0
	var min_lum := 99.0
	for t: Transform3D in xforms:
		var s := t.basis.get_scale().x
		min_scale = minf(min_scale, s)
		max_scale = maxf(max_scale, s)
		var lum := HillsFogTint.luminance(
			HillsFogTint.tree_instance_color(t.origin, params, layout, 0.0, 95.0, Vector3.ZERO))
		min_lum = minf(min_lum, lum)
	assert_gte(min_scale, params.scale_min - 0.01)
	assert_lte(max_scale, params.scale_max + 0.01)
	assert_gte(min_lum, 0.18, "instance tint lum min %.3f" % min_lum)
