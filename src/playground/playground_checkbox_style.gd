class_name PlaygroundCheckboxStyle
extends RefCounted

const ICON_SIZE := 18
const PANEL_BG := Color(0.06, 0.08, 0.10, 1.0)

static func apply(checkbox: CheckBox) -> void:
	checkbox.add_theme_icon_override("unchecked", ImageTexture.create_from_image(make_unchecked_image()))
	checkbox.add_theme_icon_override("checked", ImageTexture.create_from_image(make_checked_image()))
	checkbox.add_theme_icon_override("unchecked_disabled", ImageTexture.create_from_image(make_unchecked_image()))
	checkbox.add_theme_icon_override("checked_disabled", ImageTexture.create_from_image(make_checked_image()))


static func make_unchecked_image() -> Image:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var inner := Rect2i(2, 2, ICON_SIZE - 4, ICON_SIZE - 4)
	img.fill_rect(inner, Color(0.11, 0.13, 0.16, 0.95))
	_draw_border(img, inner, Color(0.78, 0.84, 0.90, 1.0), 1)
	return img


static func make_checked_image() -> Image:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var inner := Rect2i(2, 2, ICON_SIZE - 4, ICON_SIZE - 4)
	img.fill_rect(inner, Color(0.32, 0.78, 0.48, 1.0))
	_draw_border(img, inner, Color(0.55, 0.95, 0.70, 1.0), 1)
	_draw_checkmark(img, Color(0.98, 0.99, 1.0, 1.0))
	return img


static func relative_luminance(c: Color) -> float:
	var ch := [c.r, c.g, c.b]
	for i in 3:
		if ch[i] <= 0.03928:
			ch[i] *= 1.0 / 12.92
		else:
			ch[i] = pow((ch[i] + 0.055) / 1.055, 2.4)
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


static func max_opaque_pixels(img: Image) -> int:
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				count += 1
	return count


static func peak_opaque_luminance(img: Image) -> float:
	var peak := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a > 0.5:
				peak = maxf(peak, relative_luminance(p))
	return peak


static func images_visually_same(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return false
	return true


static func _draw_border(img: Image, rect: Rect2i, color: Color, width: int) -> void:
	for w in width:
		var r := Rect2i(rect.position.x + w, rect.position.y + w,
			rect.size.x - w * 2, rect.size.y - w * 2)
		_stroke_rect(img, r, color)


static func _stroke_rect(img: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		_set_px(img, x, rect.position.y, color)
		_set_px(img, x, rect.position.y + rect.size.y - 1, color)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		_set_px(img, rect.position.x, y, color)
		_set_px(img, rect.position.x + rect.size.x - 1, y, color)


static func _draw_checkmark(img: Image, color: Color) -> void:
	var points: Array[Vector2i] = [
		Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 10), Vector2i(8, 11),
		Vector2i(9, 12), Vector2i(10, 11), Vector2i(11, 10), Vector2i(12, 9),
		Vector2i(13, 8),
	]
	for p in points:
		_set_px(img, p.x, p.y, color)
		_set_px(img, p.x, p.y + 1, color)
	# Short leg
	for x in range(5, 8):
		_set_px(img, x, 10, color)
		_set_px(img, x, 11, color)


static func _set_px(img: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, color)
