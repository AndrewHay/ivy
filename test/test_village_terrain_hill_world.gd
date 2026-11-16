## ivy-82zn.14.10 — village hill in the game World (AC 1, AC 7): option A datum. The hero ground stays
## at world y = 0; World lowers VillageBackdrop and the visible ground plane by hero_datum_y; every
## consumer that turns a lawn XZ into a world Y (camera floor, wanderer, fauna, garden props) sits on
## the lowered terrain. Classic / variant 1 keep every offset at 0 (AC-VT1 / INV-15).
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")
const FaunaMotionScript = preload("res://src/presentation/fauna/fauna_motion.gd")

const _SEED := 7


func _boot_generated() -> Node:
	var main := MainScene.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", SquareScenario)
	add_child_autofree(main)
	for _i in range(30):
		await get_tree().process_frame
	var world := main.get_node("World")
	world.call("set_village_mode", GameModes.GENERATED, _SEED)
	world.call("rebuild_backdrop")
	await get_tree().process_frame
	return world


func test_world_lowers_village_so_hero_ground_is_world_zero() -> void:
	var world: Node = await _boot_generated()
	var bd := world.get_node_or_null("VillageBackdrop") as VillageBackdrop
	assert_not_null(bd, "generated backdrop")
	if bd == null:
		return
	var datum := bd.hero_datum_y()
	assert_gt(datum, 6.0, "seed 7 hill: hero datum is the crest (%.2f m)" % datum)
	assert_almost_eq(bd.global_position.y, -datum, 1e-4, "backdrop lowered by the hero datum")
	var stoop_world_y := bd.global_position.y + bd.sample_terrain_y(VillageLayout.HERO_DOOR_STOOP)
	assert_almost_eq(stoop_world_y, 0.0, 0.02, "hero ground at world y 0")
	var ground_mesh := world.get_node("Ground/GroundMesh") as Node3D
	assert_almost_eq(ground_mesh.global_position.y, bd.global_position.y, 1e-4,
		"visible ground plane lowered with the village (outer hills not covered)")
	var collision := world.get_node("Ground/GroundCollision") as Node3D
	assert_almost_eq(collision.global_position.y, 0.0, 1e-4, "ground collision stays at the hero ground")


func test_camera_floor_is_terrain_in_world_space() -> void:
	var world: Node = await _boot_generated()
	var bd := world.get_node_or_null("VillageBackdrop") as VillageBackdrop
	var rig := world.get("_camera_rig") as Node
	if bd == null or rig == null:
		fail_test("backdrop / rig missing")
		return
	var floor_fn: Callable = rig.get("_terrain_floor_fn")
	assert_true(floor_fn.is_valid(), "rig has a terrain floor")
	var clearance := (bd.get("_terrain_params") as VillageTerrainParams).camera_ground_clearance_m
	var o := bd.global_position
	var layout := bd.get_layout()
	for local: Vector2 in [VillageLayout.HERO_DOOR_STOOP, layout.hamlet_centre_xz,
			layout.hamlet_centre_xz + Vector2(20.0, -10.0)]:
		var world_xz := local + Vector2(o.x, o.z)
		var want := o.y + bd.sample_terrain_y(local) + clearance
		assert_almost_eq(float(floor_fn.call(world_xz)), want, 0.05,
			"camera floor at %s on the lowered terrain" % local)


func test_garden_props_sit_on_the_terrain() -> void:
	var bd := GeneratedBackdropScene.instantiate() as GeneratedVillageBackdrop
	bd.set_village_seed(_SEED)
	add_child_autofree(bd)
	await get_tree().process_frame
	var n := 0
	for c in bd.get_children():
		if not str(c.name).begins_with("Garden_"):
			continue
		var p := (c as Node3D).position
		assert_almost_eq(p.y, bd.sample_terrain_y(Vector2(p.x, p.z)), 0.05,
			"%s seated on the terrain (not buried under the crest)" % c.name)
		n += 1
	assert_gt(n, 0, "garden props checked")


func test_fauna_hovers_above_the_anchor_ground() -> void:
	## Anchors carry the terrain y (backdrop-local); the hover is added on top, in world space.
	var env := FaunaEnvironment.new()
	var a := FaunaAnchor.new()
	a.kind = FaunaConstants.AnchorKind.FLOWER
	a.local_transform = Transform3D(Basis.IDENTITY, Vector3(3.0, 8.4, -2.0))
	env.anchors.append(a)
	var backdrop := Transform3D(Basis.IDENTITY, Vector3(0.0, -8.5, 0.0))
	for species in [FaunaConstants.Species.BEE, FaunaConstants.Species.BUTTERFLY]:
		var p: Vector3 = FaunaMotionScript.anchor_world_pos(env, 0, backdrop, species)
		assert_almost_eq(p.y, -8.5 + 8.4 + FaunaMotionScript.anchor_hover_y(species), 1e-4,
			"species %d hovers above its anchor's ground" % species)


func test_classic_keeps_every_offset_at_zero() -> void:
	var world: Node = await _boot_generated()
	world.call("set_village_mode", GameModes.CLASSIC, 0)
	world.call("rebuild_backdrop")
	await get_tree().process_frame
	var bd := world.get_node_or_null("VillageBackdrop") as Node3D
	assert_not_null(bd, "classic backdrop")
	if bd == null:
		return
	assert_eq(bd.global_position.y, 0.0, "classic backdrop at y 0 (INV-15)")
	assert_eq((world.get_node("Ground/GroundMesh") as Node3D).global_position.y, 0.0, "classic ground at y 0")
