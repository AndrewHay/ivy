## Returning to the building picker mid-session (ivy-gyf).
##
## Drives the real Main scene: pick a building, plant, go back, pick again. The failure modes
## this guards against are all "second session inherits state from the first": leftover ivy
## meshes, a second HUD / dev overlay stacked on the first, a clock that keeps ticking behind
## the picker, and a camera that still answers keys while the picker is up.
extends GutTest

const MainScene = preload("res://src/main/main.tscn")
const SimClock = preload("res://src/core/sim_clock.gd")
const StemMeshBuilder = preload("res://src/render/stem_mesh.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func _boot(building_id: String) -> Node:
	var main := MainScene.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	await _pick(main, building_id)
	return main


## Choose a building the way the player does: through the picker, which frees itself. The
## selection handler is a coroutine the signal does not wait for, so poll until the HUD
## (the last thing a session builds) is up.
func _pick(main: Node, building_id: String) -> void:
	var picker: Node = main.get_node("UI/BuildingPicker")
	picker._on_entry_pressed(building_id)
	# After switching buildings, a coarse-cache verification miss can trigger a full
	# interactive ray bake (~30–60s). Headless runs ~100+ process frames/s; 900 frames
	# was too tight for cylinder → test_wall (ivy-nrp / change-building flake).
	const MAX_FRAMES := 7200
	for _i in range(MAX_FRAMES):
		if main._hud != null:
			break
		await get_tree().process_frame
	assert_not_null(main._hud, "session for '%s' never came up" % building_id)
	await get_tree().process_frame  # the picker's queue_free lands here


## Plant a seed at the south anchor and grow it, as a player would after clicking.
func _plant_and_grow(main: Node, ticks: int) -> void:
	var world: Node = main.get_node("World")
	var sim: Node = main.get_node("Sim")
	var anchor = world.call("get_seed_anchors").get_anchors()[2]
	sim.call("plant_at", anchor.position, anchor.normal)
	(sim.get_clock() as SimClock).set_speed(SimClock.Speed.GROW)
	sim.call("advance_ticks", ticks)


## Number of rendered stem triangles' surfaces across every chunk under PlantRender.
func _stem_surface_count(main: Node) -> int:
	var n := 0
	for chunk in main.get_node("PlantRender/StemChunks").get_children():
		var mesh := (chunk as MeshInstance3D).mesh
		if mesh != null:
			n += mesh.get_surface_count()
	return n


func _stem_chunk_count(main: Node) -> int:
	return main.get_node("PlantRender/StemChunks").get_child_count()


func _find_button(root: Node, text_prefix: String) -> Button:
	if root is Button and (root as Button).text.begins_with(text_prefix):
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, text_prefix)
		if found != null:
			return found
	return null


# ── renderer reset ──────────────────────────────────────────────────────────

func _make_plant_with_segments(n: int) -> PlantData:
	var plant := PlantData.new()
	for i in range(n):
		var a := Vector3(float(i) * 0.03, 0.0, 0.0)
		var b := Vector3(float(i + 1) * 0.03, 0.0, 0.0)
		plant.append_segment(a, b, Vector3.UP, 0, 0, float(i) * 0.03)
	return plant


## A second setup() must not stack a fresh chunk on top of the old session's chunks.
func test_stem_setup_twice_discards_the_previous_chunks() -> void:
	var builder := StemMeshBuilder.new()
	add_child_autofree(builder)
	builder.setup(IvyParams.new())
	builder.sync_from(_make_plant_with_segments(StemMeshBuilder.CHUNK_SEGMENTS * 2 + 5), 0)
	assert_gt(builder.get_child_count(), 1, "precondition: several sealed chunks exist")

	builder.setup(IvyParams.new())
	await get_tree().process_frame  # queue_free'd chunks leave the tree here
	assert_eq(builder.get_child_count(), 1,
		"only the fresh, empty hot chunk may remain after a second setup")
	assert_eq(builder._hot_count, 0)


# ── Clear ivy ───────────────────────────────────────────────────────────────

## "Clear ivy" replaced the plant data but left every stem mesh on screen, and the render's
## high-water mark meant a re-planted vine stayed invisible until it outgrew the old one.
func test_clear_ivy_removes_rendered_stems_and_new_growth_is_visible() -> void:
	var main: Node = await _boot("cylinder")
	main.get_node("PlantRender").call("setup", main.params)
	_plant_and_grow(main, 96)
	assert_gt(_stem_surface_count(main), 0, "precondition: grown ivy is rendered")

	main.get_node("Sim").call("clear_plants")
	await get_tree().process_frame
	assert_eq(_stem_surface_count(main), 0, "Clear ivy must remove the rendered stems")

	_plant_and_grow(main, 12)
	assert_gt(_stem_surface_count(main), 0,
		"a vine planted after clearing must render even though it is shorter than the old one")


