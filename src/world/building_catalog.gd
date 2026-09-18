class_name BuildingCatalog
extends RefCounted

const StructureScenario = preload("res://src/world/structure_scenario.gd")

## Playable building choices for the M6 picker (procedural cylinder + two mesh structures).

class Entry:
	var id: String
	var label: String
	var scenario_path: String  # empty → procedural analytic tower

	func _init(p_id: String, p_label: String, p_scenario_path: String = "") -> void:
		id = p_id
		label = p_label
		scenario_path = p_scenario_path


static func all() -> Array[Entry]:
	return [
		Entry.new("cylinder", "Test cylinder"),
		Entry.new("wall", "Test wall"),
		Entry.new("tower", "Tower", "res://assets/structures/scenarios/tower.tres"),
		Entry.new("square", "Squat house", "res://assets/structures/scenarios/square.tres"),
	]


static func scenario_for(id: String) -> StructureScenario:
	for entry in all():
		if entry.id == id and not entry.scenario_path.is_empty():
			return load(entry.scenario_path) as StructureScenario
	return null


static func is_procedural(id: String) -> bool:
	return id == "cylinder" or id == "wall"
