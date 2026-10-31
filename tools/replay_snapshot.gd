extends Node

## Replay a debug snapshot folder and write replay.png (ivy-nrp S2).
##
## Usage:
##   Godot res://tools/replay_snapshot.tscn -- --snapshot=<folder|latest> [--orbit-highlight=<id>]
##
## Non-headless only on macOS (viewport capture).

const _MAIN_SCENE := "res://src/main/main.tscn"
const _SnapshotReplay = preload("res://src/debug/snapshot_replay.gd")
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
	main.set("skip_script_bootstrap", true)
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
	var recipe: Variant = result.get("recipe")
	var highlight_id: int = int(args.get("orbit_highlight", -1))
	if verdict.get("match", false):
		print("[replay-snapshot] MATCH run_hash=", verdict.get("actual", ""))
	else:
		printerr("[replay-snapshot] MISMATCH expected=", verdict.get("expected", ""),
			" actual=", verdict.get("actual", ""))
	if recipe != null:
		_SnapshotReplay.restore_camera(main, recipe)
	for _f in range(3):
		await get_tree().process_frame
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
	if highlight_id >= 0 and recipe != null:
		await _write_orbit_highlights(main, dir, recipe, highlight_id)
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
		elif a.begins_with("--orbit-highlight="):
			out["orbit_highlight"] = a.substr(18)
	return out


func _write_orbit_highlights(main: Node, dir: String, recipe: Variant, ann_id: int) -> void:
	var focal: Variant = _focal_for_annotation(recipe, ann_id)
	if focal == null:
		printerr("[replay-snapshot] no world_anchors for annotation id ", ann_id)
		return
	var world: Node3D = main.get_node_or_null("World") as Node3D
	if world == null:
		return
	var orbit_cam := world.get_node_or_null("ReplayOrbitCam") as Camera3D
	if orbit_cam == null:
		orbit_cam = Camera3D.new()
		orbit_cam.name = "ReplayOrbitCam"
		world.add_child(orbit_cam)
	var radius := 5.0
	var height: float = focal.y + 1.5
	for az_deg in [0, 90, 180, 270]:
		var az := deg_to_rad(float(az_deg))
		var eye := Vector3(
			focal.x + sin(az) * radius,
			height,
			focal.z + cos(az) * radius
		)
		orbit_cam.look_at_from_position(eye, focal)
		orbit_cam.make_current()
		if not await _present_fresh_frame():
			continue
		var shot: Image = get_viewport().get_texture().get_image()
		if shot == null:
			continue
		var orbit_path := dir.path_join("orbit_highlight_%d_%d.png" % [ann_id, az_deg])
		if shot.save_png(orbit_path) == OK:
			print("[replay-snapshot] wrote ", orbit_path)


func _focal_for_annotation(recipe: Variant, ann_id: int) -> Variant:
	var annotations: Array = recipe.annotations if recipe != null else []
	for entry in annotations:
		if int(entry.get("id", -1)) != ann_id:
			continue
		var anchors: Array = entry.get("world_anchors", [])
		if anchors.is_empty():
			return null
		var sum := Vector3.ZERO
		var count := 0
		for a in anchors:
			var pos: Array = a.get("position", [])
			if pos.size() < 3:
				continue
			sum += Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			count += 1
		if count == 0:
			return null
		return sum / float(count)
	printerr("[replay-snapshot] annotation id not found: ", ann_id)
	return null
