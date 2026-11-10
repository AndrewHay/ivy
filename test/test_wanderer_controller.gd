extends GutTest

const WandererController = preload("res://src/presentation/wanderer/wanderer_controller.gd")
const WandererBrain = preload("res://src/presentation/wanderer/wanderer_brain.gd")
const WandererIntegration = preload("res://src/presentation/wanderer/wanderer_integration.gd")
const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")
const VillageBackdropScene = preload("res://src/world/village_backdrop.tscn")


func _classic_controller(pause_with_sim: bool) -> WandererController:
	WandererIntegration.set_gut_wanderer_test_active(true)
	var bd: VillageBackdrop = VillageBackdropScene.instantiate()
	add_child_autofree(bd)
	await get_tree().process_frame
	var w := WandererController.new()
	var p: WandererParams = w.get("_params")
	p.pause_with_sim = pause_with_sim
	w.set("_params", p)
	add_child_autofree(w)
	w.bind_backdrop(bd, "classic")
	return w


func test_instance_smoke() -> void:
	WandererIntegration.set_gut_wanderer_test_active(true)
	var w := WandererController.new()
	add_child_autofree(w)
	assert_not_null(w.get_brain())
	w.debug_advance(2.0)
	WandererIntegration.set_gut_wanderer_test_active(false)


func test_pause_with_sim_freezes_position() -> void:
	var w := await _classic_controller(true)
	w.tick(0.0, false)
	var p0 := w.get_figure_global_position()
	w.tick(1.0 / 30.0, true)
	w.tick(1.0 / 30.0, true)
	assert_eq(w.get_figure_global_position(), p0)


func test_pause_with_sim_false_keeps_moving() -> void:
	var w := await _classic_controller(false)
	var p0 := w.get_figure_global_position()
	w.tick(0.5, true)
	var p1 := w.get_figure_global_position()
	assert_gt(p0.distance_to(p1), 0.01)


func test_debug_advance_ignores_sim_pause() -> void:
	var w := await _classic_controller(true)
	var p0 := w.get_figure_global_position()
	w.debug_advance(0.5)
	var p1 := w.get_figure_global_position()
	assert_gt(p0.distance_to(p1), 0.01)


func test_twelve_cycle_node_stability() -> void:
	var w := await _classic_controller(false)
	var n0 := w.get_child_count()
	w.debug_advance(1200.0)
	assert_eq(w.get_child_count(), n0)
	assert_gte(w.get_brain().cycles_completed, 12)


func test_bubble_panel_hidden_after_quote_ends() -> void:
	var w := await _classic_controller(false)
	assert_true(w.debug_advance_to("SAYING", 120.0))
	var brain := w.get_brain()
	var t := 0.0
	while t < 30.0 and brain.bubble_text.length() > 0:
		w.tick(1.0 / 30.0, false)
		t += 1.0 / 30.0
	while t < 60.0 and brain.state == WandererBrain.State.SAYING:
		w.tick(1.0 / 30.0, false)
		t += 1.0 / 30.0
	assert_true(brain.bubble_text.is_empty())
	var panel: Sprite3D = w.get("_bubble_panel")
	assert_false(panel.visible)


func test_debug_advance_to_exit_walk() -> void:
	var w := await _classic_controller(false)
	assert_true(w.debug_advance_to("EXIT_WALK", 180.0))


func test_showing_image_node_matches_placement() -> void:
	var w := await _classic_controller(false)
	assert_true(w.debug_advance_to("SHOWING", 180.0))
	w.tick(0.5, false)
	var brain := w.get_brain()
	var mi: MeshInstance3D = w.get("_image_mi")
	assert_true(mi.visible)
	var pl: Dictionary = brain.image_placement
	assert_almost_eq(mi.position.x, float(pl["centre"].x), 1e-4)
	assert_almost_eq(mi.rotation.y, float(pl["yaw"]), 1e-4)
	var sz: Vector2 = (mi.mesh as QuadMesh).size
	var psz: Vector2 = pl["size"]
	assert_almost_eq(sz.x, psz.x, 1e-3)
	assert_almost_eq(sz.y, psz.y, 1e-3)


func _exit_tree() -> void:
	WandererIntegration.set_gut_wanderer_test_active(false)
