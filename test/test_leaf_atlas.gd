## W-062: Tests for LeafAtlas.tier_for(id) and LeafAtlas.ids_in_tier(tier).
##
## Fixed id order per tier (SD-LEAF-6, SD-RNG-6):
##   H = ["a", "c", "e"]  (healthy: larger, saturated, clean)
##   W = ["b", "d", "f"]  (weathered: smaller, paler, mottled)
##
## These tests are RED before W-062 lands and GREEN afterwards.
extends GutTest

const LeafAtlas = preload("res://src/render/leaf_atlas.gd")

var _atlas: LeafAtlas


func before_each() -> void:
	_atlas = LeafAtlas.new()


func test_tier_for_id_a_is_healthy() -> void:
	assert_eq(_atlas.tier_for("a"), "H", "leaf 'a' is in the healthy tier")


func test_tier_for_id_b_is_weathered() -> void:
	assert_eq(_atlas.tier_for("b"), "W", "leaf 'b' is in the weathered tier")


func test_tier_for_id_c_is_healthy() -> void:
	assert_eq(_atlas.tier_for("c"), "H", "leaf 'c' is in the healthy tier")


func test_tier_for_id_d_is_weathered() -> void:
	assert_eq(_atlas.tier_for("d"), "W", "leaf 'd' is in the weathered tier")


func test_tier_for_id_e_is_healthy() -> void:
	assert_eq(_atlas.tier_for("e"), "H", "leaf 'e' is in the healthy tier")


func test_tier_for_id_f_is_weathered() -> void:
	assert_eq(_atlas.tier_for("f"), "W", "leaf 'f' is in the weathered tier")


func test_ids_in_tier_healthy_fixed_order() -> void:
	var ids: PackedStringArray = _atlas.ids_in_tier("H")
	assert_eq(ids.size(), 3, "healthy tier must have exactly 3 ids")
	assert_eq(ids[0], "a", "healthy[0] must be 'a'")
	assert_eq(ids[1], "c", "healthy[1] must be 'c'")
	assert_eq(ids[2], "e", "healthy[2] must be 'e'")


func test_ids_in_tier_weathered_fixed_order() -> void:
	var ids: PackedStringArray = _atlas.ids_in_tier("W")
	assert_eq(ids.size(), 3, "weathered tier must have exactly 3 ids")
	assert_eq(ids[0], "b", "weathered[0] must be 'b'")
	assert_eq(ids[1], "d", "weathered[1] must be 'd'")
	assert_eq(ids[2], "f", "weathered[2] must be 'f'")


func test_tier_for_round_trips_with_ids_in_tier() -> void:
	## Every id returned by ids_in_tier("H") must have tier_for() == "H", and vice versa.
	for id: String in _atlas.ids_in_tier("H"):
		assert_eq(_atlas.tier_for(id), "H",
			"id '%s' from healthy list must tier_for to 'H'" % id)
	for id: String in _atlas.ids_in_tier("W"):
		assert_eq(_atlas.tier_for(id), "W",
			"id '%s' from weathered list must tier_for to 'W'" % id)


func test_tier_for_all_six_ids_covered() -> void:
	## Every leaf id in the atlas JSON has a tier.
	for id: String in ["a", "b", "c", "d", "e", "f"]:
		var tier: String = _atlas.tier_for(id)
		assert_true(tier == "H" or tier == "W",
			"tier_for('%s') must be 'H' or 'W', got '%s'" % [id, tier])
