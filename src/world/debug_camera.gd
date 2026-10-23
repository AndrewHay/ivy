class_name DebugCamera
extends Camera3D

## Developer-only orbit/zoom/pan camera (AR-DBGCAM). One Camera3D, one script, three
## orbit floats plus a pan offset, one _unhandled_input — explicitly not a camera framework.
##
## Structural invariant for Code Review (AR-DBGCAM-5):
##   Every write to [current] and to the transform (make_current, global_transform)
##   occurs exclusively inside [_unhandled_input], and nowhere else in this file.
##   [_ready] writes only the private floats _yaw/_pitch/_radius via setup(); it never touches
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
var _zoom_min_r: float = 3.0
var _zoom_max_r: float = 12.0
var _dragging: bool = false
## Arrow-key pan, added to the building pivot. Reset whenever the base pivot is replaced.
var _pan_offset: Vector3 = Vector3.ZERO
## The view setup() settled on; the reset key (R / Home) returns to it.
var _home_yaw: float = 0.0
var _home_pitch: float = 0.031415927
var _home_radius: float = 8.01

const _DRAG_DEG_PER_PIXEL := 0.3
## One arrow press moves the pivot by this fraction of the orbit radius, so a press covers the
## same share of the screen whether zoomed in on a leaf or pulled back to the whole wall.
const _PAN_FRACTION_PER_KEY_PRESS := 0.06
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


## Called from Main._ready() after World has assigned tower_spec (W-055).
## AR-DBGCAM-2 seeding lives here, not in _ready — children run before parent, so
## Main cannot inject spec before DebugCamera._ready() without racing the seed.
func setup(tower_spec: TowerSpec, zoom_bounds: Vector2 = Vector2(-1.0, -1.0)) -> void:
	spec = tower_spec
	var bounds := zoom_bounds
	if bounds.x < 0.0:
		bounds = tower_zoom_bounds(tower_spec)
	_zoom_min_r = bounds.x
	_zoom_max_r = bounds.y
	# Large buildings (test wall) need a pull-back default; CamSun seeding is cylinder-scale.
	if _zoom_max_r > 20.0:
		_radius = clamp_radius_with_bounds(
			(_zoom_min_r + _zoom_max_r) * 0.35, _zoom_min_r, _zoom_max_r)
	elif not script_driven:
		# Seed orbit state from CamSun's authored transform so that first activation
		# produces no visible jump (AR-DBGCAM-2). Only the private floats are written here —
		# current and the camera transform are never touched outside _unhandled_input.
		var cam_sun := get_node_or_null("../CameraRig/CamSun") as Camera3D
		if cam_sun != null:
			var pivot := _pivot()
			var offset := cam_sun.global_position - pivot
			var raw_r := offset.length()
			if raw_r > 1e-4:
				_radius = clamp_radius_with_bounds(raw_r, _zoom_min_r, _zoom_max_r)
				_pitch  = clamp_pitch(asin(clampf(offset.y / raw_r, -1.0, 1.0)))
				_yaw    = atan2(offset.x, offset.z)
	# Whatever view we settled on is "home" for the reset key. Private floats only.
	_home_yaw = _yaw
	_home_pitch = _pitch
	_home_radius = _radius


## Interactive-only entry for M6 ground planting. Automated runners never call this.
var _orbit_pivot_override: Variant = null
var _planting_mode: bool = false


## Read-only: which side of the building the camera is on, as atan2(offset.x, offset.z). 0 is the
## south side looking north. The HUD's sun compass turns by this.
func get_yaw() -> float:
	return _yaw


## Serializable orbit state for debug snapshots (AR-SNAP-5). Read-only; no transform writes.
func capture_state() -> Dictionary:
	var pivot := _pivot()
	return {
		"yaw": _yaw,
		"pitch": _pitch,
		"radius": _radius,
		"pan_offset": [_pan_offset.x, _pan_offset.y, _pan_offset.z],
		"pivot": [pivot.x, pivot.y, pivot.z],
	}


## Restore orbit floats from [capture_state]. Does not make this camera current.
func restore_state(state: Dictionary) -> void:
	_yaw = float(state.get("yaw", _yaw))
	_pitch = float(state.get("pitch", _pitch))
	_radius = float(state.get("radius", _radius))
	var pan: Array = state.get("pan_offset", [0.0, 0.0, 0.0])
	_pan_offset = Vector3(float(pan[0]), float(pan[1]), float(pan[2]))


## Script-driven replay only (AR-DBGCAM-5). Restores a saved snapshot camera block.
func apply_scripted_snapshot(block: Dictionary) -> void:
	if not script_driven:
		push_error("DebugCamera.apply_scripted_snapshot is script_driven only")
		return
	if block.has("debug_camera"):
		restore_state(block["debug_camera"] as Dictionary)
	if block.has("global_transform"):
		global_transform = _transform_from_array(block["global_transform"] as Array)
	if block.has("fov"):
		fov = float(block["fov"])
	if block.has("near"):
		near = float(block["near"])
	if block.has("far"):
		far = float(block["far"])
	current = true


static func _transform_from_array(values: Array) -> Transform3D:
	if values.size() < 12:
		return Transform3D.IDENTITY
	var b := Basis(
		Vector3(float(values[0]), float(values[1]), float(values[2])),
		Vector3(float(values[4]), float(values[5]), float(values[6])),
		Vector3(float(values[8]), float(values[9]), float(values[10]))
	)
	var o := Vector3(float(values[3]), float(values[7]), float(values[11]))
	return Transform3D(b, o)


func set_orbit_pivot(p: Vector3) -> void:
	_orbit_pivot_override = p
	_pan_offset = Vector3.ZERO


