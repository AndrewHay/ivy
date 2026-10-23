class_name SnapshotCapture
extends RefCounted

const _SnapshotRecipe = preload("res://src/debug/snapshot_recipe.gd")
const _RunHash = preload("res://src/metrics/run_hash.gd")
const _DebugSessionLog = preload("res://src/debug/debug_session_log.gd")
const _AnnotationModel = preload("res://src/debug/snapshot_annotation_model.gd")
const _DEFAULT_PARAMS := "res://src/params/ivy_params_default.tres"
const _SNAPSHOT_ROOT := "res://.tmp/snapshots/"


static func build_recipe(
	main: Node,
	session_log: RefCounted,
	free_plant_mode: bool,
	note: String = ""
):
	var recipe := _SnapshotRecipe.new()
	recipe.build = _git_metadata()
	var world: Node = main.get_node("World")
	var sim: Node = main.get_node("Sim")
	var params: IvyParams = main.get("params") as IvyParams
	var clock: SimClock = sim.get_clock()
	recipe.scene = {
		"building_id": world.get_active_building_id() if world.has_method("get_active_building_id") else "",
		"seed_index": world.get_seed_index() if world.has_method("get_seed_index") else 0,
		"free_plant_mode": free_plant_mode,
	}
	recipe.plant_log = session_log.plant_log.duplicate(true)
	recipe.param_log = session_log.param_log.duplicate(true)
	recipe.param_overrides = _param_overrides(params)
	recipe.time = {
		"tick_index": clock.tick_index,
		"game_day": clock.game_day,
		"speed": clock.speed,
	}
	recipe.camera = _capture_camera(main)
	recipe.view = _capture_view(main, params)
	recipe.fingerprint = _fingerprint(sim)
	recipe.annotations = []
	recipe.note = note
	return recipe


## Downscale a viewport capture to canvas/UI coordinates (Retina texture vs window size).
static func image_for_display(captured: Image, display_size: Vector2) -> Image:
	if captured == null:
		return null
	var out := captured.duplicate()
	if display_size.x <= 0.0 or display_size.y <= 0.0:
		return out
	var target := Vector2i(int(display_size.x), int(display_size.y))
	if out.get_size() == target:
		return out
	out.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
	return out


static func make_folder_name(building_id: String, game_day: float) -> String:
	var dt := Time.get_datetime_dict_from_system()
	var day_i := int(floor(game_day)) + 1
	return "%04d%02d%02d-%02d%02d%02d_%s_d%d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second,
		building_id if not building_id.is_empty() else "unknown",
		day_i,
	]


