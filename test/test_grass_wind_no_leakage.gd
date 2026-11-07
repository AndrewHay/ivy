extends GutTest

const PlaygroundScene = preload("res://scenes/playground/grass_wind_playground.tscn")


func _snapshot_wind_globals() -> Dictionary:
	var names := [
		"ivy_wind_dir", "ivy_wind_strength", "ivy_wind_scroll", "ivy_wind_flutter_phase"]
	var out := {}
	for n in names:
		out[n] = RenderingServer.global_shader_parameter_get(n)
	return out


func test_playground_source_never_sets_global_shader_params() -> void:
	var text := FileAccess.get_file_as_string(
		"res://src/playground/grass_wind_playground.gd")
	assert_false(
		text.contains("global_shader_parameter_set"),
		"Playground must not call global_shader_parameter_set")


func test_playground_does_not_mutate_wind_globals() -> void:
	var before := _snapshot_wind_globals()
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	for _i in range(8):
		await get_tree().process_frame
	var after := _snapshot_wind_globals()
	for key in before.keys():
		assert_eq(after[key], before[key], "Global %s must be unchanged" % key)
