## Wall time for apply_village_mode_live (generated seed 1).
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"


func _ready() -> void:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(30):
		await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	main.call("apply_village_mode_live", "generated_village", 1)
	for _i in range(5):
		await get_tree().process_frame
	var wall := Time.get_ticks_msec() - t0
	print("[mode-switch] generated apply_village_mode_live wall_ms=%d" % wall)
	get_tree().quit(0)
