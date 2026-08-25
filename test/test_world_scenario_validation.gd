extends GutTest

## W-089 follow-up (ivy-2p0.1): invalid StructureScenario must not build StructureBody.
const StructureScenarioScript = preload("res://src/world/structure_scenario.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func test_invalid_mesh_scenario_leaves_structure_null() -> void:
	var main_ps := load("res://src/main/main.tscn") as PackedScene
	var main := main_ps.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var scenario := StructureScenarioScript.new()
	scenario.scenario_id = "invalid"
	scenario.collision_glb = ""
	scenario.sdf_path = ""
	scenario.seed_positions = PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	scenario.seed_normals = PackedVector3Array([Vector3.UP, Vector3.UP])
	var world: Node = main.get_node("World")
	world.set("mesh_scenario", scenario)
	world.set("surface", null)
	world.call("ensure_mesh_scenario_loaded")
	await get_tree().process_frame
	var structure: Node = world.get("_structure")
	assert_null(structure, "validate() failure must leave _structure null")
	var params := IvyParams.new()
	var surface: Variant = world.call("get_surface_query", params)
	assert_null(surface, "get_surface_query must return null when scenario failed to load")
