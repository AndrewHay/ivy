class_name SnapshotReplay
extends RefCounted

const _RunHash = preload("res://src/metrics/run_hash.gd")
const _SNAPSHOT_ROOT := "res://.tmp/snapshots/"


static func resolve_dir(spec: String) -> String:
	var root := ProjectSettings.globalize_path(_SNAPSHOT_ROOT)
	var folder := spec.strip_edges()
	if folder == "latest":
		var latest_path := root.path_join("latest")
		if not FileAccess.file_exists(latest_path):
			push_error("SnapshotReplay: no latest snapshot (missing %s)" % latest_path)
			return ""
		var latest_file := FileAccess.open(latest_path, FileAccess.READ)
		if latest_file == null:
			return ""
		folder = latest_file.get_as_text().strip_edges()
	if folder.is_empty():
		return ""
	if DirAccess.dir_exists_absolute(folder):
		return folder
	var candidate := root.path_join(folder)
	if DirAccess.dir_exists_absolute(candidate):
		return candidate
	push_error("SnapshotReplay: snapshot folder not found: %s" % spec)
	return ""


static func replay_to_tick(sim: Node, params: IvyParams, recipe) -> void:
	var target: int = int(recipe.time.get("tick_index", 0))
	var plant_log: Array = recipe.plant_log
	var param_log: Array = recipe.param_log
	var pi := 0
	var pai := 0
	while sim.get_clock().tick_index < target:
		var t: int = sim.get_clock().tick_index
		while pi < plant_log.size() and int(plant_log[pi].get("tick", -1)) == t:
			var e: Dictionary = plant_log[pi]
			var pos := _vec3_from_array(e.get("position", [0.0, 0.0, 0.0]))
			var n := _vec3_from_array(e.get("normal", [0.0, 0.0, 1.0]))
			sim.plant_at(pos, n)
			pi += 1
		while pai < param_log.size() and int(param_log[pai].get("tick", -1)) == t:
			var pe: Dictionary = param_log[pai]
			_apply_param(params, str(pe.get("name", "")), pe.get("value"))
			pai += 1
		sim.advance_ticks(1)


static func verify_fingerprint(sim: Node, recipe) -> Dictionary:
	var plant: PlantData = sim.plant
	var tips: TipManager = sim.tips
	var live_hash := _RunHash.of(plant, tips)
	var expected: String = str(recipe.fingerprint.get("run_hash", ""))
	var match := live_hash == expected
	return {
		"match": match,
		"expected": expected,
		"actual": live_hash,
		"segment_count": plant.segment_count(),
		"expected_segments": int(recipe.fingerprint.get("segment_count", -1)),
	}


static func restore_camera(main: Node, recipe) -> void:
	var block: Dictionary = recipe.camera
	if block.is_empty():
		return
	var debug_cam: DebugCamera = main.get_node_or_null("World/DebugCamera") as DebugCamera
	var active := str(block.get("active_camera", ""))
	if debug_cam != null and debug_cam.script_driven and debug_cam.has_method("apply_scripted_snapshot"):
		debug_cam.apply_scripted_snapshot(block)
		return
	if active == "CamSun":
		var cam_sun := main.get_node_or_null("World/CameraRig/CamSun") as Camera3D
		if cam_sun != null:
			cam_sun.make_current()


static func _vec3_from_array(arr: Variant) -> Vector3:
	if arr is Vector3:
		return arr
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


static func _apply_param(params: IvyParams, name: String, value: Variant) -> void:
	if name.is_empty():
		return
	if value is Array and value.size() >= 4:
		params.set(name, Color(float(value[0]), float(value[1]), float(value[2]), float(value[3])))
	else:
		params.set(name, value)
