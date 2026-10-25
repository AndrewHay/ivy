extends Node

const FaunaProxyMeshes = preload("res://src/presentation/fauna/fauna_proxy_meshes.gd")

## Isolated render of fauna meshes at canonical leaf-relative scale.
##
##   Godot res://tools/capture_fauna_proxies.tscn -- --out=res://.tmp/fauna/fauna_proxies.png

const _DEFAULT_OUT := "res://.tmp/fauna/fauna_proxies_isolated.png"
const _PRESENT_TIMEOUT_MS := 4000
const _BG := Color(0.18, 0.20, 0.22)


func _ready() -> void:
	var args := _parse_args()
	var out_path := ProjectSettings.globalize_path(str(args.get("out", _DEFAULT_OUT)))
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())

	_build_world()
	await _settle(6)
	if not await _present_fresh_frame():
		printerr("[fauna-proxies] no frame rendered")
		get_tree().quit(5)
		return
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err != OK:
		printerr("[fauna-proxies] save failed ", err)
		get_tree().quit(2)
		return
	print("[fauna-proxies] saved ", out_path, " size=", img.get_size())
	get_tree().quit(0)


func _build_world() -> void:
	var root := Node3D.new()
	root.name = "FaunaProxyRoot"
	add_child(root)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.55)
	env.ambient_light_energy = 1.0
	env_node.environment = env
	root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 42, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.35, 0.2)
	ground.mesh = plane
	ground.rotation_degrees = Vector3(-90, 0, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.28, 0.42, 0.26)
	ground.set_surface_override_material(0, gm)
	root.add_child(ground)

	var leaf_w := FaunaConstants.LEAF_REFERENCE_WIDTH_M
	_add_leaf_silhouette(root, Vector3(0.0, 0.002, 0.08))

	_add_proxy(root, FaunaConstants.Species.BEE, Vector3(-0.06, leaf_w * 0.15, 0.0))
	_add_proxy(root, FaunaConstants.Species.BUTTERFLY, Vector3(0.06, leaf_w * 0.2, 0.0))

	_add_label(root, "bee L=leaf/3", Vector3(-0.06, leaf_w * 0.42, 0.0))
	_add_label(root, "fly span=leaf/2", Vector3(0.06, leaf_w * 0.42, 0.0))

	_add_scale_bar(root, leaf_w, Vector3(0.0, 0.004, 0.08), "7.5 cm leaf")

	var cam := Camera3D.new()
	cam.fov = 35.0
	cam.near = 0.005
	cam.far = 10.0
	root.add_child(cam)
	cam.global_position = Vector3(0.0, leaf_w * 0.45, 0.28)
	cam.look_at(Vector3(0.0, leaf_w * 0.12, 0.02), Vector3.UP)
	cam.current = true


func _add_leaf_silhouette(parent: Node3D, pos: Vector3) -> void:
	var w := FaunaConstants.LEAF_REFERENCE_WIDTH_M
	var h := w * 1.15
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w, 0.002, h)
	mi.mesh = box
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.42, 0.22)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.set_surface_override_material(0, m)
	parent.add_child(mi)


func _add_proxy(parent: Node3D, species: FaunaConstants.Species, pos: Vector3) -> void:
	var mi := FaunaProxyMeshes.make_mesh_instance(species)
	mi.position = pos
	if species == FaunaConstants.Species.BUTTERFLY:
		mi.rotation_degrees = Vector3(15, 20, 0)
	parent.add_child(mi)


func _add_label(parent: Node3D, text: String, pos: Vector3) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 16
	lbl.modulate = Color(0.85, 0.88, 0.92, 0.95)
	lbl.position = pos
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.00011
	parent.add_child(lbl)


func _add_scale_bar(parent: Node3D, length_m: float, pos: Vector3, caption: String) -> void:
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length_m, 0.002, length_m * 0.06)
	bar.mesh = box
	bar.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.85, 0.35)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.set_surface_override_material(0, m)
	parent.add_child(bar)
	var lbl := Label3D.new()
	lbl.text = caption
	lbl.font_size = 14
	lbl.modulate = Color(0.95, 0.85, 0.8, 0.9)
	lbl.position = pos + Vector3(0, length_m * 0.22, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.0001
	parent.add_child(lbl)


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