static func write_snapshot(
	recipe: RefCounted,
	clean_image: Image,
	folder_name: String,
	annotated_image: Image = null
) -> String:
	var root := ProjectSettings.globalize_path(_SNAPSHOT_ROOT)
	DirAccess.make_dir_recursive_absolute(root)
	var dir_path := root.path_join(folder_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var json_err: Error = recipe.write_json(dir_path.path_join("snapshot.json"))
	if json_err != OK:
		push_error("SnapshotCapture: write snapshot.json failed (%s)" % json_err)
	var png_err := clean_image.save_png(dir_path.path_join("clean.png"))
	if png_err != OK:
		push_error("SnapshotCapture: write clean.png failed (%s)" % png_err)
	if annotated_image != null:
		var ann_err := annotated_image.save_png(dir_path.path_join("annotated.png"))
		if ann_err != OK:
			push_error("SnapshotCapture: write annotated.png failed (%s)" % ann_err)
	var latest_path := root.path_join("latest")
	var latest_file := FileAccess.open(latest_path, FileAccess.WRITE)
	if latest_file != null:
		latest_file.store_string(folder_name)
	return dir_path


static func _git_metadata() -> Dictionary:
	var meta := {
		"git_commit": "",
		"git_dirty": false,
		"godot_version": Engine.get_version_info().string,
	}
	var out: Array = []
	var exit := OS.execute("git", ["rev-parse", "HEAD"], out, true, false)
	if exit == 0 and out.size() > 0:
		meta["git_commit"] = str(out[0]).strip_edges()
	var dirty_out: Array = []
	var dirty_exit := OS.execute("git", ["diff", "--quiet"], dirty_out, true, false)
	meta["git_dirty"] = dirty_exit != 0
	return meta


static func _param_overrides(live: IvyParams) -> Dictionary:
	if live == null:
		return {}
	var defaults := load(_DEFAULT_PARAMS) as IvyParams
	if defaults == null:
		return {}
	var out: Dictionary = {}
	for prop in live.get_property_list():
		var usage: int = prop["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name: String = prop["name"]
		if name in ["resource_local_to_scene", "resource_name", "script"]:
			continue
		var a: Variant = live.get(name)
		var b: Variant = defaults.get(name)
		if a != b:
			out[name] = _DebugSessionLog._encode_value(a)
	return out


static func _capture_camera(main: Node) -> Dictionary:
	var debug_cam: DebugCamera = main.get_node("World/DebugCamera") as DebugCamera
	var cam_sun: Camera3D = main.get_node("World/CameraRig/CamSun") as Camera3D
	var active := "unknown"
	var active_cam: Camera3D = null
	if debug_cam != null and debug_cam.current:
		active = "DebugCamera"
		active_cam = debug_cam
	elif cam_sun != null and cam_sun.current:
		active = "CamSun"
		active_cam = cam_sun
	elif debug_cam != null:
		active_cam = debug_cam
		active = "DebugCamera"
	var block := {
		"active_camera": active,
	}
	if debug_cam != null and debug_cam.has_method("capture_state"):
		block["debug_camera"] = debug_cam.capture_state()
	if active_cam != null:
		block["global_transform"] = _transform_array(active_cam.global_transform)
		block["fov"] = active_cam.fov
		block["near"] = active_cam.near
		block["far"] = active_cam.far
	return block


static func _transform_array(xf: Transform3D) -> Array:
	var b := xf.basis
	var o := xf.origin
	return [
		b.x.x, b.x.y, b.x.z, o.x,
		b.y.x, b.y.y, b.y.z, o.y,
		b.z.x, b.z.y, b.z.z, o.z,
	]


static func _capture_view(main: Node, params: IvyParams) -> Dictionary:
	var vp := main.get_viewport()
	var dev_overlay: Node = null
	for child in main.get_children():
		if child.name == "DevUI":
			dev_overlay = child.get_node_or_null("DevOverlay")
	var field_viz: Node = main.get_node_or_null("World/FieldViz")
	var hud: Hud = null
	var ui: CanvasLayer = main.get_node_or_null("UI") as CanvasLayer
	if ui != null:
		hud = ui.get_node_or_null("Hud") as Hud
	return {
		"viewport_size": [vp.size.x, vp.size.y],
		"dev_overlay_visible": dev_overlay != null and dev_overlay.visible,
		"field_viz_visible": field_viz != null and field_viz.visible,
		"help_open": hud != null and hud.is_help_open(),
		"dev_build": params != null and params.dev_build,
	}


static func enrich_annotations(
	main: Node,
	sim: Node,
	annotations: Array,
	viewport_size: Vector2
) -> Array:
	var cam := _active_camera_node(main)
	if cam == null:
		return annotations.duplicate(true)
	var world: World3D = main.get_world_3d()
	if world == null:
		return annotations.duplicate(true)
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var out: Array = []
	for entry in annotations:
		var copy: Dictionary = entry.duplicate(true)
		copy["world_anchors"] = _world_anchors_for_entry(cam, space, entry, viewport_size)
		copy["nearby_plant"] = _nearby_plant_refs(sim, copy["world_anchors"])
		out.append(copy)
	return out


static func _active_camera_node(main: Node) -> Camera3D:
	var debug_cam: Camera3D = main.get_node_or_null("World/DebugCamera") as Camera3D
	var cam_sun: Camera3D = main.get_node_or_null("World/CameraRig/CamSun") as Camera3D
	if debug_cam != null and debug_cam.current:
		return debug_cam
	if cam_sun != null and cam_sun.current:
		return cam_sun
	return debug_cam if debug_cam != null else cam_sun


static func _world_anchors_for_entry(
	cam: Camera3D,
	space: PhysicsDirectSpaceState3D,
	entry: Dictionary,
	viewport_size: Vector2
) -> Array:
	var anchors: Array = []
	match str(entry.get("kind", "")):
		"box":
			var rect := _AnnotationModel.dict_to_norm_rect(entry.get("rect", {}))
			for u in [0.25, 0.5, 0.75]:
				for v in [0.25, 0.5, 0.75]:
					var norm := Vector2(
						rect.position.x + rect.size.x * u,
						rect.position.y + rect.size.y * v
					)
					_append_ray_hit(cam, space, norm, viewport_size, anchors)
		"stroke":
			var points: Array = entry.get("points", [])
			var step := maxi(1, points.size() / 9)
			for i in range(0, points.size(), step):
				var item = points[i]
				if item is Array and item.size() >= 2:
					var norm := Vector2(float(item[0]), float(item[1]))
					_append_ray_hit(cam, space, norm, viewport_size, anchors)
	return anchors


static func _append_ray_hit(
	cam: Camera3D,
	space: PhysicsDirectSpaceState3D,
	norm: Vector2,
	viewport_size: Vector2,
	anchors: Array
) -> void:
	var pixel := _AnnotationModel.denorm_point(norm, viewport_size)
	var from := cam.project_ray_origin(pixel)
	var dir := cam.project_ray_normal(pixel)
	var to := from + dir * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	anchors.append({
		"position": [hit.position.x, hit.position.y, hit.position.z],
		"normal": [hit.normal.x, hit.normal.y, hit.normal.z],
		"collider": str(hit.collider.name) if hit.collider != null else "",
	})


static func _nearby_plant_refs(sim: Node, anchors: Array) -> Array:
	var out: Array = []
	if sim == null or not sim.has_method("get") or sim.get("plant") == null:
		return out
	var plant: PlantData = sim.plant
	var tips: TipManager = sim.tips
	const MAX := 20
	const RADIUS := 0.35
	for anchor in anchors:
		if out.size() >= MAX:
			break
		var pos_arr: Array = anchor.get("position", [])
		if pos_arr.size() < 3:
			continue
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var best_seg := -1
		var best_d := RADIUS
		for i in plant.segment_count():
			var mid := (plant.seg_a[i] + plant.seg_b[i]) * 0.5
			var d := mid.distance_to(pos)
			if d < best_d:
				best_d = d
				best_seg = i
		if best_seg >= 0:
			var tip_id: int = plant.seg_tip[best_seg]
			var tip_state := ""
			if tip_id >= 0 and tip_id < tips.tips.size():
				tip_state = str(tips.tips[tip_id].state)
			out.append({
				"segment_index": best_seg,
				"tip_id": tip_id,
				"tip_state": tip_state,
				"distance": best_d,
			})
	return out


static func fingerprint_for(sim: Node) -> Dictionary:
	return _fingerprint(sim)


static func _fingerprint(sim: Node) -> Dictionary:
	var plant: PlantData = sim.plant
	var tips: TipManager = sim.tips
	return {
		"run_hash": _RunHash.of(plant, tips),
		"segment_count": plant.segment_count(),
		"leaf_count": plant.leaf_count(),
		"tip_count": tips.tips.size(),
		"live_tip_count": tips.live_count(),
		"total_length": plant.total_length,
	}
