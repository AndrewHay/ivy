class_name HillsFogTint
extends RefCounted

const HillsParams = preload("res://src/playground/hills_params.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")
const SkySun = preload("res://src/world/sky_sun.gd")

## Calibrated rendered lawn colour (measured pixel at the seam toe under warm sunset).
## The GPU shader blends hill terrain toward this value at r = lawn_radius.
const _LAWN_COLOUR := Color(0.270, 0.350, 0.210)
## Near-seam colour: rework5 value — kept unchanged because the unshaded mode
## (rework6) already halves brightness vs double-lit; no need to alter the green ratio.
## Luminance ~0.308 — must be lower than _L1_GREEN.
const _L0_GREEN := Color(0.22, 0.38, 0.17)
## Mid-distance colour (lighter, slightly bluer, lum≈0.330).
const _L1_GREEN := Color(0.25, 0.38, 0.28)


static func reference_camera_pos() -> Vector3:
	return ForestPlaygroundCamera.camsun_position()


static func horizon_reference_color() -> Color:
	var s_y := 0.32
	return SkySun.sky_horizon_color_for(s_y, SkySun.lit_for(s_y))


static func refresh_horizon_on_world(world: Node, s_y: float, lit: float, sun_dir: Vector3 = Vector3.ZERO) -> void:
	if world == null:
		return
	var backdrop: Node = world.get_node_or_null("VillageBackdrop")
	if backdrop == null:
		return
	var hill: MeshInstance3D = backdrop.get_node_or_null("HillTerrain") as MeshInstance3D
	if hill == null or hill.mesh == null:
		return
	var mat: Material = hill.mesh.surface_get_material(0)
	if mat is ShaderMaterial:
		var hor := SkySun.sky_horizon_color_for(s_y, lit)
		var sm := mat as ShaderMaterial
		sm.set_shader_parameter("u_horizon_rgb", Vector3(hor.r, hor.g, hor.b))
		var tw := SkySun.twilight_glow_for(s_y, lit)
		sm.set_shader_parameter("u_twilight", tw)
		if sun_dir.length_squared() > 1e-6:
			sm.set_shader_parameter("u_sun_dir", Vector3(sun_dir.x, sun_dir.y, sun_dir.z))


