extends GutTest

const UiScriptVerbs = preload("res://tools/ui_script_verbs.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func test_compass_to_seed_index() -> void:
	assert_eq(UiScriptVerbs.compass_to_seed_index("n"), 0)
	assert_eq(UiScriptVerbs.compass_to_seed_index("EAST"), 1)
	assert_eq(UiScriptVerbs.compass_to_seed_index("s"), 2)
	assert_eq(UiScriptVerbs.compass_to_seed_index("West"), 3)
	assert_eq(UiScriptVerbs.compass_to_seed_index("2"), 2)
	assert_eq(UiScriptVerbs.compass_to_seed_index("bogus"), -1)


func test_compare_operators() -> void:
	assert_true(UiScriptVerbs.compare(5.0, ">=", 5.0))
	assert_true(UiScriptVerbs.compare(5.1, ">", 5.0))
	assert_true(UiScriptVerbs.compare(4.9, "<", 5.0))
	assert_true(UiScriptVerbs.compare(5.0, "==", 5.0))
	assert_true(UiScriptVerbs.compare(5.0, "!=", 4.0))
	assert_false(UiScriptVerbs.compare(4.0, ">=", 5.0))


func test_collect_metrics_after_short_growth() -> void:
	var sim := SimRoot.new()
	var params := IvyParams.new()
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var sq := SurfaceQuery.new()
	sq.setup(null, null, TowerSdf.new(spec), PackedByteArray(), params)
	sim.setup(params, sq, null, 2)
	sim.advance_ticks(24)
	var world := Node.new()
	world.set("tower_spec", spec)
	var metrics := UiScriptVerbs.collect_metrics(sim, world, 180.0)
	assert_gt(metrics["total_stem_length"], 0.0)
	assert_gt(metrics["segments"], 0.0)
	assert_gte(metrics["stem_asymmetry"], 0.0)
