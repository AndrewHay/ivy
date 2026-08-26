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
## structure_configs storey_sides yaw labels (kit yaw 0 → +Z wall ring in baked Godot GLBs).
const _CARDINALS := [
	{"label": "south", "outward": Vector3(0, 0, 1)},
	{"label": "east", "outward": Vector3(-1, 0, 0)},
	{"label": "north", "outward": Vector3(0, 0, -1)},
	{"label": "west", "outward": Vector3(1, 0, 0)},
]
const _WALL_R := 1.51  ## half − EXT_OFFSET in baked GLB space (matches kit wall ring).
const _DIAGONALS := [
	{"label": "se", "outward": Vector3(0.707107, 0.0, 0.707107)},
	{"label": "sw", "outward": Vector3(-0.707107, 0.0, 0.707107)},
	{"label": "nw", "outward": Vector3(-0.707107, 0.0, -0.707107)},
	{"label": "ne", "outward": Vector3(0.707107, 0.0, -0.707107)},
]


func _ready() -> void:
	var outdir: String = ProjectSettings.globalize_path(_parse_outdir())
	DirAccess.make_dir_recursive_absolute(outdir)

	var scenarios: Array = [
		{"id": "procedural_tower", "path": ""},
		{"id": "square", "path": "res://assets/structures/scenarios/square.tres"},
		{"id": "tower", "path": "res://assets/structures/scenarios/tower.tres"},
	]

	var only_id := _parse_only()
	for entry in scenarios:
		if not only_id.is_empty() and entry.id != only_id:
			continue
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
	var world_aabb: AABB = framing.aabb
	var distance: float = framing.distance
	var look_center: Vector3 = framing.get("look_center", world_aabb.get_center())

	var review_cam := Camera3D.new()
	review_cam.name = "ReviewCamera"
	world.add_child(review_cam)

	for face in _CARDINALS:
		_place_face_camera(review_cam, world_aabb, look_center, distance, face.outward)
		var path := outdir.path_join("face_%s.png" % face.label)
		if not await _save_viewport(viewport, path):
			printerr("[structure_review] failed ", id, " face ", face.label)

	for face in _DIAGONALS:
		_place_face_camera(review_cam, world_aabb, look_center, distance, face.outward)
		var path := outdir.path_join("diag_%s.png" % face.label)
		if not await _save_viewport(viewport, path):
			printerr("[structure_review] failed ", id, " diag ", face.label)

	_place_top_camera(review_cam, world_aabb)
	if not await _save_viewport(viewport, outdir.path_join("top.png")):
		printerr("[structure_review] failed ", id, " top")

	if not scenario_path.is_empty():
		var scenario: StructureScenario = load(scenario_path) as StructureScenario
		# Kit yaw-0 door wall is on the +Z ring; camera north of wall, aim at mesh AABB centre height.
		_place_face_camera(review_cam, world_aabb, look_center, distance, Vector3(0.0, 0.0, 1.0))
		if not await _save_viewport(viewport, outdir.path_join("face_door.png")):
			printerr("[structure_review] failed ", id, " face_door")
		if scenario.seed_positions.size() > 0:
			var seed_outward := -scenario.seed_normals[0].normalized()
			_place_face_camera(review_cam, world_aabb, look_center, distance, seed_outward)
			if not await _save_viewport(viewport, outdir.path_join("face_seed_south.png")):
				printerr("[structure_review] failed ", id, " face_seed_south")

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
		var world_aabb := AABB(center - aabb.size * 0.5, aabb.size)
		return {
			"aabb": world_aabb,
			"distance": extent * 1.85,
			"body": null,
			"look_center": center,
		}

	var scenario: StructureScenario = load(scenario_path) as StructureScenario
	var body := _StructureBody.new()
	body.name = "Structure"
	world.add_child(body)
	body.build(scenario.collision_glb, scenario.hero_glb)
	await get_tree().process_frame
	var sdf := _MeshSdf.new()
	sdf.load_from_file(scenario.sdf_path)
	var world_aabb: AABB = sdf.mesh_aabb
	var hero_aabb := _hero_visual_aabb(body)
	if hero_aabb.size.length_squared() > 1e-6:
		world_aabb = hero_aabb
	var look_center: Vector3 = scenario.resolve_camera_pivot()
	if look_center == Vector3.ZERO:
		look_center = world_aabb.get_center()
	var size: Vector3 = world_aabb.size
	var distance := maxf(size.x, size.z) * 0.75 + 2.0
	return {
		"aabb": world_aabb,
		"distance": distance,
		"body": body,
		"look_center": look_center,
	}


func _hero_visual_aabb(root: Node) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_inst := node as MeshInstance3D
			if mesh_inst.mesh != null:
				var piece: AABB = mesh_inst.global_transform * mesh_inst.mesh.get_aabb()
				if first:
					merged = piece
					first = false
				else:
					merged = merged.merge(piece)
		for child in node.get_children():
			stack.append(child)
	return merged


func _place_face_camera(
	cam: Camera3D,
	aabb: AABB,
	look_center: Vector3,
	distance: float,
	outward: Vector3
) -> void:
	const ELEV_DEG := 8.0
	var el := deg_to_rad(ELEV_DEG)
	var horiz := Vector3(outward.x, 0.0, outward.z)
	if horiz.length_squared() < 1e-8:
		horiz = outward.normalized()
	else:
		horiz = horiz.normalized()
	var face_point := look_center + horiz * _WALL_R
	var offset := horiz * distance * cos(el) + Vector3.UP * distance * sin(el)
	cam.global_position = face_point + offset
	cam.look_at(look_center, Vector3.UP)


func _place_top_camera(cam: Camera3D, aabb: AABB) -> void:
	var center := aabb.get_center()
	var height := aabb.size.y * 0.55 + 2.0
	cam.global_position = center + Vector3(0.0, height, 0.0)
	cam.look_at(center, Vector3(0.0, 0.0, -1.0))


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


func _parse_only() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			return a.substr(6)
	return ""
