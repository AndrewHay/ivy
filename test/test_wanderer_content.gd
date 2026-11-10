extends GutTest

const WandererContent = preload("res://src/presentation/wanderer/wanderer_content.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")


func test_parse_quotes_bom_blank_hash() -> void:
	var text := "\ufeff# comment\n\nHello\n# skip\nLong line"
	var q := WandererContent.parse_quotes(text, 10)
	assert_eq(q.size(), 2)
	assert_eq(q[0], "Hello")


func test_load_shipped_content() -> void:
	var p := WandererParams.production()
	var c := WandererContent.load_from_dir(p)
	if c.image_count() == 0 and c.quote_count() == 0:
		pending("wanderer_content/ is local-only (gitignored); nothing to load in this checkout")
		return
	assert_gte(c.image_count(), 3)
	assert_gte(c.quote_count(), 1)


func _jpeg_exif_bytes(orientation: int, little_endian: bool) -> PackedByteArray:
	var tiff := PackedByteArray()
	if little_endian:
		tiff.append_array([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
		tiff.append_array([0x01, 0x00])
		tiff.append_array([0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00])
		tiff.append_array([orientation & 0xFF, (orientation >> 8) & 0xFF, 0x00, 0x00])
		tiff.append_array([0x00, 0x00])
	else:
		tiff.append_array([0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08])
		tiff.append_array([0x00, 0x01])
		tiff.append_array([0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01])
		tiff.append_array([(orientation >> 8) & 0xFF, orientation & 0xFF, 0x00, 0x00])
		tiff.append_array([0x00, 0x00, 0x00, 0x00])
	var app1 := PackedByteArray()
	app1.append_array("Exif".to_ascii_buffer())
	app1.append(0)
	app1.append(0)
	app1.append_array(tiff)
	var seg_len := app1.size() + 2
	var out := PackedByteArray([0xFF, 0xD8, 0xFF, 0xE1])
	out.append((seg_len >> 8) & 0xFF)
	out.append(seg_len & 0xFF)
	out.append_array(app1)
	out.append_array([0xFF, 0xD9])
	return out


func test_exif_parser_little_endian_orient_6() -> void:
	var data := _jpeg_exif_bytes(6, true)
	assert_eq(WandererContent.parse_jpeg_exif_orientation(data), 6)


func test_exif_parser_big_endian_orient_6() -> void:
	var data := _jpeg_exif_bytes(6, false)
	assert_eq(WandererContent.parse_jpeg_exif_orientation(data), 6)


func test_exif_parser_no_exif_returns_1() -> void:
	var data := PackedByteArray([0xFF, 0xD8, 0xFF, 0xD9])
	assert_eq(WandererContent.parse_jpeg_exif_orientation(data), 1)


func test_exif_parser_truncated_returns_1() -> void:
	var data := PackedByteArray([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x04])
	assert_eq(WandererContent.parse_jpeg_exif_orientation(data), 1)
	var corrupt := PackedByteArray([0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 0x45, 0x78])
	assert_eq(WandererContent.parse_jpeg_exif_orientation(corrupt), 1)


func test_missing_dir_graceful() -> void:
	var p := WandererParams.production()
	p.content_dir = "res://nonexistent_wanderer_xyz/"
	var c := WandererContent.load_from_dir(p)
	assert_eq(c.image_count(), 0)
	assert_eq(c.quote_count(), 0)
