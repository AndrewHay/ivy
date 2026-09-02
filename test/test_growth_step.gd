## W-043 — direction_memory blend must not zero on antiparallel reflection.
extends GutTest

const GrowthStep = preload("res://src/sim/growth_step.gd")


func test_direction_memory_antiparallel_preserves_heading() -> void:
	var prev := Vector3.RIGHT
	var actual := Vector3.LEFT
	var mem := 0.5
	var result := GrowthStep.apply_direction_memory(prev, actual, mem)
	assert_ne(result, Vector3.ZERO, "antiparallel blend must not zero persistence heading")
	assert_eq(result, prev, "antiparallel blend should keep the previous heading")


func test_direction_memory_non_degenerate_normalizes() -> void:
	var prev := Vector3.RIGHT
	var actual := Vector3.UP
	var mem := 0.5
	var result := GrowthStep.apply_direction_memory(prev, actual, mem)
	assert_almost_eq(result.length(), 1.0, 1e-6)
	assert_gt(result.dot(prev), 0.0)
	assert_gt(result.dot(actual), 0.0)
