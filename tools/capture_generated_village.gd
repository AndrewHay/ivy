## Throwaway capture tool for S4 generated village screenshots (ivy-80z).
##
## Instantiates main.tscn with a square scenario, calls Main.apply_village_mode_live()
## to switch to generated mode, then orbits three cameras per seed and saves PNGs.
## Seeds 1, 2, 3 are captured; S4 has no paths/stones (that's S3).
##
## Non-headless only (--headless produces no image on macOS).
##
## Usage:
##   /Applications/Godot.app/Contents/MacOS/Godot \
##     res://tools/capture_generated_village.tscn \
##     -- --outdir=/Users/andrewhay/github/ivy/.tmp/village_gen/s4
##
## Output:
##   gen_seed1_overview.png, gen_seed1_high.png, gen_seed1_eye.png
##   gen_seed2_overview.png, ...  gen_seed3_overview.png, ...
extends Node

const _MAIN_SCENE := "res://src/main/main.tscn"
const _SQUARE_SCENARIO := "res://assets/structures/scenarios/square.tres"

const _SEEDS: Array[int] = [1, 2, 3]

## Camera positions per shot: [azimuth_deg, radius_m, height_m, label]
const _CAMERAS: Array = [
	[0,  50, 45, "overview"],
	[0,  26, 14, "high"],
	[0,  12,  2, "eye"],
]

const _PRESENT_TIMEOUT_MS := 4000


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
	var args := _parse_args()
	var outdir: String = args.get("outdir", "/Users/andrewhay/github/ivy/.tmp/village_gen/s4")
	DirAccess.make_dir_recursive_absolute(outdir)

	var ps := load(_MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("[gen-capture] failed to load main.tscn")
		get_tree().quit(2)
		return

	var scenario := load(_SQUARE_SCENARIO) as Resource
	if scenario == null:
		printerr("[gen-capture] failed to load square.tres")
		get_tree().quit(2)
		return

	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", scenario)
	add_child(main)

	# Keep window visible for rendering.
	var w := get_window()
	if w != null and w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	DisplayServer.window_move_to_foreground()

	# Wait for bootstrap coroutine to settle.
	for _i in range(30):
		await get_tree().process_frame

	var world := main.get_node("World")

	# Shared throwaway orbit camera (re-used across all seeds).
	var orbit_cam := Camera3D.new()
	orbit_cam.name = "GenCaptureOrbitCam"
	world.add_child(orbit_cam)

	for seed in _SEEDS:
		print("[gen-capture] switching to generated_village seed=%d…" % seed)
		main.call("apply_village_mode_live", "generated_village", seed)

		# Settle frames after mode switch + backdrop rebuild.
		for _f in range(10):
			await get_tree().process_frame

		var pivot: Vector3 = world.get_orbit_pivot()
		print("[gen-capture]   pivot=", pivot)

		for cam_def in _CAMERAS:
			var az_deg: float = float(cam_def[0])
			var radius: float = float(cam_def[1])
			var height: float = float(cam_def[2])
			var label: String = cam_def[3]

			var az := deg_to_rad(az_deg)
			var eye := Vector3(
				pivot.x + sin(az) * radius,
				height,
				pivot.z + cos(az) * radius
			)
			orbit_cam.look_at_from_position(eye, Vector3(pivot.x, minf(pivot.y, height), pivot.z))
			orbit_cam.make_current()

			for _f in range(5):
				await get_tree().process_frame

			if not await _present_fresh_frame():
				printerr("[gen-capture] no frame rendered for seed=%d %s" % [seed, label])
				get_tree().quit(1)
				return

			var img: Image = get_viewport().get_texture().get_image()
			if img == null:
				printerr("[gen-capture] null image for seed=%d %s" % [seed, label])
				get_tree().quit(1)
				return
			var fname := "gen_seed%d_%s.png" % [seed, label]
			var path := outdir.path_join(fname)
			img.save_png(path)
			print("[gen-capture]   saved: ", path)

	print("[gen-capture] done.")
	get_tree().quit(0)


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--") and arg.contains("="):
			var eq := arg.find("=")
			var key := arg.substr(2, eq - 2)
			var val := arg.substr(eq + 1)
			out[key] = val
	return out
