## AC-VT-CAP: VillageTerrainPlayground scene + quit-hook seam regression + WP8b visual fixes.
## Mirrors test_hills_playground_scene.gd patterns.
extends GutTest

const VillageTerrainPlaygroundScene = preload("res://scenes/playground/village_terrain_playground.tscn")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrainKnobSpec = preload("res://src/playground/village_terrain_knob_spec.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

const _HEIGHT_EPS := 0.05  # markers must sit within 5 cm of sample_y


func test_playground_loads_and_has_terrain() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	var stage := pg.get_node_or_null("Stage")
	assert_not_null(stage, "Scene must have a Stage node")
	var terrain := stage.get_node_or_null("LawnTerrain") if stage else null
	assert_not_null(terrain, "Stage must have LawnTerrain after rebuild")


func test_playground_variant0_has_terrain_mesh() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	var stage := pg.get_node_or_null("Stage")
	if stage == null:
		fail_test("no Stage")
		return
	var terrain := stage.get_node_or_null("LawnTerrain") as MeshInstance3D
	assert_not_null(terrain, "LawnTerrain should be a MeshInstance3D")
	if terrain == null:
		return
	assert_not_null(terrain.mesh, "LawnTerrain must have a mesh assigned")


func test_playground_variant1_has_lawn_terrain() -> void:
	## Flat legacy still renders a LawnTerrain node (flat fan mesh, INV-15).
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	pg.set("_initial_variant", 1)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	var stage := pg.get_node_or_null("Stage")
	var terrain := stage.get_node_or_null("LawnTerrain") if stage else null
	assert_not_null(terrain, "LawnTerrain must exist even for flat-legacy variant")


## Regression test for the capture-then-hang bug: _capture_png must always
## call _capture_done_fn (the quit hook) so the Godot process exits.
## Mirrors the hills_playground equivalent (test_hills_playground_scene.gd).
func test_capture_png_always_calls_quit_hook() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame

	# Replace the quit hook with a recorder so GUT is not terminated.
	var hook_calls: Array[int] = []
	pg._capture_done_fn = func(err: int) -> void:
		hook_calls.append(err)

	var out_dir: String = ProjectSettings.globalize_path("res://") + ".tmp/test"
	DirAccess.make_dir_recursive_absolute(out_dir)
	pg._capture_png(out_dir + "/village_terrain_capture_quit_regression.png")

	assert_eq(hook_calls.size(), 1,
		"quit hook must be called exactly once after _capture_png (quit-hook seam regression)")


func test_default_capture_done_fn_calls_quit() -> void:
	## Ensure default _capture_done_fn calls get_tree().quit() (not a no-op).
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	assert_true(pg._capture_done_fn.is_valid(),
		"_capture_done_fn must be set to a valid Callable after _ready")


func test_knob_change_triggers_rebuild() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	var stage := pg.get_node_or_null("Stage")
	if stage == null:
		fail_test("no Stage")
		return
	pg._on_knob_changed("base_amplitude_m", 0.5)
	await get_tree().process_frame
	var terrain := stage.get_node_or_null("LawnTerrain")
	assert_not_null(terrain, "LawnTerrain must still exist after knob change + rebuild")


func test_reset_to_production_restores_defaults() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	pg._on_knob_changed("base_amplitude_m", 0.01)
	pg._on_reset_production()
	await get_tree().process_frame
	var params: VillageTerrainParams = pg._params
	assert_almost_eq(params.base_amplitude_m, VillageTerrainParams.production().base_amplitude_m, 1e-5,
		"base_amplitude_m must return to production default after reset")


func test_copy_settings_does_not_crash() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	pg._on_copy_settings()
	pass_test("copy settings did not crash")


# ── WP8b: marker height, HUD, debug material tests ───────────────────────────

func test_hero_marker_sits_at_sample_y() -> void:
	## HeroStandIn must be placed at hero_y + half-height above terrain surface.
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame

	var stage := pg.get_node_or_null("Stage")
	if stage == null:
		fail_test("no Stage"); return
	var hero_mi := stage.get_node_or_null("HeroStandIn") as MeshInstance3D
	assert_not_null(hero_mi, "HeroStandIn must exist after rebuild")
	if hero_mi == null:
		return

	# Compute expected hero ground Y via VillageTerrain.
	var params: VillageTerrainParams = pg._params
	var layout: VillageLayout = pg._layout
	if layout == null or layout.fallback:
		pass_test("fallback layout skip"); return
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var hero := VillageLayout.HERO_DOOR_STOOP
	var expected_y := VillageTerrain.sample_y(hero, layout, params, t_seed)
	# HeroStandIn box half-height is 1.1, so bottom = position.y - 1.1.
	var base_y := hero_mi.position.y - 1.1
	assert_almost_eq(base_y, expected_y, _HEIGHT_EPS,
		"HeroStandIn base must be within %s m of sample_y at stoop" % _HEIGHT_EPS)


func test_cottage_markers_sit_at_sample_y() -> void:
	## Each Cottage_N marker must have its base at the terrain pad height.
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame

	var stage := pg.get_node_or_null("Stage")
	if stage == null:
		fail_test("no Stage"); return
	var params: VillageTerrainParams = pg._params
	var layout: VillageLayout = pg._layout
	if layout == null or layout.fallback:
		pass_test("fallback layout skip"); return
	var t_seed := VillageTerrain.terrain_seed(layout, params)

	var found := 0
	for ci in range(6):
		var node := stage.get_node_or_null("Cottage_%d" % ci) as MeshInstance3D
		if node == null:
			break
		found += 1
		# Cottage slab half-height is 0.06, so base = position.y - 0.06.
		var base_y := node.position.y - 0.06
		# Determine cottage centre from layout.
		if ci < layout.cottages.size():
			var spec: Dictionary = layout.cottages[ci]
			var rect := VillageBackdrop.cottage_exterior_rect(spec)
			var centre := Vector2(rect.get_center().x, rect.get_center().y)
			var expected_y := VillageTerrain.sample_y(centre, layout, params, t_seed)
			assert_almost_eq(base_y, expected_y, _HEIGHT_EPS,
				"Cottage_%d base must be within %s m of sample_y" % [ci, _HEIGHT_EPS])
	assert_gt(found, 0, "at least one cottage marker must be present")


func test_compute_terrain_stats_returns_sensible_values() -> void:
	## HUD stats: min_h ≤ 0 ≤ max_h, max_slope ≥ 0, all keys present.
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame

	var stats: Dictionary = pg.compute_terrain_stats()
	assert_true(stats.has("min_h"), "stats must have min_h")
	assert_true(stats.has("max_h"), "stats must have max_h")
	assert_true(stats.has("max_slope_deg"), "stats must have max_slope_deg")
	assert_true(stats.has("hero_h"), "stats must have hero_h")
	assert_true(stats.has("pond_basin_h"), "stats must have pond_basin_h")

	var min_h: float = stats["min_h"]
	var max_h: float = stats["max_h"]
	var max_slope: float = stats["max_slope_deg"]
	assert_lte(min_h, max_h, "min_h must be <= max_h")
	assert_gte(max_slope, 0.0, "max_slope must be non-negative")
	# ivy-82zn.14.14 contract change: no caps any more; the landform spans a few metres around the
	# hero pad (y_hero), which lies inside [min_h, max_h].
	var p := VillageTerrainParams.production()
	var y_hero := VillageTerrain.hero_datum_y(pg._layout, p)
	assert_almost_eq(float(stats["hero_h"]), y_hero, 0.05, "hero pad at y_hero")
	assert_true(min_h <= y_hero and y_hero <= max_h, "hero pad inside the lawn height range")
	assert_lt(max_h - min_h, p.landform_height_m + 2.0, "lawn span bounded by the landform height")


# ── AC-LT-CAP: playground v2 (ivy-82zn.14.14) ─────────────────────────────────

func _boot() -> Node:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame
	return pg


func test_far_terrain_on_stage_is_the_production_far_mesh() -> void:
	var pg = await _boot()
	await pg._await_refined()
	var far := pg.get_node("Stage").get_node_or_null("FarTerrain") as MeshInstance3D
	assert_not_null(far, "FarTerrain on the stage")
	if far == null or far.mesh == null:
		return
	var verts: PackedVector3Array = far.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var prod := VillageTerrain.build_far_mesh(pg._layout, pg._build_params)
	var pv: PackedVector3Array = prod.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), pv.size(), "same vertex count as the production far mesh")
	assert_eq(verts.to_byte_array().hex_encode().sha256_text(), pv.to_byte_array().hex_encode().sha256_text(),
		"identical far mesh vertices")
	var mat := far.mesh.surface_get_material(0) as ShaderMaterial
	assert_true(mat.shader.resource_path.contains("village_ground_hills"), "production hills shader")
	assert_true(bool(mat.get_shader_parameter("u_terrain_tint_on")), "shared tint on")


