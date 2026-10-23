class_name SnapshotRecipe
extends RefCounted

const SCHEMA_VERSION := 1

var schema_version: int = SCHEMA_VERSION
var build: Dictionary = {}
var scene: Dictionary = {}
var plant_log: Array = []
var param_log: Array = []
var param_overrides: Dictionary = {}
var time: Dictionary = {}
var camera: Dictionary = {}
var view: Dictionary = {}
var fingerprint: Dictionary = {}
var annotations: Array = []
var note: String = ""


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"build": build.duplicate(true),
		"scene": scene.duplicate(true),
		"plant_log": plant_log.duplicate(true),
		"param_log": param_log.duplicate(true),
		"param_overrides": param_overrides.duplicate(true),
		"time": time.duplicate(true),
		"camera": camera.duplicate(true),
		"view": view.duplicate(true),
		"fingerprint": fingerprint.duplicate(true),
		"annotations": annotations.duplicate(true),
		"note": note,
	}


static func from_dict(data: Dictionary):
	var r = load("res://src/debug/snapshot_recipe.gd").new()
	r.schema_version = int(data.get("schema_version", 0))
	r.build = data.get("build", {})
	r.scene = data.get("scene", {})
	r.plant_log = data.get("plant_log", [])
	r.param_log = data.get("param_log", [])
	r.param_overrides = data.get("param_overrides", {})
	r.time = data.get("time", {})
	r.camera = data.get("camera", {})
	r.view = data.get("view", {})
	r.fingerprint = data.get("fingerprint", {})
	r.annotations = data.get("annotations", [])
	r.note = str(data.get("note", ""))
	return r


func write_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


static func read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SnapshotRecipe: cannot read %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("SnapshotRecipe: invalid JSON in %s" % path)
		return null
	return load("res://src/debug/snapshot_recipe.gd").from_dict(parsed)
