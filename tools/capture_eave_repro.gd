extends Node

## Repro capture for "ivy climbs an invisible wall hanging from the roof overhang".
## Plants along the Squat house south wall the way a player click would, grows, then
## captures an oblique shot and a profile shot looking along the wall, and prints how
## many stem segments sit off the visible wall face.
##
## Non-headless only:
##   Godot res://tools/capture_eave_repro.tscn -- --label=before --day=40

const _MAIN_SCENE := "res://src/main/main.tscn"
const _OUTDIR := "res://.tmp/eave_repro/"
const _TICKS_PER_DAY := 24
## South wall exterior face of square_sim.glb (wall node z=2.91, face at local z=0).
const _WALL_FACE_Z := 2.91
const _CLICK_XS := [-9.2, -8.4, -5.6, -4.9]


func _ready() -> void:
	var args := _parse_args()
	var label: String = args.get("label", "repro")
	var day := int(args.get("day", "40"))
	var outdir := ProjectSettings.globalize_path(_OUTDIR)
	DirAccess.make_dir_recursive_absolute(outdir)

	var ps := load(_MAIN_SCENE) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", false)
	add_child(main)
	await _settle(35)
	main.call("_on_building_selected", "square")
	var ui := main.get_node("UI")
	var picker := ui.get_node_or_null("BuildingPicker")
	if picker != null:
		picker.queue_free()
	if not await _wait_ready(main, 600000):
		printerr("[eave] load timed out")
		get_tree().quit(1)
		return

	var world: Node = main.get_node("World")
	var sim: Node = main.get_node("Sim")
	var params: IvyParams = main.get("params")
	var surface: SurfaceQuery = world.call("get_surface_query", params)

	for x in _CLICK_XS:
		# A player camera south of the house looking down at the wall base.
		var from := Vector3(x, 1.7, 8.0)
		var aim := Vector3(x, 0.15, _WALL_FACE_Z)
		var hit := surface.raycast(from, from + (aim - from).normalized() * 20.0)
		var reason := PlantingTool.hover_reject_reason(hit, params)
		print("[eave] click x=%.2f hit=%s pos=%s n=%s reason='%s'" % [
			x, hit.hit, hit.position, hit.normal, reason])
		if reason.is_empty():
			sim.plant_at(hit.position, hit.normal)
	if main.has_method("_on_plant_success"):
		main.call("_on_plant_success")
	await _settle(5)

	sim.advance_ticks(_TICKS_PER_DAY * day + 6)
	await _settle(10)
	_report(sim.get("plant") as PlantData)

	await _capture(main, outdir.path_join("%s_oblique.png" % label),
		Vector3(-3.2, 1.4, 7.8), Vector3(-7.0, 1.4, 3.0), 55.0)
	await _capture(main, outdir.path_join("%s_profile.png" % label),
		Vector3(-4.0, 1.6, 4.6), Vector3(-9.5, 1.5, 3.1), 60.0)
	print("[eave] done")
	get_tree().quit(0)


func _report(plant: PlantData) -> void:
	var on_wall := 0
	var off_wall := 0
	var max_off := 0.0
	var off_by_x := {}
	var n := plant.segment_count()
	for i in range(n):
		var p := plant.seg_b[i]
		if p.z < _WALL_FACE_Z - 0.3 or p.y < 0.3:
			continue
		var off := p.z - _WALL_FACE_Z
		max_off = maxf(max_off, off)
		if off > 0.15:
			off_wall += 1
			var bucket := snappedf(p.x, 0.5)
			off_by_x[bucket] = int(off_by_x.get(bucket, 0)) + 1
		else:
			on_wall += 1
	print("[eave] segs=%d south_face_on=%d south_face_off(>0.15m)=%d max_off=%.3f" % [
		n, on_wall, off_wall, max_off])
	var keys := off_by_x.keys()
	keys.sort()
	for k in keys:
		print("[eave]   off-wall x≈%.1f : %d" % [k, off_by_x[k]])


func _capture(main: Node, path: String, eye: Vector3, target: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	(main.get_node("World") as Node3D).add_child(cam)
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.current = true
	await _settle(4)
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[eave] saved ", path)
	cam.queue_free()


func _wait_ready(main: Node, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var ui := main.get_node_or_null("UI")
		var overlay := ui.get_node_or_null("LoadingOverlay") if ui != null else null
		var tool := main.get_node_or_null("World/PlantingTool")
		if overlay == null and tool != null:
			await _settle(15)
			return true
		await get_tree().process_frame
	return false


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
