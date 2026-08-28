extends Node

const _MAIN_SCENE := "res://src/main/main.tscn"
const _StructureScenario = preload("res://src/world/structure_scenario.gd")
const OUTDIR := "res://.tmp/wall_audit/surface_wall"
const _PRESENT_TIMEOUT_MS := 4000


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTDIR))
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/surface_wall.tres"
	) as StructureScenario
	var ps := load(_MAIN_SCENE) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", scenario)
	add_child(main)
	_keep_window_presenting()
	for _i in range(40):
		await get_tree().process_frame

	var rig := main.get_node("World/CameraRig") as Node3D
	var pivot := scenario.resolve_camera_pivot()
	if pivot == Vector3.ZERO:
		pivot = Vector3(0, 1.56, 0)

	await _capture_rig_cam(rig, 0, "south")
	await _capture_rig_cam(rig, 1, "north")
	await _capture_custom(Vector3(-7.5, 2.0, 0.0), pivot, "east")
	await _capture_custom(Vector3(7.5, 2.0, 0.0), pivot, "west")
	print("[wall_audit] done ", OUTDIR)
	get_tree().quit(0)


func _capture_rig_cam(rig: Node3D, index: int, label: String) -> void:
	if rig.has_method("select"):
		rig.select(index)
	if not await _present_fresh_frame():
		printerr("[wall_audit] no frame for ", label)
		return
	var path := ProjectSettings.globalize_path("%s/face_%s.png" % [OUTDIR, label])
	get_viewport().get_texture().get_image().save_png(path)
	print("[wall_audit] saved ", path)


func _capture_custom(pos: Vector3, pivot: Vector3, label: String) -> void:
	var cam := Camera3D.new()
	cam.name = "AuditCam"
	add_child(cam)
	cam.global_position = pos
	cam.look_at(pivot, Vector3.UP)
	cam.current = true
	if not await _present_fresh_frame():
		printerr("[wall_audit] no frame for ", label)
		cam.queue_free()
		return
	var path := ProjectSettings.globalize_path("%s/face_%s.png" % [OUTDIR, label])
	get_viewport().get_texture().get_image().save_png(path)
	print("[wall_audit] saved ", path)
	cam.queue_free()


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


func _keep_window_presenting() -> void:
	var w := get_window()
	if w == null:
		return
	if w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()
