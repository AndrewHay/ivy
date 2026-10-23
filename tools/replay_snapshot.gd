extends Node

## Replay a debug snapshot folder and write replay.png (ivy-nrp S2).
##
## Usage:
##   Godot res://tools/replay_snapshot.tscn -- --snapshot=<folder|latest>
##
## Non-headless only on macOS (viewport capture).

const _MAIN_SCENE := "res://src/main/main.tscn"
const _PRESENT_TIMEOUT_MS := 4000


func _ready() -> void:
	var args := _parse_args()
	var spec: String = args.get("snapshot", "latest")
	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[replay-snapshot] failed to load main scene")
		get_tree().quit(2)
		return
	var main := ps.instantiate()
	main.set("script_driven", true)
	add_child(main)
	for _i in range(30):
		await get_tree().process_frame
	if not main.has_method("load_snapshot_from_dir"):
		printerr("[replay-snapshot] Main missing load_snapshot_from_dir")
		get_tree().quit(2)
		return
	var result: Dictionary = await main.load_snapshot_from_dir(spec)
	if not result.get("ok", false):
		printerr("[replay-snapshot] ", result.get("reason", "load failed"))
		get_tree().quit(1)
		return
	var verdict: Dictionary = result.get("verdict", {})
	var dir: String = result.get("dir", "")
	if verdict.get("match", false):
		print("[replay-snapshot] MATCH run_hash=", verdict.get("actual", ""))
	else:
		printerr("[replay-snapshot] MISMATCH expected=", verdict.get("expected", ""),
			" actual=", verdict.get("actual", ""))
	if not await _present_fresh_frame():
		printerr("[replay-snapshot] no fresh frame for replay.png")
		get_tree().quit(1)
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		printerr("[replay-snapshot] no viewport image")
		get_tree().quit(1)
		return
	var out_path := dir.path_join("replay.png")
	var err: Error = img.save_png(out_path)
	if err != OK:
		printerr("[replay-snapshot] save_png failed: ", err)
		get_tree().quit(1)
		return
	print("[replay-snapshot] wrote ", out_path)
	get_tree().quit(0 if verdict.get("match", false) else 1)


func _present_fresh_frame() -> bool:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
		return true
	var drawn := [false]
	var on_draw := func() -> void: drawn[0] = true
	RenderingServer.frame_post_draw.connect(on_draw, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + _PRESENT_TIMEOUT_MS
	while not drawn[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if RenderingServer.frame_post_draw.is_connected(on_draw):
		RenderingServer.frame_post_draw.disconnect(on_draw)
	return drawn[0]


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snapshot="):
			out["snapshot"] = a.substr(11)
	return out
