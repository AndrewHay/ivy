class_name BuildingPicker
extends Control

signal building_selected(building_id: String)
## Emitted when the player changes the village mode via the toggle.
## mode_id is one of GameModes.CLASSIC / GameModes.GENERATED.
## Main is responsible for rolling a new seed on GENERATED and calling set_village_seed().
signal village_mode_changed(mode_id: String)

const BuildingCatalog = preload("res://src/world/building_catalog.gd")
const GameModes = preload("res://src/world/game_modes.gd")
const _OverlayStyle = preload("res://src/ui/overlay_style.gd")

## Set via init_village_mode() before add_child so _ready picks it up without emitting.
var _init_mode: String = GameModes.CLASSIC
## The seed shown in the hint label (set by Main after rolling; does not affect generation).
var _displayed_seed: int = 0

## Stable-named node references populated in _ready.
var _toggle: CheckButton = null
var _seed_hint: Label = null
var _reroll_btn: Button = null


## Call before add_child to restore persisted mode across return_to_picker.
## Does NOT emit village_mode_changed.
func init_village_mode(mode_id: String) -> void:
	_init_mode = mode_id


## Called by Main after rolling a new seed so the hint label stays accurate.
func set_village_seed(seed: int) -> void:
	_displayed_seed = seed
	_update_seed_ui()


func _ready() -> void:
	# _ready runs once we are already in the tree, where set_anchors_preset alone leaves the
	# offsets untouched and the control zero-sized (menu stuck top-left, no backdrop). The
	# *_and_offsets_ form sets both, so it works whenever it is called.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.05, 0.07, 0.09, 0.92)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 14)
	center.add_child(panel)

	var title := Label.new()
	title.text = "Choose a scenario"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Then click the glowing cursor to plant ivy at the base."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(subtitle)

	# ── Village-mode toggle (AR-VG-WIRE S5) ──────────────────────────────────
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	panel.add_child(mode_row)

	_toggle = CheckButton.new()
	_toggle.name = "VillageModeToggle"
	_toggle.text = "Generated village"
	_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(_toggle)

	_reroll_btn = Button.new()
	_reroll_btn.name = "VillageSeedReroll"
	_reroll_btn.text = "Re-roll"
	_reroll_btn.custom_minimum_size = Vector2(80, 0)
	_OverlayStyle.style_button(_reroll_btn)
	mode_row.add_child(_reroll_btn)

	_seed_hint = Label.new()
	_seed_hint.name = "VillageSeedHint"
	_seed_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_seed_hint.add_theme_font_size_override("font_size", 11)
	_seed_hint.modulate = Color(0.75, 0.85, 0.80)
	panel.add_child(_seed_hint)

	# Restore persisted toggle state without emitting.
	_toggle.set_pressed_no_signal(_init_mode == GameModes.GENERATED)
	_update_seed_ui()

	_toggle.toggled.connect(_on_toggle_toggled)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	# ─────────────────────────────────────────────────────────────────────────

	for entry in BuildingCatalog.all():
		var btn := Button.new()
		btn.text = entry.label
		btn.custom_minimum_size = Vector2(280, 48)
		_OverlayStyle.style_button(btn)
		btn.pressed.connect(_on_entry_pressed.bind(entry.id))
		panel.add_child(btn)


func _on_toggle_toggled(pressed: bool) -> void:
	var mode_id := GameModes.GENERATED if pressed else GameModes.CLASSIC
	_update_seed_ui()
	village_mode_changed.emit(mode_id)


## Deviation (noted in S5 handoff): Re-roll emits village_mode_changed(GENERATED) again
## so Main rolls a fresh seed and calls set_village_seed(). Purely a dev/QA convenience.
func _on_reroll_pressed() -> void:
	village_mode_changed.emit(GameModes.GENERATED)


func _update_seed_ui() -> void:
	if _toggle == null or _seed_hint == null:
		return
	var generated := _toggle.button_pressed
	if _reroll_btn != null:
		_reroll_btn.visible = generated
	if generated:
		_seed_hint.visible = true
		_seed_hint.text = "Procedurally generated houses & paths — seed: %d" % _displayed_seed
	else:
		_seed_hint.visible = false
		_seed_hint.text = ""


func _on_entry_pressed(building_id: String) -> void:
	building_selected.emit(building_id)
	queue_free()
