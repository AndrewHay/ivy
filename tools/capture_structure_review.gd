extends Node

## M2.65 structure review — orbit + top captures for user approval (no sim / no light bake).
##
## Run:
##   godot --headless res://tools/capture_structure_review.tscn
##   godot --headless res://tools/capture_structure_review.tscn -- --outdir=res://.tmp/structure_review/

const _StructureScenario = preload("res://src/world/structure_scenario.gd")
const _StructureBody = preload("res://src/world/structure_body.gd")
const _MeshSdf = preload("res://src/world/mesh_sdf.gd")
const _Tower = preload("res://src/world/tower.gd")
const _DEFAULT_OUTDIR := "res://.tmp/structure_review/"
const _VIEWPORT_SIZE := Vector2i(1920, 1080)
const _SIDE_COUNT := 8


func _ready() -> void:
	var outdir: String = ProjectSettings.globalize_path(_parse_outdir())
	DirAccess.make_dir_recursive_absolute(outdir)

	var scenarios: Array = [
		{"id": "procedural_tower", "path": ""},
		{"id": "square", "path": "res://assets/structures/scenarios/square.tres"},
		{"id": "tower", "path": "res://assets/structures/scenarios/tower.tres"},
	]

	for entry in scenarios:
		var subdir := outdir.path_join(entry.id)
		DirAccess.make_dir_recursive_absolute(subdir)
		await _capture_structure(entry.id, entry.path, subdir)

	print("[structure_review] done — output under ", outdir)
	get_tree().quit(0)


func _capture_structure(id: String, scenario_path: String, outdir: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = _VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	add_child(viewport)

	var world := Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	_setup_environment(world)

	var framing := await _add_structure(world, scenario_path)
	var pivot: Vector3 = framing.pivot
	var radius: float = framing.radius
	var top_height: float = framing.top_height

	var review_cam := Camera3D.new()
	review_cam.name = "ReviewCamera"
	world.add_child(review_cam)

	for i in _SIDE_COUNT:
		var azimuth_deg: float = float(i) * 360.0 / float(_SIDE_COUNT)
		_place_side_camera(review_cam, pivot, radius, azimuth_deg)
		var path := outdir.path_join("side_%03d.png" % int(azimuth_deg))
		if not await _save_viewport(viewport, path):
			printerr("[structure_review] failed ", id, " side ", azimuth_deg)

	_place_top_camera(review_cam, pivot, top_height)
	if not await _save_viewport(viewport, outdir.path_join("top.png")):
		printerr("[structure_review] failed ", id, " top")

	viewport.queue_free()
	print("[structure_review] ", id, " → ", outdir)


func _setup_environment(world: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.39, 0.65)
	sky_mat.sky_horizon_color = Color(0.62, 0.78, 0.92)
	sky_mat.ground_bottom_color = Color(0.08, 0.09, 0.06)
	sky_mat.ground_horizon_color = Color(0.3, 0.33, 0.25)
	sky_mat.sun_angle_max = 2.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_SKY
	env_res.sky = sky
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env_res.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env_res
	world.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)

	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(48.0, 48.0)
	ground_mesh.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.35, 0.38, 0.32)
	ground_mesh.material_override = ground_mat
	world.add_child(ground_mesh)


func _add_structure(world: Node3D, scenario_path: String) -> Dictionary:
	if scenario_path.is_empty():
		var tower: Tower = _Tower.new()
		tower.name = "Tower"
		world.add_child(tower)
		var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
		tower.build_from_spec(spec, true)
		await get_tree().process_frame
		var mesh_node := tower.get_node_or_null("TowerMesh") as MeshInstance3D
		var aabb: AABB = mesh_node.mesh.get_aabb() if mesh_node != null and mesh_node.mesh != null else AABB()
		var center := tower.global_transform * aabb.get_center()
		var extent := aabb.size.length() * 0.55
		return {
			"pivot": center,
			"radius": extent * 1.85,
			"top_height": extent * 2.2,
		}

	var scenario: Resource = load(scenario_path) as Resource
	var body := _StructureBody.new()
	body.name = "Structure"
	world.add_child(body)
	body.build(scenario.collision_glb, scenario.hero_glb)
	await get_tree().process_frame
	var pivot: Vector3 = scenario.resolve_camera_pivot()
	var sdf := _MeshSdf.new()
	sdf.load_from_file(scenario.sdf_path)
	var size: Vector3 = sdf.mesh_aabb.size
	var radius := maxf(size.x, size.z) * 1.1 + size.length() * 0.35
	var top_height := size.y * 1.35 + size.length() * 0.25
	return {"pivot": pivot, "radius": radius, "top_height": top_height}


func _place_side_camera(cam: Camera3D, pivot: Vector3, radius: float, azimuth_deg: float) -> void:
	var az := deg_to_rad(azimuth_deg)
	const ELEV_DEG := 18.0
	var el := deg_to_rad(ELEV_DEG)
	var offset := Vector3(
		radius * cos(el) * sin(az),
		radius * sin(el),
		radius * cos(el) * cos(az)
	)
	cam.global_position = pivot + offset
	cam.look_at(pivot, Vector3.UP)


func _place_top_camera(cam: Camera3D, pivot: Vector3, height: float) -> void:
	cam.global_position = pivot + Vector3(0.0, height, 0.0)
	cam.look_at(pivot, Vector3(0.0, 0.0, -1.0))


func _save_viewport(viewport: SubViewport, path: String) -> bool:
	await get_tree().process_frame
	await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(true)
	var tex := viewport.get_texture()
	if tex == null:
		printerr("[structure_review] no viewport texture")
		return false
	var img: Image = tex.get_image()
	if img == null:
		printerr("[structure_review] no image from texture")
		return false
	var err := img.save_png(path)
	if err != OK:
		printerr("[structure_review] save_png failed: ", path, " err=", err)
		return false
	print("[structure_review] saved ", path)
	return true


func _parse_outdir() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--outdir="):
			return a.substr(9)
	return _DEFAULT_OUTDIR
