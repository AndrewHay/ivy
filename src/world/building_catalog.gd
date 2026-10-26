class_name BuildingCatalog
extends RefCounted

const StructureScenario = preload("res://src/world/structure_scenario.gd")

## Playable scenario choices for the main-menu picker (procedural fixtures + mesh structures).

class Entry:
	var id: String
	var label: String
	var scenario_path: String  # empty → procedural analytic tower
	var eave_traversal: bool   # true only for the going-around overhang fixture
	## When set, picking this entry loads this scene instead of the ivy session (dev / QA).
	var standalone_scene_path: String

	func _init(
			p_id: String,
			p_label: String,
			p_scenario_path: String = "",
			p_eave_traversal: bool = false,
			p_standalone_scene_path: String = "") -> void:
		id = p_id
		label = p_label
		scenario_path = p_scenario_path
		eave_traversal = p_eave_traversal
		standalone_scene_path = p_standalone_scene_path


static func all() -> Array[Entry]:
	return [
		Entry.new("cylinder", "Test cylinder"),
		Entry.new("test_wall", "Test wall"),
		Entry.new("overhang", "Eave wall", "", true),
		Entry.new("overhang_spread", "Eave wall (stop-spread)"),
		Entry.new("tower", "Tower", "res://assets/structures/scenarios/tower.tres"),
		Entry.new("square", "Squat house", "res://assets/structures/scenarios/square.tres"),
		Entry.new(
			"test_fauna",
			"Test fauna",
			"",
			false,
			"res://scenes/test_fauna/test_fauna.tscn"),
		Entry.new(
			"nature_flora_lineup",
			"Nature flora lineup",
			"",
			false,
			"res://tools/nature_flora_lineup.tscn"),
	]


static func scenario_for(id: String) -> StructureScenario:
	for entry in all():
		if entry.id == id and not entry.scenario_path.is_empty():
			return load(entry.scenario_path) as StructureScenario
	return null


static func is_procedural(id: String) -> bool:
	return id == "cylinder" or id == "test_wall" or id == "overhang" or id == "overhang_spread"


static func standalone_scene_for(id: String) -> String:
	for entry in all():
		if entry.id == id:
			return entry.standalone_scene_path
	return ""


## Returns true only for the building id that runs with eave_traversal_enabled=true.
static func traversal_for(id: String) -> bool:
	for entry in all():
		if entry.id == id:
			return entry.eave_traversal
	return false