static func luminance(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


static func layer_t_for_radius(planar_r: float, params: HillsParams) -> float:
	var t0 := _gaussian_layer(planar_r, params.layer_dist_0, params.layer_width_0)
	var t1 := _gaussian_layer(planar_r, params.layer_dist_1, params.layer_width_1)
	var t2 := _gaussian_layer(planar_r, params.layer_dist_2, params.layer_width_2)
	var t3 := _gaussian_layer(planar_r, params.layer_dist_3, params.layer_width_3)
	var sum := t0 + t1 + t2 + t3
	if sum < 1e-6:
		return clampf((planar_r - params.r_inner_m) / maxf(params.r_outer_m - params.r_inner_m, 1.0), 0.0, 1.0)
	return clampf((t0 * 0.0 + t1 * 0.35 + t2 * 0.7 + t3 * 1.0) / sum, 0.0, 1.0)


static func _gaussian_layer(r: float, centre: float, width: float) -> float:
	var d := (r - centre) / maxf(width, 0.01)
	return exp(-0.5 * d * d)


static func terrain_albedo(
		_world: Vector3, layout: VillageLayout, params: HillsParams, ndl: float,
		planar_r: float, height_m: float, slope_deg: float) -> Color:
	var layer_t := layer_t_for_radius(planar_r, params)
	var col := _L0_GREEN.lerp(_L1_GREEN, smoothstep(0.15, 0.55, layer_t))
	var hor := horizon_reference_color()
	var far_cap := hor * 0.86
	col = col.lerp(far_cap, smoothstep(0.45, 1.0, layer_t))
	var shade := lerpf(0.72, 1.08, clampf(ndl, 0.0, 1.0))
	col.r *= shade
	col.g *= shade * 1.02
	col.b *= shade * 0.96
	var slope_lift := clampf(slope_deg / 30.0, 0.0, 1.0) * 0.06
	col.g += slope_lift
	var hor_lum := luminance(hor)
	var lum := luminance(col)
	if lum > hor_lum * 0.94:
		col *= (hor_lum * 0.90) / maxf(lum, 1e-4)
	# Seam calibration: mirror GPU meadow_ring — blend toward _LAWN_COLOUR at the
	# lawn edge so the CPU colour path closes the seam on the same schedule.
	var seam_ring := 1.0 - clampf((planar_r - layout.lawn_radius) / 50.0, 0.0, 1.0)
	col = col.lerp(_LAWN_COLOUR, seam_ring)
	return col


static func tree_albedo(
		_world: Vector3, layout: VillageLayout, params: HillsParams, planar_r: float) -> Color:
	var dist_t := clampf((planar_r - 62.0) / 75.0, 0.0, 1.0)
	var g_boost := lerpf(1.12, 0.95, dist_t)
	return Color(0.92 * g_boost, 1.08 * g_boost, 0.86 * g_boost)


static func haze_at(
		world: Vector3, layout: VillageLayout, fog_begin: float, fog_end: float,
		camera_pos: Vector3, _model: HeroFog.FogModel) -> float:
	var g := layout.hamlet_centre_xz
	var d := Vector2(world.x - g.x, world.z - g.y).length()
	return HeroFog.fog_amount(d, fog_begin, fog_end)


static func color_for_world(
		world: Vector3, params: HillsParams, layout: VillageLayout,
		fog_begin: float, fog_end: float, camera_pos: Vector3,
		slope_deg: float = 0.0, planar_r: float = -1.0, ndl: float = 0.65) -> Color:
	if not params.ridge_fog_tint_on:
		return Color(1, 1, 1, 1)
	var g := layout.hamlet_centre_xz
	var r := planar_r if planar_r >= 0.0 else Vector2(world.x - g.x, world.z - g.y).length()
	var y_rel := world.y - VillageBackdrop.LAWN_GROUND_Y_OFFSET
	return terrain_albedo(world, layout, params, ndl, r, y_rel, slope_deg)


static func tree_instance_color(
		world: Vector3, params: HillsParams, layout: VillageLayout,
		fog_begin: float, fog_end: float, camera_pos: Vector3) -> Color:
	var g := layout.hamlet_centre_xz
	var r := Vector2(world.x - g.x, world.z - g.y).length()
	return tree_albedo(world, layout, params, r)


static func apply_terrain_shader(mat: ShaderMaterial, layout: VillageLayout, params: HillsParams) -> void:
	var g := layout.hamlet_centre_xz
	var hor := horizon_reference_color()
	mat.set_shader_parameter("u_hamlet_xz", Vector2(g.x, g.y))
	mat.set_shader_parameter("u_lawn_radius", layout.lawn_radius)
	mat.set_shader_parameter("u_horizon_rgb", Vector3(hor.r, hor.g, hor.b))
	mat.set_shader_parameter("u_sun_dir", Vector3(0.35, 0.78, 0.52))
	mat.set_shader_parameter("u_twilight", 0.0)
	# Seam calibration: measured rendered lawn colour used by the unshaded meadow_ring
	# blend.  Adjust this value if the rendered lawn changes (e.g. different sky).
	mat.set_shader_parameter("u_lawn_colour",
			Vector3(_LAWN_COLOUR.r, _LAWN_COLOUR.g, _LAWN_COLOUR.b))
	# Hill base colours (rework5 values, pre-lighting).
	# With unshaded mode these are ~1.67× darker than the old double-lit output.
	mat.set_shader_parameter("u_meadow_near", Vector3(0.22, 0.38, 0.17))
	mat.set_shader_parameter("u_meadow_mid",  Vector3(0.25, 0.38, 0.28))
	mat.set_shader_parameter("sun_warmth", params.sun_warmth)
	# Ridge layer geometry (MAJOR-2): pass params → shader so layer_t_for_r reads
	# uniforms instead of hardcoded literals, keeping one source of truth.
	# Weights match HillsFogTint.layer_t_for_radius: 0.0 / 0.35 / 0.70 / 1.0.
	mat.set_shader_parameter("u_layer_dist_0",  params.layer_dist_0)
	mat.set_shader_parameter("u_layer_dist_1",  params.layer_dist_1)
	mat.set_shader_parameter("u_layer_dist_2",  params.layer_dist_2)
	mat.set_shader_parameter("u_layer_dist_3",  params.layer_dist_3)
	mat.set_shader_parameter("u_layer_width_0", params.layer_width_0)
	mat.set_shader_parameter("u_layer_width_1", params.layer_width_1)
	mat.set_shader_parameter("u_layer_width_2", params.layer_width_2)
	mat.set_shader_parameter("u_layer_width_3", params.layer_width_3)
	mat.set_shader_parameter("u_layer_weight_1", 0.35)
	mat.set_shader_parameter("u_layer_weight_2", 0.70)  # was 0.72 in shader (drift fix)
	mat.set_shader_parameter("u_layer_weight_3", 1.0)
	# Azimuth wedge (MAJOR-4): pass wedge geometry so the shader can fade hill
	# colouring outside the north wedge, rendering flat east/west as plain meadow.
	mat.set_shader_parameter("u_azimuth_centre_rad",     deg_to_rad(params.azimuth_centre_deg))
	mat.set_shader_parameter("u_azimuth_half_width_rad", deg_to_rad(params.azimuth_half_width_deg))
	mat.set_shader_parameter("u_azimuth_fade_width_rad", deg_to_rad(params.azimuth_fade_width_deg))


