## ivy-9bt7 / ivy-hfik: on a mesh, each collision ray starts a skin behind the tip and ends a skin past
## the target, so a tip lying exactly in the plane of a one-sided face still sees that face.
extends GutTest

const GrowthStep = preload("res://src/sim/growth_step.gd")


func test_mesh_ray_starts_a_skin_behind_the_tip() -> void:
	var from := Vector3(1.0, 2.0, 3.0)
	var to := Vector3(1.0, 2.0, 3.03)
	var start := GrowthStep._ray_start(from, to, true)
	assert_almost_eq(start.z, 3.0 - GrowthStep.COLLISION_SKIN, 1e-7)
	assert_almost_eq(start.x, 1.0, 1e-7)
	assert_almost_eq(start.y, 2.0, 1e-7)


func test_mesh_ray_ends_a_skin_past_the_target() -> void:
	var end := GrowthStep._ray_end(Vector3.ZERO, Vector3(0.0, 0.03, 0.0), true)
	assert_almost_eq(end.y, 0.03 + GrowthStep.COLLISION_SKIN, 1e-7)


func test_analytic_backends_keep_the_exact_segment() -> void:
	# SG-1 (procedural tower) depends on these rays being unchanged.
	var from := Vector3(0.5, 1.0, -0.2)
	var to := Vector3(0.52, 1.02, -0.2)
	assert_eq(GrowthStep._ray_start(from, to, false), from)
	assert_eq(GrowthStep._ray_end(from, to, false), to)


func test_zero_length_leg_is_left_alone() -> void:
	var p := Vector3(1.0, 1.0, 1.0)
	assert_eq(GrowthStep._ray_start(p, p, true), p)
	assert_eq(GrowthStep._ray_end(p, p, true), p)
