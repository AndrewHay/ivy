class_name WandererContent
extends RefCounted

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")

var textures: Array[Texture2D] = []
var aspects: PackedFloat32Array = PackedFloat32Array()
var names: PackedStringArray = PackedStringArray()
var quotes: PackedStringArray = PackedStringArray()


static func load_from_dir(params: WandererParams) -> RefCounted:
	var out = (load("res://src/presentation/wanderer/wanderer_content.gd") as GDScript).new()
	var dir_path := params.content_dir
	if not dir_path.ends_with("/"):
		dir_path += "/"
	var global := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(global):
		push_warning("WandererContent: missing content dir %s" % dir_path)
		return out
	var files: PackedStringArray = PackedStringArray()
	var da := DirAccess.open(global)
	if da == null:
		push_warning("WandererContent: cannot open %s" % dir_path)
		return out
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if not da.current_is_dir() and not fn.begins_with("."):
			files.append(fn)
		fn = da.get_next()
	da.list_dir_end()
	files.sort()
	var txt_files: Array[String] = []
	for f in files:
		var lower := f.to_lower()
		if lower.ends_with(".jpg") or lower.ends_with(".jpeg"):
			_load_image(out, params, dir_path, f)
		elif lower.ends_with(".txt"):
			txt_files.append(f)
	if out.textures.size() >= params.max_images:
		while out.textures.size() > params.max_images:
			out.textures.pop_back()
			out.aspects.resize(out.textures.size())
			out.names.resize(out.textures.size())
	var quotes_name := params.quotes_file
	if quotes_name.is_empty():
		quotes_name = "quotes.txt"
	var quotes_path := ""
	if files.has(quotes_name):
		quotes_path = dir_path + quotes_name
	elif txt_files.size() > 0:
		txt_files.sort()
		quotes_path = dir_path + txt_files[0]
		if txt_files.size() > 1:
			push_warning("WandererContent: multiple .txt files; using %s" % txt_files[0])
	if not quotes_path.is_empty():
		var text := _read_text_file(quotes_path)
		out.quotes = parse_quotes(text, params.bubble_max_chars)
	return out


static func _read_text_file(path: String) -> String:
	var p := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


static func _load_image(out: RefCounted, params: WandererParams, dir_path: String, filename: String) -> void:
	if out.textures.size() >= params.max_images:
		return
	var path := dir_path + filename
	var global_path := ProjectSettings.globalize_path(path)
	var f := FileAccess.open(global_path, FileAccess.READ)
	if f == null:
		push_warning("WandererContent: skipped unreadable %s" % filename)
		return
	var raw := f.get_buffer(f.get_length())
	f.close()
	var orient := parse_jpeg_exif_orientation(raw)
	var img := Image.new()
	var err := img.load_jpg_from_buffer(raw)
	if err != OK:
		err = img.load_png_from_buffer(raw)
	if err != OK or img.is_empty():
		push_warning("WandererContent: skipped unreadable %s" % filename)
		return
	apply_exif_orientation(img, orient)
	var w := img.get_width()
	var h := img.get_height()
	var max_px := params.image_max_px
	if max(w, h) > max_px:
		var scale := float(max_px) / float(max(w, h))
		img.resize(int(w * scale), int(h * scale), Image.INTERPOLATE_LANCZOS)
		w = img.get_width()
		h = img.get_height()
	if w < 1 or h < 1:
		return
	var tex := ImageTexture.create_from_image(img)
	out.textures.append(tex)
	out.aspects.append(float(w) / float(h))
	out.names.append(filename)


