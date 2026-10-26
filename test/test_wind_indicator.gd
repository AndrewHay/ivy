extends GutTest

const WindIndicator = preload("res://src/ui/wind_indicator.gd")
const SimClock = preload("res://src/core/sim_clock.gd")


func test_caption_breeze_only_at_normal_strength() -> void:
	assert_eq(WindIndicator.caption_for_speed(SimClock.Speed.NORMAL, true), "Breeze")
	assert_eq(WindIndicator.caption_for_speed(SimClock.Speed.NORMAL, false), "Still")
	assert_eq(WindIndicator.caption_for_speed(SimClock.Speed.FAST, false), "Still · fast")


func test_arrow_end_unit_length() -> void:
	var end := WindIndicator.arrow_end(Vector2(1.0, 0.0), 0.0, 10.0)
	assert_almost_eq(end.length(), 10.0, 0.01)
