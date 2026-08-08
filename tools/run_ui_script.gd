extends Node

## Minimal UI script runner for bootstrap. Extend verbs as Ivy gains interactive UI.

const _MAIN_SCENE := "res://src/main/main.tscn"
const _DEFAULT_OUTDIR := "/tmp/ivy_ui_script/"


func _ready() -> void:
	var args := _parse_args()
	var script_path: String = args.get("script", "")
	var outdir: String = args.get("outdir", _DEFAULT_OUTDIR)
	if script_path.is_empty() or not FileAccess.file_exists(script_path):
		printerr("[ui-script] missing or invalid --script=", script_path)
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(outdir)

	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[ui-script] failed to load ", _MAIN_SCENE)
		get_tree().quit(2)
		return
	add_child(ps.instantiate())

	for _i in range(30):
		await get_tree().process_frame

	var lines := FileAccess.get_file_as_string(script_path).split("\n")
	var step := 0
	var shot := 0
	print("[ui-script] script=", script_path, "  outdir=", outdir, "  steps=", lines.size())

	for raw in lines:
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		step += 1
		if line.begins_with("WAIT "):
			var ms := int(line.substr(5).strip_edges())
			await get_tree().create_timer(ms / 1000.0).timeout
		elif line.begins_with("SCREENSHOT"):
			shot += 1
			var name := "%02d_capture.png" % shot
			var parts := line.split(" ", false)
			if parts.size() >= 2:
				name = parts[1]
			var path := outdir.path_join(name)
			var img: Image = get_viewport().get_texture().get_image()
			if img == null:
				printerr("[ui-script] FAILED step ", step, ": no viewport image")
				get_tree().quit(1)
				return
			var err := img.save_png(path)
			if err != OK:
				printerr("[ui-script] FAILED step ", step, ": save_png ", err)
				get_tree().quit(1)
				return
			print("[ui-script]   saved ", path, " size=", img.get_size())
		else:
			printerr("[ui-script] FAILED step ", step, ": unknown verb: ", line)
			get_tree().quit(1)
			return

	get_tree().quit(0)


func _parse_args() -> Dictionary:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--script="):
			args["script"] = a.substr(9)
		elif a.begins_with("--outdir="):
			args["outdir"] = a.substr(9)
	return args
