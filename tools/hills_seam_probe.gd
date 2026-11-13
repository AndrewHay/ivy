## Seam colour probe tool — captures a frame from the seam-line camera,
## then reads pixel RGB on both sides and prints to stdout.
##
## Usage: godot tools/hills_seam_probe.tscn -- --seed=7 --out=/tmp/seam_probe.png
##
## Output lines: "SEAM_LAWN R G B" and "SEAM_HILL R G B" in [0..1] float space.
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hills_seam_probe: headless produces no PNG on macOS")
		get_tree().quit(1)
		return
	var seed_val := 7
	var out_path := "/tmp/seam_probe.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_val = int(arg.get_slice("=", 1))
		elif arg.begins_with("--out="): out_path = arg.get_slice("=", 1)

	var main := await _boot_generated(seed_val)
	var world: Node3D = main.get_node("World")
	var sky: SkySun = world.get_sky_sun()
	sky.set_fog_model(HeroFog.FogModel.WORLD_AROUND_HERO)
	sky.set_fog_anchor(world.call("_hero_fog_anchor_world"))

	var bounds: Dictionary = world.get_village_lawn_camera_bounds()
	var centre: Vector2 = bounds.get("centre_xz", Vector2.ZERO)
	var lawn_r: float = bounds.get("radius", 56.0)

	# Seam camera: stand at village centre (G), looking north toward the seam at distance.
	# Bottom half of the image = near ground (lawn grass), middle = lawn edge transition,
	# upper = hill terrain toe. We sample near-bottom (lawn) vs mid-upper (hill toe).
	var eye_xz := Vector3(centre.x, 3.0, centre.y + 10.0)  # slightly south of G, low elevation
	# Look slightly downward toward the seam/hill toe zone ~80m north
	var look_at := Vector3(centre.x, 0.5, centre.y - 80.0)

	var cam := Camera3D.new()
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
	print("[seam-probe] saved ", out_path)

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
	get_tree().quit(0)


static func _sample_region(img: Image, x0: int, x1: int, y0: int, y1: int) -> Color:
	var sr := 0.0; var sg := 0.0; var sb := 0.0; var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			sr += c.r; sg += c.g; sb += c.b; n += 1
	if n == 0: return Color.BLACK
	return Color(sr/n, sg/n, sb/n)


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
