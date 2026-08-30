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
