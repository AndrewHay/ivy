extends GutTest

## D-5 / W-022 — automatable blacklist checks fire on synthetic violations.

const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const BlacklistAssertions = preload("res://src/metrics/blacklist.gd")
const TipManager = preload("res://src/sim/tip_manager.gd")
const Tip = preload("res://src/sim/tip.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const MaterialRegistry = preload("res://src/world/material_registry.gd")


func _surface() -> SurfaceQuery:
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var sq := SurfaceQuery.new()
	sq.setup(null, null, TowerSdf.new(spec), PackedByteArray(), IvyParams.new())
	return sq


func _clean_plant_on_wall() -> PlantData:
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var plant := PlantData.new()
	var r := spec.radius_outer
	var a := Vector3(0.0, 1.0, r - 0.01)
	var b := Vector3(0.0, 1.03, r - 0.01)
	plant.append_segment(a, b, Vector3(0, 0, 1), 0, 0, 0.0, MaterialRegistry.BRICK_WALL)
	return plant


func test_clean_plant_passes_hard_blacklist() -> void:
	var params := IvyParams.new()
	var plant := _clean_plant_on_wall()
	var tips := TipManager.new()
	var seed := Vector3(0.0, params.ground_y_min, 0.0) + Conv.SOUTH * 8.0
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var bl := BlacklistAssertions.measure(plant, tips, _surface(), params, seed, spec)
	assert_true(BlacklistAssertions.hard_pass(bl), "clean wall-hugging plant must pass hard checks")


func test_through_wall_segment_fails_item1() -> void:
	var params := IvyParams.new()
	var plant := _clean_plant_on_wall()
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var sq := _surface()
	var sdf := TowerSdf.new(spec)
	var probe := Vector3(0.0, 1.0, spec.radius_outer - 0.08)
	while sdf.signed_distance(probe) > -0.06:
		probe.z -= 0.01
	plant.append_segment(probe, probe + Vector3.UP * 0.03, Vector3(0, 0, 1), 0, 0, 0.03)
	var bl := BlacklistAssertions.measure(plant, TipManager.new(), sq, params, Vector3.ZERO, spec)
	assert_false(BlacklistAssertions.hard_pass(bl))
	assert_true(String(bl.hard_failures[0]).contains("item1"))


func test_floating_tip_counter_fails_item2() -> void:
	var params := IvyParams.new()
	var plant := _clean_plant_on_wall()
	var tips := TipManager.new()
	var t := Tip.new()
	t.id = 0
	t.state = Tip.State.FLOATING
	t.floating_length = params.max_float + 0.1
	tips.tips.append(t)
	var bl := BlacklistAssertions.measure(plant, tips, _surface(), params, Vector3.ZERO)
	assert_false(BlacklistAssertions.hard_pass(bl))
	assert_true(String(bl.hard_failures[0]).contains("item2"))


func test_ground_growth_far_from_seed_fails_item6() -> void:
	var params := IvyParams.new()
	var plant := _clean_plant_on_wall()
	var low := Vector3(3.0, 0.0, 0.0)
	var low_b := Vector3(3.0, 0.03, 0.0)
	plant.append_segment(low, low_b, Vector3(0, 1, 0), 0, 0, 0.03)
	var seed := Vector3(0.0, params.ground_y_min, 2.0)
	var bl := BlacklistAssertions.measure(plant, TipManager.new(), _surface(), params, seed)
	assert_false(BlacklistAssertions.hard_pass(bl))
	var found := false
	for msg in bl.hard_failures:
		if String(msg).contains("item6"):
			found = true
	assert_true(found, "expected item6 ground growth failure")


func test_item7_inconclusive_on_sparse_plant() -> void:
	var params := IvyParams.new()
	var plant := _clean_plant_on_wall()
	var bl := BlacklistAssertions.measure(plant, TipManager.new(), _surface(), params, Vector3.ZERO)
	assert_eq(bl.item7_status, "inconclusive")
