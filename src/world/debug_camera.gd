class_name DebugCamera
extends Camera3D

## Orbit camera rooted to one world point (AR-DBGCAM). The wheel zooms. WASD and the arrow
## keys yaw and pitch. Tab unlocks mouse-look (the pointer is captured and motion orbits,
## the way a left-drag used to) or locks it again so the pointer can click the HUD. In the
## locked mode a left-click raycasts and glides the orbit origin to that point, speeding up
## then slowing down. While the player is still planting, left-click belongs to the planter.
##
## Who may write [current] and the transform (AR-DBGCAM-5):
##   Interactive input writes both inside [_unhandled_input], and only there calls
##   [make_current]. A glide in progress writes [global_transform] from [_process] only
##   while this camera is already [current] — it must never steal the view from CamSun.
##   [activate_for_planting] and [apply_scripted_snapshot] are the other two writers.
##   [script_driven] disables input and process, so automated runs stay on CamSun.

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
var _base_zoom_min_r: float = 3.0
var _base_zoom_max_r: float = 12.0
var _village_camera_mult: float = 1.0
## True while Tab has captured the pointer: motion orbits, and there is no cursor to aim a click.
var _mouse_look: bool = false
## Absolute orbit origin once the player has a rooted point. Until then [_pivot] uses the building.
var _origin: Vector3 = Vector3.ZERO
var _has_origin: bool = false
var _gliding: bool = false
var _glide_from: Vector3 = Vector3.ZERO
var _glide_to: Vector3 = Vector3.ZERO
var _glide_elapsed: float = 0.0
var _glide_seconds: float = 0.0
## Legacy snapshot field. Live control no longer pans; restore folds this into the origin.
var _pan_offset: Vector3 = Vector3.ZERO
## The view setup() or set_orbit_pivot() settled on; R / Home returns to it.
var _home_yaw: float = 0.0
var _home_pitch: float = 0.031415927
var _home_radius: float = 8.01
var _home_origin: Vector3 = Vector3.ZERO
var _has_home_origin: bool = false

const _DRAG_DEG_PER_PIXEL := 0.3
## One key press (including auto-repeat) turns the orbit by this many degrees.
const _KEY_DEG_PER_PRESS := 3.0
## Smoothstep glide. Short hops still take [_GLIDE_MIN_SEC] so the ease reads; long ones cap.
const _GLIDE_MIN_SEC := 0.35
const _GLIDE_MAX_SEC := 1.05
const _GLIDE_METRES_PER_SEC := 7.0
## Structures live on layer 1, the ground plane on layer 2. Pick structures first, then ground.
const _PICK_MASK_STRUCTURE := 1
const _PICK_MASK_GROUND := 2
const _PICK_RANGE := 120.0
## Zoom limits scale the AR-DBGCAM-4 baseline: 4× closer in, 2× further out.
const _ZOOM_MIN_DIVISOR := 4.0
const _ZOOM_MAX_MULTIPLIER := 2.0
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
		# Engine-level gate: kill input and the glide process for UI-script runs (AR-DBGCAM-5b).
		# In-function guards still exist, because tests call those methods directly.
		set_process_unhandled_input(false)
		set_process(false)
	else:
		set_process(true)


## Called from Main._ready() after World has assigned tower_spec (W-055).
## AR-DBGCAM-2 seeding lives here, not in _ready — children run before parent, so
## Main cannot inject spec before DebugCamera._ready() without racing the seed.
func setup(tower_spec: TowerSpec, zoom_bounds: Vector2 = Vector2(-1.0, -1.0)) -> void:
	spec = tower_spec
	var bounds := zoom_bounds
	if bounds.x < 0.0:
		bounds = tower_zoom_bounds(tower_spec)
	_base_zoom_min_r = bounds.x
	_base_zoom_max_r = bounds.y
	_apply_village_camera_mult_to_zoom_bounds()
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
	_origin = _base_pivot()
	_has_origin = true
	_gliding = false
	_home_yaw = _yaw
	_home_pitch = _pitch
	_home_radius = _radius
	_home_origin = _origin
	_has_home_origin = true


## Scale orbit radius and zoom limits for generated village framing (ivy-0ka). Classic = 1.0.
func apply_village_camera_scale(mult: float) -> void:
	if absf(mult - _village_camera_mult) < 1e-6:
		return
	var prev := _village_camera_mult
	_village_camera_mult = mult
	_apply_village_camera_mult_to_zoom_bounds()
	if prev > 1e-6:
		_radius = clamp_radius_with_bounds(_radius / prev * mult, _zoom_min_r, _zoom_max_r)
		_home_radius = clamp_radius_with_bounds(_home_radius / prev * mult, _zoom_min_r, _zoom_max_r)
	else:
		_radius = clamp_radius_with_bounds(_radius * mult, _zoom_min_r, _zoom_max_r)
		_home_radius = clamp_radius_with_bounds(_home_radius * mult, _zoom_min_r, _zoom_max_r)


