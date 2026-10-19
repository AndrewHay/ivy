## The "?" keyboard-commands popup (ivy-6hh).
##
## The content test is a drift guard: the popup is only useful while it matches the real
## bindings, so it checks the rows against the handlers that actually implement them.
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const HelpPanelScript = preload("res://src/ui/help_panel.gd")
const SimClock = preload("res://src/core/sim_clock.gd")


## Every key and action string in the popup, one line per row, for substring checks.
func _text(dev_build: bool) -> String:
	var lines: PackedStringArray = []
	for section in HelpPanelScript.sections(dev_build):
		lines.append(section.title)
		for row in section.rows:
			lines.append("%s | %s" % [row[0], row[1]])
	return "\n".join(lines)


func test_lists_camera_time_and_interface_commands() -> void:
	var text := _text(false)
	for needle in ["Camera", "Time", "Interface", "Arrow keys", "W / S", "Home", "Space", "1 / 2 / 3", "F1", "Esc"]:
		assert_string_contains(text, needle, "help must mention '%s'" % needle)


## Dev-only keys exist only when dev_build is on, and a player build must not advertise them.
func test_dev_keys_listed_only_in_dev_builds() -> void:
	assert_false(_text(false).contains("`"), "player build must not list the dev panel key")
	assert_string_contains(_text(true), "`")
	assert_string_contains(_text(true), "Field")


## The speed rows must describe the speeds the number keys really select.
func test_time_rows_match_the_real_hotkeys() -> void:
	assert_eq(SimClock.speed_for_hotkey(KEY_1), SimClock.Speed.WATCH)
	assert_eq(SimClock.speed_for_hotkey(KEY_2), SimClock.Speed.FAST)
	assert_eq(SimClock.speed_for_hotkey(KEY_3), SimClock.Speed.GROW)
	assert_string_contains(_text(false), "Watch / Fast / Grow")


func test_every_row_has_a_key_and_an_action() -> void:
	for section in HelpPanelScript.sections(true):
		assert_gt(section.rows.size(), 0, "section '%s' is empty" % section.title)
		for row in section.rows:
			assert_false(String(row[0]).strip_edges().is_empty(), "blank key in %s" % section.title)
			assert_false(String(row[1]).strip_edges().is_empty(), "blank action in %s" % section.title)


# ── in the real HUD ─────────────────────────────────────────────────────────

func _boot() -> Node:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	main.get_node("UI/BuildingPicker")._on_entry_pressed("cylinder")
	for _i in range(900):
		if main._hud != null:
			break
		await get_tree().process_frame
	await get_tree().process_frame
	return main


func _key(main: Node, keycode: Key, unicode: int = 0) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = keycode
	ev.unicode = unicode
	main._unhandled_input(ev)


func _find_button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func test_help_starts_closed() -> void:
	var main: Node = await _boot()
	assert_false(main._hud.is_help_open())


## "?" is Shift+/ — Godot reports keycode SLASH with unicode 63, so match on the character.
func test_question_mark_key_toggles_help() -> void:
	var main: Node = await _boot()
	_key(main, KEY_SLASH, 63)
	assert_true(main._hud.is_help_open(), "? must open the help")
	_key(main, KEY_SLASH, 63)
	assert_false(main._hud.is_help_open(), "? again must close it")


func test_f1_toggles_help_and_escape_closes_it() -> void:
	var main: Node = await _boot()
	_key(main, KEY_F1)
	assert_true(main._hud.is_help_open())
	_key(main, KEY_ESCAPE)
	assert_false(main._hud.is_help_open(), "Esc must close the help")
	_key(main, KEY_ESCAPE)
	assert_false(main._hud.is_help_open(), "Esc with the help closed must do nothing")


func test_question_mark_button_toggles_help() -> void:
	var main: Node = await _boot()
	var btn := _find_button(main.get_node("UI"), "?")
	assert_not_null(btn, "HUD must have a ? button")
	btn.pressed.emit()
	assert_true(main._hud.is_help_open())
	btn.pressed.emit()
	assert_false(main._hud.is_help_open())


## The popup is most needed before the first plant, when the player is still aiming and the
## time hotkeys are inert, so it must not depend on having planted.
func test_help_works_while_aiming_before_planting() -> void:
	var main: Node = await _boot()
	assert_not_null(main._planting_tool, "precondition: still aiming")
	_key(main, KEY_SLASH, 63)
	assert_true(main._hud.is_help_open())


## While the popup is up the "?" key must not also trigger something else, such as the
## number-key speed change or a camera move.
func test_opening_help_does_not_change_speed() -> void:
	var main: Node = await _boot()
	var clock: SimClock = main._sim.get_clock()
	var before := clock.speed
	_key(main, KEY_SLASH, 63)
	assert_eq(clock.speed, before)


## It is a popup, not a corner widget: it opens centred over the scene. (A full-rect Control
## under a CanvasLayer is not sized by anchors alone here, so centring is done explicitly.)
func test_popup_opens_centred_in_the_viewport() -> void:
	var main: Node = await _boot()
	_key(main, KEY_F1)
	await get_tree().process_frame
	var panel: Control = main._hud.get_help_panel()
	var viewport_size: Vector2 = main._hud.get_viewport_rect().size
	assert_gt(panel.size.x, 100.0, "the popup must have real size, not 0x0")
	var centre: Vector2 = panel.position + panel.size * 0.5
	assert_almost_eq(centre.x, viewport_size.x * 0.5, 1.5, "horizontally centred")
	assert_almost_eq(centre.y, viewport_size.y * 0.5, 1.5, "vertically centred")


## It sits over the scene, so it must be readable: nearly opaque, not the theme's see-through grey.
func test_popup_background_is_nearly_opaque() -> void:
	var main: Node = await _boot()
	var style := main._hud.get_help_panel().get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(style, "the popup needs its own StyleBoxFlat background")
	assert_gte(style.bg_color.a, 0.9, "background must be nearly opaque")


## A click on the popup must not fall through and plant ivy behind it.
func test_popup_blocks_mouse_clicks() -> void:
	var main: Node = await _boot()
	_key(main, KEY_F1)
	assert_eq(main._hud.get_help_panel().mouse_filter, Control.MOUSE_FILTER_STOP)


func test_returning_to_the_picker_closes_the_help() -> void:
	var main: Node = await _boot()
	_key(main, KEY_F1)
	main.return_to_picker()
	await get_tree().process_frame
	assert_null(main.get_node("UI").get_node_or_null("Hud"), "HUD, and its popup, are gone")
