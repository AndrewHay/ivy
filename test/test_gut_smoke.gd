extends GutTest

# Minimal smoke test — no game code dependencies.
# If this passes, GUT infrastructure is working.

func test_true_is_true() -> void:
	assert_true(true)

func test_math() -> void:
	assert_eq(1 + 1, 2)
