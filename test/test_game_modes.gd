## Tests for GameModes catalog (ivy-80z S4).
##
## (a) all() returns exactly two entries in the correct order.
## (b) Entry fields: ids, labels, scene paths, is_generated flags.
## (c) by_id() resolves both known ids and falls back to CLASSIC for unknown ids.
extends GutTest

const GameModes = preload("res://src/world/game_modes.gd")


# ── (a) Entry count ───────────────────────────────────────────────────────────

func test_all_returns_two_entries() -> void:
	var modes := GameModes.all()
	assert_eq(modes.size(), 2, "GameModes.all() must return exactly 2 entries")


# ── (b) Entry fields ──────────────────────────────────────────────────────────

func test_classic_entry() -> void:
	var modes := GameModes.all()
	var classic := modes[0]
	assert_eq(classic.id, GameModes.CLASSIC,
		"First entry id must be CLASSIC")
	assert_false(classic.label.is_empty(),
		"Classic label must not be empty")
	assert_eq(classic.backdrop_scene_path, "res://src/world/village_backdrop.tscn",
		"Classic backdrop_scene_path must point to village_backdrop.tscn")
	assert_false(classic.is_generated,
		"Classic is_generated must be false")


func test_generated_entry() -> void:
	var modes := GameModes.all()
	var gen := modes[1]
	assert_eq(gen.id, GameModes.GENERATED,
		"Second entry id must be GENERATED")
	assert_false(gen.label.is_empty(),
		"Generated label must not be empty")
	assert_eq(gen.backdrop_scene_path, "res://src/world/generated_village_backdrop.tscn",
		"Generated backdrop_scene_path must point to generated_village_backdrop.tscn")
	assert_true(gen.is_generated,
		"Generated is_generated must be true")


func test_constants_match_expected_strings() -> void:
	assert_eq(GameModes.CLASSIC, "classic_village",
		"CLASSIC constant must equal 'classic_village'")
	assert_eq(GameModes.GENERATED, "generated_village",
		"GENERATED constant must equal 'generated_village'")


# ── (c) by_id() ──────────────────────────────────────────────────────────────

func test_by_id_classic() -> void:
	var mode := GameModes.by_id(GameModes.CLASSIC)
	assert_not_null(mode, "by_id(CLASSIC) must not return null")
	assert_eq(mode.id, GameModes.CLASSIC,
		"by_id(CLASSIC) must return the classic entry")


func test_by_id_generated() -> void:
	var mode := GameModes.by_id(GameModes.GENERATED)
	assert_not_null(mode, "by_id(GENERATED) must not return null")
	assert_eq(mode.id, GameModes.GENERATED,
		"by_id(GENERATED) must return the generated entry")


func test_by_id_unknown_falls_back_to_classic() -> void:
	var mode := GameModes.by_id("nonexistent_mode_id")
	assert_not_null(mode, "by_id(unknown) must not return null")
	assert_eq(mode.id, GameModes.CLASSIC,
		"by_id(unknown id) must fall back to CLASSIC")


func test_scene_paths_are_loadable() -> void:
	for mode in GameModes.all():
		var scene := load(mode.backdrop_scene_path)
		assert_not_null(scene,
			"Scene '%s' must be loadable for mode '%s'" \
			% [mode.backdrop_scene_path, mode.id])
