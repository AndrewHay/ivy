extends GutTest

const HillsPlaygroundScene = preload("res://scenes/playground/hills_playground.tscn")


func test_playground_loads_and_has_terrain() -> void:
	var pg := HillsPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	var stage := pg.get_node_or_null("Stage")
	assert_not_null(stage)
	var hill := stage.get_node_or_null("HillTerrain") if stage else null
	assert_not_null(hill, "Stage must have HillTerrain after rebuild")


## Regression test for the capture-then-hang bug: _capture_png must always
## call _capture_done_fn (the quit hook) so the Godot process exits.
## In headless/dummy-renderer mode get_image() returns null and save fails, so
## we only assert the hook fires; exit-code 0 on success is verified end-to-end
## by the repro command in the bead notes.
func test_capture_png_always_calls_quit_hook() -> void:
	var pg := HillsPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame

	# Replace the quit hook with a recorder so GUT is not terminated.
	# Use an Array container because GDScript 4 lambdas capture by value.
	var hook_calls: Array[int] = []
	pg._capture_done_fn = func(err: int) -> void:
		hook_calls.append(err)

	var out_dir: String = ProjectSettings.globalize_path("res://") + ".tmp/test"
	DirAccess.make_dir_recursive_absolute(out_dir)
	pg._capture_png(out_dir + "/hills_capture_quit_regression.png")

	assert_eq(hook_calls.size(), 1,
		"quit hook must be called exactly once after _capture_png (was never called before fix)")
