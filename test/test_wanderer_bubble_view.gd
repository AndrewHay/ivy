extends GutTest

const WandererBubbleView = preload("res://src/presentation/wanderer/wanderer_bubble_view.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")


func _label() -> Label3D:
	var p := WandererParams.production()
	var lbl := Label3D.new()
	lbl.font_size = p.bubble_font_size
	lbl.pixel_size = p.bubble_pixel_size
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return lbl


func test_panel_covers_text_width_and_height_aligned() -> void:
	var lbl := _label()
	lbl.position = Vector3(0.0, 2.35, 0.0)
	var text := "A door, a pause, a thought."
	var lay := WandererBubbleView.layout_for(lbl, text)
	assert_gte(lay["panel_width_m"], lay["text_width_m"])
	assert_almost_eq(lay["panel_center_y"], lay["text_center_y"], 0.15)


func test_sync_reuses_texture_same_text() -> void:
	var lbl := _label()
	lbl.position = Vector3(0.0, 2.35, 0.0)
	var panel := Sprite3D.new()
	var text := "Same words twice."
	WandererBubbleView.sync(panel, lbl, text, 1.0)
	var tex_a := panel.texture
	WandererBubbleView.sync(panel, lbl, text, 0.8)
	assert_same(tex_a, panel.texture)