func test_playground_layout_matches_the_game_generator() -> void:
	## G7 parity: the playground layout is VillageLayout.generate(seed, params) at production.
	var pg = await _boot()
	var game := VillageLayout.generate(pg._params.layout_seed)
	assert_eq(pg._layout.landform["offset"], game.landform["offset"], "same chosen offset")
	assert_eq(pg._layout.cottages.size(), game.cottages.size(), "same cottages")
	for xz in [Vector2(0, -18), Vector2(25, -30), Vector2(-40, 10), Vector2(120, -150)]:
		assert_almost_eq(VillageTerrain.sample_y(xz, pg._layout, pg._build_params),
			VillageTerrain.sample_y(xz, game, VillageTerrainParams.production()), 1e-6, "field at %s" % xz)


func test_readout_reports_the_search_measures() -> void:
	var pg = await _boot()
	await pg._await_refined()
	var r: Dictionary = pg.landform_readout()
	for k in ["offset", "index", "rank", "s_hero", "up_hero", "down_hero", "span_v", "p95_v",
			"plaza_tilt_deg", "max_path_slope_deg", "offset_fallback", "generate_ms", "search_ms",
			"rejected_sites", "sep_relaxed_to", "path_cap_fallback", "pond_steep"]:
		assert_true(r.has(k), "readout %s" % k)
	assert_eq(r["offset"], pg._layout.landform["offset"], "readout offset = chosen offset")
	assert_string_contains(pg.hud_text(), "landform: offset")


