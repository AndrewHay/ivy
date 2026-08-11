class_name SkySun
extends Node3D

## Presentation only. Drives the DirectionalLight3D and the procedural sky from
## `Solar`, applying the SD-TIME-4 render blend so the sun does not strobe at
## time-lapse speeds. The light field never sees this blend.
##
## The ProceduralSkyMaterial in the WorldEnvironment automatically draws a sun disc
## at the DirectionalLight's position (Godot 4 built-in behaviour), so no separate
## sky-sun direction is needed — the light and sky sun are the same object by
## construction.

## Elevation band (as sin of angle) over which the rendered light fades in at dawn.
## Wider than a hard horizon test so sunrise is a fade rather than a pop.
const TWILIGHT_SIN := 0.12

## Directional-light colour endpoints: warm orange near the horizon, near-white at
## high elevation. The lerp uses smoothstep(0, 0.5, s_y) so colour saturates to
## noon-white well before the sun reaches zenith, matching perceptual experience.
const _COLOR_DAWN := Color(1.0, 0.60, 0.28)
const _COLOR_NOON := Color(1.0, 0.97, 0.93)

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

var solar: Solar

var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _base_energy: float = 1.2


func setup(s: Solar) -> void:
	solar = s
	_sun = get_node_or_null("Sun") as DirectionalLight3D
	_env = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _sun != null:
		_base_energy = _sun.light_energy


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
		_env.environment.background_energy_multiplier = background_energy_for(lit)
		_env.environment.ambient_light_energy = ambient_energy_for(lit)


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
