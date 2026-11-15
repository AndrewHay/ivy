extends GutTest

## ivy-b1e.6 — the relief test article (SD-MESH-19.5) loads by id in its four growth-surface
## variants and never shows up in the building picker.

const BuildingCatalog = preload("res://src/world/building_catalog.gd")
const StructureScenario = preload("res://src/world/structure_scenario.gd")

const IDS := {
	"relief_article": "res://assets/structures/relief_article_sim",
	"relief_article_r025": "res://assets/structures/relief_article_r025_sim",
	"relief_article_r050": "res://assets/structures/relief_article_r050_sim",
	"relief_article_bbox": "res://assets/structures/relief_article_bbox_sim",
}
const HERO := "res://assets/structures/relief_article_hero.glb"
## SD-MESH-19.5 seed anchors A1-A4: all at y = 0.10 on the front face (z = 0, facing +z).
const ANCHOR_X: Array[float] = [-0.90, 0.075, 0.60, 1.28]


func _entry(id: String):
	for entry in BuildingCatalog.all():
		if entry.id == id:
			return entry
	return null


func test_every_variant_is_a_catalog_entry_hidden_from_the_picker() -> void:
	for id in IDS:
		var entry = _entry(id)
		assert_not_null(entry, "catalog entry %s" % id)
		if entry == null:
			continue
		assert_false(entry.in_picker, "%s must not get a picker button" % id)
		assert_false(BuildingCatalog.is_procedural(id))
		assert_eq(BuildingCatalog.standalone_scene_for(id), "")
		assert_false(BuildingCatalog.traversal_for(id))


func test_every_variant_loads_by_id_with_its_own_growth_surface_and_the_one_hero() -> void:
	for id in IDS:
		var scenario: StructureScenario = BuildingCatalog.scenario_for(id)
		assert_not_null(scenario, "scenario_for(%s)" % id)
		if scenario == null:
			continue
		assert_eq(scenario.scenario_id, id)
		assert_eq(scenario.collision_glb, IDS[id] + ".glb")
		assert_eq(scenario.sdf_path, IDS[id] + ".sdf")
		assert_eq(scenario.hero_glb, HERO)
		assert_eq(scenario.validate(), PackedStringArray(), "%s validates" % id)
		assert_true(FileAccess.file_exists(HERO))


func test_seed_anchors_are_a1_to_a4_aimed_at_the_front_face() -> void:
	for id in IDS:
		var scenario: StructureScenario = BuildingCatalog.scenario_for(id)
		if scenario == null:
			fail_test("no scenario for %s" % id)
			continue
		assert_eq(scenario.seed_positions.size(), ANCHOR_X.size())
		for i in ANCHOR_X.size():
			var p: Vector3 = scenario.seed_positions[i]
			assert_almost_eq(p.x, ANCHOR_X[i], 1e-6, "A%d x" % (i + 1))
			assert_almost_eq(p.y, 0.10, 1e-6, "A%d y" % (i + 1))
			assert_gt(p.z, 0.10, "A%d starts in front of everything on the front face" % (i + 1))
			assert_eq(scenario.seed_normals[i], Vector3(0, 0, -1), "seed normals point into the wall")
