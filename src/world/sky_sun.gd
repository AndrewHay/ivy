class_name SkySun
extends Node3D

## Presentation only. Drives the DirectionalLight3D and the sky from `Solar`,
## applying the SD-TIME-4 render blend so the sun does not strobe at time-lapse
## speeds. The light field never sees this blend.

## Elevation band over which the rendered light fades in at dawn. Wider than a hard
## horizon test so sunrise is a fade rather than a pop, and so a sun a fraction of a
## degree up does not render a near-black frame.
const TWILIGHT_SIN := 0.12

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
	var lit := smoothstep(0.0, TWILIGHT_SIN, s.y)
	_sun.light_energy = _base_energy * lit
	_sun.visible = lit > 0.0
	if _env != null and _env.environment != null:
		_env.environment.ambient_light_energy = lerpf(0.1, 1.0, lit)


## True when the rendered sun is showing daily-average light rather than the live
## sun, which the HUD surfaces as the SD-TIME-5 time-lapse indicator.
func is_time_lapse(seconds_per_game_day: float) -> bool:
	return solar != null and solar.render_blend(seconds_per_game_day) < 1.0
