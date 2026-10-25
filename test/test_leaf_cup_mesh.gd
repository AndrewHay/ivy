extends GutTest

const LeafCupMeshScript = preload("res://src/render/leaf_cup_mesh.gd")
const LeafRenderer = preload("res://src/render/leaf_renderer.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


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


func test_crease_peaks_on_midrib_and_vanishes_at_edges() -> void:
	var amp := 0.1
	assert_almost_eq(LeafCupMeshScript._crease_offset(0.0, amp), amp, 1e-5)
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
