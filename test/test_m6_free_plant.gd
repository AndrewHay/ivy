extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SimClock = preload("res://src/core/sim_clock.gd")


func test_plant_at_grows_segments_on_cylinder() -> void:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	var world: Node = main.get_node("World")
	world.call("load_building", "cylinder")
	await get_tree().physics_frame
	await get_tree().process_frame
	var sim: Node = main.get_node("Sim")
	var params: IvyParams = main.get("params")
	var surface: SurfaceQuery = world.call("get_surface_query", params)
	assert_not_null(surface, "surface query")
	sim.call(
		"setup",
		params,
		surface,
		null,
		0,
		world.call("get_seed_anchors"),
		false
	)
	var anchors = world.call("get_seed_anchors")
	assert_not_null(anchors)
	var anchor_list: Array = anchors.get_anchors()
	var south = anchor_list[2]
	assert_true(south.available, "south anchor")
	sim.call("plant_at", south.position, south.normal)
	assert_eq(sim.tips.tips.size(), 1)
	var clock: SimClock = sim.get_clock()
	clock.set_speed(SimClock.Speed.GROW)
	sim.call("advance_ticks", 48)
	assert_gt(sim.plant.segment_count(), 0, "expected stem segments after 2 game-days")
