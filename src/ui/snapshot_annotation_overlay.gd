class_name SnapshotAnnotationOverlay
extends Control

## Frozen-frame highlight UI during debug snapshot save (AR-SNAP-6).

signal completed(annotations: Array, note: String)
signal cancelled()

enum Tool { BOX, MARKER }

const _Model = preload("res://src/debug/snapshot_annotation_model.gd")

var _model := _Model.new()
var _tool: Tool = Tool.BOX
var _viewport_size: Vector2 = Vector2.ONE
var _dragging := false
var _drag_start: Vector2
var _draft_rect: Rect2
var _draft_stroke: PackedVector2Array = PackedVector2Array()
var _note_field: LineEdit
var _comment_field: LineEdit
var _background: TextureRect
var _hint_label: Label
var _discard_armed := false


func setup(
	frozen_image: Image,
	viewport_size: Vector2,
	seed_norm_boxes: Array = []
) -> void:
	_viewport_size = viewport_size
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_size(viewport_size)
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	var tex := ImageTexture.create_from_image(frozen_image)
	_background = TextureRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.texture = tex
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	for item in seed_norm_boxes:
		if item is Rect2:
			_model.add_box(item, "highlight")
	_build_chrome()
	set_process_unhandled_input(true)
	call_deferred("_grab_ui_focus")


func is_active() -> bool:
	return is_inside_tree()


func _build_chrome() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -120
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	bar.add_child(margin)
	var col := VBoxContainer.new()
	margin.add_child(col)
	_hint_label = Label.new()
	_hint_label.text = "Box (B) · Marker (M) · Undo Ctrl+Z · Enter save · Esc cancel"
	col.add_child(_hint_label)
	_note_field = LineEdit.new()
	_note_field.placeholder_text = "Note for this snapshot"
	col.add_child(_note_field)
	_comment_field = LineEdit.new()
	_comment_field.placeholder_text = "Comment for the next highlight"
	col.add_child(_comment_field)
	var row := HBoxContainer.new()
	var save_btn := Button.new()
	save_btn.text = "Save snapshot"
	save_btn.pressed.connect(_on_save_pressed)
	row.add_child(save_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel_btn)
	col.add_child(row)
	add_child(bar)


func _draw() -> void:
	for entry in _model.to_array():
		_draw_entry(entry)
	if _dragging and _tool == Tool.BOX and _draft_rect.size.length_squared() > 1.0:
		_draw_norm_rect(_draft_rect, _model.entry_count() + 1)
	elif _draft_stroke.size() > 1:
		_draw_stroke_pixels(_pixel_points_from_norm_stroke(_draft_stroke), _model.entry_count() + 1)


func _draw_entry(entry: Dictionary) -> void:
	var id: int = int(entry.get("id", 0))
	match str(entry.get("kind", "")):
		"box":
			_draw_norm_rect(_Model.dict_to_norm_rect(entry.get("rect", {})), id)
		"stroke":
			var pts := PackedVector2Array()
			for item in entry.get("points", []):
				if item is Array and item.size() >= 2:
					pts.append(_Model.denorm_point(Vector2(float(item[0]), float(item[1])), _viewport_size))
			_draw_stroke_pixels(pts, id)


func _draw_norm_rect(norm: Rect2, badge_id: int) -> void:
	var rect := _Model.pixel_rect_from_norm(norm, _viewport_size)
	var fill := _Model.HIGHLIGHT
	draw_rect(rect, fill, true)
	draw_rect(rect, Color(fill.r, fill.g, fill.b, 0.95), false, 2.0)
	_draw_badge(rect.position + Vector2(4, 4), badge_id)


func _draw_stroke_pixels(points: PackedVector2Array, badge_id: int) -> void:
	if points.is_empty():
		return
	for i in range(1, points.size()):
		draw_line(points[i - 1], points[i], Color(1.0, 0.2, 0.75, 0.9), _Model.STROKE_WIDTH_PX, true)
	_draw_badge(points[0] + Vector2(4, 4), badge_id)


