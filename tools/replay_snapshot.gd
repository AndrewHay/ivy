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
	if args.has("look_target"):
		await _write_look_shots(main, dir, args)
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
		elif a.begins_with("--look-target="):
			out["look_target"] = a.substr(14)
		elif a.begins_with("--look-radius="):
			out["look_radius"] = a.substr(14)
		elif a.begins_with("--look-height="):
			out["look_height"] = a.substr(14)
		elif a.begins_with("--look-az="):
			out["look_az"] = a.substr(10)
		elif a.begins_with("--look-prefix="):
			out["look_prefix"] = a.substr(14)
	return out


## Eye-level shots around an explicit world point:
## --look-target=<x,y,z|door> (door: nearest cottage door; azimuths are relative to its normal) [--look-radius=3] [--look-height=1.2] [--look-az=0,90,180,270] [--look-prefix=look]
func _write_look_shots(main: Node, dir: String, args: Dictionary) -> void:
	var target := Vector3.ZERO
	var az_base := 0.0
	if String(args["look_target"]) == "door":
		# Nearest cottage door to the debug-camera pivot; az 0 looks straight at the door.
		var door := _nearest_door(main)
		if door.is_empty():
			printerr("[replay-snapshot] no cottage door found")
			return
		target = door["pos"] + Vector3(0.0, 1.0, 0.0)
		var n: Vector3 = door["normal"]
		az_base = atan2(n.x, n.z)
		print("[replay-snapshot] door pos=", door["pos"], " normal=", n)
		_print_door_depths(main, door)
	else:
		var parts := String(args["look_target"]).split(",")
		if parts.size() < 3:
			printerr("[replay-snapshot] --look-target needs x,y,z or 'door'")
			return
		target = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	var radius := float(args.get("look_radius", 3.0))
	var height := float(args.get("look_height", 1.2))
	var prefix := String(args.get("look_prefix", "look"))
	var world: Node3D = main.get_node_or_null("World") as Node3D
	if world == null:
		return
	var cam := world.get_node_or_null("ReplayLookCam") as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.name = "ReplayLookCam"
		cam.near = 0.05
		world.add_child(cam)
	var azimuths: Array = []
	for tok in String(args.get("look_az", "0,90,180,270")).split(","):
		azimuths.append(int(tok))
	for az_deg in azimuths:
		var az := az_base + deg_to_rad(float(az_deg))
		var eye := Vector3(target.x + sin(az) * radius, target.y + height, target.z + cos(az) * radius)
		cam.look_at_from_position(eye, target)
		cam.make_current()
		for _f in range(3):
			await get_tree().process_frame
		if not await _present_fresh_frame():
			continue
		var shot: Image = get_viewport().get_texture().get_image()
		if shot != null and shot.save_png(dir.path_join("%s_%d.png" % [prefix, az_deg])) == OK:
			print("[replay-snapshot] wrote ", prefix, "_", az_deg, ".png")


func _nearest_door(main: Node) -> Dictionary:
	var backdrop := main.get_node_or_null("World/VillageBackdrop") as Node3D
	var debug_cam := main.get_node_or_null("World/DebugCamera") as Node3D
	if backdrop == null or not backdrop.has_method("get_layout"):
		return {}
	var layout = backdrop.get_layout()
	var ref := debug_cam.global_position if debug_cam != null else Vector3.ZERO
	var best := {}
	var best_d := INF
	for spec in layout.cottages:
		var d: Array[Vector2] = VillageBackdrop.cottage_door(spec)
		var world_pos: Vector3 = backdrop.to_global(Vector3(d[0].x, 0.0, d[0].y))
		var dist := world_pos.distance_to(ref)
		if dist < best_d:
			best_d = dist
			best = {"pos": world_pos, "normal": Vector3(d[1].x, 0.0, d[1].y)}
	return best


## For every cottage MultiMesh instance within 1.2 m of the door, print the min/max extent of its
## mesh along the door normal (metres, 0 = door anchor, + = outward) and across the wall.
func _print_door_depths(main: Node, door: Dictionary) -> void:
	var backdrop := main.get_node_or_null("World/VillageBackdrop") as Node3D
	var pos: Vector3 = door["pos"]
	var n: Vector3 = door["normal"]
	var side := Vector3(n.z, 0.0, -n.x)
	for child in backdrop.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or not mmi.name.begins_with("Cottage_"):
			continue
		var mm := mmi.multimesh
		var aabb := mm.mesh.get_aabb()
		for i in range(mm.instance_count):
			var xf: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
			if xf.origin.distance_to(pos) > 1.2:
				continue
			var lo_n := INF
			var hi_n := -INF
			var lo_s := INF
			var hi_s := -INF
			for cx in [0, 1]:
				for cy in [0, 1]:
					for cz in [0, 1]:
						var corner := aabb.position + aabb.size * Vector3(cx, cy, cz)
						var w := xf * corner
						var dn := (w - pos).dot(n)
						var ds := (w - pos).dot(side)
						lo_n = minf(lo_n, dn)
						hi_n = maxf(hi_n, dn)
						lo_s = minf(lo_s, ds)
						hi_s = maxf(hi_s, ds)
			print("[door-depth] %s #%d along_normal=[%.3f, %.3f] across=[%.3f, %.3f]" % [
				mmi.name, i, lo_n, hi_n, lo_s, hi_s])


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