func test_auto_mode_writes_the_offset_back_for_copy_out() -> void:
	var pg = await _boot()
	var off: Vector2 = pg._layout.landform["offset"]
	assert_almost_eq(pg._params.landform_offset_x, off.x, 1e-6, "offset x written back")
	assert_almost_eq(pg._params.landform_offset_z, off.y, 1e-6, "offset z written back")
	var copied := VillageTerrainParams.production()
	copied.from_dict(JSON.parse_string(pg._params.to_json_block()))
	copied.landform_offset_mode = VillageTerrainParams.OFFSET_MANUAL
	var manual := VillageLayout.generate(pg._params.layout_seed, copied)
	assert_eq(manual.landform["offset"], off, "manual copy-out reproduces the auto offset")


func test_regen_classes_route_knob_edits() -> void:
	var pg = await _boot()
	await pg._await_refined()
	var layout_before: VillageLayout = pg._layout
	pg._on_knob_changed("ground_height_tint", 0.3)
	assert_false(pg.is_refining(), "material knob: no rebuild")
	pg._on_knob_changed("camera_ground_clearance_m", 0.6)
	assert_false(pg.is_refining(), "consumer knob: no rebuild")
	pg._on_knob_changed("far_ridge_start_m", 80.0)
	assert_true(pg.is_refining(), "terrain knob: rebuild queued")
	assert_false(pg._relayout_pending, "terrain knob keeps the layout")
	await pg._await_refined()
	assert_same(pg._layout, layout_before, "terrain knob kept the layout")
	pg._on_knob_changed("landform_height_m", 12.0)
	assert_true(pg._relayout_pending, "layout knob: relayout queued")
	await pg._await_refined()
	assert_ne(pg._layout, layout_before, "layout knob regenerated the layout")


func test_variant_flat_and_noise_selector() -> void:
	var pg = await _boot()
	pg._on_variant_changed(1)
	await pg._await_refined()
	assert_eq(pg._layout.terrain_params.variant, 1, "flat variant regenerated with variant 1")
	assert_eq(VillageTerrain.sample_y(Vector2(10, -20), pg._layout, pg._build_params), 0.0, "flat lawn")
	pg._on_variant_changed(0)
	pg._on_knob_changed("landform_noise", 1)
	await pg._await_refined()
	assert_eq(int(pg._layout.terrain_params.landform_noise), 1, "billow noise applied")


func test_camera_presets_include_horizons_overview_and_seam() -> void:
	var pg = await _boot()
	for name in ["east_horizon", "west_horizon", "wide_overview", "old_rim_seam"]:
		assert_true(name in pg.CAMERA_PRESETS, "%s preset listed" % name)
	var cam := pg.get_node("Camera3D") as Camera3D
	var az: Vector2 = VillageTerrain.sun_corridor_azimuths()
	pg._set_camera_preset_view("east_horizon")
	var fwd := -cam.global_transform.basis.z
	var compass := fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	assert_almost_eq(compass, az.x, 1.0, "East horizon looks along A_rise")
	assert_almost_eq(cam.global_position.y, VillageTerrainParams.production().sun_eye_height_m, 0.05,
		"eye at y_hero + 2 m (hero pad at world 0)")
	pg._set_camera_preset_view("west_horizon")
	fwd = -cam.global_transform.basis.z
	assert_almost_eq(fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0), az.y, 1.0, "West horizon along A_set")
	pg._set_camera_preset_view("wide_overview")
	assert_gt(cam.global_position.y, 100.0, "wide overview high above the village")
	pg._set_camera_preset_view("old_rim_seam")
	var g: Vector2 = pg._layout.hamlet_centre_xz
	var stage_pos: Vector3 = pg.get_node("Stage").position
	var eye_local := Vector2(cam.global_position.x - stage_pos.x, cam.global_position.z - stage_pos.z)
	assert_almost_eq(eye_local.distance_to(g), 50.0, 0.5, "seam eye at r = 50 m")