func _apply_village_camera_mult_to_zoom_bounds() -> void:
	_zoom_min_r = _base_zoom_min_r * _village_camera_mult
	_zoom_max_r = _base_zoom_max_r * _village_camera_mult


## Interactive-only entry for M6 ground planting. Automated runners never call this.
var _orbit_pivot_override: Variant = null
var _planting_mode: bool = false
## Live session surface query (structures on layer 1). Main wires this after bootstrap.
var _surface: SurfaceQuery = null


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
	_gliding = false
	var pan: Array = state.get("pan_offset", [0.0, 0.0, 0.0])
	_pan_offset = Vector3(float(pan[0]), float(pan[1]), float(pan[2]))
	# The saved pivot is the resolved world point (base + any old pan). Prefer it so a
	# click-to-move origin round-trips; fall back to the pan offset for older snapshots.
	if state.has("pivot"):
		var pivot: Array = state["pivot"]
		_origin = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))
		_has_origin = true
		_pan_offset = Vector3.ZERO
		_orbit_pivot_override = _origin


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


func set_surface_query(surface: SurfaceQuery) -> void:
	_surface = surface


func set_orbit_pivot(p: Vector3) -> void:
	_orbit_pivot_override = p
	_pan_offset = Vector3.ZERO
	_origin = p
	_has_origin = true
	_home_origin = p
	_has_home_origin = true
	_gliding = false


func activate_for_planting() -> void:
	if script_driven or spec == null:
		return
	_planting_mode = true
	_set_mouse_look(false)
	current = true
	global_transform = solve(_pivot(), _yaw, _pitch, _radius)


func finish_planting() -> void:
	_planting_mode = false


## Interactive-only. Called when the player leaves a building for the picker: stop answering
## keys and drags (the view is not on screen) until setup() hands us a spec again. Writes
## private state only; the caller makes another camera current.
func suspend() -> void:
	spec = null
	_planting_mode = false
	_orbit_pivot_override = null
	_pan_offset = Vector3.ZERO
	_has_origin = false
	_gliding = false
	_surface = null
	_set_mouse_look(false)


func _unhandled_input(event: InputEvent) -> void:
	# Interactive [current] is claimed here. Transforms update here too, except during an
	# origin glide while this camera is already [current] — see [_process].
	if script_driven:
		return

	if spec == null:
		return

	var moved := false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by_notches(_NOTCHES_PER_KEY_PRESS)
			moved = true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by_notches(-_NOTCHES_PER_KEY_PRESS)
			moved = true
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _planting_mode and not _mouse_look:
			var hit: Vector3 = _raycast_world_point(mb.position)
			if hit.is_finite():
				_begin_glide_to(hit)
				moved = true
	elif event is InputEventPanGesture:
		# A trackpad two-finger scroll on macOS arrives here, never as a wheel button.
		_zoom_by_notches(-(event as InputEventPanGesture).delta.y * _NOTCHES_PER_PAN_UNIT)
		moved = true
	elif event is InputEventMouseMotion and _mouse_look:
		var mm := event as InputEventMouseMotion
		_yaw   -= mm.relative.x * deg_to_rad(_DRAG_DEG_PER_PIXEL)
		_pitch = clamp_pitch(
			_pitch - mm.relative.y * deg_to_rad(_DRAG_DEG_PER_PIXEL), _radius, _pivot().y)
		moved = true
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_TAB and not key.echo:
			_set_mouse_look(not _mouse_look)
			moved = true
		elif _rotate_by_key(key.keycode):
			moved = true
		elif key.keycode == KEY_R or key.keycode == KEY_HOME:
			_yaw = _home_yaw
			_pitch = _home_pitch
			_radius = _home_radius
			_pan_offset = Vector3.ZERO
			_gliding = false
			if _has_home_origin:
				_origin = _home_origin
				_has_origin = true
				_orbit_pivot_override = _home_origin
			moved = true

	if moved:
		_apply_orbit_view()


func _process(delta: float) -> void:
	if script_driven or not _gliding or not current:
		return
	_glide_elapsed += delta
	if _glide_elapsed >= _glide_seconds:
		_gliding = false
		_origin = _glide_to
		_has_origin = true
		_orbit_pivot_override = _origin
	global_transform = solve(_pivot(), _yaw, _pitch, _radius)