func activate_for_planting() -> void:
	if script_driven or spec == null:
		return
	_planting_mode = true
	current = true
	global_transform = solve(_pivot(), _yaw, _pitch, _radius)


func finish_planting() -> void:
	_planting_mode = false
	_dragging = false


## Interactive-only. Called when the player leaves a building for the picker: stop answering
## keys and drags (the view is not on screen) until setup() hands us a spec again. Writes
## private state only; the caller makes another camera current.
func suspend() -> void:
	spec = null
	_planting_mode = false
	_dragging = false
	_orbit_pivot_override = null
	_pan_offset = Vector3.ZERO


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
		return

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
		elif mb.button_index == MOUSE_BUTTON_LEFT and not _planting_mode:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and _planting_mode:
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
		# Echo (auto-repeat) events are accepted so holding the key keeps zooming/panning. Doing
		# this smoothly from _process would put a transform write outside _unhandled_input and
		# forfeit the AR-DBGCAM-5 guarantee, which is not worth trading for easing.
		match (event as InputEventKey).keycode:
			KEY_W:
				_zoom_by_notches(_NOTCHES_PER_KEY_PRESS)
				moved = true
			KEY_S:
				_zoom_by_notches(-_NOTCHES_PER_KEY_PRESS)
				moved = true
			KEY_LEFT:
				_pan_by_steps(-1.0, 0.0)
				moved = true
			KEY_RIGHT:
				_pan_by_steps(1.0, 0.0)
				moved = true
			KEY_UP:
				_pan_by_steps(0.0, 1.0)
				moved = true
			KEY_DOWN:
				_pan_by_steps(0.0, -1.0)
				moved = true
			KEY_R, KEY_HOME:
				_yaw = _home_yaw
				_pitch = _home_pitch
				_radius = _home_radius
				_pan_offset = Vector3.ZERO
				moved = true

	if moved:
		make_current()
		global_transform = solve(_pivot(), _yaw, _pitch, _radius)


func _pan_by_steps(right_steps: float, up_steps: float) -> void:
	_pan_offset = pan(_pan_offset, _yaw, right_steps, up_steps,
		_radius * _PAN_FRACTION_PER_KEY_PRESS, _zoom_max_r, -_base_pivot().y)


func _zoom_by_notches(notches: float) -> void:
	_radius = clamp_radius_with_bounds(
		_radius * pow(_ZOOM_PER_NOTCH, notches), _zoom_min_r, _zoom_max_r)


func _notification(what: int) -> void:
	# A button-release delivered outside the window never reaches _unhandled_input, which
	# would leave the drag latched on and make the view spin on the next mouse move.
	# Clears a flag only — no transform write, so the AR-DBGCAM-5 structure is preserved.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false


func _pivot() -> Vector3:
	return _base_pivot() + _pan_offset


func _base_pivot() -> Vector3:
	if _orbit_pivot_override != null:
		return _orbit_pivot_override
	# AR-DBGCAM-3: pivot at tower mid-height derived from TowerSpec, never hardcoded.
	return Vector3(0.0, spec.height * 0.5, 0.0)


## Move a pan offset by `right_steps` along the camera's horizontal right vector (derived from
## `yaw`, so "right" is always screen-right) and `up_steps` along world up, each step `step` m.
## The result is clamped to `max_len` from the base pivot so the building can't be lost
## off-screen, and its y kept ≥ `min_y` so the pivot never sinks below the ground.
## Pure — no side effects, safe to call from tests headlessly.
static func pan(offset: Vector3, yaw: float, right_steps: float, up_steps: float,
		step: float, max_len: float, min_y: float) -> Vector3:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var out := offset + right * (right_steps * step) + Vector3.UP * (up_steps * step)
	out = out.limit_length(max_len)
	out.y = maxf(out.y, min_y)
	return out


## Orbit zoom bounds for a tower/cylinder from TowerSpec (AR-DBGCAM-4).
static func tower_zoom_bounds(s: TowerSpec) -> Vector2:
	return Vector2(s.radius_outer + 1.0, (s.height + 2.0 * s.radius_outer) * 1.6)


## Orbit zoom bounds for the procedural test wall — same formula shape as the tower
## path, with half-diagonal of the wall rectangle as the analogous radial extent.
static func wall_zoom_bounds(s: WallSpec) -> Vector2:
	var radial_extent := sqrt(s.length * s.length + s.height * s.height) * 0.5
	return Vector2(s.thickness * 0.5 + 1.0, (s.height + 2.0 * radial_extent) * 1.6)


## Clamp radius to explicit bounds. Pure — no side effects, safe for headless tests.
static func clamp_radius_with_bounds(r: float, min_r: float, max_r: float) -> float:
	return clampf(r, min_r, max_r)


## Clamp radius to [radius_outer + 1.0, (height + 2·radius_outer)·1.6] (AR-DBGCAM-4).
## Pure — no side effects, safe to call from tests headlessly.
static func clamp_radius(r: float, s: TowerSpec) -> float:
	var b := tower_zoom_bounds(s)
	return clamp_radius_with_bounds(r, b.x, b.y)


## Scale radius by `notches` multiplicative zoom steps, positive being closer, then clamp.
## Multiplicative rather than additive so N notches feel the same at 3 m and at 12 m.
## Pure — no side effects, safe to call from tests headlessly.
static func zoom(r: float, notches: float, s: TowerSpec) -> float:
	var b := tower_zoom_bounds(s)
	return clamp_radius_with_bounds(r * pow(_ZOOM_PER_NOTCH, notches), b.x, b.y)


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
