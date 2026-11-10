extends SceneTree


func _init() -> void:
	var base := ProjectSettings.globalize_path("res://wanderer_content/")
	DirAccess.make_dir_recursive_absolute(base)
	_write_marker_jpg(base + "placeholder_4x3.jpg", 512, 384, 1)
	_write_marker_jpg(base + "placeholder_3x4.jpg", 384, 512, 2)
	_write_marker_jpg(base + "placeholder_16x9.jpg", 640, 360, 3)
	var quotes := """# Village wanderer starter quotes
Lovely day for a stroll.
Have you seen the hero's ivy?
Paths know where feet should go.
A door, a pause, a thought.
The pond glitters quietly.
# comment line ignored
Cottages lean toward stories.
The ring remembers every step.
Morning light on the cobbles.
"""
	var qf := FileAccess.open(base + "quotes.txt", FileAccess.WRITE)
	qf.store_string(quotes)
	qf.close()
	var gi := FileAccess.open(base + ".gdignore", FileAccess.WRITE)
	gi.store_string("")
	gi.close()
	print("wanderer_content placeholders written to ", base)
	quit()


func _write_marker_jpg(path: String, w: int, h: int, marker_id: int) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var sky := Color(0.55, 0.65, 0.82)
	var ground := Color(0.42, 0.58, 0.38)
	for y in range(h):
		for x in range(w):
			var t := float(y) / float(maxi(h - 1, 1))
			img.set_pixel(x, y, sky.lerp(ground, clampf(t * 1.2 - 0.15, 0.0, 1.0)))
	for t in range(6):
		var c := Color.BLACK if t % 2 == 0 else Color.WHITE
		img.fill_rect(Rect2i(t, t, w - t * 2, h - t * 2), c)
	_draw_block_digit(img, marker_id, w / 2 - 60, h / 2 - 40, 120, Color(1, 0.95, 0.1))
	_draw_label_top(img, w, h)
	_draw_arrow_right(img, w, h)
	img.save_jpg(path, 0.9)


func _draw_block_digit(img: Image, digit: int, x0: int, y0: int, scale: int, c: Color) -> void:
	var blocks: Dictionary = {
		1: [
			Rect2i(4, 0, 2, 8),
			Rect2i(2, 2, 6, 2),
		],
		2: [
			Rect2i(0, 0, 8, 2), Rect2i(6, 0, 2, 4), Rect2i(0, 3, 8, 2),
			Rect2i(0, 5, 2, 3), Rect2i(0, 7, 8, 2),
		],
		3: [
			Rect2i(0, 0, 8, 2), Rect2i(6, 0, 2, 8), Rect2i(0, 3, 8, 2), Rect2i(0, 7, 8, 2),
		],
	}
	for r in blocks.get(digit, blocks[1]):
		var rr: Rect2i = r
		img.fill_rect(Rect2i(
			x0 + rr.position.x * scale / 8,
			y0 + rr.position.y * scale / 8,
			maxi(2, rr.size.x * scale / 8),
			maxi(2, rr.size.y * scale / 8)), c)


func _draw_label_top(img: Image, w: int, h: int) -> void:
	var c := Color(0.95, 0.2, 0.15)
	var y := 24
	var x := w / 2 - 90
	for letter in ["T", "O", "P"]:
		img.fill_rect(Rect2i(x, y, 24, 8), c)
		x += 32


func _draw_arrow_right(img: Image, w: int, h: int) -> void:
	var c := Color(0.1, 0.1, 0.75)
	var cx := w - 120
	var cy := h / 2
	img.fill_rect(Rect2i(cx, cy - 8, 80, 16), c)
	img.fill_rect(Rect2i(cx + 70, cy - 28, 16, 56), c)
	for i in range(28):
		img.set_pixel(cx + 86 + i, cy - 28 + i, c)
		img.set_pixel(cx + 86 + i, cy + 28 - i, c)
