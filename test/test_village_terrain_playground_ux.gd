## ivy-82zn.14.7: terrain playground responsiveness + grass.
## Material-only knobs keep the mesh, HUD stats read the LUT, shape knobs rebuild time-sliced
## (coarse preview, then full resolution, debounced), Grass checkbox uses the production builder.
extends GutTest

const VillageTerrainPlaygroundScene = preload("res://scenes/playground/village_terrain_playground.tscn")
const VillageTerrainPlayground = preload("res://src/playground/village_terrain_playground.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

const _IDLE_FRAME_CAP := 3000


func _make_pg(grass_on: bool = false) -> Node:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	pg.set("_grass_on", grass_on)
	pg.set("_village_on", false)  # village has its own tests (test_village_terrain_playground_village)
	pg.set("_debounce_s", 0.02)
	add_child_autofree(pg)
	return pg


func _await_idle(pg: Node) -> bool:
	for _i in range(_IDLE_FRAME_CAP):
		if not pg.is_refining():
			return true
		await get_tree().process_frame
	return false


func _terrain(pg: Node) -> MeshInstance3D:
	return pg.get_node("Stage").get_node_or_null("LawnTerrain") as MeshInstance3D


# ── VillageTerrain: resumable LUT + mesh-from-LUT (shared with build_mesh) ────

func test_lut_job_in_slices_matches_one_shot_lut() -> void:
	var params := VillageTerrainParams.production()
	params.layout_seed = 7
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	VillageTerrain.clear_caches()
	var job := VillageTerrain.lut_job_begin(layout, params, t_seed, 6.0)
	var steps := 0
	while not VillageTerrain.lut_job_step(job, 2000):
		steps += 1
		assert_lt(steps, 100000, "job must finish")
		if steps >= 100000:
			return
	assert_gt(steps, 1, "a 2 ms budget must split the 6 m LUT over several steps")
	var sliced: PackedFloat32Array = (job["lut"] as Dictionary)["data"]
	VillageTerrain.clear_caches()
	var one_shot := VillageTerrain.build_sample_lut(layout, params, t_seed, 6.0)
	assert_eq(hash(sliced), hash(one_shot["data"]), "sliced LUT must equal the one-shot LUT")


func test_mesh_from_lut_equals_build_mesh() -> void:
	var params := VillageTerrainParams.production()
	params.layout_seed = 7
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var mesh := VillageTerrain.build_mesh(layout, params)
	var step := maxf(params.terrain_mesh_step_m, 0.1)
	var lut := VillageTerrain.build_sample_lut(layout, params, t_seed, step)
	# ivy-82zn.14.14: with params the join-loop vertices take the exact field (as build_mesh).
	var mesh2 := VillageTerrain.mesh_from_lut(layout, step, lut, params)
	assert_not_null(mesh2)
	if mesh2 == null:
		return
	var a: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = mesh2.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(a.size(), b.size(), "same vertex count")
	assert_eq(hash(a), hash(b), "same vertex positions")


# ── HUD stats from the LUT ────────────────────────────────────────────────────

func test_stats_from_lut_read_only_the_lut() -> void:
	## Synthetic planar ramp h = 0.1 * (x - x0): no terrain sampler could produce it.
	var cols := 21
	var data := PackedFloat32Array()
	data.resize(cols * cols)
	for row in range(cols):
		for col in range(cols):
			data[row * cols + col] = 0.1 * float(col)
	var lut := {"origin_xz": Vector2(-10, -10), "cell_m": 1.0, "cols": cols, "rows": cols, "data": data}
	var s: Dictionary = VillageTerrainPlayground.terrain_stats_from_lut(
		lut, Vector2.ZERO, 8.0, Vector2(2.0, 0.0), Vector2(-3.0, 0.0))
	assert_almost_eq(float(s["min_h"]), 0.3, 0.051, "min inside r=8 disc (x=-7)")
	assert_almost_eq(float(s["max_h"]), 1.7, 0.051, "max inside r=8 disc (x=+7)")
	assert_almost_eq(float(s["max_slope_deg"]), rad_to_deg(atan(0.1)), 0.05, "ramp slope")
	assert_almost_eq(float(s["hero_h"]), 1.2, 1e-4, "hero from LUT")
	assert_almost_eq(float(s["pond_basin_h"]), 0.7, 1e-4, "pond from LUT")


func test_compute_terrain_stats_matches_current_lut() -> void:
	var pg := _make_pg()
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "rebuild must finish")
	var lut: Dictionary = pg._terrain_lut
	assert_false(lut.is_empty(), "playground keeps the full-resolution LUT")
	var layout: VillageLayout = pg._layout
	var expect: Dictionary = VillageTerrainPlayground.terrain_stats_from_lut(
		lut, layout.hamlet_centre_xz, layout.lawn_radius,
		VillageLayout.HERO_DOOR_STOOP, layout.pond_center)
	var got: Dictionary = pg.compute_terrain_stats()
	for k in ["min_h", "max_h", "max_slope_deg", "hero_h", "pond_basin_h"]:
		assert_almost_eq(float(got[k]), float(expect[k]), 1e-6, "stat %s from LUT" % k)


