class_name SkySun
extends Node3D

## Presentation only. Drives the DirectionalLight3D and the procedural sky from
## `Solar`, applying the SD-TIME-4 render blend so the sun does not strobe at
## time-lapse speeds. The light field never sees this blend.
##
## The WorldEnvironment sky shader draws the sun disc from the first
## DirectionalLight (LIGHT0), so the light and sky sun stay aligned by construction.

## Elevation band (as sin of angle) over which the rendered light fades in at dawn.
## Wider than a hard horizon test so sunrise is a fade rather than a pop.
const TWILIGHT_SIN := 0.12

## Directional-light colour endpoints: warm orange near the horizon, near-white at
## high elevation. The lerp uses smoothstep(0, 0.5, s_y) so colour saturates to
## noon-white well before the sun reaches zenith, matching perceptual experience.
const _COLOR_DAWN := Color(1.0, 0.60, 0.28)
# ivy-3cx slice 1: warmed noon colour. #FFF1DA = (1.0, 0.945, 0.855) — reads warm/golden
# while keeping blue >= 0.85 so test_light_color_near_white_at_high_elevation stays green.
const _COLOR_NOON := Color(1.0, 0.945, 0.855)

## Night-sky energy multiplier for the Environment background. Low but not zero —
## implies moon/stars without a separate material. Zero would give a pitch-black
## background that breaks silhouette reads at midnight.
const _SKY_NIGHT := 0.02

## Ambient energy scalar at midnight (floor) and at noon (ceiling). With
## AMBIENT_SOURCE_SKY the floor keeps the night-side of the tower from going
## pitch-black while the sky itself is very dim; the ceiling gives full sky-
## sourced ambient at noon so shaded surfaces read as shaded rather than as black.
const _AMBIENT_NIGHT := 0.06
const _AMBIENT_DAY   := 1.0

## Authored sky palette (matches main.tscn defaults). Runtime twilight tints blend
## toward the warm / violet endpoints below when the sun hugs the horizon.
const _SKY_TOP_DAY := Color(0.361, 0.561, 0.722)
const _SKY_HORIZON_DAY := Color(0.784, 0.851, 0.91)
const _SKY_TOP_TWILIGHT := Color(0.22, 0.28, 0.52)
const _SKY_HORIZON_TWILIGHT := Color(1.0, 0.52, 0.32)

const _FOG_DAY := Color(0.78, 0.84, 0.91)
const _FOG_TWILIGHT := Color(0.96, 0.58, 0.40)

## Matches ProceduralSkyMaterial.sky_energy_multiplier in main.tscn.
const _SKY_ENERGY_BASE := 1.4

var solar: Solar

var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _sky_shader: ShaderMaterial
var _base_energy: float = 1.2


func setup(s: Solar) -> void:
	solar = s
	_sun = get_node_or_null("Sun") as DirectionalLight3D
	_env = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _sun != null:
		_base_energy = _sun.light_energy
	if _env != null and _env.environment != null and _env.environment.sky != null:
		var mat := _env.environment.sky.sky_material
		if mat is ShaderMaterial:
			_sky_shader = mat as ShaderMaterial


## Sets fog depth range on the shared Environment (AR-VG-DECIDE §2).
## Called by World.rebuild_backdrop() after each build so the fog seam is updated.
## Classic layout carries 9.5/95, so rebuilding into classic restores the default.
func set_fog_depth(begin: float, end: float) -> void:
	if _env == null or _env.environment == null:
		return
	_env.environment.fog_depth_begin = begin
	_env.environment.fog_depth_end = end


