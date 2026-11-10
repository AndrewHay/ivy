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
	## When set, picking this entry switches the village to this GameModes id first.
	var village_mode: String
	## The village wanderer appears only in entries with this set.
	var wanderer: bool
	## Retired entries stay loadable by id (scripts, tests) but get no picker button.
	var in_picker: bool

	func _init(
			p_id: String,
			p_label: String,
			p_scenario_path: String = "",
			p_eave_traversal: bool = false,
			p_standalone_scene_path: String = "",
			p_village_mode: String = "",
			p_wanderer: bool = false,
			p_in_picker: bool = true) -> void:
		id = p_id
		label = p_label
		scenario_path = p_scenario_path
		eave_traversal = p_eave_traversal
		standalone_scene_path = p_standalone_scene_path
		village_mode = p_village_mode
		wanderer = p_wanderer
		in_picker = p_in_picker


static func all() -> Array[Entry]:
	return [
		Entry.new("cylinder", "Test cylinder"),
		Entry.new("test_wall", "Test wall"),
		Entry.new("overhang", "Eave wall", "", true),
		Entry.new("overhang_spread", "Eave wall (stop-spread)"),
		Entry.new("tower", "Tower", "res://assets/structures/scenarios/tower.tres"),
		Entry.new("ivy", "Village cottage", "res://assets/structures/scenarios/ivy.tres"),
		Entry.new(
			"birthday",
			"Birthday",
			"res://assets/structures/scenarios/ivy.tres",
			false,
			"",
			GameModes.GENERATED,
			true,
			false),
		Entry.new(
			"test_fauna",
			"Test fauna",
			"",
			false,
			"res://scenes/test_fauna/test_fauna.tscn"),
		Entry.new(
			"grass_wind_playground",
			"Grass wind playground",
			"",
			false,
			"res://scenes/playground/grass_wind_playground.tscn"),
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


## GameModes id the entry forces, or "" to keep the picker's village toggle.
static func village_mode_for(id: String) -> String:
	for entry in all():
		if entry.id == id:
			return entry.village_mode
	return ""


static func wanderer_for(id: String) -> bool:
	for entry in all():
		if entry.id == id:
			return entry.wanderer
	return false


## Returns true only for the building id that runs with eave_traversal_enabled=true.
static func traversal_for(id: String) -> bool:
	for entry in all():
		if entry.id == id:
			return entry.eave_traversal
	return false
