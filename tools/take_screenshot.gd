extends Node

## Dev tool: loads the main scene, waits for frames, captures the viewport, writes PNG.
##
## Run with:
##   godot res://tools/take_screenshot.tscn -- --out=res://.tmp/screenshots/shot.png
##
## Defaults inside the project so runs need no write access outside the
## workspace. `.tmp/` is gitignored.

const _MAIN_SCENE := "res://src/main/main.tscn"
const _DEFAULT_OUT := "res://.tmp/screenshots/ivy_debug.png"
const _DEFAULT_SETTLE := 30
## How long the capture waits for a real presented frame before giving up.
const _PRESENT_TIMEOUT_MS := 4000


## Renders a frame reflecting current state; see run_ui_script.gd for the full
## rationale. Draws synchronously so capture does not depend on macOS presenting
## an occluded or unfocused window, which could otherwise hang indefinitely.
func _present_fresh_frame() -> bool:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
		return true

	# Boxed so the lambda can mutate it; GDScript lambdas capture locals by value.
	var drawn := [false]
	var on_draw := func() -> void: drawn[0] = true
	RenderingServer.frame_post_draw.connect(on_draw, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + _PRESENT_TIMEOUT_MS
	while not drawn[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if RenderingServer.frame_post_draw.is_connected(on_draw):
		RenderingServer.frame_post_draw.disconnect(on_draw)
	return drawn[0]


## Brings the window forward so a human can watch; cosmetic only.
func _keep_window_presenting() -> void:
	var w := get_window()
	if w == null:
		return
	if w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()


func _ready() -> void:
	var args := _parse_args()
	# globalize_path resolves res:// and passes absolute paths through unchanged.
	var out_path: String = ProjectSettings.globalize_path(
		args.get("out", _DEFAULT_OUT)
	)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var settle_frames: int = int(args.get("settle_frames", _DEFAULT_SETTLE))

	print("[screenshot] out=", out_path, "  settle=", settle_frames)

	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[screenshot] failed to load ", _MAIN_SCENE)
		get_tree().quit(2)
		return
	add_child(ps.instantiate())

	_keep_window_presenting()

	for i in range(settle_frames):
		await get_tree().process_frame

	if not await _present_fresh_frame():
		printerr("[screenshot] no frame rendered within ", _PRESENT_TIMEOUT_MS,
			" ms — refusing to save a possibly stale capture. Check that no other ",
			"scripted run is active.")
		get_tree().quit(5)
		return

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
