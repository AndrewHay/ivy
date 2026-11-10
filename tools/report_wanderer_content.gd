extends SceneTree

const WandererContent = preload("res://src/presentation/wanderer/wanderer_content.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")


func _initialize() -> void:
	var params := WandererParams.production()
	var dir_path := params.content_dir
	if not dir_path.ends_with("/"):
		dir_path += "/"
	var global := ProjectSettings.globalize_path(dir_path)
	var da := DirAccess.open(global)
	if da == null:
		print("missing dir ", dir_path)
		quit(1)
		return
	var files: Array[String] = []
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if not da.current_is_dir() and not fn.begins_with("."):
			var lower := fn.to_lower()
			if lower.ends_with(".jpg") or lower.ends_with(".jpeg"):
				files.append(fn)
		fn = da.get_next()
	da.list_dir_end()
	files.sort()
	print("wanderer_content report (", files.size(), " jpgs)")
	for f in files:
		var path := global + f
		var raw := FileAccess.get_file_as_bytes(path)
		var orient := WandererContent.parse_jpeg_exif_orientation(raw)
		var img := Image.new()
		var err := img.load_jpg_from_buffer(raw)
		if err != OK:
			print(f, ": unreadable")
			continue
		WandererContent.apply_exif_orientation(img, orient)
		print(
			f,
			" raw=", raw.size(),
			" exif_orient=", orient,
			" final=", img.get_width(), "x", img.get_height()
		)
	quit(0)