func _draw_badge(at: Vector2, id: int) -> void:
	var text := str(id)
	var font := ThemeDB.fallback_font
	var size := 16
	var ext := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var bg := Rect2(at, ext + Vector2(8, 4))
	draw_rect(bg, Color(0.05, 0.05, 0.08, 0.85))
	draw_string(font, at + Vector2(4, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


func _grab_ui_focus() -> void:
	if _note_field != null:
		_note_field.grab_focus()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_handle_overlay_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_overlay_input(event)


func _handle_overlay_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_B:
			_tool = Tool.BOX
			accept_event()
			return
		if key.keycode == KEY_M:
			_tool = Tool.MARKER
			accept_event()
			return
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			_on_save_pressed()
			accept_event()
			return
		if key.keycode == KEY_ESCAPE:
			_on_cancel_pressed()
			accept_event()
			return
		if key.keycode == KEY_Z and (key.ctrl_pressed or key.meta_pressed):
			_model.undo()
			queue_redraw()
			accept_event()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if _tool == Tool.BOX:
			if mb.pressed:
				_dragging = true
				_drag_start = mb.position
				_draft_rect = Rect2()
			else:
				_dragging = false
				var end := mb.position
				var px := Rect2(_drag_start, end - _drag_start).abs()
				if px.size.x > 4.0 and px.size.y > 4.0:
					_commit_box(px)
				_draft_rect = Rect2()
			queue_redraw()
			accept_event()
		elif _tool == Tool.MARKER:
			if mb.pressed:
				_draft_stroke = PackedVector2Array([mb.position])
			else:
				if _draft_stroke.size() > 1:
					_commit_stroke(_draft_stroke)
				_draft_stroke = PackedVector2Array()
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _tool == Tool.MARKER:
		if _draft_stroke.size() > 0:
			_draft_stroke.append((event as InputEventMouseMotion).position)
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _tool == Tool.BOX and _dragging:
		var mm := event as InputEventMouseMotion
		_draft_rect = _Model.norm_rect_from_pixels(Rect2(_drag_start, mm.position - _drag_start).abs(), _viewport_size)
		queue_redraw()
		accept_event()


func _commit_box(pixel_rect: Rect2) -> void:
	var comment := _take_comment()
	_model.add_box(_Model.norm_rect_from_pixels(pixel_rect, _viewport_size), comment)


func _commit_stroke(pixel_points: PackedVector2Array) -> void:
	var norm_pts := PackedVector2Array()
	for p in pixel_points:
		norm_pts.append(_Model.norm_point(p, _viewport_size))
	var comment := _take_comment()
	_model.add_stroke(norm_pts, comment)


func _pixel_points_from_norm_stroke(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(_Model.denorm_point(p, _viewport_size))
	return out


func _take_comment() -> String:
	var t := _comment_field.text.strip_edges()
	_comment_field.text = ""
	return t


func request_cancel() -> void:
	_on_cancel_pressed()


func _on_save_pressed() -> void:
	completed.emit(_model.to_array(), _note_field.text.strip_edges())


func _on_cancel_pressed() -> void:
	if _model.entry_count() > 0 and not _discard_armed:
		_discard_armed = true
		_hint_label.text = "Esc again to discard highlights (nothing will be saved)"
		return
	cancelled.emit()


func render_annotated_image(base: Image) -> Image:
	var out := base.duplicate()
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	# Burn highlights by drawing into a scratch viewport-sized image via CPU rects.
	for entry in _model.to_array():
		match str(entry.get("kind", "")):
			"box":
				var norm := _Model.dict_to_norm_rect(entry.get("rect", {}))
				var rect := _Model.pixel_rect_from_norm(norm, _viewport_size)
				var scale := Vector2(float(out.get_width()) / _viewport_size.x,
					float(out.get_height()) / _viewport_size.y)
				var img_rect := Rect2i(
					int(rect.position.x * scale.x),
					int(rect.position.y * scale.y),
					int(rect.size.x * scale.x),
					int(rect.size.y * scale.y)
				)
				out.fill_rect(img_rect, _Model.HIGHLIGHT)
	return out
