extends SceneTree

const DEFAULT_SRC := "res://.tmp/wanderer/likeness/reference.jpg"
const DEFAULT_OUT := "res://assets/wanderer/figure_face.png"


func _initialize() -> void:
	var src := DEFAULT_SRC
	var out := DEFAULT_OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--src="):
			src = arg.substr(6)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
	var global_src := ProjectSettings.globalize_path(src)
	var img := Image.load_from_file(global_src)
	if img == null or img.is_empty():
		printerr("failed to load ", src)
		quit(1)
		return
	var crop := Rect2i(218, 85, 210, 270)
	crop.position.x = clampi(crop.position.x, 0, img.get_width() - 1)
	crop.position.y = clampi(crop.position.y, 0, img.get_height() - 1)
	crop.size.x = mini(crop.size.x, img.get_width() - crop.position.x)
	crop.size.y = mini(crop.size.y, img.get_height() - crop.position.y)
	img = img.get_region(crop)
	img.resize(32, 40, Image.INTERPOLATE_LANCZOS)
	var global_out := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(global_out.get_base_dir())
	var err := img.save_png(global_out)
	if err != OK:
		printerr("save failed ", err)
		quit(1)
		return
	print("[make_wanderer_face] wrote ", out, " (", img.get_width(), "x", img.get_height(), ")")
	quit(0)
