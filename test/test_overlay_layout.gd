## Full-screen overlays must actually fill the screen (ivy-yds).
##
## `set_anchors_preset(PRESET_FULL_RECT)` on a Control under a CanvasLayer leaves it
## zero-sized, so the building picker's menu hugged the top-left corner and its dark backdrop
## never covered the scene. These tests fail on that, and pass once the offsets are set too.
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const LoadingOverlayScript = preload("res://src/ui/loading_overlay.gd")


func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## First descendant of the given class, depth-first.
func _first(root: Node, cls: String) -> Node:
	for child in root.get_children():
		if child.is_class(cls):
			return child
		var deeper := _first(child, cls)
		if deeper != null:
			return deeper
	return null


func _assert_fills_viewport(c: Control, what: String) -> void:
	var vp := _viewport_size()
	assert_almost_eq(c.size.x, vp.x, 1.5, "%s must be as wide as the viewport" % what)
	assert_almost_eq(c.size.y, vp.y, 1.5, "%s must be as tall as the viewport" % what)


func _assert_centred(c: Control, what: String) -> void:
	var vp := _viewport_size()
	var centre: Vector2 = c.get_global_rect().get_center()
	assert_almost_eq(centre.x, vp.x * 0.5, 2.0, "%s must be horizontally centred" % what)
	assert_almost_eq(centre.y, vp.y * 0.5, 2.0, "%s must be vertically centred" % what)


func _picker() -> Control:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	await get_tree().process_frame
	return main.get_node("UI/BuildingPicker")


func test_picker_fills_the_viewport() -> void:
	var picker := await _picker()
	_assert_fills_viewport(picker, "the picker")
	_assert_fills_viewport(_first(picker, "ColorRect"), "the picker's dark backdrop")


## Same reason as the failure screen's Back button: default buttons vanish into the backdrop.
func test_picker_buttons_stand_out_from_the_backdrop() -> void:
	var picker := await _picker()
	var checked := 0
	var stack: Array = [picker]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			checked += 1
			var style := (n as Button).get_theme_stylebox("normal") as StyleBoxFlat
			assert_not_null(style, "%s needs its own StyleBoxFlat" % (n as Button).text)
			if style != null:
				assert_gte(style.bg_color.get_luminance(), 0.15,
					"%s must stand out from the dark backdrop" % (n as Button).text)
		stack.append_array(n.get_children())
	assert_gt(checked, 0, "precondition: the picker has building buttons")


func test_picker_menu_is_centred() -> void:
	var picker := await _picker()
	_assert_centred(_first(picker, "VBoxContainer"), "the picker menu")


func _loading_overlay() -> Control:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var overlay := LoadingOverlayScript.new()
	layer.add_child(overlay)
	overlay.set_progress("Loading building…", 0.3)
	await get_tree().process_frame
	await get_tree().process_frame
	return overlay


func test_loading_overlay_fills_the_viewport() -> void:
	var overlay := await _loading_overlay()
	_assert_fills_viewport(overlay, "the loading overlay")
	_assert_fills_viewport(_first(overlay, "ColorRect"), "the loading overlay's backdrop")


func test_loading_progress_is_centred() -> void:
	var overlay := await _loading_overlay()
	_assert_centred(_first(overlay, "VBoxContainer"), "the loading progress")
