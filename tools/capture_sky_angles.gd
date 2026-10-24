extends Node

## Captures sky comparison shots: horizontal horizon view vs straight-up zenith.
## Run: godot res://tools/capture_sky_angles.tscn

const _MAIN := "res://src/main/main.tscn"
const _SCENARIO := "res://assets/structures/scenarios/tower.tres"
const _OUT_DIR := "res://.tmp/sky_atmosphere"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_OUT_DIR))
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SCENARIO) as Resource)
	add_child(main)

	var clock: SimClock = null
	for _attempt in range(240):
		await get_tree().process_frame
		var sim := main.get_node_or_null("Sim")
		if sim != null and sim.has_method("get_clock"):
			clock = sim.get_clock()
			if clock != null:
				break
	if clock == null:
		printerr("[capture_sky_angles] SimClock never became available")
		get_tree().quit(1)
		return

	var ticks_to_noon := int(round(0.25 / clock.params.sim_tick))
	clock.advance_ticks(ticks_to_noon)
	for _i in range(15):
		await get_tree().process_frame

	var world: Node3D = main.get_node("World")
	var cam := Camera3D.new()
	cam.name = "SkyAngleCaptureCam"
	cam.fov = 70.0
	world.add_child(cam)

	var eye := Vector3(0.0, 1.75, 0.0)
	await _shot(cam, eye, Vector3(0.0, 6.0, 400.0), _OUT_DIR.path_join("view_horizon_noon.png"))
	cam.global_position = eye
	cam.look_at(eye + Vector3(0.0, 100.0, 0.0), Vector3.UP)
	cam.make_current()
	await _capture(_OUT_DIR.path_join("view_zenith_noon.png"))

	get_tree().quit(0)


func _shot(cam: Camera3D, from: Vector3, at: Vector3, path: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	cam.make_current()
	await _capture(path)


func _capture(path: String) -> void:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	for _i in range(3):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(path)
	img.save_png(abs_path)
	print("[capture_sky_angles] saved ", abs_path)
