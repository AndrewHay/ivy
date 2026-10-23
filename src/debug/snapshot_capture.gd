class_name SnapshotCapture
extends RefCounted

const _SnapshotRecipe = preload("res://src/debug/snapshot_recipe.gd")
const _RunHash = preload("res://src/metrics/run_hash.gd")
const _DebugSessionLog = preload("res://src/debug/debug_session_log.gd")
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
	folder_name: String
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
