## WP2 backdrop wiring tests — LawnTerrain / LawnGround node names, disc-discard ready state.
## AC-VT8 backdrop half: generated backdrop has LawnTerrain (not LawnGround);
## classic (VillageBackdrop base) has LawnGround (INV-15 byte-identical).
## AR-VT-DECIDE-1 / AR-VT-WIRE / AR-VT-INV.
extends GutTest

const GeneratedBackdropScene = preload("res://src/world/generated_village_backdrop.tscn")
const ClassicBackdropScene = preload("res://src/world/village_backdrop.tscn")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _TEST_SEED := 7


func _make_generated(seed: int) -> GeneratedVillageBackdrop:
	var bd := GeneratedBackdropScene.instantiate() as GeneratedVillageBackdrop
	bd.set_village_seed(seed)
	add_child_autofree(bd)
	return bd


func _make_classic() -> VillageBackdrop:
	var bd := ClassicBackdropScene.instantiate() as VillageBackdrop
	add_child_autofree(bd)
	return bd


# ── (1) Generated backdrop must have LawnTerrain, not LawnGround ─────────────

func test_generated_has_lawn_terrain_node() -> void:
	## WP2 / AR-VT-DECIDE-1: generated backdrop creates LawnTerrain (displaced mesh),
	## not the old flat LawnGround.
	var bd := _make_generated(_TEST_SEED)
	var terrain := bd.get_node_or_null("LawnTerrain") as MeshInstance3D
	assert_not_null(terrain, "Generated backdrop must have a 'LawnTerrain' node (WP2)")
	if terrain == null:
		return
	assert_not_null(terrain.mesh, "LawnTerrain must have an ArrayMesh")
	assert_eq(terrain.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"LawnTerrain cast_shadow must be OFF")


func test_generated_has_no_lawn_ground_node() -> void:
	## WP2: after terrain wiring, generated backdrop must NOT have the old flat LawnGround.
	var bd := _make_generated(_TEST_SEED)
	var old_ground := bd.get_node_or_null("LawnGround")
	assert_null(old_ground, "Generated backdrop must NOT have 'LawnGround' after WP2 wiring")


func test_generated_lawn_terrain_is_displaced() -> void:
	## WP2: LawnTerrain vertices must not all be flat (at least 1 vertex displaced from datum).
	## Production terrain (variant=0, base_amplitude_m=0.56) must produce relief.
	var bd := _make_generated(_TEST_SEED)
	var terrain := bd.get_node_or_null("LawnTerrain") as MeshInstance3D
	if terrain == null or terrain.mesh == null:
		fail_test("no LawnTerrain mesh found"); return
	var arrays := terrain.mesh.surface_get_arrays(0)
	if arrays == null or arrays.size() == 0:
		fail_test("LawnTerrain mesh has no surface arrays"); return
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var max_dev := 0.0
	for v: Vector3 in verts:
		max_dev = maxf(max_dev, absf(v.y))  # Y deviation from datum (y=0)
	assert_gt(max_dev, 0.01, "LawnTerrain must have at least 1 cm of relief (variant=0)")


func test_generated_lawn_terrain_vertex_count() -> void:
	## WP2 / SD-VILLAGE-TERRAIN-8: mesh must be ≤ 8k tris target (16k hard cap).
	var bd := _make_generated(_TEST_SEED)
	var terrain := bd.get_node_or_null("LawnTerrain") as MeshInstance3D
	if terrain == null or terrain.mesh == null:
		fail_test("no LawnTerrain mesh"); return
	var arrays := terrain.mesh.surface_get_arrays(0)
	if arrays == null:
		fail_test("no surface arrays"); return
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	# Triangles = verts / 3 (PRIMITIVE_TRIANGLES)
	var tris := verts.size() / 3
	assert_lte(tris, 16000, "LawnTerrain must be ≤ 16k tris (hard cap)")
	assert_lte(tris, 8000,
		"SD-VILLAGE-TERRAIN-8: LawnTerrain must be ≤ 8k tris budget (got %d)" % tris)


func test_generated_lawn_terrain_uses_village_ground_shader() -> void:
	## LawnTerrain must use village_ground.gdshader (production shader, not debug).
	var bd := _make_generated(_TEST_SEED)
	var terrain := bd.get_node_or_null("LawnTerrain") as MeshInstance3D
	if terrain == null or terrain.mesh == null:
		fail_test("no LawnTerrain mesh"); return
	var mat := terrain.mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(mat, "LawnTerrain surface 0 must have a ShaderMaterial")
	if mat == null:
		return
	var shader := mat.shader
	assert_not_null(shader, "LawnTerrain ShaderMaterial must have a shader")
	if shader == null:
		return
	assert_true(shader.resource_path.contains("village_ground"),
		"LawnTerrain must use village_ground shader, got: %s" % shader.resource_path)


