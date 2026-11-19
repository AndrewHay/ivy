## HillsTint (AR-NOFOG, ivy-82zn.14.32; was the fog-tint test). Keeps the shader-literal and uniform
## plumbing regressions (MAJOR-2 / MAJOR-4); the haze tests went with the haze. Adds the layer-colour
## hold past the last ridge layer and the far meadow colour the sky uses below the horizon.
extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsTint = preload("res://src/playground/hills_tint.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _SHADER_PATH := "res://src/render/shaders/village_ground_hills.gdshader"


func _material(seed: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(_SHADER_PATH) as Shader
	var layout := VillageLayout.generate(seed)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	HillsTint.apply_terrain_shader(mat, layout, HillsParams.production())
	return mat


## MAJOR-2 regression: shader layer_t_for_r must not use hardcoded ridge distance
## literals in its expressions — values must come from u_layer_dist_* uniforms.
## The acceptable place for these numbers is in uniform default values only.
## Also verifies the weight drift fix: 0.72 must not appear anywhere.
func test_shader_no_hardcoded_ridge_literals() -> void:
	var text := FileAccess.get_file_as_string(_SHADER_PATH)
	assert_false(text.is_empty(), "gdshader file must be readable")
	for literal in ["155.0", "190.0", "225.0", "260.0"]:
		var hardcoded_pattern := "planar_r - %s" % literal
		assert_false(text.contains(hardcoded_pattern),
			"gdshader must not hardcode ridge literal in expression '%s' — use uniforms" % hardcoded_pattern)
	for i in range(4):
		assert_true(text.contains("u_layer_dist_%d" % i),
			"gdshader layer_t_for_r must reference uniform u_layer_dist_%d" % i)
	assert_false(text.contains("0.72"),
		"gdshader weight drift 0.72 must be removed; GDScript uses 0.70")


func test_shader_has_no_horizon_blend() -> void:
	## AR-NOFOG: the flat-sector tint, far-ridge cap and luminance cap are gone with u_horizon_rgb.
	var text := FileAccess.get_file_as_string(_SHADER_PATH)
	for word in ["u_horizon_rgb", "far_cap", "hor_lum", "flat_tone"]:
		assert_false(text.contains(word), "hills shader still contains %s" % word)


## MAJOR-2 regression: apply_terrain_shader must set the ridge-geometry uniforms.
func test_apply_terrain_shader_sets_ridge_uniforms() -> void:
	var mat := _material(7)
	for i in range(4):
		var u := "u_layer_dist_%d" % i
		var v = mat.get_shader_parameter(u)
		assert_not_null(v, "apply_terrain_shader must set uniform %s" % u)
		if v != null:
			assert_gt(float(v), 0.0, "%s must be > 0" % u)
	for i in range(4):
		var u := "u_layer_width_%d" % i
		assert_not_null(mat.get_shader_parameter(u), "apply_terrain_shader must set uniform %s" % u)
	for i in [1, 2, 3]:
		var u := "u_layer_weight_%d" % i
		assert_not_null(mat.get_shader_parameter(u), "apply_terrain_shader must set uniform %s" % u)
	var w2 = mat.get_shader_parameter("u_layer_weight_2")
	if w2 != null:
		assert_almost_eq(float(w2), 0.70, 1e-4, "u_layer_weight_2 must be 0.70 (not 0.72 drift)")


## MAJOR-4 regression: apply_terrain_shader must set the azimuth-wedge uniforms.
func test_apply_terrain_shader_sets_wedge_uniforms() -> void:
	var mat := _material(7)
	var params := HillsParams.production()
	for u in ["u_azimuth_centre_rad", "u_azimuth_half_width_rad", "u_azimuth_fade_width_rad"]:
		assert_not_null(mat.get_shader_parameter(u), "apply_terrain_shader must set %s" % u)
	var hw = mat.get_shader_parameter("u_azimuth_half_width_rad")
	if hw != null:
		assert_almost_eq(float(hw), deg_to_rad(params.azimuth_half_width_deg), 1e-4,
			"u_azimuth_half_width_rad must match params.azimuth_half_width_deg")


func test_layer_colour_fades_to_plain_meadow_across_the_skirt() -> void:
	## AR-NOFOG-EDGE: the skirt renders plain meadow (layer_t 0) past the ease band; the fade is
	## monotone (the hold keeps the Gaussians from underflowing into a colour ring near 430 m).
	var p := HillsParams.production()
	var prev := HillsTint.layer_t_for_radius(p.r_outer_m, p)
	var rr := p.r_outer_m
	while rr < p.r_outer_m + VillageTerrain.SKIRT_EASE_M:
		rr += 5.0
		var t := HillsTint.layer_t_for_radius(rr, p)
		assert_lte(t, prev + 1e-6, "layer_t non-increasing across the skirt at r = %.0f" % rr)
		prev = t
	for far_r in [p.r_outer_m + VillageTerrain.SKIRT_EASE_M, 1500.0, 3000.0]:
		assert_almost_eq(HillsTint.layer_t_for_radius(far_r, p), 0.0, 1e-9, "plain meadow at r = %.0f" % far_r)
	var mat := _material(7)
	assert_almost_eq(float(mat.get_shader_parameter("u_r_outer")), p.r_outer_m, 1e-4, "u_r_outer uniform")
	assert_almost_eq(float(mat.get_shader_parameter("u_skirt_ease")), VillageTerrain.SKIRT_EASE_M, 1e-4,
		"u_skirt_ease uniform")
	# Inside r_outer the value is the plain normalised-Gaussian blend (no hold applied).
	for r in [160.0, 225.0, 300.0]:
		var t := [0.0, 0.35, 0.7, 1.0]
		var num := 0.0
		var den := 0.0
		for i in range(4):
			var d: float = (r - p.layer_dist_at(i)) / p.layer_width_at(i)
			var w := exp(-0.5 * d * d)
			num += w * float(t[i])
			den += w
		assert_almost_eq(HillsTint.layer_t_for_radius(r, p), num / den, 1e-9, "unchanged at r = %.0f" % r)


func test_far_meadow_colour_is_green_and_follows_the_sun() -> void:
	assert_almost_eq(HillsTint._SUN_WARMTH, HillsParams.production().sun_warmth, 1e-9,
		"far meadow uses the production sun warmth")
	var high := HillsTint.far_meadow_colour(Vector3(0.2, 0.9, 0.3), 0.0)
	var low := HillsTint.far_meadow_colour(Vector3(0.9, 0.05, 0.2), 0.0)
	var dusk := HillsTint.far_meadow_colour(Vector3(0.9, 0.05, 0.2), 1.0)
	for c: Color in [high, low, dusk]:
		assert_gt(c.g, c.r, "meadow green > red (%s)" % c)
		assert_gt(c.g, c.b, "meadow green > blue (%s)" % c)
	assert_gt(HillsTint.luminance(high), HillsTint.luminance(low), "brighter under a high sun")
	assert_gt(HillsTint.luminance(low), HillsTint.luminance(dusk), "twilight dims the meadow")
	# Not the old pale horizon (0.784, 0.851, 0.91).
	assert_lt(high.b, 0.6, "not the pale sky horizon")


func test_tree_instance_color_has_no_fog_arguments() -> void:
	var layout := VillageLayout.generate(7)
	var p := HillsParams.production()
	var g := layout.hamlet_centre_xz
	var near := HillsTint.tree_instance_color(Vector3(g.x, 0.0, g.y - 70.0), p, layout)
	var far := HillsTint.tree_instance_color(Vector3(g.x, 0.0, g.y - 200.0), p, layout)
	assert_gt(near.g, far.g, "distance green boost (not haze) kept")
