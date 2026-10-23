extends Node

## Writes a minimal replayable snapshot for ivy-nrp.5 skill dry-runs (dev only).

const _SnapshotRecipe = preload("res://src/debug/snapshot_recipe.gd")
const _SnapshotCapture = preload("res://src/debug/snapshot_capture.gd")
const _SimRoot = preload("res://src/sim/sim_root.gd")
const _IvyParams = preload("res://src/params/ivy_params.gd")
const _SurfaceQuery = preload("res://src/world/surface_query.gd")
const _TowerSdf = preload("res://src/world/tower_sdf.gd")
const _TowerSpec = preload("res://src/world/tower_spec.gd")
const _SNAPSHOT_ROOT := "res://.tmp/snapshots/"


func _ready() -> void:
	var params := _IvyParams.new()
	var surface := _SurfaceQuery.new()
	surface.setup(null, null, _TowerSdf.new(_TowerSpec.new()), PackedByteArray(), params)
	var sim := _SimRoot.new()
	add_child(sim)
	sim.setup(params, surface, null, 0, null, false)
	var recipe := _SnapshotRecipe.new()
	recipe.scene = {"building_id": "cylinder", "seed_index": 0, "free_plant_mode": true}
	recipe.time = {"tick_index": sim.get_clock().tick_index, "game_day": sim.get_clock().game_day}
	recipe.plant_log = []
	recipe.param_log = []
	recipe.fingerprint = _SnapshotCapture.fingerprint_for(sim)
	recipe.note = "fixture for revisit-snapshot skill dry-run"
	recipe.annotations = [{
		"id": 1,
		"kind": "box",
		"comment": "south face seam",
		"rect": {"x": 0.4, "y": 0.35, "w": 0.2, "h": 0.25},
		"world_anchors": [{
			"position": [0.0, 2.0, 4.5],
			"normal": [0.0, 0.0, -1.0],
			"collider": "TowerWall",
		}],
		"nearby_plant": [],
	}]
	var img := Image.create(640, 480, false, Image.FORMAT_RGB8)
	img.fill(Color(0.42, 0.45, 0.5))
	var ann := img.duplicate()
	ann.fill_rect(Rect2i(256, 168, 128, 120), Color(1.0, 0.2, 0.75, 0.35))
	var folder := "fixture_nrp5"
	var dir := _SnapshotCapture.write_snapshot(recipe, img, folder, ann)
	var root := ProjectSettings.globalize_path(_SNAPSHOT_ROOT)
	var latest := FileAccess.open(root.path_join("latest"), FileAccess.WRITE)
	if latest != null:
		latest.store_string(folder)
	print("[write-snapshot-fixture] wrote ", dir)
	get_tree().quit()
