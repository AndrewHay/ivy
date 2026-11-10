extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")
const WandererIntegration = preload("res://src/presentation/wanderer/wanderer_integration.gd")
const WandererController = preload("res://src/presentation/wanderer/wanderer_controller.gd")


func after_each() -> void:
	WandererIntegration.set_gut_wanderer_test_active(false)


func _world_with_building(building_id: String) -> Node3D:
	WandererIntegration.set_gut_wanderer_test_active(true)
	var main := MainScene.instantiate()
	add_child_autofree(main)
	var world: Node3D = main.get_node("World")
	await get_tree().process_frame
	world.set_scripted_building_id(building_id)
	return world


func _wanderer_count(world: Node3D) -> int:
	var count := 0
	for c in world.get_children():
		if c.get_script() == WandererController:
			count += 1
	return count


func test_rebuild_creates_single_wanderer() -> void:
	var world := await _world_with_building("birthday")
	world.rebuild_backdrop()
	var w1: Node3D = world.get_wanderer_controller()
	assert_not_null(w1)
	world.rebuild_backdrop()
	world.rebuild_backdrop()
	assert_eq(_wanderer_count(world), 1)


func test_no_wanderer_outside_birthday() -> void:
	for entry in BuildingCatalog.all():
		if entry.id == "birthday" or not entry.standalone_scene_path.is_empty():
			continue
		var world := await _world_with_building(entry.id)
		world.rebuild_backdrop()
		assert_null(world.get_wanderer_controller(), "no wanderer for '%s'" % entry.id)
		assert_eq(_wanderer_count(world), 0, "no wanderer node for '%s'" % entry.id)


func test_leaving_birthday_unbinds_wanderer() -> void:
	var world := await _world_with_building("birthday")
	world.rebuild_backdrop()
	var w: Node3D = world.get_wanderer_controller()
	assert_not_null(w)
	world.set_scripted_building_id("ivy")
	world.rebuild_backdrop()
	w.tick(0.1, false)
	assert_false(w.visible, "wanderer hidden once a non-birthday building rebuilds the village")


func test_only_birthday_entry_has_wanderer() -> void:
	var with_wanderer: Array[String] = []
	for entry in BuildingCatalog.all():
		if entry.wanderer:
			with_wanderer.append(entry.id)
	assert_eq(with_wanderer, ["birthday"] as Array[String])


func test_birthday_entry_is_cottage_in_generated_village() -> void:
	var birthday: BuildingCatalog.Entry = null
	for entry in BuildingCatalog.all():
		if entry.id == "birthday":
			birthday = entry
	assert_not_null(birthday)
	assert_eq(birthday.label, "Birthday")
	assert_eq(birthday.scenario_path, "res://assets/structures/scenarios/ivy.tres")
	assert_eq(birthday.standalone_scene_path, "")
	assert_eq(BuildingCatalog.village_mode_for("birthday"), GameModes.GENERATED)
	assert_eq(BuildingCatalog.village_mode_for("ivy"), "")