## `seconds_per_game_day` comes from `SimClock.seconds_per_game_day()`.
func update(game_day: float, seconds_per_game_day: float) -> void:
	if solar == null or _sun == null:
		return
	var s := solar.render_direction(game_day, seconds_per_game_day)
	# The light emits along its local -Z, so it must be aimed away from the sun
	# for its forward to equal -S (SD-CONV-9).
	var target := _sun.global_position - s
	if absf(s.x) < 1e-4 and absf(s.z) < 1e-4:
		# Sun straight overhead or straight down: look_at's up vector degenerates.
		_sun.global_basis = Basis(Conv.EAST, Conv.SOUTH * signf(s.y), Conv.UP * signf(s.y))
	else:
		_sun.look_at(target, Conv.UP)
	var lit := lit_for(s.y)
	_sun.light_energy = _base_energy * lit
	_sun.visible = lit > 0.0
	_sun.light_color = light_color_for(s.y)
	if _env != null and _env.environment != null:
		var bg := background_energy_for(lit)
		_env.environment.background_energy_multiplier = bg
		# Cloud-free ambient: SKY radiance includes bright clouds and washes out the
		# meadow. COLOR + gradient from sky palette until we split sky lighting.
		_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.environment.ambient_light_color = ambient_light_color_for(s.y, lit)
		_env.environment.ambient_light_energy = ambient_energy_for(lit)
		_env.environment.fog_light_color = fog_color_for(s.y, lit)
		if _sky_shader != null:
			var tw := twilight_glow_for(s.y, lit)
			_sky_shader.set_shader_parameter("sky_top_color", sky_top_color_for(s.y, lit))
			_sky_shader.set_shader_parameter("sky_horizon_color", sky_horizon_color_for(s.y, lit))
			_sky_shader.set_shader_parameter("sky_energy", bg * _SKY_ENERGY_BASE)
			_sky_shader.set_shader_parameter("twilight_glow", tw)
			var cloud_tint := Color(0.88, 0.90, 0.93).lerp(Color(0.95, 0.72, 0.55), tw * 0.65)
			_sky_shader.set_shader_parameter("cloud_tint", Vector3(cloud_tint.r, cloud_tint.g, cloud_tint.b))
			var rim := twilight_rim_color_for(s.y, lit)
			_sky_shader.set_shader_parameter(
				"twilight_rim_color", Vector3(rim.r, rim.g, rim.b))


## True when the rendered sun is showing daily-average light rather than the live
## sun, which the HUD surfaces as the SD-TIME-5 time-lapse indicator.
func is_time_lapse(seconds_per_game_day: float) -> bool:
	return solar != null and solar.render_blend(seconds_per_game_day) < 1.0


## ─── Pure helpers — static, testable headlessly ───────────────────────────

## Smoothstep fade from dark to lit over the twilight band. Returns 0.0 when the
## sun is at or below the horizon, 1.0 once it has cleared TWILIGHT_SIN.
static func lit_for(s_y: float) -> float:
	return smoothstep(0.0, TWILIGHT_SIN, s_y)


## Directional-light colour temperature. Warm orange at low elevation, near-white
## at high elevation. `s_y` is the sin of the solar elevation angle.
## The smoothstep over [0, 0.5] means the colour reaches noon-white around 30°
## elevation, which matches perceived sky colouring.
static func light_color_for(s_y: float) -> Color:
	var t := smoothstep(0.0, 0.5, s_y)
	return _COLOR_DAWN.lerp(_COLOR_NOON, t)


## Environment background energy multiplier. Dims the sky to near-zero at night
## so the procedural sky reads as dark, not as its authored daytime colours.
static func background_energy_for(lit: float) -> float:
	return lerpf(_SKY_NIGHT, 1.0, lit)


## Ambient light energy scalar. A small floor at night keeps silhouettes visible
## against a very dim sky; full energy at noon gives proper sky-sourced ambient
## illumination so shaded surfaces read as shaded rather than as black.
static func ambient_energy_for(lit: float) -> float:
	return lerpf(_AMBIENT_NIGHT, _AMBIENT_DAY, lit)


## Gaussian-ish weight peaking when the sun is near the horizon — drives sky and fog
## colour shifts without a second solar read.
static func twilight_glow_for(s_y: float, lit: float) -> float:
	if lit <= 0.0:
		return 0.0
	var band := exp(-s_y * s_y / 0.014)
	return clampf(band * lit, 0.0, 1.0)


static func sky_top_color_for(s_y: float, lit: float) -> Color:
	var tw := twilight_glow_for(s_y, lit)
	return _SKY_TOP_DAY.lerp(_SKY_TOP_TWILIGHT, tw * 0.75)


static func sky_horizon_color_for(s_y: float, lit: float) -> Color:
	var tw := twilight_glow_for(s_y, lit)
	return _SKY_HORIZON_DAY.lerp(_SKY_HORIZON_TWILIGHT, tw)


static func fog_color_for(s_y: float, lit: float) -> Color:
	var tw := twilight_glow_for(s_y, lit)
	return _FOG_DAY.lerp(_FOG_TWILIGHT, tw)


## Diffuse ambient without cloud radiance — blend of authored sky gradient colors.
static func ambient_light_color_for(s_y: float, lit: float) -> Color:
	var top := sky_top_color_for(s_y, lit)
	var hor := sky_horizon_color_for(s_y, lit)
	return top.lerp(hor, 0.5)


## Silver lining at noon; warm gold rim at twilight (shader mixes by twilight_glow).
static func twilight_rim_color_for(s_y: float, lit: float) -> Color:
	var tw := twilight_glow_for(s_y, lit)
	return Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.48, 0.28), tw)
