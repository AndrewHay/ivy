extends GutTest

const WandererFigure = preload("res://src/presentation/wanderer/wanderer_figure.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")


func test_build_height_and_mesh_budget() -> void:
	var p := WandererParams.production()
	var fig := WandererFigure.build(p)
	add_child_autofree(fig)
	var meshes := WandererFigure.count_mesh_instances(fig)
	assert_gte(meshes, 12)
	assert_lte(WandererFigure.count_triangles(fig), 400)
	assert_almost_eq(WandererFigure.measured_height(fig), 2.0, 0.03)


func test_face_plate_points_forward() -> void:
	var fig := WandererFigure.build(WandererParams.production())
	add_child_autofree(fig)
	await get_tree().process_frame
	assert_almost_eq(WandererFigure.face_forward_dot(fig), 1.0, 0.05)


func test_pose_idle_neutral() -> void:
	var p := WandererParams.production()
	var pose := WandererFigure.pose(0, p, 1.2, 0.0)
	assert_eq(pose["leg_l_deg"], 0.0)


func test_face_plate_albedo_texture() -> void:
	assert_true(FileAccess.file_exists("res://assets/wanderer/figure_face.png.import"))
	var fig := WandererFigure.build(WandererParams.production())
	add_child_autofree(fig)
	await get_tree().process_frame
	var face := fig.get_node("Head/FacePlate") as MeshInstance3D
	var mat := face.material_override as StandardMaterial3D
	assert_not_null(mat.albedo_texture, "face texture should load")


func test_arm_top_at_or_below_shoulder_at_rest() -> void:
	var fig := WandererFigure.build(WandererParams.production())
	add_child_autofree(fig)
	await get_tree().process_frame
	assert_lte(WandererFigure.limb_mesh_top_y(fig, "ArmL"), 1.62)


func test_arm_rotation_pivot_at_shoulder() -> void:
	var fig := WandererFigure.build(WandererParams.production())
	add_child_autofree(fig)
	await get_tree().process_frame
	var p := WandererParams.production()
	var shoulder_before := WandererFigure.limb_pivot_global(fig, "ArmL")
	assert_almost_eq(WandererFigure.limb_mesh_top_y(fig, "ArmL"), shoulder_before.y, 0.03)
	WandererFigure.apply_pose(fig, {"arm_l_deg": 30.0, "bob_m": 0.0, "roll_deg": 0.0, "lean_deg": 0.0}, p)
	await get_tree().process_frame
	var shoulder_after := WandererFigure.limb_pivot_global(fig, "ArmL")
	assert_lt(shoulder_before.distance_to(shoulder_after), 0.01)


func test_leg_swing_hip_fixed_foot_moves() -> void:
	var fig := WandererFigure.build(WandererParams.production())
	add_child_autofree(fig)
	await get_tree().process_frame
	var p := WandererParams.production()
	var hip_rest := WandererFigure.limb_pivot_global(fig, "LegL")
	var foot_rest := WandererFigure.foot_global(fig, "LegL")
	var swing := p.leg_swing_deg
	WandererFigure.apply_pose(
		fig,
		{
			"leg_l_deg": swing,
			"leg_r_deg": -swing,
			"arm_l_deg": 0.0,
			"arm_r_deg": 0.0,
			"bob_m": 0.0,
			"roll_deg": 0.0,
			"lean_deg": 0.0,
		},
		p)
	await get_tree().process_frame
	var hip_swing := WandererFigure.limb_pivot_global(fig, "LegL")
	var foot_swing := WandererFigure.foot_global(fig, "LegL")
	assert_lt(hip_rest.distance_to(hip_swing), 0.01)
	assert_gt(foot_rest.distance_to(foot_swing), 0.05)
