## WP7 one-shot capture: boots generated village (seed 7), advances wanderer on a sloped
## path segment, reaches DOOR_PAUSE, then captures the viewport. Self-quits.
## Run: Godot res://tools/wp7_terrain_wanderer_capture.tscn (non-headless)
extends Node

const _MAIN_SCENE := "res://src/main/main.tscn"
const _IVY_SCENARIO := "res://assets/structures/scenarios/ivy.tres"
const _OUT_DIR := "res://.tmp/village_terrain/wp7"
const GameModes = preload("res://src/world/game_modes.gd")

const _PRESENT_TIMEOUT_MS := 4000
const _SEED := 7


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


func _ready() -> void:
	var w := get_window()
	if w != null:
		if w.mode == Window.MODE_MINIMIZED:
			w.mode = Window.MODE_WINDOWED
		w.size = Vector2i(1280, 720)
	DisplayServer.window_move_to_foreground()
	await _run()


func _run() -> void:
	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[WP7-capture] failed to load main.tscn")
		get_tree().quit(2)
		return
	var scenario := load(_IVY_SCENARIO) as Resource
	if scenario == null:
		printerr("[WP7-capture] failed to load ivy.tres")
		get_tree().quit(2)
		return

	var main: Node = ps.instantiate()
	main.set("script_driven", true)
	main.set("script_building_id", "birthday")
	main.set("mesh_scenario", scenario)
	add_child.call_deferred(main)
	for _i in range(40):
		await get_tree().process_frame

	if not main.is_inside_tree():
		printerr("[WP7-capture] main failed to enter tree")
		get_tree().quit(2)
		return

	var world: Node = main.get_node("World")
	main.call("apply_village_mode_live", GameModes.GENERATED, _SEED)
	for _f in range(25):
		await get_tree().process_frame

	var ctrl: Node = world.get_wanderer_controller()
	if ctrl == null:
		printerr("[WP7-capture] no wanderer controller")
		get_tree().quit(1)
		return

	ctrl.call("reseed", 11)
	ctrl.call("debug_advance", 6.0)
	for _f in range(5):
		await get_tree().process_frame

	if not ctrl.call("debug_advance_to", "DOOR_PAUSE", 120.0):
		printerr("[WP7-capture] failed to reach DOOR_PAUSE")
		get_tree().quit(1)
		return
	ctrl.call("debug_advance", 0.3)
	for _f in range(5):
		await get_tree().process_frame

	var fig_pos: Vector3 = ctrl.get_figure_global_position()
	var bd: Node = world.get("_village_backdrop")
	if bd != null and bd.has_method("sample_terrain_y"):
		var ty: float = bd.call("sample_terrain_y", Vector2(fig_pos.x, fig_pos.z))
		if fig_pos.y < ty - 0.08:
			printerr("[WP7-capture] feet check failed: fig y=%.3f terrain=%.3f" % [fig_pos.y, ty])
			get_tree().quit(1)
			return

	_place_wanderer_cam(world, ctrl, 7.0, 1.6, 1.0, -90.0)
	await _present_fresh_frame()
	for _f in range(3):
		await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_OUT_DIR))
	var out := ProjectSettings.globalize_path(_OUT_DIR + "/wanderer_terrain.png")
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("[WP7-capture] viewport image was null")
		get_tree().quit(1)
		return
	img.save_png(out)
	print("[WP7-capture] wrote ", out, " size=", img.get_size())
	get_tree().quit()


func _place_wanderer_cam(world: Node, ctrl: Node, standoff: float, eye_h: float, look_h: float, bearing_deg: float) -> void:
	var fig_pos: Vector3 = ctrl.get_figure_global_position()
	var aim_x := fig_pos.x
	var aim_z := fig_pos.z
	var aim_pt := Vector3(aim_x, look_h, aim_z)
	var pivot: Vector3 = world.get_orbit_pivot()
	var to_pivot := Vector2(pivot.x - aim_x, pivot.z - aim_z)
	if to_pivot.length_squared() < 0.25:
		to_pivot = Vector2(0.0, -1.0)
	if absf(bearing_deg) > 1e-4:
		var br := deg_to_rad(bearing_deg)
		var c := cos(br)
		var s := sin(br)
		to_pivot = Vector2(to_pivot.x * c - to_pivot.y * s, to_pivot.x * s + to_pivot.y * c)
	to_pivot = to_pivot.normalized()
	var dist := absf(standoff)
	var side := -1.0 if standoff < 0.0 else 1.0
	var eye_aim := Vector3(
		aim_x + to_pivot.x * dist * side, eye_h, aim_z + to_pivot.y * dist * side)
	var cam := world.get_node_or_null("WPCaptureCam") as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.name = "WPCaptureCam"
		world.add_child(cam)
	cam.look_at_from_position(eye_aim, aim_pt)
	cam.current = true