func test_apply_ground_material_sets_shading_uniforms_from_params() -> void:
	## ivy-82zn.14.1: slope shading + height tint strengths flow params → shader uniforms
	## through one helper used by both the game backdrop and the playground (no fork).
	var p := VillageTerrainParams.production()
	p.ground_slope_dark = 0.41
	p.ground_slope_full_deg = 11.0
	p.ground_height_tint = 0.13
	p.ground_height_range_m = 1.7
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/render/shaders/village_ground.gdshader") as Shader
	VillageTerrain.apply_ground_material(mat, p)
	assert_almost_eq(float(mat.get_shader_parameter("terrain_slope_dark")), 0.41, 1e-5)
	assert_almost_eq(float(mat.get_shader_parameter("terrain_slope_full_deg")), 11.0, 1e-5)
	assert_almost_eq(float(mat.get_shader_parameter("terrain_height_tint")), 0.13, 1e-5)
	assert_almost_eq(float(mat.get_shader_parameter("terrain_height_range_m")), 1.7, 1e-5)


func test_ground_shader_renormalises_normal_before_slope_ramp() -> void:
	## ivy-82zn.14.5 (review MINOR-3): v_world_normal is interpolated per fragment, so its length
	## drops below 1 between vertices; with the acos ramp (full dim at 10°) that shortfall read as
	## ~0.5° of false slope on flat ground. The fragment slope term must use a unit normal.
	## Headless GUT cannot render, so this pins the source (manual check: playground screenshot).
	var code := (load("res://src/render/shaders/village_ground.gdshader") as Shader).code
	var frag := code.substr(code.find("void fragment()"))
	assert_true(frag.contains("normalize(v_world_normal)"),
		"fragment() must normalize(v_world_normal) before the slope ramp")
	assert_false(frag.contains("clamp(v_world_normal.y"),
		"fragment() must not read the raw interpolated v_world_normal.y")


func test_generated_lawn_terrain_material_uses_production_shading_params() -> void:
	## ivy-82zn.14.1: the real-game LawnTerrain carries production shading uniforms.
	var bd := _make_generated(_TEST_SEED)
	var terrain := bd.get_node_or_null("LawnTerrain") as MeshInstance3D
	if terrain == null or terrain.mesh == null:
		fail_test("no LawnTerrain mesh"); return
	var mat := terrain.mesh.surface_get_material(0) as ShaderMaterial
	var p := VillageTerrainParams.production()
	assert_almost_eq(float(mat.get_shader_parameter("terrain_slope_full_deg")),
		p.ground_slope_full_deg, 1e-5, "LawnTerrain slope full-dim angle == production")
	assert_almost_eq(float(mat.get_shader_parameter("terrain_height_tint")),
		p.ground_height_tint, 1e-5, "LawnTerrain height tint == production")


func test_classic_lawn_ground_has_no_height_tint() -> void:
	## INV-15: flat classic LawnGround keeps shader defaults (height tint off).
	var bd := _make_classic()
	var ground := bd.get_node_or_null("LawnGround") as MeshInstance3D
	if ground == null or ground.mesh == null:
		fail_test("no LawnGround mesh"); return
	var mat := ground.mesh.surface_get_material(0) as ShaderMaterial
	var tint: Variant = mat.get_shader_parameter("terrain_height_tint")
	assert_true(tint == null or is_zero_approx(float(tint)),
		"classic LawnGround height tint must stay 0 (got %s)" % str(tint))


# ── (2) Classic backdrop must still have LawnGround (INV-15) ─────────────────

func test_classic_has_lawn_ground_not_terrain() -> void:
	## INV-15 / AR-VT-DECIDE-1: classic (authored) backdrop keeps LawnGround node byte-identical.
	var bd := _make_classic()
	var ground := bd.get_node_or_null("LawnGround") as MeshInstance3D
	assert_not_null(ground, "Classic backdrop must still have 'LawnGround' (INV-15)")
	var terrain := bd.get_node_or_null("LawnTerrain")
	assert_null(terrain, "Classic backdrop must NOT have 'LawnTerrain' (INV-15)")


func test_classic_lawn_ground_is_flat() -> void:
	## INV-15 byte-identical: all LawnGround vertices must be at LAWN_GROUND_Y_OFFSET (-0.03).
	var bd := _make_classic()
	var ground := bd.get_node_or_null("LawnGround") as MeshInstance3D
	if ground == null or ground.mesh == null:
		fail_test("no LawnGround mesh"); return
	var arrays := ground.mesh.surface_get_arrays(0)
	if arrays == null:
		fail_test("no surface arrays"); return
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var expected_y := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	for v: Vector3 in verts:
		if not is_equal_approx(v.y, expected_y):
			fail_test("Classic LawnGround vertex at y=%.4f, expected %.3f (INV-15)" % [
				v.y, expected_y])
			return
	pass_test("Classic LawnGround: all %d vertices at y=%.3f (byte-identical, INV-15)" % [
		verts.size(), expected_y])


# ── (3) Generated backdropterrain params stored ───────────────────────────────

func test_generated_backdrop_has_terrain_params() -> void:
	## WP2 AR-VT-WIRE: VillageBackdrop stores _terrain_params after _ready.
	var bd := _make_generated(_TEST_SEED)
	# Access via property — the field must be set (non-null) after _ready.
	var params = bd.get("_terrain_params")
	assert_not_null(params, "_terrain_params must be set in _ready() (WP2 AR-VT-WIRE)")
	if params == null:
		return
	assert_true(params is VillageTerrainParams,
		"_terrain_params must be a VillageTerrainParams resource")
