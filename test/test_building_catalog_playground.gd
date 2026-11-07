extends GutTest

## Playground scenes must be reachable from the main-menu picker (design principle G7).

const BuildingCatalog = preload("res://src/world/building_catalog.gd")


func test_grass_wind_playground_listed_with_standalone_scene() -> void:
	var path := BuildingCatalog.standalone_scene_for("grass_wind_playground")
	assert_eq(path, "res://scenes/playground/grass_wind_playground.tscn")
	assert_true(ResourceLoader.exists(path), "playground scene must exist on disk")


func test_grass_wind_playground_is_not_an_ivy_session() -> void:
	assert_null(BuildingCatalog.scenario_for("grass_wind_playground"))
	assert_false(BuildingCatalog.is_procedural("grass_wind_playground"))
	assert_false(BuildingCatalog.traversal_for("grass_wind_playground"))


func test_catalog_ids_unique() -> void:
	var seen := {}
	for entry in BuildingCatalog.all():
		assert_false(seen.has(entry.id), "duplicate catalog id %s" % entry.id)
		seen[entry.id] = true
