class_name HillsTint
extends RefCounted
## Far-hills colour: CPU mirror of village_ground_hills.gdshader plus the uniform plumbing, used by the
## game (VillageBackdrop, SkySun) and the playgrounds (G7: one class). AR-NOFOG (ivy-82zn.14.32):
## renamed from the old fog-tint class; no haze, horizon blend, far cap or luminance cap is left.
## Meadow layer colours, the lawn seam colour and the tree tint are unchanged.

const HillsParams = preload("res://src/playground/hills_params.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

## Calibrated rendered lawn colour. The GPU shader blends hill terrain toward this value at
## r = lawn_radius. AR-NOFOG (ivy-82zn.14.32): recalibrated without fog from tools/hills_seam_probe.gd
## (seed 7, default sun, seam + CamSun views): the far side of the join loop rendered brighter than the lit
## lawn by a linear ratio of about (0.76, 0.75, 0.61); was (0.270, 0.350, 0.210).
const _LAWN_COLOUR := Color(0.204, 0.261, 0.127)
## Near-seam colour: rework5 value — kept unchanged because the unshaded mode
## (rework6) already halves brightness vs double-lit; no need to alter the green ratio.
## Luminance ~0.308 — must be lower than _L1_GREEN.
const _L0_GREEN := Color(0.22, 0.38, 0.17)
## Mid-distance colour (lighter, slightly bluer, lum≈0.330).
const _L1_GREEN := Color(0.25, 0.38, 0.28)
## Patch-noise colours (shader patch_lo / patch_hi defaults) and the shader's patch weight far from
## the lawn: patch_contrast 0.22 * 0.55 (meadow_ring = 0).
const _PATCH_LO := Color(0.20, 0.32, 0.16)
const _PATCH_HI := Color(0.34, 0.46, 0.24)
const _FAR_PATCH_WT := 0.22 * 0.55
## Default sun_warmth (shader uniform default, HillsParams.sun_warmth production).
const _SUN_WARMTH := 0.22
## Skirt colour (AR-NOFOG-EDGE): past r_outer the shader and this mirror evaluate the ridge-layer
## weights at r_outer (so the normalised Gaussians never underflow into a colour ring near 430 m) and
## fade them to 0 over VillageTerrain.SKIRT_EASE_M, so the skirt renders as plain meadow. Inside
## r_outer nothing changes.
## u_sun_dir until SkySun.update() drives it (and for good in the playgrounds, which never update).
const DEFAULT_SUN_DIR := Vector3(0.35, 0.78, 0.52)


static func reference_camera_pos() -> Vector3:
	return ForestPlaygroundCamera.camsun_position()


## Per-frame hill lighting from SkySun.update(): twilight dim and sun direction on the far mesh.
static func refresh_hill_lighting_on_world(world: Node, s_y: float, lit: float, sun_dir: Vector3 = Vector3.ZERO) -> void:
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
		var sm := mat as ShaderMaterial
		sm.set_shader_parameter("u_twilight", SkySun.twilight_glow_for(s_y, lit))
		if sun_dir.length_squared() > 1e-6:
			sm.set_shader_parameter("u_sun_dir", Vector3(sun_dir.x, sun_dir.y, sun_dir.z))


## Rendered colour of plain far meadow on flat ground (the skirt past the ridge layers, outside the
## north wedge): mirrors village_ground_hills.gdshader with eff_layer_t = 0, flat_sector = 1,
## meadow_ring = 0, mean patch noise, no gust, normal = up. Computed in linear space like the shader
## and returned as an sRGB Color, ready for a source_color uniform (SkySun sets it as the sky's
## ground_horizon_color, AR-NOFOG-EDGE). `sun_dir` is the far mesh's u_sun_dir as the shader gets it
## (SkySun passes the same vector it writes to the material). The twilight dim is the flat-sector
## value (full u_twilight); inside the north wedge the shader dims by only 0.35 + flat_sector * 0.65
## of it, so there the skirt is slightly brighter than this colour at twilight (review F5, documented).
## Colour spaces as the shader receives them: u_meadow_near is set by apply_terrain_shader as a
## Vector3, which Godot passes through unconverted (so it is already linear in the shader); patch_lo /
## patch_hi keep their source_color defaults, which Godot converts from sRGB.
static func far_meadow_colour(sun_dir: Vector3, twilight: float) -> Color:
	var near := _L0_GREEN
	var patch_col := _PATCH_LO.srgb_to_linear().lerp(_PATCH_HI.srgb_to_linear(), 0.5)
	var col := near.lerp(patch_col, _FAR_PATCH_WT)
	var ndl := clampf(sun_dir.normalized().y, 0.0, 1.0) if sun_dir.length_squared() > 1e-12 else 0.0
	var warm := Color(1.10 + _SUN_WARMTH, 1.04 + _SUN_WARMTH * 0.45, 0.90)
	var cool := Color(0.78, 0.86, 0.94)
	var light := cool.lerp(warm, ndl)
	var dim := lerpf(1.0, 0.78, twilight)
	var lin := Color(col.r * light.r * dim, col.g * light.g * dim, col.b * light.b * dim, 1.0)
	return lin.linear_to_srgb()


static func luminance(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


static func skirt_layer_fade(planar_r: float, params: HillsParams) -> float:
	## 1 inside r_outer, easing to 0 by r_outer + SKIRT_EASE_M (the skirt is plain meadow).
	return 1.0 - smoothstep(params.r_outer_m, params.r_outer_m + VillageTerrain.SKIRT_EASE_M, planar_r)


static func layer_t_for_radius(planar_r: float, params: HillsParams) -> float:
	return _layer_t_inside(minf(planar_r, params.r_outer_m), params) * skirt_layer_fade(planar_r, params)


static func _layer_t_inside(r: float, params: HillsParams) -> float:
	var t0 := _gaussian_layer(r, params.layer_dist_0, params.layer_width_0)
	var t1 := _gaussian_layer(r, params.layer_dist_1, params.layer_width_1)
	var t2 := _gaussian_layer(r, params.layer_dist_2, params.layer_width_2)
	var t3 := _gaussian_layer(r, params.layer_dist_3, params.layer_width_3)
	var sum := t0 + t1 + t2 + t3
	if sum < 1e-6:
		return clampf((r - params.r_inner_m) / maxf(params.r_outer_m - params.r_inner_m, 1.0), 0.0, 1.0)
	return clampf((t0 * 0.0 + t1 * 0.35 + t2 * 0.7 + t3 * 1.0) / sum, 0.0, 1.0)


static func _gaussian_layer(r: float, centre: float, width: float) -> float:
	var d := (r - centre) / maxf(width, 0.01)
	return exp(-0.5 * d * d)


static func terrain_albedo(
		_world: Vector3, layout: VillageLayout, params: HillsParams, ndl: float,
		planar_r: float, height_m: float, slope_deg: float) -> Color:
	var layer_t := layer_t_for_radius(planar_r, params)
	var col := _L0_GREEN.lerp(_L1_GREEN, smoothstep(0.15, 0.55, layer_t))
	var shade := lerpf(0.72, 1.08, clampf(ndl, 0.0, 1.0))
	col.r *= shade
	col.g *= shade * 1.02
	col.b *= shade * 0.96
	var slope_lift := clampf(slope_deg / 30.0, 0.0, 1.0) * 0.06
	col.g += slope_lift
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


static func color_for_world(
		world: Vector3, params: HillsParams, layout: VillageLayout,
		slope_deg: float = 0.0, planar_r: float = -1.0, ndl: float = 0.65) -> Color:
	var g := layout.hamlet_centre_xz
	var r := planar_r if planar_r >= 0.0 else Vector2(world.x - g.x, world.z - g.y).length()
	var y_rel := world.y - VillageBackdrop.LAWN_GROUND_Y_OFFSET
	return terrain_albedo(world, layout, params, ndl, r, y_rel, slope_deg)


static func tree_instance_color(world: Vector3, params: HillsParams, layout: VillageLayout) -> Color:
	var g := layout.hamlet_centre_xz
	var r := Vector2(world.x - g.x, world.z - g.y).length()
	return tree_albedo(world, layout, params, r)


static func apply_terrain_shader(mat: ShaderMaterial, layout: VillageLayout, params: HillsParams) -> void:
	var g := layout.hamlet_centre_xz
	mat.set_shader_parameter("u_hamlet_xz", Vector2(g.x, g.y))
	mat.set_shader_parameter("u_lawn_radius", layout.lawn_radius)
	mat.set_shader_parameter("u_sun_dir", DEFAULT_SUN_DIR)
	mat.set_shader_parameter("u_twilight", 0.0)
	# Seam calibration: measured rendered lawn colour used by the unshaded meadow_ring
	# blend.  Adjust this value if the rendered lawn changes (e.g. different sky).
	mat.set_shader_parameter("u_lawn_colour",
			Vector3(_LAWN_COLOUR.r, _LAWN_COLOUR.g, _LAWN_COLOUR.b))
	# Hill base colours (rework5 values, pre-lighting).
	# With unshaded mode these are ~1.67× darker than the old double-lit output.
	mat.set_shader_parameter("u_meadow_near", Vector3(_L0_GREEN.r, _L0_GREEN.g, _L0_GREEN.b))
	mat.set_shader_parameter("u_meadow_mid",  Vector3(_L1_GREEN.r, _L1_GREEN.g, _L1_GREEN.b))
	mat.set_shader_parameter("sun_warmth", params.sun_warmth)
	# Ridge layer geometry (MAJOR-2): pass params → shader so layer_t_for_r reads
	# uniforms instead of hardcoded literals, keeping one source of truth.
	# Weights match HillsTint.layer_t_for_radius: 0.0 / 0.35 / 0.70 / 1.0.
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
	mat.set_shader_parameter("u_r_outer", params.r_outer_m)
	mat.set_shader_parameter("u_skirt_ease", VillageTerrain.SKIRT_EASE_M)
	# Azimuth wedge (MAJOR-4): pass wedge geometry so the shader can fade hill
	# colouring outside the north wedge, rendering flat east/west as plain meadow.
	mat.set_shader_parameter("u_azimuth_centre_rad",     deg_to_rad(params.azimuth_centre_deg))
	mat.set_shader_parameter("u_azimuth_half_width_rad", deg_to_rad(params.azimuth_half_width_deg))
	mat.set_shader_parameter("u_azimuth_fade_width_rad", deg_to_rad(params.azimuth_fade_width_deg))
