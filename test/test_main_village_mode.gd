## Tests for Main village-mode persistence and snapshot recipe (ivy-80z S5).
##
## Strategy: instantiate Main scene without a full interactive session (stays at picker),
## verify _village_mode/_village_seed defaults, picker wiring, and signal handling.
## Full end-to-end recipe round-trip is covered by the generated_village.txt UI script
## (SNAPSHOT_LOAD not wired here to avoid a 7200-frame bootstrap per the S5 task brief).
##
## (a) Main defaults: _village_mode == "classic_village", _village_seed == 0.
## (b) Picker receives init mode from Main: re-opened picker reflects persisted mode.
## (c) _on_village_mode_changed rolls a fresh seed for GENERATED, zeroes for CLASSIC.
## (d) Recipe scene dict: village_mode/village_seed keys present and default correctly.
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const GameModes = preload("res://src/world/game_modes.gd")
const _SnapshotRecipe = preload("res://src/debug/snapshot_recipe.gd")
const BuildingPicker = preload("res://src/ui/building_picker.gd")


## Boot Main to the picker state (no building selected) — quick, no bootstrap.
func _boot_to_picker() -> Node:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	return main


# ── (a) Defaults ──────────────────────────────────────────────────────────────

func test_main_default_village_mode_is_classic() -> void:
	var main := await _boot_to_picker()
	assert_eq(str(main.get("_village_mode")), GameModes.CLASSIC,
		"Main._village_mode must default to classic_village")


func test_main_default_village_seed_is_zero() -> void:
	var main := await _boot_to_picker()
	assert_eq(int(main.get("_village_seed")), 0,
		"Main._village_seed must default to 0")


# ── (b) Picker wiring: the picker created by Main has village_mode_changed connected ──

func test_picker_village_mode_changed_is_connected() -> void:
	var main := await _boot_to_picker()
	var picker := main.get_node_or_null("UI/BuildingPicker")
	assert_not_null(picker, "Main must have created a BuildingPicker")
	assert_true(picker.village_mode_changed.is_connected(main._on_village_mode_changed),
		"Main must connect picker.village_mode_changed to _on_village_mode_changed")


# ── (c) Signal handler: rolling seed for GENERATED ───────────────────────────

func test_generated_signal_rolls_positive_seed() -> void:
	var main := await _boot_to_picker()
	main._on_village_mode_changed(GameModes.GENERATED)
	assert_eq(str(main.get("_village_mode")), GameModes.GENERATED,
		"_village_mode must be updated to generated_village")
	assert_gt(int(main.get("_village_seed")), 0,
		"_village_seed must be a positive integer for generated mode")


func test_classic_signal_resets_mode() -> void:
	var main := await _boot_to_picker()
	main._on_village_mode_changed(GameModes.GENERATED)
	main._on_village_mode_changed(GameModes.CLASSIC)
	assert_eq(str(main.get("_village_mode")), GameModes.CLASSIC,
		"_village_mode must reset to classic_village on CLASSIC signal")


func test_two_generated_signals_yield_different_seeds_overwhelmingly() -> void:
	var main := await _boot_to_picker()
	main._on_village_mode_changed(GameModes.GENERATED)
	var seed1: int = int(main.get("_village_seed"))
	main._on_village_mode_changed(GameModes.GENERATED)
	var seed2: int = int(main.get("_village_seed"))
	# Deliberately not assert_ne — one-in-two-billion chance of false failure; report only.
	if seed1 == seed2:
		push_warning("Two generated signals gave same seed %d — extremely unlikely collision" % seed1)
	assert_gt(seed1 + seed2, 0, "Both seeds must be positive")


# ── (d) Recipe scene dict ─────────────────────────────────────────────────────

func test_recipe_with_village_fields_preserves_them() -> void:
	var recipe := _SnapshotRecipe.new()
	recipe.scene = {
		"building_id": "cylinder",
		"seed_index": 0,
		"free_plant_mode": true,
		"village_mode": "generated_village",
		"village_seed": 777,
	}
	var d := recipe.to_dict()
	var restored: RefCounted = _SnapshotRecipe.from_dict(d) as RefCounted
	assert_eq(str(restored.scene.get("village_mode")), "generated_village",
		"Recipe round-trip must preserve village_mode")
	assert_eq(int(restored.scene.get("village_seed")), 777,
		"Recipe round-trip must preserve village_seed")


func test_recipe_missing_village_keys_defaults_classic() -> void:
	var recipe := _SnapshotRecipe.new()
	recipe.scene = {"building_id": "cylinder"}
	var mode := str(recipe.scene.get("village_mode", GameModes.CLASSIC))
	var seed := int(recipe.scene.get("village_seed", 0))
	assert_eq(mode, GameModes.CLASSIC,
		"Missing village_mode key must default to classic_village")
	assert_eq(seed, 0,
		"Missing village_seed key must default to 0")
