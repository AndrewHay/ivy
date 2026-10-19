## A building that fails to load must not strand the player on a dead-end screen (ivy-yk8).
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const LoadingOverlayScript = preload("res://src/ui/loading_overlay.gd")


func _find_button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func test_failure_overlay_offers_a_back_button_and_hides_the_progress_bar() -> void:
	var overlay := LoadingOverlayScript.new()
	add_child_autofree(overlay)
	overlay.set_progress("Loading…", 0.4)
	overlay.show_failure("Something went wrong")
	var btn := _find_button(overlay, "Back to buildings")
	assert_not_null(btn, "the failure screen must have a way out")
	assert_false(overlay._bar.visible, "a progress bar on a failed load is misleading")
	assert_string_contains(overlay._label.text, "Something went wrong")


## The overlay backdrop is nearly black, so the default dark-grey button vanished into it:
## a way out you cannot see is not a way out.
func test_back_button_is_visible_against_the_dark_backdrop() -> void:
	var overlay := LoadingOverlayScript.new()
	add_child_autofree(overlay)
	overlay.show_failure("x")
	var btn := _find_button(overlay, "Back to buildings")
	for state in ["normal", "hover", "pressed"]:
		var style := btn.get_theme_stylebox(state) as StyleBoxFlat
		assert_not_null(style, "%s state needs its own StyleBoxFlat" % state)
		assert_gte(style.bg_color.get_luminance(), 0.15,
			"%s state must stand out from the ~0.07 luminance backdrop" % state)


func test_back_button_signals_the_overlay_owner() -> void:
	var overlay := LoadingOverlayScript.new()
	add_child_autofree(overlay)
	overlay.show_failure("x")
	watch_signals(overlay)
	_find_button(overlay, "Back to buildings").pressed.emit()
	assert_signal_emitted(overlay, "back_requested")


## The path Main takes when a session fails to build: back goes to the picker, the failure
## overlay goes away, and the authored camera is the one on screen.
func test_main_back_from_failure_shows_the_picker_again() -> void:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	main.get_node("UI/BuildingPicker").queue_free()  # as if a building had been picked
	await get_tree().process_frame

	main._show_build_failure()
	var ui: Node = main.get_node("UI")
	var btn := _find_button(ui, "Back to buildings")
	assert_not_null(btn, "Main must show the failure overlay with a Back button")
	btn.pressed.emit()
	await get_tree().process_frame

	assert_not_null(ui.get_node_or_null("BuildingPicker"), "back must bring the picker back")
	assert_null(_find_button(ui, "Back to buildings"), "the failure overlay must be gone")
	assert_true(main.get_node("World/CameraRig/CamSun").current)
