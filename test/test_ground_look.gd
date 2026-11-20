## GroundLook (ivy-82zn.17.1): grass textures, under-tree texture and ground saturation, shared by the
## lawn and the far hills' lit ring; playground knobs read the same params as production (G7).
extends GutTest

const VillageTerrainKnobSpec = preload("res://src/playground/village_terrain_knob_spec.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _LAWN := "res://src/render/shaders/village_ground.gdshader"
const _HILLS := "res://src/render/shaders/village_ground_hills.gdshader"


func _material(path: String, p: VillageTerrainParams) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path) as Shader
	VillageTerrain.apply_ground_material(mat, p, null)
	return mat


func test_production_ground_look_is_the_owner_pick() -> void:
	## Owner ruling 2026-11-21: textured ground (Grass005 open, Grass004 under trees), saturation 0.8.
	var p := VillageTerrainParams.production()
	assert_true(p.ground_tex_on)
	assert_almost_eq(p.ground_saturation, 0.8, 1e-9)
	for path in [_LAWN, _HILLS]:
		var mat := _material(path, p)
		assert_true(bool(mat.get_shader_parameter("u_ground_tex_on")), "%s texture on" % path)
		assert_almost_eq(float(mat.get_shader_parameter("u_ground_saturation")), 0.8, 1e-6)


func test_untextured_preset_restores_the_old_procedural_ground() -> void:
	var p := VillageTerrainParams.production()
	p.apply_preset(VillageTerrainParams.PRESET_UNTEXTURED)
	assert_false(p.ground_tex_on)
	assert_almost_eq(p.ground_saturation, 1.0, 1e-9)
	for path in [_LAWN, _HILLS]:
		var mat := _material(path, p)
		assert_false(bool(mat.get_shader_parameter("u_ground_tex_on")), "%s texture off" % path)
		assert_almost_eq(float(mat.get_shader_parameter("u_ground_saturation")), 1.0, 1e-9)


func test_both_shaders_include_the_shared_ground_look() -> void:
	for path in [_LAWN, _HILLS]:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.contains("ground_look.gdshaderinc"), "%s includes ground_look" % path)
		assert_true(src.contains("ground_albedo(world_xz"), "%s uses ground_albedo" % path)


func test_textured_params_reach_lawn_and_hills_with_textures() -> void:
	var p := VillageTerrainParams.production()
	assert_true(p.ground_tex_on)
	for path in [_LAWN, _HILLS]:
		var mat := _material(path, p)
		assert_true(bool(mat.get_shader_parameter("u_ground_tex_on")))
		assert_almost_eq(float(mat.get_shader_parameter("u_ground_saturation")), p.ground_saturation, 1e-6)
		for u in ["u_grass_open_albedo", "u_grass_open_normal", "u_grass_shade_albedo", "u_grass_shade_normal"]:
			assert_not_null(mat.get_shader_parameter(u), "%s sets %s" % [path, u])


func test_every_ground_look_param_is_a_material_knob() -> void:
	var rows := {}
	for row: Dictionary in VillageTerrainKnobSpec.all_knobs():
		rows[row["name"]] = row
	for k in VillageTerrainParams.GROUND_LOOK_KEYS:
		assert_true(rows.has(k), "playground knob %s" % k)
		if rows.has(k):
			assert_eq(String(rows[k]["regen"]), VillageTerrainKnobSpec.REGEN_MATERIAL, "%s is material-only" % k)
		assert_has(VillageTerrainParams.NON_FIELD_KEYS, k, "%s never rebuilds the field" % k)


func test_preset_is_listed_and_detected() -> void:
	assert_has(VillageTerrainParams.ordered_preset_names(), VillageTerrainParams.PRESET_UNTEXTURED)
	var p := VillageTerrainParams.production()
	assert_eq(VillageTerrainParams.detect_preset_name(p), VillageTerrainParams.PRESET_PRODUCTION)
	p.apply_preset(VillageTerrainParams.PRESET_UNTEXTURED)
	assert_eq(VillageTerrainParams.detect_preset_name(p), VillageTerrainParams.PRESET_UNTEXTURED)


func test_tree_mask_is_one_at_a_trunk_and_zero_in_the_open() -> void:
	var rect := Rect2(Vector2(-50, -50), Vector2(100, 100))
	var tex := GroundLook.tree_mask([Vector3(10.0, -20.0, 2.0)] as Array[Vector3], rect, 200)
	var img := tex.get_image()
	var px := func(x: float, z: float) -> float:
		return img.get_pixel(int((x - rect.position.x) / 0.5), int((z - rect.position.y) / 0.5)).r
	assert_gt(px.call(10.0, -20.0), 0.9, "trunk")
	assert_almost_eq(px.call(12.0, -20.0), 0.5, 0.1, "one canopy radius out = half (reach 2 radii)")
	assert_eq(px.call(-30.0, 30.0), 0.0, "open lawn")


func test_tree_canopies_are_the_far_treeline() -> void:
	var layout := VillageLayout.generate(7)
	var c := GroundLook.tree_canopies(layout)
	assert_eq(c.size(), VillageScatterPositions.forest_tree_positions(layout).size())
	var rect := GroundLook.mask_rect(layout)
	assert_true(rect.has_point(layout.hamlet_centre_xz), "mask is centred on the hamlet")
	assert_gt(rect.size.x, layout.lawn_radius * 2.0 + 99.0, "covers the lit ring (lawn + 50 m)")
