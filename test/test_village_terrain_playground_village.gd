## ivy-82zn.14.8: the terrain playground shows the production village (cottages, path stones,
## pond water and bank, bushes) built by VillageBackdrop code on the playground terrain, re-seated
## after shape-knob edits; Village checkbox default ON.
extends GutTest

const VillageTerrainPlaygroundScene = preload("res://scenes/playground/village_terrain_playground.tscn")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

const _IDLE_FRAME_CAP := 6000


func _make_pg(village_on: bool = true) -> Node:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	pg.set("_grass_on", false)
	pg.set("_village_on", village_on)
	pg.set("_debounce_s", 0.02)
	add_child_autofree(pg)
	return pg


func _await_idle(pg: Node) -> bool:
	for _i in range(_IDLE_FRAME_CAP):
		if not pg.is_refining():
			return true
		await get_tree().process_frame
	return false


func _village(pg: Node) -> Node:
	return pg.get_node("Stage").get_node_or_null("Village")


func _child_prefixes(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for c in n.get_children():
		out.append(str(c.name))
	return out


func _has_prefix(names: PackedStringArray, prefix: String) -> bool:
	for s in names:
		if s.begins_with(prefix):
			return true
	return false


func _assert_cottages_on_terrain(pg: Node, v: Node) -> void:
	var layout: VillageLayout = pg._layout
	var params: VillageTerrainParams = pg._params
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var origins: Array = v._cottage_origins
	assert_eq(origins.size(), layout.cottages.size(), "one origin per cottage")
	for i in range(mini(origins.size(), layout.cottages.size())):
		var c: Vector2 = layout.cottages[i]["centre"]
		assert_almost_eq((origins[i] as Vector3).y,
			VillageTerrain.sample_y(c, layout, params, t_seed), 1e-4,
			"cottage %d seated at sample_y of the playground terrain" % i)


func test_village_and_grass_default_on() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	assert_not_null(pg.get("_village_on"), "playground has a Village toggle")
	assert_true(bool(pg.get("_village_on")), "Village checkbox default ON")
	assert_true(bool(pg.get("_grass_on")), "Grass checkbox default ON")
	pg.free()


func test_village_on_builds_production_village_on_playground_terrain() -> void:
	var pg := _make_pg(true)
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "terrain + village build finishes")
	var v := _village(pg)
	assert_not_null(v, "Stage/Village present with Village ON")
	if v == null:
		return
	assert_true(v is VillageBackdrop, "village is built by the production VillageBackdrop code")
	var names := _child_prefixes(v)
	for prefix in ["Cottage_", "Scatter_Path_", "PondWater", "PondBank", "Scatter_Bush_Common"]:
		assert_true(_has_prefix(names, prefix), "village has %s* (children: %s)" % [prefix, names])
	_assert_cottages_on_terrain(pg, v)
	# Path stones ride the playground terrain. ivy-82zn.14.10 contract change: on the exact sample_y
	# (as in production now; the 1 m LUT rounded bank creases past AC-VT7's 8 cm). The origin is read
	# from the buffer: get_instance_transform returns the identity headless (the old check compared
	# y 0 with a LUT that was 0 near the origin).
	var stones := v.get_node("Scatter_Path_0") as MultiMeshInstance3D
	var buf := stones.multimesh.buffer
	var o := Vector3(buf[3], buf[7], buf[11])
	var layout: VillageLayout = pg._layout
	assert_almost_eq(o.y, VillageTerrain.sample_y(Vector2(o.x, o.z), layout, pg._params,
		VillageTerrain.terrain_seed(layout, pg._params)), 1e-3,
		"path stone Y on the playground terrain (stone at %s)" % o)
	# Placeholder markers that the real village replaces are hidden; hero stand-in stays.
	var stage := pg.get_node("Stage")
	assert_false((stage.get_node("Cottage_0") as Node3D).visible, "cottage slab marker hidden")
	assert_false((stage.get_node("PondWater") as Node3D).visible, "pond marker hidden")
	assert_true((stage.get_node("HeroStandIn") as Node3D).visible, "hero stand-in visible")


