## Seam colour probe tool — captures a frame from the seam-line camera,
## then reads pixel RGB on both sides and prints to stdout.
##
## Usage: godot tools/hills_seam_probe.tscn -- --seed=7 --out=/tmp/seam_probe.png [--view=camsun]
##
## --view=seam (default): own low camera at G looking north (band metric below).
## --view=camsun: the game's CamSun rig camera (rig index 0).
##
## Output lines: "SEAM_LAWN R G B" and "SEAM_HILL R G B" in [0..1] float space (band metric:
## bottom band vs middle band), and "SEAM_JOIN n=<samples> L1=<mean>" (join-loop metric, AR-NOFOG-EDGE):
## for each azimuth whose join-loop points project on screen, the 5x5-pixel mean at r_join - 4 m
## (lawn side) vs r_join + 4 m (far-mesh side); L1 is the mean of |far - lawn| summed over RGB.
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const _JOIN_PAD_M := 4.0
const _JOIN_AZIMUTHS := 72

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hills_seam_probe: headless produces no PNG on macOS")
		get_tree().quit(1)
		return
	var seed_val := 7
	var out_path := "/tmp/seam_probe.png"
	var view := "seam"
	var day_val := -1.0
	var seam_lit := -1  # -1 = leave the material as built; 0 / 1 = force u_seam_lit
	var seam_gain := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_val = int(arg.get_slice("=", 1))
		elif arg.begins_with("--out="): out_path = arg.get_slice("=", 1)
		elif arg.begins_with("--view="): view = arg.get_slice("=", 1)
		elif arg.begins_with("--day="): day_val = float(arg.get_slice("=", 1))
		elif arg.begins_with("--seam_lit="): seam_lit = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seam_gain="): seam_gain = float(arg.get_slice("=", 1))

	var main := await _boot_generated(seed_val)
	var world: Node3D = main.get_node("World")
	if day_val >= 0.0:
		_pin_game_day(main, day_val)
	if seam_lit >= 0:
		var hill := world.get_node_or_null("VillageBackdrop/HillTerrain") as MeshInstance3D
		var hm := hill.mesh.surface_get_material(0) as ShaderMaterial if hill != null else null
		if hm != null:
			hm.set_shader_parameter("u_seam_lit", seam_lit == 1)
			if seam_gain > 0.0:
				hm.set_shader_parameter("u_seam_albedo_gain", seam_gain)
			print("[seam-probe] u_seam_lit=", seam_lit == 1, " gain=", hm.get_shader_parameter("u_seam_albedo_gain"))

	var bounds: Dictionary = world.get_village_lawn_camera_bounds()
	var centre: Vector2 = bounds.get("centre_xz", Vector2.ZERO)
	var lawn_r: float = bounds.get("radius", 56.0)

	var cam: Camera3D
	if view == "camsun":
		var rig := world.get_node_or_null("CameraRig")
		rig.call("select", 0)
		cam = get_viewport().get_camera_3d()
	elif view == "north":
		# High overview from G looking north over the lawn edge into the far hill wedge.
		var eye := Vector3(centre.x, 28.0, centre.y + 30.0)
		var tgt := Vector3(centre.x, 4.0, centre.y - 220.0)
		cam = Camera3D.new()
		cam.far = 2000.0
		world.add_child(cam)
		cam.global_transform = Transform3D(Basis.looking_at(tgt - eye, Vector3.UP), eye)
		cam.make_current()
	else:
		# Seam camera: stand at village centre (G), looking north toward the seam at distance.
		# Bottom half of the image = near ground (lawn grass), middle = lawn edge transition,
		# upper = hill terrain toe. We sample near-bottom (lawn) vs mid-upper (hill toe).
		var eye_xz := Vector3(centre.x, 3.0, centre.y + 10.0)  # slightly south of G, low elevation
		# Look slightly downward toward the seam/hill toe zone ~80m north
		var look_at := Vector3(centre.x, 0.5, centre.y - 80.0)
		cam = Camera3D.new()
		world.add_child(cam)
		cam.global_transform = Transform3D(Basis.looking_at(look_at - eye_xz, Vector3.UP), eye_xz)
		cam.make_current()

	for _f in range(24):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)

	var img: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	img.save_png(out_path)
	print("[seam-probe] saved ", out_path, " view=", view)

	# Sample pixels: looking north from G — bottom = lawn grass, middle = hill terrain toe
	var w := img.get_width()
	var h := img.get_height()
	# Bottom band = foreground lawn (close to camera, grass geometry)
	var lawn_rgb := _sample_region(img, int(w * 0.35), int(w * 0.65), int(h * 0.68), int(h * 0.82))
	# Middle band = hill terrain toe (~80-120m from G)
	var hill_rgb := _sample_region(img, int(w * 0.35), int(w * 0.65), int(h * 0.46), int(h * 0.58))
	print("SEAM_LAWN %.4f %.4f %.4f" % [lawn_rgb.r, lawn_rgb.g, lawn_rgb.b])
	print("SEAM_HILL %.4f %.4f %.4f" % [hill_rgb.r, hill_rgb.g, hill_rgb.b])
	var delta := Color(abs(hill_rgb.r - lawn_rgb.r), abs(hill_rgb.g - lawn_rgb.g),
		abs(hill_rgb.b - lawn_rgb.b), 0)
	print("SEAM_DELTA %.4f %.4f %.4f  L1=%.4f" % [delta.r, delta.g, delta.b, delta.r+delta.g+delta.b])
	_print_join_metric(img, cam, world, centre, lawn_r)
	_print_sun_dir(world)
	get_tree().quit(0)


