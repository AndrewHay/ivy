extends Node

## Isolated leaf-card capture — production cup mesh + leaf shader, no sim/HUD.
##
##   Godot res://tools/capture_single_leaf_card.tscn -- --id=a
##   Godot res://tools/capture_single_leaf_card.tscn -- --id=a --view=oblique
##   Godot res://tools/capture_single_leaf_card.tscn -- --id=all
##
## view=front (default) | oblique | side | low | three_quarter — petiole arc reads on side/low.

const LeafAtlasScript = preload("res://src/render/leaf_atlas.gd")
const LeafCupMeshScript = preload("res://src/render/leaf_cup_mesh.gd")
const _DEFAULT_OUTDIR := "res://.tmp/leaf-lookdev/"
const _CARD_HEIGHT_M := 0.14
const _PRESENT_TIMEOUT_MS := 4000
const _BG := Color(0.22, 0.24, 0.26)


func _ready() -> void:
	var args := _parse_args()
	var leaf_id: String = args.get("id", "a")
	var view: String = str(args.get("view", "front"))
	var outdir := ProjectSettings.globalize_path(args.get("outdir", _DEFAULT_OUTDIR))
	DirAccess.make_dir_recursive_absolute(outdir)

	_build_world()
	var atlas := LeafAtlasScript.new()

	if leaf_id == "all":
		var grid_path: String = outdir.path_join("leaf_card_all.png")
		await _capture_grid(atlas, grid_path)
	else:
		var suffix := "" if view == "front" else ("_%s" % view)
		var path: String = str(args.get("out", ""))
		if path.is_empty():
			path = outdir.path_join("leaf_card_%s%s.png" % [leaf_id, suffix])
		else:
			path = ProjectSettings.globalize_path(path)
		await _capture_one(atlas, leaf_id, path, view)

	print("[leaf-card] done")
	get_tree().quit(0)


func _build_world() -> void:
	var root := Node3D.new()
	root.name = "LeafCardRoot"
	add_child(root)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.85
	env_node.environment = env
	root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	root.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_color = Color(0.75, 0.85, 1.0)
	fill.light_energy = 0.35
	root.add_child(fill)


func _make_leaf_mmi() -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = 1
	mm.mesh = LeafCupMeshScript.build()
	mmi.multimesh = mm
	mmi.material_override = load("res://src/render/materials/leaf_material.tres")
	return mmi


## Tip up, petiole down; z scaled by width like LeafRenderer; whole mesh (petiole + blade) centred.
func _card_transform(aspect: float) -> Transform3D:
	var h := _CARD_HEIGHT_M
	var w := h * aspect
	var basis := Basis(Vector3(w, 0, 0), Vector3(0, h, 0), Vector3(0, 0, w))
	var span := LeafCupMeshScript.PETIOLE_LEN + 1.0
	return Transform3D(basis, Vector3(0.0, -h * span * 0.5, 0.0))


func _half_extent(aspect: float) -> float:
	var h := _CARD_HEIGHT_M
	return maxf(h * aspect, h * (LeafCupMeshScript.PETIOLE_LEN + 1.0)) * 0.5


func _camera_distance(cam: Camera3D, half_extent: float) -> float:
	var vfov_half := deg_to_rad(cam.fov * 0.5)
	return (half_extent / tan(vfov_half)) * 1.12


func _place_camera(cam: Camera3D, half_ext: float, view: String) -> void:
	cam.fov = 28.0
	cam.near = 0.02
	cam.far = 10.0
	var dist := _camera_distance(cam, half_ext)
	var yaw_deg := 0.0
	var pitch_deg := 0.0
	match view:
		"oblique":
			yaw_deg = 45.0
			pitch_deg = 18.0
		"side":
			yaw_deg = 90.0
			pitch_deg = 8.0
		"low":
			yaw_deg = 25.0
			pitch_deg = -24.0
		"three_quarter":
			yaw_deg = 32.0
			pitch_deg = 28.0
		_:
			pass
	if view == "front":
		cam.global_position = Vector3(0.0, 0.0, dist)
	else:
		var yaw := deg_to_rad(yaw_deg)
		var pitch := deg_to_rad(pitch_deg)
		cam.global_position = Vector3(
			sin(yaw) * cos(pitch) * dist,
			sin(pitch) * dist,
			cos(yaw) * cos(pitch) * dist
		)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true


func _set_card(mmi: MultiMeshInstance3D, atlas: LeafAtlas, leaf_id: String) -> void:
	var rect := atlas.rect_for(leaf_id)
	var aspect := atlas.aspect_for(leaf_id)
	mmi.multimesh.set_instance_transform(0, _card_transform(aspect))
	mmi.multimesh.set_instance_color(0, Color.WHITE)
	mmi.multimesh.set_instance_custom_data(0, Color(rect.x, rect.y, rect.z, rect.w))


func _capture_one(atlas: LeafAtlas, leaf_id: String, path: String, view: String) -> void:
	var root := get_node("LeafCardRoot") as Node3D
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			c.queue_free()
		if c is Camera3D:
			c.queue_free()
	var mmi := _make_leaf_mmi()
	root.add_child(mmi)
	_set_card(mmi, atlas, leaf_id)

	var cam := Camera3D.new()
	root.add_child(cam)
	_place_camera(cam, _half_extent(atlas.aspect_for(leaf_id)), view)

	await _settle(4)
	await _capture(path, "%s/%s" % [leaf_id, view])


func _capture_grid(atlas: LeafAtlas, path: String) -> void:
	var root := get_node("LeafCardRoot") as Node3D
	var ids := PackedStringArray(["a", "b", "c", "d", "e", "f"])
	var cols := 3
	var spacing := 0.22
	for i in range(ids.size()):
		var mmi := _make_leaf_mmi()
		_set_card(mmi, atlas, ids[i])
		var col := i % cols
		var row := i / cols
		mmi.position = Vector3((col - 1) * spacing, -row * spacing * 1.1, 0.0)
		root.add_child(mmi)

	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.02
	root.add_child(cam)
	cam.global_position = Vector3(0.0, -0.05, 1.35)
	cam.look_at(Vector3(0.0, -0.05, 0.0), Vector3.UP)
	cam.current = true
	await _settle(4)
	await _capture(path, "all")


func _capture(path: String, label: String) -> void:
	if not await _present_fresh_frame():
		printerr("[leaf-card] no frame for ", path)
		return
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("[leaf-card] save failed ", err, " ", path)
	else:
		print("[leaf-card] saved ", path, " (", label, ") size=", img.get_size())


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


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
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
