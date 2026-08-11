class_name DebugCamera
extends Camera3D

## Developer-only orbit/zoom camera (AR-DBGCAM). One Camera3D, one script, three
## state floats, one _unhandled_input — explicitly not a camera framework.
##
## Structural invariant for Code Review (AR-DBGCAM-5):
##   Every write to [current] and to the transform (make_current, global_transform)
##   occurs exclusively inside [_unhandled_input], and nowhere else in this file.
##   [_ready] writes only the private floats _yaw/_pitch/_radius; it never touches
##   [current] or the camera transform. A reviewer can confirm this by grepping for
##   make_current, global_transform, and transform writes — all appear only below.

@export var spec: TowerSpec

## Set true before the scene enters the tree to disable all input handling.
## run_ui_script.gd propagates Main.script_driven here via _ready (AR-DBGCAM-5b).
## Tests may also set this directly on an isolated instance.
var script_driven: bool = false

# Spherical orbit state — written only in _unhandled_input (via _ready for seeding floats).
var _yaw: float = 0.0
var _pitch: float = 0.031415927  # ~1.8°, matches CamSun authored default
var _radius: float = 8.01        # ~distance of CamSun authored (0,2,8) from pivot (0,1.75,0)
var _dragging: bool = false

const _DRAG_DEG_PER_PIXEL := 0.3
## Multiplicative zoom: one "notch" scales the radius by this, so the zoom feel is uniform
## across the whole range rather than crawling when close and leaping when far (AR-DBGCAM-4).
const _ZOOM_PER_NOTCH := 0.9
## macOS trackpads emit InputEventPanGesture with per-event deltas around 0.5–1.5, so a whole
## notch per event would be far too coarse. Keyboard steps are discrete, hence a full notch.
const _NOTCHES_PER_PAN_UNIT := 0.5
const _NOTCHES_PER_KEY_PRESS := 1.0


func _ready() -> void:
	# Inherit script_driven from the scene owner (Main). This is safe because
	# run_ui_script.gd assigns the property before add_child, so it is already set by the
	# time any _ready in the scene runs — it does not depend on child-before-parent order.
	var owner_node := get_owner()
	if owner_node != null:
		var sd: Variant = owner_node.get("script_driven")
		if sd != null:
			script_driven = bool(sd)

	if script_driven:
		# Engine-level gate: kill _unhandled_input entirely for UI-script runs (AR-DBGCAM-5b).
		# A second in-function guard exists inside _unhandled_input for test visibility.
		set_process_unhandled_input(false)
		return

	if spec == null:
		spec = load("res://src/world/tower_spec_default.tres") as TowerSpec

	# Seed orbit state from CamSun's authored transform so that first activation
	# produces no visible jump (AR-DBGCAM-2). Only the private floats are written here —
	# current and the camera transform are never touched outside _unhandled_input.
	var cam_sun := get_node_or_null("../CameraRig/CamSun") as Camera3D
	if cam_sun != null:
		var pivot := _pivot()
		var offset := cam_sun.global_position - pivot
		var raw_r := offset.length()
		if raw_r > 1e-4:
			_radius = clamp_radius(raw_r, spec)
			_pitch  = clamp_pitch(asin(clampf(offset.y / raw_r, -1.0, 1.0)))
			_yaw    = atan2(offset.x, offset.z)