# ── return to picker ────────────────────────────────────────────────────────

func test_hud_has_a_change_building_button_that_returns_to_the_picker() -> void:
	var main: Node = await _boot("cylinder")
	assert_null(main.get_node("UI").get_node_or_null("BuildingPicker"),
		"precondition: picker is gone during a session")
	var btn := _find_button(main.get_node("UI"), "Change building")
	assert_not_null(btn, "HUD must offer a Change building button")
	btn.pressed.emit()
	await get_tree().process_frame
	assert_not_null(main.get_node("UI").get_node_or_null("BuildingPicker"),
		"pressing it must bring the picker back")


func test_return_to_picker_tears_down_the_session() -> void:
	var main: Node = await _boot("cylinder")
	_plant_and_grow(main, 48)
	main.return_to_picker()
	await get_tree().process_frame

	assert_null(main.get_node("UI").get_node_or_null("Hud"), "HUD must be removed")
	assert_null(main.get_node_or_null("DevUI"), "dev overlay layer must be removed")
	assert_null(main.get_node("World").get_node_or_null("FieldViz"), "field viz must be removed")
	assert_null(main.get_node("World").get_node_or_null("PlantingTool"),
		"planting tool must be removed")
	assert_eq((main.get_node("Sim").get_clock() as SimClock).speed, SimClock.Speed.PAUSE,
		"the sim must not keep ticking behind the picker")
	assert_eq(_stem_surface_count(main), 0, "the old ivy must not stay on screen")
	assert_eq(main.get_node("World/CameraRig/CamSun").current, true,
		"the authored camera must be current while the picker is up")


## Keys must not move a camera the player cannot see, nor re-activate it behind the picker.
func test_debug_camera_ignores_keys_while_the_picker_is_up() -> void:
	var main: Node = await _boot("cylinder")
	main.return_to_picker()
	await get_tree().process_frame

	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_RIGHT
	main.get_node("World/DebugCamera")._unhandled_input(key)
	assert_false(main.get_node("World/DebugCamera").current,
		"the debug camera must stay inactive until a building is chosen")


func test_second_session_is_clean_after_switching_buildings() -> void:
	var main: Node = await _boot("cylinder")
	_plant_and_grow(main, 48)
	main.return_to_picker()
	await get_tree().process_frame

	await _pick(main, "test_wall")

	assert_null(main.get_node("UI").get_node_or_null("BuildingPicker"))
	assert_eq(main.get_node("Sim").tips.tips.size(), 0, "no tip survives into the new session")
	assert_eq(main.get_node("Sim").plant.segment_count(), 0, "no segment survives either")
	assert_eq(_stem_surface_count(main), 0, "no old ivy mesh in the new session")
	assert_eq(_stem_chunk_count(main), 1, "exactly the fresh hot chunk")
	var huds := 0
	for c in main.get_node("UI").get_children():
		if c is Hud:
			huds += 1
	assert_eq(huds, 1, "exactly one HUD, not one per session")
	var dev_layers := 0
	for c in main.get_children():
		if c.name.begins_with("DevUI"):
			dev_layers += 1
	assert_eq(dev_layers, 1, "exactly one dev overlay, not one per session")
	assert_almost_eq(main.get_node("World").get_orbit_pivot().y, main.get_node("World").wall_spec.height * 0.5,
		1e-4, "the camera pivot must follow the new building")
	assert_not_null(main.get_node("World").surface, "the new building has a surface to grow on")


## Picking the same building again is the "what if I try again" path, and the second plant
## must grow and render exactly like the first.
func test_replanting_the_same_building_grows_and_renders() -> void:
	var main: Node = await _boot("cylinder")
	_plant_and_grow(main, 48)
	main.return_to_picker()
	await get_tree().process_frame

	await _pick(main, "cylinder")
	main.get_node("PlantRender").call("sync", main.get_node("Sim").plant)
	_plant_and_grow(main, 48)
	assert_gt(main.get_node("Sim").plant.segment_count(), 0, "ivy must grow in the second session")
	assert_gt(_stem_surface_count(main), 0, "and it must be drawn")
