## ivy-82zn.14.14 (WP1) — the landscape-first field in the game World (replaces
## test_village_terrain_hill_world.gd). Datum option A: hero pad at world y 0; camera floor in world
## space via sample_terrain_world_y; Garden_* seated; fauna hover above the anchor ground;
## World/Ground discard = VillageTerrain.R_SKIRT_M (AR-NOFOG-EDGE; was r_outer_m) and the plane below
## the terrain minimum (AR-LF-D7);
## classic keeps every offset at 0 (AC-VT1 / INV-15).
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const HillsParams = preload("res://src/playground/hills_params.gd")
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


func test_hero_pad_is_world_zero_and_ground_plane_below_the_terrain() -> void:
	var world: Node = await _boot_generated()
	var bd := world.get_node_or_null("VillageBackdrop") as VillageBackdrop
	assert_not_null(bd, "generated backdrop")
	if bd == null:
		return
	var datum := bd.hero_datum_y()
	assert_almost_eq(bd.global_position.y, -datum, 1e-4, "backdrop lowered by y_hero")
	var stoop_world := bd.sample_terrain_world_y(
		VillageLayout.HERO_DOOR_STOOP + Vector2(bd.global_position.x, bd.global_position.z))
	assert_almost_eq(stoop_world, 0.0, 0.02, "hero pad at world y 0")
	var ground_mesh := world.get_node("Ground/GroundMesh") as MeshInstance3D
	var min_y := bd.terrain_mesh_min_y()
	assert_lt(ground_mesh.global_position.y, bd.global_position.y + min_y,
		"World/Ground plane below the lowest terrain vertex (AR-LF-D7)")
	var mat := ground_mesh.get_surface_override_material(0) as ShaderMaterial
	# ivy-82zn.14.32 contract change (AR-NOFOG-EDGE): the far mesh's horizon skirt reaches R_SKIRT_M,
	# so the plane is discarded out to there (was r_outer_m).
	assert_almost_eq(float(mat.get_shader_parameter("village_disc_radius")), VillageTerrain.R_SKIRT_M,
		1e-4, "discard radius = R_SKIRT_M")
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
		var want := bd.sample_terrain_world_y(world_xz) + clearance
		assert_almost_eq(float(floor_fn.call(world_xz)), want, 1e-4, "camera floor at %s" % local)
		assert_almost_eq(bd.sample_terrain_world_y(world_xz), o.y + bd.sample_terrain_y(local), 1e-5,
			"sample_terrain_world_y = backdrop y + local terrain")


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
		assert_almost_eq(p.y, bd.sample_terrain_y(Vector2(p.x, p.z)), 0.05, "%s seated" % c.name)
		n += 1
	assert_gt(n, 0, "garden props checked")


func test_fauna_hovers_above_the_anchor_ground() -> void:
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
	var gm := world.get_node("Ground/GroundMesh") as MeshInstance3D
	assert_eq(gm.global_position.y, 0.0, "classic ground at y 0")
	var mat := gm.get_surface_override_material(0) as ShaderMaterial
	assert_eq(float(mat.get_shader_parameter("village_disc_radius")), 0.0, "classic: no discard")
