extends GutTest

const LeafCupMeshScript = preload("res://src/render/leaf_cup_mesh.gd")
const LeafRenderer = preload("res://src/render/leaf_renderer.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const PlantData = preload("res://src/sim/plant_data.gd")


func test_cup_offset_is_flat_at_petiole_and_tip() -> void:
	var amp := 0.1
	assert_almost_eq(LeafCupMeshScript._cup_offset(0.0, 1.0, amp), 0.0, 1e-5)
	assert_almost_eq(LeafCupMeshScript._cup_offset(0.0, 0.0, amp), 0.0, 1e-5)
	assert_almost_eq(LeafCupMeshScript._cup_offset(0.5, 1.0, amp), 0.0, 1e-5)


func test_cup_offset_peaks_at_mid_blade_centre() -> void:
	var amp := 0.1
	assert_almost_eq(LeafCupMeshScript._cup_offset(0.0, 0.5, amp), amp, 1e-5)


func test_cup_mesh_has_depth() -> void:
	var mesh := LeafCupMeshScript.build() as ArrayMesh
	assert_gt(mesh.get_aabb().size.z, 0.02, "cup mesh extends in z")


func test_blade_grid_is_denser_for_crease() -> void:
	var mesh := LeafCupMeshScript.build() as ArrayMesh
	var vert_count: int = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var n := LeafCupMeshScript.BLADE_GRID
	var petiole_verts := (LeafCupMeshScript.PETIOLE_SEGMENTS + 1) * 2
	assert_eq(vert_count, (n + 1) * (n + 1) + petiole_verts,
		"production mesh uses BLADE_GRID subdiv for the midrib fold")


func test_crease_trough_on_midrib_and_flat_at_edges() -> void:
	var amp := 0.1
	assert_almost_eq(LeafCupMeshScript._crease_offset(0.0, amp), -amp, 1e-5)
	assert_almost_eq(LeafCupMeshScript._crease_offset(0.5, amp), 0.0, 1e-5)
	assert_almost_eq(LeafCupMeshScript._crease_offset(-0.5, amp), 0.0, 1e-5)


func test_blade_is_full_width_rectangle_with_petiole_below() -> void:
	var mesh := LeafCupMeshScript.build() as ArrayMesh
	var aabb := mesh.get_aabb()
	assert_almost_eq(aabb.size.x, 1.0, 1e-4, "no apical taper: blade spans full width")
	assert_almost_eq(aabb.position.y, 0.0, 1e-5, "petiole starts at the node")
	assert_almost_eq(aabb.end.y, LeafCupMeshScript.PETIOLE_LEN + 1.0, 1e-4,
		"blade sits above the petiole")


func test_petiole_uvs_are_outside_atlas_rect() -> void:
	var mesh := LeafCupMeshScript.build() as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var found := false
	for k in range(verts.size()):
		if verts[k].y < 0.01:
			found = true
			assert_gt(uvs[k].y, 1.25, "node-end petiole vertex must carry v past the shader's 1.25 split")
	assert_true(found, "mesh has a petiole vertex at the node")


func test_s_age_smoothstep() -> void:
	var expand := 0.12
	assert_almost_eq(LeafRenderer.s_age_for(0.0, expand), 0.0, 1e-5)
	assert_almost_eq(LeafRenderer.s_age_for(expand, expand), 1.0, 1e-5)
	assert_almost_eq(LeafRenderer.s_age_for(expand * 0.5, expand), 0.5, 1e-2)


func test_should_freeze_at_expand_distance() -> void:
	var expand := IvyParams.new().leaf_expand_distance
	assert_false(LeafRenderer.should_freeze(expand - 0.001, expand))
	assert_true(LeafRenderer.should_freeze(expand, expand))


func test_static_sync_uses_tip_shoot_past_node_for_s_age() -> void:
	var expand := IvyParams.new().leaf_expand_distance
	var s_at := 2.5
	var shoot := s_at + expand * 0.4
	assert_almost_eq(LeafRenderer.s_age_for(shoot - s_at, expand), 0.352, 0.02,
		"static sync path must derive s_age from tip_shoot past-node distance")


func test_petiole_strip_is_segmented_with_outward_arc() -> void:
	var mesh := LeafCupMeshScript.build() as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_gte(verts.size(), 9 + (LeafCupMeshScript.PETIOLE_SEGMENTS + 1) * 2,
		"petiole must add segmented rows beyond the blade grid")
	var max_z := 0.0
	for v in verts:
		if v.y < LeafCupMeshScript.PETIOLE_LEN * 0.95 and v.y > 0.02:
			max_z = maxf(max_z, v.z)
	assert_gt(max_z, LeafCupMeshScript.PETIOLE_BEND * 0.4,
		"mid-petiole should bow outward (+z) along the arc")


func test_instance_color_alpha_carries_s_age() -> void:
	var plant := PlantData.new()
	plant.append_leaf(
		Transform3D(Basis.IDENTITY, Vector3.ZERO),
		Color(1.06, 1.04, 0.86, 1.0),
		Vector4(0.0, 0.0, 0.25, 0.25),
		0, 1.0, 0.01, 1.0)
	var expand := IvyParams.new().leaf_expand_distance
	var s_age := LeafRenderer.s_age_for(expand * 0.5, expand)
	var inst := LeafRenderer.instance_color_for(plant, 0, s_age)
	assert_almost_eq(inst.a, s_age, 1e-5, "COLOR.a must carry s_age for young-leaf shader")
	assert_almost_eq(inst.g, 1.04, 0.001, "sun/shade tint stays in rgb from sim")
