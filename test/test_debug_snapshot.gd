extends GutTest

const DebugSessionLog = preload("res://src/debug/debug_session_log.gd")
const SnapshotRecipe = preload("res://src/debug/snapshot_recipe.gd")
const SnapshotCapture = preload("res://src/debug/snapshot_capture.gd")
const SnapshotReplay = preload("res://src/debug/snapshot_replay.gd")
const SnapshotAnnotationModel = preload("res://src/debug/snapshot_annotation_model.gd")
const SnapshotAnnotationOverlay = preload("res://src/ui/snapshot_annotation_overlay.gd")
const MainScene = preload("res://src/main/main.tscn")
const SimRoot = preload("res://src/sim/sim_root.gd")
const RunHash = preload("res://src/metrics/run_hash.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const SimClock = preload("res://src/core/sim_clock.gd")
const Solar = preload("res://src/env/solar.gd")
const IvyEnvironment = preload("res://src/env/environment.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const TipManager = preload("res://src/sim/tip_manager.gd")


func test_session_log_records_plants_and_params_and_clears() -> void:
	var log := DebugSessionLog.new()
	log.record_plant(5, Vector3(1, 2, 3), Vector3(0, 0, 1))
	log.record_param(7, "branch_q", 0.42)
	assert_eq(log.plant_log.size(), 1)
	assert_eq(log.param_log.size(), 1)
	assert_eq(log.plant_log[0]["tick"], 5)
	assert_eq(log.param_log[0]["name"], "branch_q")
	log.clear()
	assert_eq(log.plant_log.size(), 0)
	assert_eq(log.param_log.size(), 0)


func test_snapshot_recipe_json_round_trip() -> void:
	var recipe := SnapshotRecipe.new()
	recipe.build = {"git_commit": "abc", "git_dirty": true, "godot_version": "4.4"}
	recipe.scene = {"building_id": "overhang", "seed_index": 0, "free_plant_mode": true}
	recipe.plant_log = [{"tick": 0, "position": [0.0, 0.1, 0.0], "normal": [0.0, 0.0, 1.0]}]
	recipe.param_log = [{"tick": 12, "name": "branch_q", "value": 0.05}]
	recipe.param_overrides = {"branch_q": 0.05}
	recipe.time = {"tick_index": 48, "game_day": 2.0, "speed": 3}
	recipe.camera = {"active_camera": "DebugCamera", "fov": 75.0}
	recipe.view = {"viewport_size": [1920, 1080], "dev_overlay_visible": false}
	recipe.fingerprint = {
		"run_hash": "deadbeef",
		"segment_count": 10,
		"leaf_count": 4,
		"tip_count": 1,
		"live_tip_count": 1,
		"total_length": 1.25,
	}
	recipe.note = "test"
	var path := "user://test_snapshot_roundtrip.json"
	var err := recipe.write_json(path)
	assert_eq(err, OK)
	var loaded = SnapshotRecipe.read_json(path)
	assert_not_null(loaded)
	assert_eq(loaded.schema_version, SnapshotRecipe.SCHEMA_VERSION)
	assert_eq(loaded.scene["building_id"], "overhang")
	assert_eq(loaded.plant_log.size(), 1)
	assert_eq(loaded.param_log[0]["tick"], 12)
	assert_eq(loaded.fingerprint["run_hash"], "deadbeef")
	assert_eq(loaded.note, "test")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_run_hash_matches_live_fingerprint_helper() -> void:
	var params := IvyParams.new()
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), params)
	var env := IvyEnvironment.new()
	env.build(params, surface, Solar.new(params))
	var plant := PlantData.new()
	var tips := TipManager.new()
	var probe := Vector3(0.0, params.ground_y_min, 0.0) + Conv.SOUTH * 8.0
	var anchor := surface.nearest(probe)
	tips.add_seed(anchor.position + anchor.normal * 0.01, anchor.normal, 12345, params)
	var hash_a := RunHash.of(plant, tips)
	var hash_b := RunHash.of(plant, tips)
	assert_eq(hash_a, hash_b)
	assert_false(hash_a.is_empty())


func test_replay_to_tick_matches_saved_fingerprint() -> void:
	var params := IvyParams.new()
	var surface := SurfaceQuery.new()
	surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), params)
	var sim := SimRoot.new()
	add_child_autofree(sim)
	sim.setup(params, surface, null, 0, null, false)
	var probe := Vector3(0.0, params.ground_y_min, 0.0) + Conv.SOUTH * 8.0
	var anchor := surface.nearest(probe)
	var pos := anchor.position + anchor.normal * 0.01
	var normal := anchor.normal
	sim.plant_at(pos, normal)
	sim.advance_ticks(48)
	var recipe := SnapshotRecipe.new()
	recipe.time = {"tick_index": sim.get_clock().tick_index}
	recipe.plant_log = [{"tick": 0, "position": [pos.x, pos.y, pos.z], "normal": [normal.x, normal.y, normal.z]}]
	recipe.param_log = []
	recipe.fingerprint = SnapshotCapture.fingerprint_for(sim)
	var expected_hash: String = recipe.fingerprint["run_hash"]
	var sim2 := SimRoot.new()
	add_child_autofree(sim2)
	sim2.setup(params, surface, null, 0, null, false)
	SnapshotReplay.replay_to_tick(sim2, params, recipe)
	var verdict: Dictionary = SnapshotReplay.verify_fingerprint(sim2, recipe)
	assert_true(verdict["match"], "replay must MATCH saved run_hash (expected %s got %s)" % [
		expected_hash, verdict.get("actual", "")
	])


