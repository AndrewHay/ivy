extends GutTest

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")
const WandererFigure = preload("res://src/presentation/wanderer/wanderer_figure.gd")
const WandererKnobSpec = preload("res://src/playground/wanderer_knob_spec.gd")
const WandererBrain = preload("res://src/presentation/wanderer/wanderer_brain.gd")
const PlaygroundScene = preload("res://scenes/playground/wanderer_playground.tscn")

const _DT := 1.0 / 30.0


func test_playground_defaults_match_production_knobs() -> void:
	var prod := WandererParams.production()
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	var p: WandererParams = root.call("playground_params")
	assert_not_null(p)
	for row in WandererKnobSpec.all_knobs():
		var name: String = row["name"]
		var pv: Variant = p.get(name)
		var ev: Variant = prod.get(name)
		if typeof(pv) == TYPE_FLOAT:
			assert_almost_eq(float(pv), float(ev), 1e-5, "knob %s" % name)
		else:
			assert_eq(pv, ev, "knob %s" % name)
	assert_eq(p.variant, 0, "default variant is Current (production)")


func test_pose_parity_current_variant_after_reset() -> void:
	var prod := WandererParams.production()
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	var p: WandererParams = root.call("playground_params")
	p.walk_speed_mps = 1.7
	p.bob_m = 0.11
	root.call("playground_reset_production")
	for motion in [0.0, 0.5, 1.0]:
		for phase in [0.0, PI * 0.25, PI * 0.5]:
			var a := WandererFigure.pose(0, p, phase, motion)
			var b := WandererFigure.pose(0, prod, phase, motion)
			for key in a.keys():
				if typeof(a[key]) == TYPE_FLOAT:
					assert_almost_eq(a[key], b[key], 1e-5, "%s motion=%s phase=%s" % [key, motion, phase])
				else:
					assert_eq(a[key], b[key])


func test_step_out_drives_brain_exit_walk() -> void:
	var root: Node3D = PlaygroundScene.instantiate()
	root.set("script_driven", true)
	add_child_autofree(root)
	await get_tree().process_frame
	root.call("_step_out_brain")
	var brain: WandererBrain = root.get("_brain")
	var t := 0.0
	var saw_exit_walk := false
	while t < 30.0:
		if brain.state == WandererBrain.State.EXIT_WALK:
			saw_exit_walk = true
			break
		brain.tick(_DT)
		t += _DT
	assert_true(saw_exit_walk, "Step out must reach EXIT_WALK")