func test_village_reseats_after_shape_change_with_status() -> void:
	var pg := _make_pg(true)
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "initial build finishes")
	var before := _village(pg)
	var y0: float = (before._cottage_origins[0] as Vector3).y
	pg._on_knob_changed("swell_amp_m", 2.0)
	var saw_status := false
	for _i in range(_IDLE_FRAME_CAP):
		await get_tree().process_frame
		if pg.rebuild_status().to_lower().contains("village"):
			saw_status = true
			assert_not_null(_village(pg), "old village stays on screen while the new one builds")
		if not pg.is_refining():
			break
	assert_true(saw_status, "status label shows the village re-seating")
	var after := _village(pg)
	assert_not_null(after)
	if after == null:
		return
	assert_ne(after, before, "village rebuilt for the new terrain")
	_assert_cottages_on_terrain(pg, after)
	assert_ne((after._cottage_origins[0] as Vector3).y, y0, "cottage moved with the terrain")


func test_sliced_pond_bank_equals_the_production_ring() -> void:
	## The host answers the production per-vertex bank y_fn from heights it evaluated in slices;
	## the PondBank mesh must equal the one production builds calling sample_y directly.
	var VillageHost: GDScript = load("res://src/playground/village_terrain_village_host.gd")
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var sliced: Node3D = VillageHost.new()
	var direct: Node3D = VillageHost.new()
	add_child_autofree(sliced)
	add_child_autofree(direct)
	sliced.configure(layout, params, t_seed, {})
	direct.configure(layout, params, t_seed, {})
	var pond_heights: int = VillageHost.STEPS.find("pond_heights")
	var pond: int = VillageHost.STEPS.find("pond")
	var slices := 1
	while not sliced.build_step(pond_heights, 2000):
		slices += 1
	assert_gt(slices, 3, "bank heights spread over several 2 ms slices")
	sliced.build_step(pond)
	direct.build_step(pond)  # no pond_heights first: production sample_y per vertex
	var a: PackedVector3Array = (sliced.get_node("PondBank") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = (direct.get_node("PondBank") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(a.size(), b.size(), "same bank vertex count")
	assert_eq(hash(a), hash(b), "same bank vertices as the production ring")


func test_village_off_removes_it_and_on_brings_it_back() -> void:
	var pg := _make_pg(true)
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "initial build finishes")
	var first := _village(pg)
	pg._set_village(false)
	await get_tree().process_frame
	assert_null(_village(pg), "Village OFF removes it from view")
	var stage := pg.get_node("Stage")
	assert_true((stage.get_node("Cottage_0") as Node3D).visible, "markers back when village is off")
	pg._set_village(true)
	assert_same(_village(pg), first, "ON with unchanged terrain shows the same village at once")
	assert_false(pg.is_refining(), "no rebuild needed")
	pg._set_village(false)
	pg._on_knob_changed("base_amplitude_m", 1.0)
	assert_true(await _await_idle(pg), "terrain rebuild finishes with village off")
	assert_null(_village(pg), "no village built while off")
	pg._set_village(true)
	assert_true(await _await_idle(pg), "village rebuild finishes")
	var again := _village(pg)
	assert_not_null(again, "Village ON builds it again")
	assert_ne(again, first, "re-seated on the new terrain")
	if again != null:
		_assert_cottages_on_terrain(pg, again)


func test_pond_depth_and_plaza_relief_change_the_village_ground() -> void:
	var pg := _make_pg(true)
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "initial build finishes")
	var layout: VillageLayout = pg._layout
	var pond0 := VillageTerrain.lut_sample(pg._terrain_lut, layout.pond_center)
	var plaza_c := layout.plaza_rect.get_center()
	var plaza0 := VillageTerrain.lut_sample(pg._terrain_lut, plaza_c)
	# The final clamp to -(max_depression_m + 0.05) also caps the basin, so open it with the depth.
	# Separate edits: a raised plaza also pulls the pond basin up (reported in ivy-82zn.14.8 notes;
	# test_pond_depth_response_characterization logs it).
	pg._on_knob_changed("max_depression_m", 4.0)
	pg._on_knob_changed("pond_depth_m", -3.0)
	assert_true(await _await_idle(pg), "rebuild finishes")
	var pond1 := VillageTerrain.lut_sample(pg._terrain_lut, layout.pond_center)
	pg._on_knob_changed("pond_depth_m", -0.6)
	pg._on_knob_changed("plaza_relief_m", 1.5)
	assert_true(await _await_idle(pg), "rebuild finishes")
	var plaza1 := VillageTerrain.lut_sample(pg._terrain_lut, plaza_c)
	gut.p("pond basin %.2f -> %.2f m, plaza %.2f -> %.2f m" % [pond0, pond1, plaza0, plaza1])
	assert_lt(pond1, pond0 - 1.5, "deeper pond_depth_m lowers the basin under the water")
	assert_gt(plaza1, plaza0 + 1.0, "plaza_relief_m raises the plaza")
	assert_not_null(_village(pg), "village present on the new ground")
