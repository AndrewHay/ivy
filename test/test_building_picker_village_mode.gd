## Tests for BuildingPicker village-mode toggle (ivy-80z S5).
##
## (a) Picker has a node named "VillageModeToggle" (stable name for tooling).
## (b) Default state is classic (toggle OFF).
## (c) Toggle ON emits village_mode_changed("generated_village").
## (d) Toggle OFF emits village_mode_changed("classic_village").
## (e) init_village_mode(GENERATED) pre-sets toggle ON without emitting.
## (f) building_selected / _on_entry_pressed contract unchanged.
## (g) set_village_seed updates the hint label text.
## (h) Picker has a "VillageSeedReroll" node (deviation button).
extends GutTest

const BuildingPicker = preload("res://src/ui/building_picker.gd")
const GameModes = preload("res://src/world/game_modes.gd")


# ── helpers ──────────────────────────────────────────────────────────────────

func _make_picker(mode: String = GameModes.CLASSIC) -> Control:
	var picker := BuildingPicker.new()
	picker.init_village_mode(mode)
	add_child_autofree(picker)
	return picker


func _get_toggle(picker: Control) -> CheckButton:
	return picker.find_child("VillageModeToggle", true, false) as CheckButton


# ── (a) Node exists ───────────────────────────────────────────────────────────

func test_picker_has_village_mode_toggle() -> void:
	var picker := _make_picker()
	await get_tree().process_frame
	var toggle := _get_toggle(picker)
	assert_not_null(toggle, "Picker must have a child named 'VillageModeToggle'")


# ── (b) Default classic ───────────────────────────────────────────────────────

func test_picker_default_mode_is_classic() -> void:
	var picker := _make_picker()
	await get_tree().process_frame
	var toggle := _get_toggle(picker)
	assert_not_null(toggle)
	assert_false(toggle.button_pressed, "Toggle must default to OFF (classic mode)")


# ── (c) Toggle ON emits generated ────────────────────────────────────────────

func test_toggle_on_emits_generated_village() -> void:
	var picker := _make_picker()
	await get_tree().process_frame
	var emitted: Array[String] = []
	picker.village_mode_changed.connect(func(id: String) -> void: emitted.append(id))
	var toggle := _get_toggle(picker)
	toggle.button_pressed = true
	assert_eq(emitted.size(), 1, "Toggle ON must emit village_mode_changed once")
	assert_eq(emitted[0], GameModes.GENERATED, "Toggle ON must emit 'generated_village'")


# ── (d) Toggle OFF emits classic ─────────────────────────────────────────────

func test_toggle_off_emits_classic_village() -> void:
	var picker := _make_picker()
	await get_tree().process_frame
	var emitted: Array[String] = []
	picker.village_mode_changed.connect(func(id: String) -> void: emitted.append(id))
	var toggle := _get_toggle(picker)
	# Turn on first (no-signal so we can test the OFF direction cleanly).
	toggle.set_pressed_no_signal(true)
	toggle.button_pressed = false
	assert_eq(emitted.size(), 1, "Toggle OFF must emit village_mode_changed once")
	assert_eq(emitted[0], GameModes.CLASSIC, "Toggle OFF must emit 'classic_village'")


# ── (e) init_village_mode sets toggle without emitting ────────────────────────

func test_init_generated_sets_toggle_on() -> void:
	var picker := _make_picker(GameModes.GENERATED)
	await get_tree().process_frame
	var toggle := _get_toggle(picker)
	assert_true(toggle.button_pressed, "init_village_mode(GENERATED) must show toggle ON")


func test_init_village_mode_does_not_emit() -> void:
	var picker := BuildingPicker.new()
	# Connect BEFORE add_child so we'd catch any init-time emission.
	var emitted: Array[String] = []
	picker.village_mode_changed.connect(func(id: String) -> void: emitted.append(id))
	picker.init_village_mode(GameModes.GENERATED)
	add_child_autofree(picker)
	await get_tree().process_frame
	assert_eq(emitted.size(), 0, "init_village_mode must not emit village_mode_changed")


# ── (f) building_selected / _on_entry_pressed unchanged ──────────────────────

func test_building_selected_fires_with_id() -> void:
	var picker := _make_picker()
	await get_tree().process_frame
	var ids: Array[String] = []
	picker.building_selected.connect(func(id: String) -> void: ids.append(id))
	picker._on_entry_pressed("cylinder")
	assert_eq(ids.size(), 1, "building_selected must emit exactly once")
	assert_eq(ids[0], "cylinder", "building_selected must carry the building id")


func test_on_entry_pressed_does_not_emit_village_mode() -> void:
	var picker := _make_picker()
	await get_tree().process_frame
	var modes: Array[String] = []
	picker.village_mode_changed.connect(func(id: String) -> void: modes.append(id))
	picker._on_entry_pressed("cylinder")
	assert_eq(modes.size(), 0, "_on_entry_pressed must not emit village_mode_changed")


# ── (g) set_village_seed updates label ────────────────────────────────────────

func test_set_village_seed_shows_seed_in_hint() -> void:
	var picker := _make_picker(GameModes.GENERATED)
	await get_tree().process_frame
	picker.set_village_seed(99999)
	var hint := picker.find_child("VillageSeedHint", true, false) as Label
	assert_not_null(hint, "Picker must have a Label named 'VillageSeedHint'")
	assert_true(hint.text.contains("99999"),
		"Seed hint label must contain the seed value (%s)" % hint.text)


# ── (h) Re-roll button present (deviation) ────────────────────────────────────

func test_picker_has_reroll_button() -> void:
	var picker := _make_picker()
	await get_tree().process_frame
	var btn := picker.find_child("VillageSeedReroll", true, false)
	assert_not_null(btn, "Picker must have a child named 'VillageSeedReroll'")


func test_reroll_emits_generated_village() -> void:
	var picker := _make_picker(GameModes.GENERATED)
	await get_tree().process_frame
	var emitted: Array[String] = []
	picker.village_mode_changed.connect(func(id: String) -> void: emitted.append(id))
	var btn := picker.find_child("VillageSeedReroll", true, false) as Button
	assert_not_null(btn)
	btn.emit_signal("pressed")
	assert_eq(emitted.size(), 1, "Re-roll must emit village_mode_changed once")
	assert_eq(emitted[0], GameModes.GENERATED, "Re-roll must emit 'generated_village'")