## The far mesh's u_sun_dir and its dot with the light forward (-S): > 0 means it points away from the sun.
func _print_sun_dir(world: Node3D) -> void:
	var hill := world.get_node_or_null("VillageBackdrop/HillTerrain") as MeshInstance3D
	var sun := world.get_node_or_null("SkySun/Sun") as DirectionalLight3D
	if hill == null or hill.mesh == null or sun == null:
		print("SUN_DIR unavailable")
		return
	var mat := hill.mesh.surface_get_material(0) as ShaderMaterial
	var u: Vector3 = mat.get_shader_parameter("u_sun_dir") if mat != null else Vector3.ZERO
	var fwd := -sun.global_basis.z
	print("SUN_DIR u_sun_dir=%s light_fwd=%s dot=%.3f" % [u, fwd, u.normalized().dot(fwd)])


func _print_join_metric(img: Image, cam: Camera3D, world: Node3D, centre: Vector2, r_join: float) -> void:
	var bd: Node3D = world.get("_village_backdrop") as Node3D
	var vp_size := get_viewport().get_visible_rect().size
	var sx := float(img.get_width()) / vp_size.x
	var sy := float(img.get_height()) / vp_size.y
	var sum := 0.0
	var n := 0
	var lawn_sum := Color(0, 0, 0, 0)
	var far_sum := Color(0, 0, 0, 0)
	for i in range(_JOIN_AZIMUTHS):
		var a := TAU * float(i) / float(_JOIN_AZIMUTHS)
		var dir := Vector2(sin(a), -cos(a))
		var px: Array[Vector2] = []
		for r in [r_join - _JOIN_PAD_M, r_join + _JOIN_PAD_M]:
			var xz: Vector2 = centre + dir * float(r)
			var y := float(bd.call("sample_terrain_world_y", xz)) if bd != null else 0.0
			var p := Vector3(xz.x, y, xz.y)
			if cam.is_position_behind(p):
				break
			var s := cam.unproject_position(p)
			var q := Vector2(s.x * sx, s.y * sy)
			if q.x < 3 or q.y < 3 or q.x > img.get_width() - 4 or q.y > img.get_height() - 4:
				break
			px.append(q)
		if px.size() != 2:
			continue
		var lawn := _sample_region(img, int(px[0].x) - 2, int(px[0].x) + 3, int(px[0].y) - 2, int(px[0].y) + 3)
		var far := _sample_region(img, int(px[1].x) - 2, int(px[1].x) + 3, int(px[1].y) - 2, int(px[1].y) + 3)
		sum += absf(far.r - lawn.r) + absf(far.g - lawn.g) + absf(far.b - lawn.b)
		lawn_sum += lawn
		far_sum += far
		n += 1
	var k := 1.0 / float(maxi(n, 1))
	print("SEAM_JOIN n=%d L1=%.4f" % [n, sum * k])
	# Per-side means (sRGB pixels) for recalibrating u_lawn_colour (AR-NOFOG-EDGE).
	print("SEAM_JOIN_LAWN %.4f %.4f %.4f" % [lawn_sum.r * k, lawn_sum.g * k, lawn_sum.b * k])
	print("SEAM_JOIN_FAR %.4f %.4f %.4f" % [far_sum.r * k, far_sum.g * k, far_sum.b * k])


static func _sample_region(img: Image, x0: int, x1: int, y0: int, y1: int) -> Color:
	var sr := 0.0; var sg := 0.0; var sb := 0.0; var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			sr += c.r; sg += c.g; sb += c.b; n += 1
	if n == 0: return Color.BLACK
	return Color(sr/n, sg/n, sb/n)


## Pause the sim clock at `day` (0.25 = local noon with start_hour 6) so SkySun.update lights that hour.
func _pin_game_day(main: Node, day: float) -> void:
	var sim: Node = main.get("_sim") as Node
	if sim == null or not sim.has_method("get_clock"):
		push_warning("hills_seam_probe: no sim clock; --day ignored")
		return
	var clock: SimClock = sim.call("get_clock") as SimClock
	clock.set_speed(SimClock.Speed.PAUSE)
	clock.game_day = day
	print("[seam-probe] pinned game_day=", day)


func _boot_generated(seed_val: int) -> Node:
	var ps := load(_MAIN) as PackedScene
	var main := ps.instantiate()
	main.set("script_driven", true)
	main.set("mesh_scenario", load(_SQUARE))
	add_child(main)
	for _i in range(28):
		await get_tree().process_frame
	main.call("apply_village_mode_live", GameModes.GENERATED, seed_val)
	for _i in range(20):
		await get_tree().process_frame
	return main
