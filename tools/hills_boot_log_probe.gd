## Boot generated seed 7 main scene; wait for backdrop build; exit (grep Godot log for hills).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")


func _ready() -> void:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(40):
		await get_tree().process_frame
	main.call("apply_village_mode_live", GameModes.GENERATED, 7)
	for _i in range(36):
		await get_tree().process_frame
	var world: Node = main.get_node("World")
	var hill := world.find_child("HillTerrain", true, false)
	var forest := world.find_child("HillForest", true, false)
	print(
		"[hills-boot-log] HillTerrain=%s HillForest=%s"
		% [hill != null, forest != null])
	get_tree().quit(0)
