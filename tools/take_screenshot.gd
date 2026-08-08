extends Node

## Dev tool: loads the main scene, waits for frames, captures the viewport, writes PNG.
##
## Run with:
##   godot res://tools/take_screenshot.tscn -- --out=/tmp/ivy.png

const _MAIN_SCENE := "res://src/main/main.tscn"
const _DEFAULT_OUT := "/tmp/ivy_debug.png"
const _DEFAULT_SETTLE := 30


func _ready() -> void:
	var args := _parse_args()
	var out_path: String = args.get("out", _DEFAULT_OUT)
	var settle_frames: int = int(args.get("settle_frames", _DEFAULT_SETTLE))

	print("[screenshot] out=", out_path, "  settle=", settle_frames)

	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[screenshot] failed to load ", _MAIN_SCENE)
		get_tree().quit(2)
		return
	add_child(ps.instantiate())

	for i in range(settle_frames):
		await get_tree().process_frame

	for _j in range(3):
		await get_tree().process_frame

	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		printerr("[screenshot] viewport texture had no image")
		get_tree().quit(3)
		return
	var err := img.save_png(out_path)
	if err != OK:
		printerr("[screenshot] save_png failed: ", err, " path=", out_path)
		get_tree().quit(4)
		return
	print("[screenshot] saved ", out_path, " size=", img.get_size())
	get_tree().quit(0)


func _parse_args() -> Dictionary:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			args["out"] = a.substr(6)
		elif a.begins_with("--settle-frames="):
			args["settle_frames"] = int(a.substr(16))
	return args
