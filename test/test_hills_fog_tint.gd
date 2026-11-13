extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsFogTint = preload("res://src/playground/hills_fog_tint.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")


func test_ridge_tint_mid_band_not_fully_far_albedo() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var g := layout.hamlet_centre_xz
	var fog_b := layout.fog_begin
	var fog_e := layout.fog_end
	var cam := HillsFogTint.reference_camera_pos()
	# rework5: ridges moved to 155/190/225/260m — probe between them.
	var mid := Vector3(g.x, 1.0, g.y + 172.0)   # between ridge 0 (155m) and ridge 1 (190m)
	var far := Vector3(g.x, 1.0, g.y + 242.0)  # between ridge 2 (225m) and ridge 3 (260m)
	var c_mid := HillsFogTint.color_for_world(mid, params, layout, fog_b, fog_e, cam)
	var c_far := HillsFogTint.color_for_world(far, params, layout, fog_b, fog_e, cam)
	assert_lt(
		HillsFogTint.luminance(c_mid), HillsFogTint.luminance(c_far) + 0.02,
		"mid band should stay darker than far wash")
	assert_gt(c_mid.g - c_mid.r, c_far.g - c_far.r + 0.02, "mid band should stay greener than far tint")


func test_ridge_tint_haze_monotone_with_hero_distance() -> void:
	var layout := VillageLayout.generate(1)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	var g := layout.hamlet_centre_xz
	var fog_b := layout.fog_begin
	var fog_e := layout.fog_end
	var cam := HillsFogTint.reference_camera_pos()
	# rework5: ridges farther out; probe at 155m (near ridge 0) and 190m (near ridge 1).
	# Use hills fog params (begin=80m, end=280m) not layout's tighter fog range.
	var hills_fog_b := params.fog_begin_m  # 80m
	var hills_fog_e := params.fog_end_m    # 280m
	var h155 := HillsFogTint.haze_at(
		Vector3(g.x, 1.0, g.y + 155.0), layout, hills_fog_b, hills_fog_e, cam,
		HeroFog.FogModel.WORLD_AROUND_HERO)
	var h190 := HillsFogTint.haze_at(
		Vector3(g.x, 1.0, g.y + 190.0), layout, hills_fog_b, hills_fog_e, cam,
		HeroFog.FogModel.WORLD_AROUND_HERO)
	assert_lt(h155, h190, "haze should increase with hero planar distance")
	assert_lt(h155, 0.9, "155 m band should not saturate to full far tint")


## MAJOR-2 regression: shader layer_t_for_r must not use hardcoded ridge distance
## literals in its expressions — values must come from u_layer_dist_* uniforms.
## The acceptable place for these numbers is in uniform default values only.
## Also verifies the weight drift fix: 0.72 must not appear anywhere.
func test_shader_no_hardcoded_ridge_literals() -> void:
	var shader_path := "res://src/render/shaders/village_ground_hills.gdshader"
	var text := FileAccess.get_file_as_string(shader_path)
	assert_false(text.is_empty(), "gdshader file must be readable")
	# These exact arithmetic patterns indicate hardcoded ridge distances in computations.
	# Uniform default "= 155.0" is acceptable; "planar_r - 155.0" is not.
	for literal in ["155.0", "190.0", "225.0", "260.0"]:
		var hardcoded_pattern := "planar_r - %s" % literal
		assert_false(text.contains(hardcoded_pattern),
			"gdshader must not hardcode ridge literal in expression '%s' — use uniforms" % hardcoded_pattern)
	# The u_layer_dist_* uniforms must be used in the computation.
	for i in range(4):
		assert_true(text.contains("u_layer_dist_%d" % i),
			"gdshader layer_t_for_r must reference uniform u_layer_dist_%d" % i)
	# The drifted weight 0.72 must no longer appear anywhere in the shader.
	assert_false(text.contains("0.72"),
		"gdshader weight drift 0.72 must be removed; GDScript uses 0.70")


## MAJOR-2 regression: apply_terrain_shader must set the ridge-geometry uniforms
## that the shader now reads (so no uniform is left at shader default when params change).
func test_apply_terrain_shader_sets_ridge_uniforms() -> void:
	var shader := load("res://src/render/shaders/village_ground_hills.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	HillsFogTint.apply_terrain_shader(mat, layout, params)
	# Layer distance uniforms must be set.
	for i in range(4):
		var u := "u_layer_dist_%d" % i
		var v = mat.get_shader_parameter(u)
		assert_not_null(v, "apply_terrain_shader must set uniform %s" % u)
		if v != null:
			assert_gt(float(v), 0.0, "%s must be > 0" % u)
	# Layer width uniforms must be set.
	for i in range(4):
		var u := "u_layer_width_%d" % i
		var v = mat.get_shader_parameter(u)
		assert_not_null(v, "apply_terrain_shader must set uniform %s" % u)
	# Layer weight uniforms (layers 1..3) must be set.
	for i in [1, 2, 3]:
		var u := "u_layer_weight_%d" % i
		var v = mat.get_shader_parameter(u)
		assert_not_null(v, "apply_terrain_shader must set uniform %s" % u)
	# Weight 2 must be 0.70 (not 0.72 drift).
	var w2 = mat.get_shader_parameter("u_layer_weight_2")
	if w2 != null:
		assert_almost_eq(float(w2), 0.70, 1e-4, "u_layer_weight_2 must be 0.70 (not 0.72 drift)")


## MAJOR-4 regression: apply_terrain_shader must set the azimuth-wedge uniforms
## so the shader can fade hill colouring outside the north wedge.
func test_apply_terrain_shader_sets_wedge_uniforms() -> void:
	var shader := load("res://src/render/shaders/village_ground_hills.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params := HillsParams.production()
	HillsFogTint.apply_terrain_shader(mat, layout, params)
	for u in ["u_azimuth_centre_rad", "u_azimuth_half_width_rad", "u_azimuth_fade_width_rad"]:
		var v = mat.get_shader_parameter(u)
		assert_not_null(v, "apply_terrain_shader must set %s" % u)
	# Verify the half-width matches production azimuth_half_width_deg converted to radians.
	var hw = mat.get_shader_parameter("u_azimuth_half_width_rad")
	if hw != null:
		assert_almost_eq(float(hw), deg_to_rad(params.azimuth_half_width_deg), 1e-4,
			"u_azimuth_half_width_rad must match params.azimuth_half_width_deg")