# ── Material-only knobs and debug toggles ─────────────────────────────────────

func test_material_knobs_and_debug_toggles_keep_the_mesh() -> void:
	var pg := _make_pg()
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "initial rebuild must finish")
	var mi := _terrain(pg)
	var mesh := mi.mesh
	var rebuilds: int = pg._rebuild_count
	pg._set_debug_relief(false)
	pg._on_knob_changed("ground_slope_dark", 0.55)
	pg._on_knob_changed("ground_slope_full_deg", 7.0)
	pg._on_knob_changed("ground_height_tint", 0.2)
	pg._on_knob_changed("ground_height_range_m", 0.9)
	pg._set_debug_contour(0.5)
	pg._set_debug_ve(3.0)
	pg._set_debug_relief(true)
	pg._set_debug_relief(false)
	for _i in range(10):
		await get_tree().process_frame
	assert_false(pg.is_refining(), "no rebuild pending after material-only edits")
	assert_eq(pg._rebuild_count, rebuilds, "no terrain rebuild")
	assert_same(_terrain(pg), mi, "same LawnTerrain node")
	assert_same(_terrain(pg).mesh, mesh, "same LawnTerrain mesh")
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("terrain_slope_dark")), 0.55, 1e-5)
	assert_almost_eq(float(mat.get_shader_parameter("terrain_height_range_m")), 0.9, 1e-5)
	pg._set_debug_relief(true)
	var dmat := mesh.surface_get_material(0) as ShaderMaterial
	assert_true(dmat.shader.resource_path.contains("village_terrain_debug"), "debug shader back on")
	assert_almost_eq(float(dmat.get_shader_parameter("ve_scale")), 3.0, 1e-5)
	assert_almost_eq(float(dmat.get_shader_parameter("contour_m")), 0.5, 1e-5)


# ── Shape knobs: debounced, coarse preview, then full resolution ──────────────

func test_slider_drag_burst_causes_one_rebuild() -> void:
	var pg := _make_pg()
	pg.set("_debounce_s", 0.15)
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "initial rebuild must finish")
	var rebuilds: int = pg._rebuild_count
	var mesh := _terrain(pg).mesh
	for i in range(8):
		pg._on_knob_changed("base_amplitude_m", 0.4 + 0.02 * float(i))
		await get_tree().process_frame
	assert_eq(pg._rebuild_count, rebuilds, "no rebuild starts while the drag continues")
	assert_true(pg.is_refining(), "a pending rebuild counts as refining")
	assert_true(await _await_idle(pg), "rebuild must finish")
	assert_eq(pg._rebuild_count, rebuilds + 1, "one drag causes exactly one rebuild")
	assert_ne(_terrain(pg).mesh, mesh, "terrain mesh replaced")