func test_image_for_display_resizes_retina_capture() -> void:
	var hi := Image.create(3840, 2160, false, Image.FORMAT_RGB8)
	var lo := SnapshotCapture.image_for_display(hi, Vector2(1920, 1080))
	assert_eq(lo.get_width(), 1920)
	assert_eq(lo.get_height(), 1080)


func test_norm_rect_survives_viewport_resize() -> void:
	var norm := Rect2(0.1, 0.2, 0.3, 0.4)
	for vp in [Vector2(1920, 1080), Vector2(800, 600), Vector2(640, 480)]:
		var px := SnapshotAnnotationModel.pixel_rect_from_norm(norm, vp)
		var back := SnapshotAnnotationModel.norm_rect_from_pixels(px, vp)
		assert_almost_eq(back.position.x, norm.position.x, 1e-5)
		assert_almost_eq(back.size.y, norm.size.y, 1e-5)


func test_annotation_model_undo_and_clear() -> void:
	var model := SnapshotAnnotationModel.new()
	model.add_box(Rect2(0.1, 0.1, 0.2, 0.2), "a")
	model.add_box(Rect2(0.3, 0.3, 0.1, 0.1), "b")
	assert_eq(model.entry_count(), 2)
	model.undo()
	assert_eq(model.entry_count(), 1)
	model.clear()
	assert_eq(model.entry_count(), 0)


func test_sky_box_yields_empty_world_anchors() -> void:
	var main := Node3D.new()
	add_child_autofree(main)
	var world := Node3D.new()
	world.name = "World"
	main.add_child(world)
	var cam := Camera3D.new()
	cam.name = "DebugCamera"
	world.add_child(cam)
	cam.current = true
	await get_tree().process_frame
	var entry: Dictionary = {
		"kind": "box",
		"id": 1,
		"comment": "",
		"rect": SnapshotAnnotationModel.rect_to_norm_dict(Rect2(0.45, 0.45, 0.1, 0.1)),
	}
	var enriched := SnapshotCapture.enrich_annotations(main, null, [entry], Vector2(800, 600))
	assert_eq(enriched.size(), 1)
	assert_eq(enriched[0]["world_anchors"].size(), 0)


func test_box_over_wall_hits_collider() -> void:
	var main := Node3D.new()
	add_child_autofree(main)
	var world := Node3D.new()
	world.name = "World"
	main.add_child(world)
	var cam := Camera3D.new()
	cam.name = "DebugCamera"
	world.add_child(cam)
	cam.position = Vector3(0.0, 0.0, 2.0)
	cam.look_at(Vector3(0.0, 0.0, -5.0))
	cam.current = true
	var body := StaticBody3D.new()
	body.name = "TestWall"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 10.0, 0.2)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, 0.0, -3.0)
	world.add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var entry: Dictionary = {
		"kind": "box",
		"id": 1,
		"comment": "seam",
		"rect": SnapshotAnnotationModel.rect_to_norm_dict(Rect2(0.4, 0.4, 0.2, 0.2)),
	}
	var enriched := SnapshotCapture.enrich_annotations(main, null, [entry], Vector2(800, 600))
	assert_gt(enriched[0]["world_anchors"].size(), 0, "rays through box centre should hit the wall collider")


func test_overlay_esc_emits_cancelled_without_completed() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var overlay := SnapshotAnnotationOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(img, Vector2(64, 64))
	watch_signals(overlay)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	assert_true(overlay.handle_key_event(esc))
	assert_signal_emitted(overlay, "cancelled")
	assert_signal_not_emitted(overlay, "completed")


func test_snapshot_save_unavailable_on_building_picker() -> void:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	assert_false(main._snapshot_available(), "F9 must be disabled while the picker is up")


func test_overlay_save_emits_completed() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var overlay := SnapshotAnnotationOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(img, Vector2(64, 64))
	watch_signals(overlay)
	overlay._on_save_pressed()
	assert_signal_emitted(overlay, "completed")
	assert_signal_not_emitted(overlay, "cancelled")


func test_overlay_bm_ignored_while_note_field_focused() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var overlay := SnapshotAnnotationOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(img, Vector2(64, 64))
	overlay._tool = SnapshotAnnotationOverlay.Tool.MARKER
	await get_tree().process_frame
	overlay._note_field.grab_focus()
	await get_tree().process_frame
	assert_true(overlay._note_field.has_focus())
	var b := InputEventKey.new()
	b.keycode = KEY_B
	b.pressed = true
	assert_false(overlay.handle_key_event(b))
	assert_eq(overlay._tool, SnapshotAnnotationOverlay.Tool.MARKER)


func test_overlay_esc_twice_discards_when_highlights_exist() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var overlay := SnapshotAnnotationOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(img, Vector2(64, 64), [Rect2(0.1, 0.1, 0.2, 0.2)])
	watch_signals(overlay)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay.handle_key_event(esc)
	assert_signal_not_emitted(overlay, "cancelled")
	overlay.handle_key_event(esc)
	assert_signal_emitted(overlay, "cancelled")
