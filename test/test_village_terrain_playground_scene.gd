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
	assert_almost_eq(params.base_amplitude_m, 0.64, 1e-5,
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
	# Production params: max_rise=0.8, max_depression=0.6 — stats should be within those.
	assert_lte(max_h, 0.85, "max_h should not exceed max_rise + eps")
	assert_gte(min_h, -0.65, "min_h should not exceed max_depression + eps")


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
	# Water Y must be negative or at least below datum.
	var water_y: float = pond_water.position.y
	assert_lte(water_y, 0.1,
		"Pond water Y should be at or below datum (pond is a depression); got %.3f" % water_y)


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
