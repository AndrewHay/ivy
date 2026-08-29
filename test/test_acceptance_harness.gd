extends GutTest

const Harness = preload("res://tools/acceptance_harness.gd")


func test_stem_lengths_within_relative_tolerance() -> void:
	assert_true(Harness.stem_lengths_within_relative_tolerance(100.0, 101.0, 0.02))
	assert_true(Harness.stem_lengths_within_relative_tolerance(100.0, 98.1, 0.02))
	assert_false(Harness.stem_lengths_within_relative_tolerance(100.0, 97.0, 0.02))
