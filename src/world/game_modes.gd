## GameModes — catalog of selectable village backdrop modes (ivy-80z S4).
##
## Provides the mode registry used by Main/World/Picker to select which backdrop
## scene to instance. Designed to carry future rules_path/goals fields (none now).
## Style mirrors BuildingCatalog: a lightweight static-method catalog over a
## typed inner class.
class_name GameModes
extends RefCounted

const CLASSIC   := "classic_village"
const GENERATED := "generated_village"

## A single game-mode entry. Fields per SD-VILLAGE-GEN-7.
class Mode:
	var id: String
	var label: String
	var backdrop_scene_path: String
	var is_generated: bool

	func _init(p_id: String, p_label: String, p_path: String, p_is_generated: bool) -> void:
		id = p_id
		label = p_label
		backdrop_scene_path = p_path
		is_generated = p_is_generated


## All registered modes in display order.
static func all() -> Array[Mode]:
	var out: Array[Mode] = []
	out.append(Mode.new(
		CLASSIC, "Classic village",
		"res://src/world/village_backdrop.tscn", false))
	out.append(Mode.new(
		GENERATED, "Generated village",
		"res://src/world/generated_village_backdrop.tscn", true))
	return out


## Look up a mode by id. Falls back to CLASSIC on an unknown id (AR-VG-API).
static func by_id(id: String) -> Mode:
	for mode in all():
		if mode.id == id:
			return mode
	# Unknown id → return classic (safe default, never null).
	return all()[0]
