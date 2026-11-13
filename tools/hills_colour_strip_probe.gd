## Colour-strip probe: samples rendered pixel RGB at world positions across every join:
##   lawn (r≈30m) → lawn-edge (r≈55m) → flat-zone (r≈75m) → hill-toe (r≈110m)
##   → ridge-0 (r≈160m) → ridge-1 (r≈195m) → far (r≈250m) → east-flat (r≈80m +X)
##
## Reports ZONE_<name> R G B and DELTA_<pair> per-channel so calibration is numerical.
## Usage: godot tools/hills_colour_strip_probe.tscn -- --seed=7 --out=.tmp/hills/rework6/probe.png
extends Node

const _MAIN := "res://src/main/main.tscn"
const _SQUARE := "res://assets/structures/scenarios/square.tres"
const GameModes = preload("res://src/world/game_modes.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")

## World positions sampled (relative to hamlet_centre_xz, +Z = south, -Z = north)
const _NORTH_OFFSETS: Array[float] = [30.0, 55.0, 75.0, 110.0, 160.0, 195.0, 250.0]
const _ZONE_NAMES: Array[String] = ["lawn30", "seam55", "flat75", "toe110", "ridge160", "ridge195", "far250"]


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("hills_colour_strip_probe: headless produces no PNG on macOS")
		get_tree().quit(1)
		return
	var seed_val := 7
	var out_path := "/tmp/strip_probe.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_val = int(arg.get_slice("=", 1))
		elif arg.begins_with("--out="): out_path = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())

	var main := await _boot_generated(seed_val)
	var world: Node3D = main.get_node("World")
	var sky: SkySun = world.get_sky_sun()
	sky.set_fog_model(HeroFog.FogModel.WORLD_AROUND_HERO)
	sky.set_fog_anchor(world.call("_hero_fog_anchor_world"))
	var bounds: Dictionary = world.get_village_lawn_camera_bounds()
	var g := Vector2(bounds.get("centre_xz", Vector2.ZERO))

	# Camera: 20 m EAST of G to avoid central buildings; steep down-angle.
	# Offset x avoids buildings. Look toward north-ground strip.
	var probe_x := g.x + 20.0  # 20 m east of G
	var cam_pos := Vector3(probe_x, 18.0, g.y + 5.0)
	var look_at := Vector3(probe_x, 0.0, g.y - 260.0)
	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(look_at - cam_pos, Vector3.UP), cam_pos)
	cam.make_current()

	for _f in range(30):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)

	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("[strip-probe] saved ", out_path, " (", img.get_width(), "x", img.get_height(), ")")

	# Project each world position to screen and sample pixels there.
	# Sample points are along the probe-x strip north of G.
	var w := img.get_width()
	var h_px := img.get_height()
	var results: Dictionary = {}
	for i in range(_ZONE_NAMES.size()):
		var north_offset := _NORTH_OFFSETS[i]
		# Sample at ground level (y=0) along the probe strip
		var world_pt := Vector3(probe_x, 0.0, g.y - north_offset)
		var screen_pt := cam.unproject_position(world_pt)
		var sx := int(clamp(screen_pt.x, 0, w - 1))
		var sy := int(clamp(screen_pt.y, 0, h_px - 1))
		# Sample a 13×13 patch around the projected point (avoids single-pixel noise)
		var rgb := _sample_patch(img, sx, sy, 13)
		results[_ZONE_NAMES[i]] = rgb
		print("ZONE_%s %.4f %.4f %.4f  (screen %d,%d)" % [
			_ZONE_NAMES[i], rgb.r, rgb.g, rgb.b, sx, sy])

	# East-flat zone: 80 m east, same Z as G — pure world_ground, no hills
	var east_pt := Vector3(g.x + 80.0, 0.0, g.y)
	var screen_east := cam.unproject_position(east_pt)
	var sx_e := int(clamp(screen_east.x, 0, w - 1))
	var sy_e := int(clamp(screen_east.y, 0, h_px - 1))
	var east_rgb := _sample_patch(img, sx_e, sy_e, 13)
	print("ZONE_east80 %.4f %.4f %.4f  (screen %d,%d)" % [east_rgb.r, east_rgb.g, east_rgb.b, sx_e, sy_e])

	# Compute deltas between adjacent zones
	var prev_name := _ZONE_NAMES[0]
	var prev_rgb: Color = results[prev_name]
	for i in range(1, _ZONE_NAMES.size()):
		var cur_name := _ZONE_NAMES[i]
		var cur_rgb: Color = results[cur_name]
		var dr := absf(cur_rgb.r - prev_rgb.r)
		var dg := absf(cur_rgb.g - prev_rgb.g)
		var db := absf(cur_rgb.b - prev_rgb.b)
		print("DELTA_%s_to_%s %.4f %.4f %.4f  L1=%.4f" % [prev_name, cur_name, dr, dg, db, dr+dg+db])
		prev_name = cur_name
		prev_rgb = cur_rgb

	get_tree().quit(0)


static func _sample_patch(img: Image, cx: int, cy: int, size: int) -> Color:
	var half := size / 2
	var sr := 0.0; var sg := 0.0; var sb := 0.0; var n := 0
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var px := clampi(cx + dx, 0, img.get_width() - 1)
			var py := clampi(cy + dy, 0, img.get_height() - 1)
			var c := img.get_pixel(px, py)
			sr += c.r; sg += c.g; sb += c.b; n += 1
	return Color(sr / n, sg / n, sb / n)


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
