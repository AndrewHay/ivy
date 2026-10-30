extends Node

## One-off tool: capture the building picker with generated-village toggle ON.
## Written for ivy-80z S5 visual verification; can be deleted after acceptance.
##
## Usage:
##   godot res://tools/capture_picker_village_mode.tscn -- \
##     --out=/tmp/picker_generated.png --mode=generated_village --seed=42

const _MAIN_SCENE := "res://src/main/main.tscn"
const GameModes = preload("res://src/world/game_modes.gd")


func _ready() -> void:
	var args := _parse_args()
	var out: String = ProjectSettings.globalize_path(args.get("out", "res://.tmp/picker_village.png"))
	var mode: String = args.get("mode", GameModes.CLASSIC)
	var seed_val: int = int(args.get("seed", "0"))

	DirAccess.make_dir_recursive_absolute(out.get_base_dir())

	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[capture_picker] failed to load main.tscn")
		get_tree().quit(2)
		return
	var main := ps.instantiate()
	# Inject village mode before _ready so picker shows the persisted state.
	main.set("_village_mode", mode)
	main.set("_village_seed", seed_val)
	add_child(main)

	for _i in range(60):
		await get_tree().process_frame

	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)

	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		printerr("[capture_picker] no viewport image")
		get_tree().quit(3)
		return
	var err := img.save_png(out)
	if err != OK:
		printerr("[capture_picker] save_png failed: ", err)
		get_tree().quit(4)
		return
	print("[capture_picker] saved ", out, " size=", img.get_size(), " mode=", mode, " seed=", seed_val)
	get_tree().quit(0)


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out["out"] = a.substr(6)
		elif a.begins_with("--mode="):
			out["mode"] = a.substr(7)
		elif a.begins_with("--seed="):
			out["seed"] = a.substr(7)
	return out
