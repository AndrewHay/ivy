extends GutTest

const PlaygroundScene = preload("res://scenes/playground/forest_playground.tscn")


func test_playground_restores_village_pond_shape() -> void:
	VillagePondShape.set_active(VillagePondShape.classic())
	var before := VillagePondShape.active()
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_ne(VillagePondShape.active(), before,
		"playground should activate a layout pond while running")
	root.queue_free()
	await get_tree().process_frame
	assert_eq(VillagePondShape.active(), before,
		"pond shape must restore to classic after playground exits")