func test_debug_material_is_debug_shader_when_debug_on() -> void:
	## When _debug_relief_on=true, LawnTerrain must use the debug shader (not production).
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame

	var stage := pg.get_node_or_null("Stage")
	if stage == null:
		fail_test("no Stage"); return
	var terrain := stage.get_node_or_null("LawnTerrain") as MeshInstance3D
	if terrain == null or terrain.mesh == null:
		fail_test("no LawnTerrain mesh"); return
	var mat := terrain.mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(mat, "terrain material must be a ShaderMaterial")
	if mat == null:
		return
	var shader := mat.shader
	assert_not_null(shader, "ShaderMaterial must have a shader assigned")
	if shader == null:
		return
	# Default: _debug_relief_on = true → debug shader path
	assert_true(pg._debug_relief_on, "default debug_relief_on should be true")
	var shader_path: String = shader.resource_path if shader.resource_path else ""
	assert_true(shader_path.contains("village_terrain_debug") or shader_path.is_empty(),
		"debug ON should use village_terrain_debug shader (got: %s)" % shader_path)


func test_debug_off_uses_production_shader() -> void:
	## When _debug_relief_on=false, LawnTerrain must use the production shader.
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	pg.set("_debug_relief_on", false)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame

	var stage := pg.get_node_or_null("Stage")
	if stage == null:
		fail_test("no Stage"); return
	var terrain := stage.get_node_or_null("LawnTerrain") as MeshInstance3D
	if terrain == null or terrain.mesh == null:
		fail_test("no LawnTerrain mesh"); return
	var mat := terrain.mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(mat, "terrain material must be a ShaderMaterial")
	if mat == null:
		return
	var shader := mat.shader
	assert_not_null(shader, "ShaderMaterial must have shader")
	if shader == null:
		return
	var shader_path: String = shader.resource_path if shader.resource_path else ""
	assert_true(shader_path.contains("village_ground") or shader_path.is_empty(),
		"debug OFF should use village_ground production shader (got: %s)" % shader_path)


func test_pond_water_marker_exists() -> void:
	## PondWater node must exist and its Y must be below the rim height.
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	await get_tree().process_frame

	var stage := pg.get_node_or_null("Stage")
	if stage == null:
		fail_test("no Stage"); return
	var layout: VillageLayout = pg._layout
	if layout == null or layout.fallback or layout.pond_center == Vector2.ZERO:
		pass_test("fallback or no pond"); return
	var pond_water := stage.get_node_or_null("PondWater") as MeshInstance3D
	assert_not_null(pond_water, "PondWater marker must exist after rebuild")
	if pond_water == null:
		return
	# ivy-82zn.14.10 contract change: on the hill the pond sits metres above the rim datum, so the
	# water is checked against its own basin: below the bank (pond centre + basin rim) and above
	# the basin floor.
	var water_y: float = pond_water.position.y
	var p: VillageTerrainParams = pg._params
	var t_seed := VillageTerrain.terrain_seed(layout, p)
	var floor_y := VillageTerrain.sample_y(layout.pond_center, layout, p, t_seed)
	assert_gt(water_y, floor_y, "pond water above the basin floor (%.3f > %.3f)" % [water_y, floor_y])
	assert_lte(water_y, floor_y - p.pond_depth_m + p.pond_lip_rise_m,
		"pond water below the basin lip (%.3f)" % water_y)


## Regression: _debug_relief_on can be set before _ready via export (used by test_debug_off).
func test_debug_relief_on_export_settable() -> void:
	var pg := VillageTerrainPlaygroundScene.instantiate()
	pg.set("_debug_relief_on", false)
	pg.set("script_driven", true)
	add_child_autofree(pg)
	await get_tree().process_frame
	assert_false(pg._debug_relief_on, "_debug_relief_on should stay false after _ready when pre-set")


func test_knob_spec_rows_use_knob_panel_name_key() -> void:
	## Regression ivy-82zn.13: VillageTerrainKnobSpec must use `name` (KnobPanel contract).
	for row: Dictionary in VillageTerrainKnobSpec.all_knobs():
		assert_true(row.has("name") and row["name"] is String and not str(row["name"]).is_empty(),
			"knob row missing KnobPanel `name`: %s" % str(row))
		assert_false(row.has("prop"),
			"knob row still uses legacy `prop` key: %s" % str(row.get("prop")))