func _unhandled_input(event: InputEvent) -> void:
	# ALL writes to [current] and to the transform live exclusively in this function
	# (AR-DBGCAM-5a). No automated runner (take_screenshot.gd, run_ui_script.gd, GUT)
	# injects mouse, trackpad or key events, so CamSun stays current in every automated run.
	#
	# In-function script_driven guard: catches removal of this gate (AR-DBGCAM-6 Test 3).
	# The engine gate set_process_unhandled_input(false) in _ready also applies, but
	# that gate is bypassed when tests call this method directly — this guard catches it.
	if script_driven:
		return

	if spec == null:
		spec = load("res://src/world/tower_spec_default.tres") as TowerSpec

	# Branches below only update the orbit floats and set `moved`; the single write to
	# `current` and to the transform happens at the end of this function, so the
	# AR-DBGCAM-5 structure stays literally true as input sources are added.
	var moved := false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by_notches(_NOTCHES_PER_KEY_PRESS)
			moved = true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by_notches(-_NOTCHES_PER_KEY_PRESS)
			moved = true
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif event is InputEventPanGesture:
		# A trackpad two-finger scroll on macOS arrives here, never as a wheel button.
		_zoom_by_notches(-(event as InputEventPanGesture).delta.y * _NOTCHES_PER_PAN_UNIT)
		moved = true
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw   -= mm.relative.x * deg_to_rad(_DRAG_DEG_PER_PIXEL)
		_pitch  = clamp_pitch(_pitch - mm.relative.y * deg_to_rad(_DRAG_DEG_PER_PIXEL))
		moved = true
	elif event is InputEventKey and (event as InputEventKey).pressed:
		# Echo (auto-repeat) events are accepted so holding the key keeps zooming. Doing this
		# smoothly from _process would put a transform write outside _unhandled_input and
		# forfeit the AR-DBGCAM-5 guarantee, which is not worth trading for easing.
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				_zoom_by_notches(_NOTCHES_PER_KEY_PRESS)
				moved = true
			KEY_DOWN, KEY_S:
				_zoom_by_notches(-_NOTCHES_PER_KEY_PRESS)
				moved = true

	if moved:
		make_current()
		global_transform = solve(_pivot(), _yaw, _pitch, _radius)


func _zoom_by_notches(notches: float) -> void:
	_radius = zoom(_radius, notches, spec)


func _notification(what: int) -> void:
	# A button-release delivered outside the window never reaches _unhandled_input, which
	# would leave the drag latched on and make the view spin on the next mouse move.
	# Clears a flag only — no transform write, so the AR-DBGCAM-5 structure is preserved.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false


func _pivot() -> Vector3:
	# AR-DBGCAM-3: pivot at tower mid-height derived from TowerSpec, never hardcoded.
	return Vector3(0.0, spec.height * 0.5, 0.0)


## Clamp radius to [radius_outer + 1.0, (height + 2·radius_outer)·1.6] (AR-DBGCAM-4).
## Pure — no side effects, safe to call from tests headlessly.
static func clamp_radius(r: float, s: TowerSpec) -> float:
	var min_r := s.radius_outer + 1.0
	var max_r := (s.height + 2.0 * s.radius_outer) * 1.6
	return clampf(r, min_r, max_r)


## Scale radius by `notches` multiplicative zoom steps, positive being closer, then clamp.
## Multiplicative rather than additive so N notches feel the same at 3 m and at 12 m.
## Pure — no side effects, safe to call from tests headlessly.
static func zoom(r: float, notches: float, s: TowerSpec) -> float:
	return clamp_radius(r * pow(_ZOOM_PER_NOTCH, notches), s)


## Clamp pitch to [-5°, +85°] (AR-DBGCAM-4).
## Lower bound keeps camera above ground at max radius; upper bound avoids look_at pole.
## Pure — no side effects, safe to call from tests headlessly.
static func clamp_pitch(p: float) -> float:
	return clampf(p, deg_to_rad(-5.0), deg_to_rad(85.0))


## Compute camera Transform3D from spherical orbit parameters.
## Camera placed at pivot + spherical offset(yaw, pitch, radius), aimed at pivot.
## Yaw=0 places the camera on the +Z (south) side, matching CamSun's authored position.
## Pure — no side effects, safe to call from tests headlessly.
static func solve(pivot: Vector3, yaw: float, pitch: float, radius: float) -> Transform3D:
	var offset := Vector3(
		radius * sin(yaw) * cos(pitch),
		radius * sin(pitch),
		radius * cos(yaw) * cos(pitch)
	)
	var cam_pos := pivot + offset
	# Basis.looking_at makes -Z point toward the first argument (pivot direction).
	# pitch is clamped to ±85° so cos(pitch) > 0 and cam_pos is never directly above pivot,
	# keeping the up vector stable.
	return Transform3D(Basis.looking_at(pivot - cam_pos, Vector3.UP), cam_pos)
