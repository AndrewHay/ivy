## Tests for World.rebuild_backdrop() mode-swap (ivy-80z S4).
##
## (a) After rebuild_backdrop() with GENERATED mode:
##     - node named "VillageBackdrop" exists exactly once as a child of World
##     - it is a GeneratedVillageBackdrop
##     - it is still named "VillageBackdrop"
##     - SkySun fog_depth_begin == 14.0 (layout.fog_begin for generated)
## (b) After rebuild_backdrop() with CLASSIC mode:
##     - node is a VillageBackdrop (base class, not GeneratedVillageBackdrop)
##     - SkySun fog_depth_begin == 9.5 (layout.fog_begin for classic; restore proof)
## (c) Classic → Generated → Classic round-trip: fog restores to 9.5 (AR-VG-DECIDE §2).
## (d) Node named "VillageBackdrop" exists exactly once after each swap.
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SquareScenario = preload("res://assets/structures/scenarios/square.tres")
const GameModes = preload("res://src/world/game_modes.gd")

const _GEN_SEED := 12345


## Boot main with the square scenario in script_driven mode, then activate the mesh scenario
## so that rebuild_backdrop() is triggered (which happens inside _activate_mesh_scenario).
func _boot_with_scenario() -> Node:
	var main := MainScene.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", SquareScenario)
	add_child_autofree(main)
	# Wait for _bootstrap_simulation coroutine (script_driven path) to complete.
	for _i in range(30):
		await get_tree().process_frame
	return main


## Get the World node from a booted main.
func _world(main: Node) -> Node:
	return main.get_node("World")


## Count direct children of World named "VillageBackdrop".
func _count_backdrop_children(world: Node) -> int:
	var count := 0
	for child in world.get_children():
		if child.name == "VillageBackdrop":
			count += 1
	return count


## Read fog_depth_begin from SkySun's WorldEnvironment.
func _fog_depth_begin(world: Node) -> float:
	var sky_sun := world.get_node_or_null("SkySun") as SkySun
	if sky_sun == null:
		return -1.0
	var env := sky_sun.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env == null or env.environment == null:
		return -1.0
	return env.environment.fog_depth_begin


# ── (a) Generated mode swap ───────────────────────────────────────────────────

func test_generated_backdrop_class_and_name() -> void:
	var main := await _boot_with_scenario()
	var world := _world(main)

	# Swap to generated mode.
	world.call("set_village_mode", GameModes.GENERATED, _GEN_SEED)
	world.call("rebuild_backdrop")
	await get_tree().process_frame

	var backdrop := world.get_node_or_null("VillageBackdrop")
	assert_not_null(backdrop, "VillageBackdrop node must exist after generated swap")
	if backdrop == null:
		return

	assert_eq(backdrop.name, "VillageBackdrop",
		"Rebuilt backdrop must be named 'VillageBackdrop' (AR-VG-COMPAT)")
	assert_true(backdrop is GeneratedVillageBackdrop,
		"After GENERATED swap, VillageBackdrop must be a GeneratedVillageBackdrop")


func test_generated_fog_depth_begin() -> void:
	var main := await _boot_with_scenario()
	var world := _world(main)

	world.call("set_village_mode", GameModes.GENERATED, _GEN_SEED)
	world.call("rebuild_backdrop")
	await get_tree().process_frame

	var fog := _fog_depth_begin(world)
	assert_almost_eq(fog, 14.0, 0.01,
		"fog_depth_begin must be 14.0 after generated swap (layout.fog_begin)")


func test_generated_backdrop_exists_exactly_once() -> void:
	var main := await _boot_with_scenario()
	var world := _world(main)

	world.call("set_village_mode", GameModes.GENERATED, _GEN_SEED)
	world.call("rebuild_backdrop")
	await get_tree().process_frame

	var count := _count_backdrop_children(world)
	assert_eq(count, 1,
		"Exactly one child named 'VillageBackdrop' must exist after swap; found %d" % count)


# ── (b) Classic restore ───────────────────────────────────────────────────────

func test_classic_restore_class() -> void:
	var main := await _boot_with_scenario()
	var world := _world(main)

	# Swap to generated then back to classic.
	world.call("set_village_mode", GameModes.GENERATED, _GEN_SEED)
	world.call("rebuild_backdrop")
	await get_tree().process_frame

	world.call("set_village_mode", GameModes.CLASSIC, 0)
	world.call("rebuild_backdrop")
	await get_tree().process_frame

	var backdrop := world.get_node_or_null("VillageBackdrop")
	assert_not_null(backdrop, "VillageBackdrop must exist after classic restore")
	if backdrop == null:
		return

	assert_false(backdrop is GeneratedVillageBackdrop,
		"After CLASSIC restore, VillageBackdrop must NOT be a GeneratedVillageBackdrop")
	assert_true(backdrop is VillageBackdrop,
		"After CLASSIC restore, VillageBackdrop must be a VillageBackdrop")


func test_classic_restore_fog_depth_begin() -> void:
	var main := await _boot_with_scenario()
	var world := _world(main)

	# Swap generated then classic.
	world.call("set_village_mode", GameModes.GENERATED, _GEN_SEED)
	world.call("rebuild_backdrop")
	await get_tree().process_frame

	world.call("set_village_mode", GameModes.CLASSIC, 0)
	world.call("rebuild_backdrop")
	await get_tree().process_frame

	var fog := _fog_depth_begin(world)
	assert_almost_eq(fog, 9.5, 0.01,
		"fog_depth_begin must restore to 9.5 after classic swap (AR-VG-DECIDE §2 restore proof)")


# ── (c) Round-trip: fog restores correctly ────────────────────────────────────

func test_round_trip_fog_restore() -> void:
	var main := await _boot_with_scenario()
	var world := _world(main)

	# Classic → Generated.
	world.call("set_village_mode", GameModes.GENERATED, _GEN_SEED)
	world.call("rebuild_backdrop")
	await get_tree().process_frame
	var fog_gen := _fog_depth_begin(world)

	# Generated → Classic.
	world.call("set_village_mode", GameModes.CLASSIC, 0)
	world.call("rebuild_backdrop")
	await get_tree().process_frame
	var fog_classic := _fog_depth_begin(world)

	assert_almost_eq(fog_gen, 14.0, 0.01,
		"Generated fog_depth_begin must be 14.0")
	assert_almost_eq(fog_classic, 9.5, 0.01,
		"Classic fog_depth_begin must restore to 9.5 (no stale 14.0)")


# ── (d) Exactly one backdrop after each swap ──────────────────────────────────

func test_no_duplicate_backdrops_after_round_trip() -> void:
	var main := await _boot_with_scenario()
	var world := _world(main)

	world.call("set_village_mode", GameModes.GENERATED, _GEN_SEED)
	world.call("rebuild_backdrop")
	await get_tree().process_frame
	var count_gen := _count_backdrop_children(world)

	world.call("set_village_mode", GameModes.CLASSIC, 0)
	world.call("rebuild_backdrop")
	await get_tree().process_frame
	var count_classic := _count_backdrop_children(world)

	assert_eq(count_gen, 1,
		"Exactly one VillageBackdrop after generated swap; found %d" % count_gen)
	assert_eq(count_classic, 1,
		"Exactly one VillageBackdrop after classic restore; found %d" % count_classic)