func test_shape_change_shows_coarse_preview_then_full_mesh() -> void:
	var pg := _make_pg()
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "initial rebuild must finish")
	var full_verts := _terrain(pg).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() as int
	pg._on_knob_changed("pond_depth_m", -0.8)  # terrain class: same layout, field + meshes rebuilt
	var saw_coarse := false
	for _i in range(_IDLE_FRAME_CAP):
		await get_tree().process_frame
		if pg.is_refining() and pg._shown_step_m > pg._params.terrain_mesh_step_m + 0.01:
			saw_coarse = true
			assert_ne(pg.rebuild_status(), "", "status text while refining")
		if not pg.is_refining():
			break
	assert_true(saw_coarse, "a coarse preview mesh is shown before full resolution")
	assert_false(pg.is_refining(), "refine finishes")
	assert_eq(pg.rebuild_status(), "", "status clears when idle")
	var verts := _terrain(pg).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() as int
	assert_eq(verts, full_verts, "full-resolution mesh after refine")


# ── Grass (production builder + 1 m LUT) ──────────────────────────────────────

func test_grass_on_uses_production_builder_and_off_removes_it() -> void:
	var pg := _make_pg(true)
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "terrain + grass build must finish")
	var grass: Node = pg.get_node("Stage").get_node_or_null("LawnGrass")
	assert_not_null(grass, "LawnGrass host present with grass ON")
	if grass == null:
		return
	assert_true(grass is VillageBackdrop, "grass host is the production VillageBackdrop builder")
	var blades: MultiMeshInstance3D = null
	var n_chunks := 0
	for c in grass.get_children():
		if str(c.name).begins_with("Scatter_Grass_Blades_"):
			n_chunks += 1
			blades = c as MultiMeshInstance3D
	assert_gt(n_chunks, 10, "grass blade chunks built")
	if blades == null:
		return
	# Blade Y comes from the production 1 m LUT for the playground params.
	var params: VillageTerrainParams = pg._params
	var layout: VillageLayout = pg._layout
	var lut := VillageTerrain.build_sample_lut(
		layout, params, VillageTerrain.terrain_seed(layout, params), 1.0)
	## ivy-82zn.14.10: read the instance origin from the buffer (get_instance_transform returns the
	## identity for these buffer-filled MultiMeshes headless; the old check compared y 0 with a LUT
	## that was 0 at (0, 0) before the hill, so it never looked at a baked blade).
	var buf := blades.multimesh.buffer
	var stride := 16 if blades.multimesh.use_colors else 12
	var o := Vector3(buf[3], buf[7], buf[11])
	assert_true(blades.multimesh.instance_count > 0 and buf.size() >= stride, "blade instances present")
	assert_almost_eq(o.y, VillageTerrain.lut_sample(lut, Vector2(o.x, o.z)), 1e-3,
		"blade Y baked from the 1 m LUT (blade at %s)" % o)
	pg._set_grass(false)
	await get_tree().process_frame
	assert_null(pg.get_node("Stage").get_node_or_null("LawnGrass"), "grass OFF removes it")


func test_grass_refreshes_after_shape_change() -> void:
	var pg := _make_pg(true)
	await get_tree().process_frame
	assert_true(await _await_idle(pg), "initial build must finish")
	var grass_before: Node = pg.get_node("Stage").get_node_or_null("LawnGrass")
	assert_not_null(grass_before)
	pg._on_knob_changed("base_amplitude_m", 0.2)
	assert_true(await _await_idle(pg), "rebuild + grass must finish")
	var grass_after: Node = pg.get_node("Stage").get_node_or_null("LawnGrass")
	assert_not_null(grass_after, "grass present after rebuild")
	assert_ne(grass_after, grass_before, "grass rebuilt for the new terrain")


# ── Global state restored on exit ─────────────────────────────────────────────

func test_exit_restores_pond_shape_and_terrain_batch_state() -> void:
	var before := VillagePondShape.active()
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	pg.set("_grass_on", false)
	add_child(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	remove_child(pg)
	pg.free()
	assert_eq(VillagePondShape.active(), before, "pond shape restored on exit")
	# ivy-82zn.14.14: no static signature batch any more (the field cache lives on the layout).
	assert_false((VillageTerrain as GDScript).get_script_constant_map().has("_sig_batch_depth"),
		"no global terrain batch state")
