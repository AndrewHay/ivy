class_name WandererBubbleView
extends RefCounted

const PAD_PX := 24
const TAIL_PX := 32
const CORNER_R_PX := 18
const PAD_M := 0.08
const TAIL_M := 0.14
const META_TEX_KEY := "_wanderer_bubble_tex_key"
const META_TEX := "_wanderer_bubble_tex"


static func attach(parent: Node3D, label: Label3D) -> Dictionary:
	var panel := Sprite3D.new()
	panel.name = "BubblePanel"
	panel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	panel.fixed_size = false
	panel.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.sorting_offset = -2.0
	parent.add_child(panel)
	parent.move_child(panel, 0)
	return {"panel": panel, "label": label}


static func text_extent_m(label: Label3D, text: String) -> Vector2:
	var font := label.font
	if font == null:
		font = ThemeDB.fallback_font
	var px := label.font_size
	var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px)
	return Vector2(sz) * label.pixel_size


static func layout_for(label: Label3D, text: String) -> Dictionary:
	var ext := text_extent_m(label, text)
	var w_m := ext.x + PAD_M * 2.0
	var body_h := ext.y + PAD_M * 2.0
	var total_h := body_h + TAIL_M
	var anchor_y := label.position.y
	var text_center_y := anchor_y + ext.y * 0.5
	var panel_center_y := text_center_y - TAIL_M * 0.5
	return {
		"text_width_m": ext.x,
		"text_center_y": text_center_y,
		"panel_width_m": w_m,
		"panel_height_m": total_h,
		"panel_center_y": panel_center_y,
		"body_height_m": body_h,
	}


static func sync(panel: Sprite3D, label: Label3D, text: String, alpha: float) -> void:
	if panel == null:
		return
	if text.is_empty() or alpha <= 0.001:
		panel.visible = false
		return
	panel.visible = true
	var lay := layout_for(label, text)
	var tex_key := "%s|%.5f|%.5f|%.5f" % [
		text, lay["panel_width_m"], lay["panel_height_m"], lay["body_height_m"]]
	var tex: Texture2D = panel.get_meta(META_TEX) if panel.has_meta(META_TEX) else null
	if not panel.has_meta(META_TEX_KEY) or String(panel.get_meta(META_TEX_KEY)) != tex_key or tex == null:
		tex = _make_bubble_texture(lay["panel_width_m"], lay["panel_height_m"], lay["body_height_m"])
		panel.set_meta(META_TEX_KEY, tex_key)
		panel.set_meta(META_TEX, tex)
	panel.texture = tex
	panel.modulate = Color(1, 1, 1, clampf(alpha, 0.0, 1.0))
	panel.pixel_size = lay["panel_width_m"] / float(tex.get_width())
	panel.position = Vector3(
		label.position.x,
		lay["panel_center_y"],
		label.position.z + 0.01)
	panel.no_depth_test = true
	panel.render_priority = 0
	label.modulate = Color(0.12, 0.1, 0.08, clampf(alpha, 0.0, 1.0))
	label.outline_size = 0
	label.no_depth_test = true
	label.render_priority = 1
	label.sorting_offset = 2.0


static func _make_bubble_texture(panel_w_m: float, panel_h_m: float, body_h_m: float) -> ImageTexture:
	var scale := 512.0 / maxf(panel_w_m, 0.5)
	var tw := maxi(64, int(panel_w_m * scale))
	var th := maxi(64, int(panel_h_m * scale))
	var tail_px := maxi(8, int(TAIL_M * scale))
	var body_px := th - tail_px
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fill := Color(0.96, 0.94, 0.9, 0.92)
	var border := Color(0.35, 0.32, 0.3, 1.0)
	_fill_rounded_rect(img, Rect2i(PAD_PX / 2, PAD_PX / 2, tw - PAD_PX, body_px - PAD_PX), CORNER_R_PX, fill)
	_draw_border(img, tw, body_px, border)
	var cx := tw / 2
	_draw_tail(img, cx, body_px - 2, tail_px, fill)
	return ImageTexture.create_from_image(img)


static func _fill_rounded_rect(img: Image, r: Rect2i, radius: int, c: Color) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if _in_rounded_rect(x, y, r, radius):
				img.set_pixel(x, y, c)


static func _in_rounded_rect(x: int, y: int, r: Rect2i, radius: int) -> bool:
	if x < r.position.x + radius and y < r.position.y + radius:
		return Vector2(x, y).distance_to(Vector2(r.position.x + radius, r.position.y + radius)) <= radius
	if x >= r.position.x + r.size.x - radius and y < r.position.y + radius:
		return Vector2(x, y).distance_to(
			Vector2(r.position.x + r.size.x - radius - 1, r.position.y + radius)) <= radius
	if x < r.position.x + radius and y >= r.position.y + r.size.y - radius:
		return Vector2(x, y).distance_to(
			Vector2(r.position.x + radius, r.position.y + r.size.y - radius - 1)) <= radius
	if x >= r.position.x + r.size.x - radius and y >= r.position.y + r.size.y - radius:
		return Vector2(x, y).distance_to(Vector2(
			r.position.x + r.size.x - radius - 1, r.position.y + r.size.y - radius - 1)) <= radius
	return x >= r.position.x and x < r.position.x + r.size.x and y >= r.position.y and y < r.position.y + r.size.y


static func _draw_border(img: Image, w: int, body_h: int, c: Color) -> void:
	for x in range(w):
		img.set_pixel(x, 0, c)
		img.set_pixel(x, body_h - 1, c)
	for y in range(body_h):
		img.set_pixel(0, y, c)
		img.set_pixel(w - 1, y, c)


static func _draw_tail(img: Image, cx: int, top_y: int, tail_h: int, c: Color) -> void:
	for row in range(tail_h):
		var half := maxi(1, (tail_h - row) / 3)
		for dx in range(-half, half + 1):
			var x := cx + dx
			var y := top_y + row
			if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
				img.set_pixel(x, y, c)