func _apply_orbit_view() -> void:
	make_current()
	global_transform = solve(_pivot(), _yaw, _pitch, _radius)


func _rotate_by_key(keycode: Key) -> bool:
	var step := deg_to_rad(_KEY_DEG_PER_PRESS)
	match keycode:
		KEY_LEFT, KEY_A:
			_yaw -= step
			return true
		KEY_RIGHT, KEY_D:
			_yaw += step
			return true
		KEY_UP, KEY_W:
			_pitch = clamp_pitch(_pitch + step, _radius, _pivot().y)
			return true
		KEY_DOWN, KEY_S:
			_pitch = clamp_pitch(_pitch - step, _radius, _pivot().y)
			return true
	return false


func _begin_glide_to(world_point: Vector3) -> void:
	var from := _pivot()
	if from.distance_squared_to(world_point) < 0.01:
		_origin = world_point
		_has_origin = true
		_orbit_pivot_override = _origin
		_gliding = false
		return
	_glide_from = from
	_glide_to = world_point
	_glide_elapsed = 0.0
	var dist := from.distance_to(world_point)
	_glide_seconds = clampf(dist / _GLIDE_METRES_PER_SEC, _GLIDE_MIN_SEC, _GLIDE_MAX_SEC)
	_gliding = true


func _glide_blend() -> float:
	if _glide_seconds <= 0.0:
		return 1.0
	var t := clampf(_glide_elapsed / _glide_seconds, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _raycast_world_point(screen: Vector2) -> Vector3:
	var from := project_ray_origin(screen)
	var to := from + project_ray_normal(screen) * _PICK_RANGE
	if _surface != null:
		var sq_hit := _surface.raycast(from, to)
		if sq_hit.hit:
			return sq_hit.position
	var world := get_world_3d()
	if world == null:
		return Vector3(INF, INF, INF)
	var space := world.direct_space_state
	var on_structure := _physics_ray_point(from, to, space, _PICK_MASK_STRUCTURE)
	if on_structure.is_finite():
		return on_structure
	return _physics_ray_point(from, to, space, _PICK_MASK_GROUND)


func _physics_ray_point(from: Vector3, to: Vector3, space: PhysicsDirectSpaceState3D, mask: int) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3(INF, INF, INF)
	return hit.position


func _set_mouse_look(enabled: bool) -> void:
	if _mouse_look == enabled:
		return
	_mouse_look = enabled
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _zoom_by_notches(notches: float) -> void:
	_radius = clamp_radius_with_bounds(
		_radius * pow(_ZOOM_PER_NOTCH, notches), _zoom_min_r, _zoom_max_r)
	_pitch = clamp_pitch(_pitch, _radius, _pivot().y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_set_mouse_look(false)


func _pivot() -> Vector3:
	if _gliding:
		return _glide_from.lerp(_glide_to, _glide_blend())
	if _has_origin:
		return _origin
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
	var baseline_min := s.radius_outer + 1.0
	var baseline_max := (s.height + 2.0 * s.radius_outer) * 1.6
	return Vector2(baseline_min / _ZOOM_MIN_DIVISOR, baseline_max * _ZOOM_MAX_MULTIPLIER)


## Orbit zoom bounds for the procedural test wall — same formula shape as the tower
## path, with half-diagonal of the wall rectangle as the analogous radial extent.
static func wall_zoom_bounds(s: WallSpec) -> Vector2:
	var radial_extent := sqrt(s.length * s.length + s.height * s.height) * 0.5
	var baseline_min := s.thickness * 0.5 + 1.0
	var baseline_max := (s.height + 2.0 * radial_extent) * 1.6
	return Vector2(baseline_min / _ZOOM_MIN_DIVISOR, baseline_max * _ZOOM_MAX_MULTIPLIER)


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


## Steepest downward pitch that still keeps the camera above [ground_clearance] at this radius.
static func min_pitch_for_radius(radius: float, pivot_y: float, ground_clearance: float = 0.05) -> float:
	var floor := deg_to_rad(-5.0)
	if radius <= 1e-4:
		return floor
	var min_sin := (ground_clearance - pivot_y) / radius
	return maxf(floor, asin(clampf(min_sin, -1.0, 1.0)))


## Clamp pitch to [-5°, +85°] (AR-DBGCAM-4), raising the floor when [radius] would
## drop the camera underground at wide zoom-out.
static func clamp_pitch(p: float, radius: float = -1.0, pivot_y: float = 0.0) -> float:
	var min_p := deg_to_rad(-5.0)
	if radius > 0.0:
		min_p = min_pitch_for_radius(radius, pivot_y)
	return clampf(p, min_p, deg_to_rad(85.0))


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