static func parse_jpeg_exif_orientation(data: PackedByteArray) -> int:
	if data.size() < 4:
		return 1
	if data[0] != 0xFF or data[1] != 0xD8:
		return 1
	var pos := 2
	var guard := 0
	while pos + 4 < data.size() and guard < 256:
		guard += 1
		if data[pos] != 0xFF:
			pos += 1
			continue
		var marker := data[pos + 1]
		pos += 2
		if marker == 0xD9 or marker == 0xDA:
			break
		if pos + 2 > data.size():
			break
		var seg_len := int(data[pos]) << 8 | int(data[pos + 1])
		if seg_len < 2:
			return 1
		var seg_start := pos + 2
		var seg_end := seg_start + seg_len - 2
		if seg_end > data.size():
			return 1
		if marker == 0xE1 and seg_end - seg_start >= 6:
			if data[seg_start] == 0x45 and data[seg_start + 1] == 0x78 \
					and data[seg_start + 2] == 0x69 and data[seg_start + 3] == 0x66 \
					and data[seg_start + 4] == 0x00 and data[seg_start + 5] == 0x00:
				var tiff := seg_start + 6
				var orient := _read_exif_orientation_at_tiff(data, tiff, seg_end)
				if orient >= 1 and orient <= 8:
					return orient
		pos = seg_end
	return 1


static func _read_u16(data: PackedByteArray, offset: int, little: bool) -> int:
	if offset + 2 > data.size():
		return 0
	if little:
		return int(data[offset]) | (int(data[offset + 1]) << 8)
	return (int(data[offset]) << 8) | int(data[offset + 1])


static func _read_u32(data: PackedByteArray, offset: int, little: bool) -> int:
	if offset + 4 > data.size():
		return 0
	if little:
		return int(data[offset]) | (int(data[offset + 1]) << 8) | \
			(int(data[offset + 2]) << 16) | (int(data[offset + 3]) << 24)
	return (int(data[offset]) << 24) | (int(data[offset + 1]) << 16) | \
		(int(data[offset + 2]) << 8) | int(data[offset + 3])


static func _read_exif_orientation_at_tiff(data: PackedByteArray, tiff: int, limit: int) -> int:
	if tiff + 8 > limit or tiff + 8 > data.size():
		return 1
	var little := data[tiff] == 0x49 and data[tiff + 1] == 0x49
	var big := data[tiff] == 0x4D and data[tiff + 1] == 0x4D
	if not little and not big:
		return 1
	var magic := _read_u16(data, tiff + 2, little)
	if magic != 42:
		return 1
	var ifd_off := _read_u32(data, tiff + 4, little)
	var ifd := tiff + ifd_off
	if ifd + 2 > limit or ifd + 2 > data.size():
		return 1
	var count := _read_u16(data, ifd, little)
	var pos := ifd + 2
	for _i in count:
		if pos + 12 > limit or pos + 12 > data.size():
			break
		var tag := _read_u16(data, pos, little)
		var typ := _read_u16(data, pos + 2, little)
		var cnt := _read_u32(data, pos + 4, little)
		if tag == 0x0112 and typ == 3 and cnt >= 1:
			var voff := pos + 8
			var val := _read_u16(data, voff, little)
			if val >= 1 and val <= 8:
				return val
		pos += 12
	return 1


static func apply_exif_orientation(img: Image, orientation: int) -> void:
	match orientation:
		2:
			img.flip_x()
		3:
			img.rotate_180()
		4:
			img.flip_y()
		5:
			img.flip_x()
			img.rotate_90(1)
		6:
			img.rotate_90(0)
		7:
			img.flip_x()
			img.rotate_90(0)
		8:
			img.rotate_90(0)
			img.rotate_90(0)
			img.rotate_90(0)
		_:
			pass


static func parse_quotes(text: String, max_chars: int) -> PackedStringArray:
	var out := PackedStringArray()
	if text.is_empty():
		return out
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	for line in text.split("\n", false):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.length() > max_chars:
			line = line.substr(0, max_chars - 1) + "…"
		out.append(line)
	return out


static func from_arrays(q: PackedStringArray, asp: PackedFloat32Array) -> RefCounted:
	var c = (load("res://src/presentation/wanderer/wanderer_content.gd") as GDScript).new()
	c.quotes = q
	c.aspects = asp
	for _i in asp.size():
		c.textures.append(null)
	return c


func image_count() -> int:
	return textures.size()


func quote_count() -> int:
	return quotes.size()


func aspect(i: int) -> float:
	if i < 0 or i >= aspects.size():
		return 4.0 / 3.0
	return aspects[i]


func quote(i: int) -> String:
	if i < 0 or i >= quotes.size():
		return ""
	return quotes[i]
