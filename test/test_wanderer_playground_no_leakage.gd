extends GutTest

const PlaygroundScene = preload("res://scenes/playground/wanderer_playground.tscn")
const WandererIntegration = preload("res://src/presentation/wanderer/wanderer_integration.gd")


func test_playground_does_not_mutate_engine_time_scale() -> void:
	Engine.time_scale = 0.5
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	for _i in range(6):
		await get_tree().process_frame
	assert_eq(Engine.time_scale, 0.5, "playground must not touch Engine.time_scale")


func test_playground_restores_input_mouse_mode() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	var mode_after_ready := Input.get_mouse_mode()
	root.queue_free()
	await get_tree().process_frame
	assert_eq(Input.get_mouse_mode(), mode_after_ready, "mouse mode restored to entry snapshot")


func test_playground_never_sets_wanderer_integration_meta() -> void:
	var text := FileAccess.get_file_as_string("res://src/playground/wanderer_playground.gd")
	assert_false(text.contains("set_gut_wanderer_test_active"))


func test_playground_leaves_integration_meta_unchanged() -> void:
	var had := Engine.has_meta("ivy_gut_wanderer_integration")
	var val = Engine.get_meta("ivy_gut_wanderer_integration") if had else null
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	root.queue_free()
	await get_tree().process_frame
	assert_eq(Engine.has_meta("ivy_gut_wanderer_integration"), had)
	if had:
		assert_eq(Engine.get_meta("ivy_gut_wanderer_integration"), val)
