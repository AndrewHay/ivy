extends Node3D

## Standalone grass-wind algorithm playground (AR-PLAY-GRASS).

const GrassWindParams = preload("res://src/playground/grass_wind_params.gd")
const GrassWindKnobSpec = preload("res://src/playground/grass_wind_knob_spec.gd")
const GrassWindClock = preload("res://src/presentation/fauna/grass_wind_clock.gd")
const KnobPanel = preload("res://src/playground/knob_panel.gd")
const PlaygroundCheckboxStyle = preload("res://src/playground/playground_checkbox_style.gd")
const DebugCamera = preload("res://src/world/debug_camera.gd")
const VillageGrassMesh = preload("res://src/world/village_grass_mesh.gd")

@export var script_driven: bool = false

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _camera: Camera3D = $Camera3D
@onready var _lawn_root: Node3D = $Lawn
@onready var _grass_mm: MultiMeshInstance3D = $Lawn/GrassMultiMesh
@onready var _ground: MeshInstance3D = $Lawn/Ground
@onready var _scale_post: MeshInstance3D = $Lawn/ScalePost
@onready var _grid: MeshInstance3D = $Lawn/Grid

var _params := GrassWindParams.new()
var _clock_state: Dictionary = {}
var _material: ShaderMaterial
var _knob_panel: KnobPanel
var _show_ui := true
var _allow_input := true
var _orbit_yaw := 0.6
var _orbit_pitch := 0.35
var _orbit_radius := 6.0
var _pivot := Vector3.ZERO
## Tab toggles mouse-look (cursor captured). Off by default so the knob panel is usable,
## matching the main game's DebugCamera.
var _mouse_orbit := false
var _camera_hint: Label
var _last_preset := "orbit45"
var _gliding := false
var _glide_from := Vector3.ZERO
var _glide_to := Vector3.ZERO
var _glide_elapsed := 0.0
var _glide_seconds := 0.0

# Values mirror src/world/debug_camera.gd so the two cameras feel the same.
const _DRAG_RAD_PER_PIXEL := 0.3 * PI / 180.0
const _KEY_RAD_PER_PRESS := 3.0 * PI / 180.0
const _ZOOM_PER_NOTCH := 0.9
const _NOTCHES_PER_PAN_UNIT := 0.5
const _ZOOM_MIN_RADIUS := 1.5
const _ZOOM_MAX_RADIUS := 24.0
const _GLIDE_MIN_SEC := 0.35
const _GLIDE_MAX_SEC := 1.05
const _GLIDE_METRES_PER_SEC := 7.0
const _PICK_RANGE := 120.0
var _rebuild_pending := false
var _rng := RandomNumberGenerator.new()
var _show_grid := true
var _show_scale_post := true
var _capture_advance_sec := 0.0


func _ready() -> void:
	_rng.seed = 88002
	var out_path := _parse_out_arg()
	_show_ui = not script_driven
	_allow_input = out_path.is_empty() and not script_driven
	_setup_environment()
	_material = ShaderMaterial.new()
	_material.shader = load("res://src/render/shaders/grass_wind_playground.gdshader") as Shader
	_material.set_shader_parameter(
		"pg_gust_noise", load("res://assets/render/wind_gust_noise.tres"))
	_clock_state = GrassWindClock.make_initial_state(_params.to_clock_cfg())
	_apply_cli_overrides()
	_rebuild_lawn()
	_build_ui()
	_apply_camera_preset("orbit45")
	if _camera:
		_camera.current = true
	if not out_path.is_empty():
		await _capture_png(out_path)


func _process(delta: float) -> void:
	if _rebuild_pending:
		_rebuild_pending = false
		_rebuild_lawn()
	_clock_state = GrassWindClock.advance(_clock_state, _params.to_clock_cfg(), delta, 1.0)
	_push_material_uniforms()
	_advance_glide(delta)
	if _show_ui or _allow_input:
		_apply_orbit_camera()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.74, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.52)
	env.ambient_light_energy = 1.1
	_world_env.environment = env


func _build_ui() -> void:
	if not _show_ui:
		return
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	layer.add_child(margin)
	_knob_panel = KnobPanel.new()
	_knob_panel.build_from_spec(
		GrassWindKnobSpec.all_knobs(), _params, GrassWindParams.presets())
	margin.add_child(_knob_panel)
	_knob_panel.knob_changed.connect(_on_knob_changed)
	_knob_panel.variant_changed.connect(_on_variant_changed)
	_knob_panel.preset_selected.connect(_on_preset_selected)
	_knob_panel.reset_requested.connect(_on_reset_production)
	_knob_panel.copy_requested.connect(_on_copy_settings)
	layer.add_child(_make_stage_panel())


func _make_stage_panel() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# Zero-width at the right edge would otherwise grow off-screen.
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_camera_hint = Label.new()
	col.add_child(_camera_hint)
	_refresh_camera_hint()
	col.add_child(_labeled_button("Eye-level", func(): _apply_camera_preset("eye")))
	col.add_child(_labeled_button("Top-down", func(): _apply_camera_preset("top")))
	col.add_child(_labeled_button("Orbit 45°", func(): _apply_camera_preset("orbit45")))
	col.add_child(_labeled_button("Pause", func(): _params.time_scale = 0.0))
	col.add_child(_labeled_button("Resume 1×", func(): _params.time_scale = 1.0))
	col.add_child(_labeled_button("Reset phase", func(): _reset_phase()))
	col.add_child(_labeled_button("Force gust now", func(): _force_gust_now()))
	col.add_child(_make_stage_toggle("Show 1 m grid", _show_grid, func(on: bool):
		_show_grid = on
		if _grid:
			_grid.visible = on))
	col.add_child(_make_stage_toggle("Show scale post (1.8 m)", _show_scale_post, func(on: bool):
		_show_scale_post = on
		if _scale_post:
			_scale_post.visible = on))
	return margin


func _make_stage_toggle(label: String, initial: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	PlaygroundCheckboxStyle.apply(c)
	c.text = label
	c.button_pressed = initial
	c.toggled.connect(cb)
	return c


func _labeled_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _on_knob_changed(name: String, value: Variant) -> void:
	_params.set(name, value)
	if name in ["lawn_size_m", "blade_density_per_m2"]:
		_rebuild_pending = true


func _on_variant_changed(v: int) -> void:
	_params.variant = v
	if _knob_panel:
		_knob_panel.set_variant(v)


func _on_preset_selected(name: String) -> void:
	if name == GrassWindParams.CUSTOM_PRESET:
		return
	_params.apply_preset(name)  # full recipe: resets knobs to production, then overrides
	if _knob_panel:
		_knob_panel.set_variant(_params.variant)
		_knob_panel.refresh_values()


func _on_reset_production() -> void:
	_params.reset_to_production()
	if _knob_panel:
		_knob_panel.set_variant(0)
		_knob_panel.refresh_values()


func _on_copy_settings() -> void:
	var block := _params.to_json_block()
	print(block)
	DisplayServer.clipboard_set(block)


func _reset_phase() -> void:
	_clock_state = GrassWindClock.make_initial_state(_params.to_clock_cfg())


func _force_gust_now() -> void:
	match _params.variant:
		1, 4:
			_clock_state["sim_time"] = 0.0
		_:
			_clock_state["gust_phase"] = PI * 0.5


func _rebuild_lawn() -> void:
	var size_m := clampf(_params.lawn_size_m, 4.0, 40.0)
	var density := clampf(_params.blade_density_per_m2, 20.0, 400.0)
	var step := sqrt(1.0 / density)
	var half := size_m * 0.5
	var transforms: Array[Transform3D] = []
	var x := -half
	while x < half:
		var z := -half
		while z < half:
			var jx := _rng.randf_range(-step * 0.35, step * 0.35)
			var jz := _rng.randf_range(-step * 0.35, step * 0.35)
			var yaw := _rng.randf() * TAU
			transforms.append(Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), Vector3(x + jx, 0.0, z + jz)))
			z += step
		x += step
	var mesh := VillageGrassMesh.blade_tuft_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	_grass_mm.multimesh = mm
	_grass_mm.material_override = _material
	_ground.position = Vector3.ZERO
	var plane := _ground.mesh as PlaneMesh
	if plane == null:
		plane = PlaneMesh.new()
		_ground.mesh = plane
	plane.size = Vector2(size_m, size_m)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.07, 0.22, 0.09)
	gm.roughness = 1.0
	_ground.set_surface_override_material(0, gm)
	_scale_post.position = Vector3(half - 0.5, 0.0, -half + 0.5)
	if _scale_post.mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 1.8, 0.08)
		_scale_post.mesh = box
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.55, 0.52, 0.48)
	post_mat.roughness = 0.9
	_scale_post.set_surface_override_material(0, post_mat)
	_scale_post.visible = _show_scale_post
	_grid.mesh = _make_ground_grid_mesh(size_m, 1.0)
	var grid_mat := StandardMaterial3D.new()
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.albedo_color = Color(0.35, 0.42, 0.38, 0.55)
	grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_grid.set_surface_override_material(0, grid_mat)
	_grid.visible = _show_grid


func _push_material_uniforms() -> void:
	var strength: float = float(_clock_state.get("effective_strength", _params.wind_strength))
	_material.set_shader_parameter("pg_wind_dir", _clock_state["direction_xz"])
	_material.set_shader_parameter("pg_wind_strength", strength)
	_material.set_shader_parameter("pg_wind_scroll", _clock_state["scroll_xz"])
	_material.set_shader_parameter("pg_wind_flutter_phase", _clock_state["flutter_phase"])
	_material.set_shader_parameter("pg_gust_tile_m", _params.gust_tile_m)
	_material.set_shader_parameter("pg_sim_time", _clock_state["sim_time"])
	_material.set_shader_parameter("pg_variant", _params.variant)
	_material.set_shader_parameter("pg_gust_edge_lo", _params.gust_edge_lo)
	_material.set_shader_parameter("pg_gust_edge_hi", _params.gust_edge_hi)
	_material.set_shader_parameter("pg_lean_base", _params.lean_base)
	_material.set_shader_parameter("pg_lean_gust_gain", _params.lean_gust_gain)
	_material.set_shader_parameter("pg_flutter_amp", _params.flutter_amp)
	_material.set_shader_parameter("pg_flutter_gust_base", _params.flutter_gust_base)
	_material.set_shader_parameter("pg_flutter_space_freq", _params.flutter_space_freq)
	_material.set_shader_parameter("pg_height_exp", _params.height_exp)
	_material.set_shader_parameter("pg_droop_on", _params.droop_on)
	_material.set_shader_parameter("pg_wave_length_m", _params.wave_length_m)
	_material.set_shader_parameter("pg_wave_speed_m_s", _params.wave_speed_m_s)
	_material.set_shader_parameter("pg_wave_sharpness", _params.wave_sharpness)
	_material.set_shader_parameter("pg_spring_freq_hz", _params.spring_freq_hz)
	_material.set_shader_parameter("pg_spring_damping", _params.spring_damping)
	_material.set_shader_parameter("pg_overshoot_gain", _params.overshoot_gain)
	_material.set_shader_parameter("pg_phase_spread", _params.phase_spread)
	_material.set_shader_parameter("pg_front_width_m", _params.front_width_m)
	_material.set_shader_parameter("pg_front_speed_m_s", _params.front_speed_m_s)
	_material.set_shader_parameter("pg_front_spacing_m", _params.front_spacing_m)
	_material.set_shader_parameter("pg_front_peak", _params.front_peak)
	_material.set_shader_parameter("pg_flutter_period_sec", _params.flutter_period_sec)


func _apply_camera_preset(name: String) -> void:
	_last_preset = name
	match name:
		"eye":
			_orbit_pitch = deg_to_rad(8.0)
			_orbit_radius = 4.5
			_orbit_yaw = deg_to_rad(25.0)
		"top":
			_orbit_pitch = deg_to_rad(82.0)
			_orbit_radius = 10.0
			_orbit_yaw = 0.0
		_:
			_orbit_pitch = deg_to_rad(35.0)
			_orbit_radius = 6.0
			_orbit_yaw = deg_to_rad(40.0)
	_apply_orbit_camera()


func _apply_orbit_camera() -> void:
	var pivot := _current_pivot()
	_orbit_pitch = DebugCamera.clamp_pitch(_orbit_pitch, _orbit_radius, pivot.y)
	_camera.global_transform = DebugCamera.solve(pivot, _orbit_yaw, _orbit_pitch, _orbit_radius)


# ── Camera controls (same scheme as the main game's DebugCamera) ─────────────
# Tab = mouse-look on/off (cursor captured while on), left click = glide the orbit
# pivot to the clicked ground point, wheel / trackpad scroll = zoom, WASD / arrows =
# rotate, R / Home = reset.

func _current_pivot() -> Vector3:
	if _gliding:
		return _glide_from.lerp(_glide_to, _glide_blend())
	return _pivot


func _glide_blend() -> float:
	if _glide_seconds <= 0.0:
		return 1.0
	var t := clampf(_glide_elapsed / _glide_seconds, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _advance_glide(delta: float) -> void:
	if not _gliding:
		return
	_glide_elapsed += delta
	if _glide_elapsed >= _glide_seconds:
		_gliding = false
		_pivot = _glide_to


func _begin_glide_to(world_point: Vector3) -> void:
	var from := _current_pivot()
	if from.distance_squared_to(world_point) < 0.01:
		_pivot = world_point
		_gliding = false
		return
	_glide_from = from
	_glide_to = world_point
	_glide_elapsed = 0.0
	_glide_seconds = clampf(
		from.distance_to(world_point) / _GLIDE_METRES_PER_SEC, _GLIDE_MIN_SEC, _GLIDE_MAX_SEC)
	_gliding = true


## The lawn has no collision shapes, so pick on the y = 0 ground plane.
func _pick_ground_point(screen: Vector2) -> Vector3:
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if dir.y > -1e-4:
		return Vector3(INF, INF, INF)
	var t := -from.y / dir.y
	if t < 0.0 or t > _PICK_RANGE:
		return Vector3(INF, INF, INF)
	return from + dir * t


func _zoom_by_notches(notches: float) -> void:
	_orbit_radius = clampf(
		_orbit_radius * pow(_ZOOM_PER_NOTCH, notches), _ZOOM_MIN_RADIUS, _ZOOM_MAX_RADIUS)


func _reset_camera() -> void:
	_pivot = Vector3.ZERO
	_gliding = false
	_apply_camera_preset(_last_preset)


func _set_mouse_orbit(on: bool) -> void:
	_mouse_orbit = on
	if _allow_input:
		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE)
	_refresh_camera_hint()


func _refresh_camera_hint() -> void:
	if _camera_hint:
		_camera_hint.text = (
			"Tab: mouse-look %s\nClick: move pivot · Wheel: zoom\nWASD/arrows: rotate · R: reset"
			% ("ON" if _mouse_orbit else "off"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _mouse_orbit:
		_set_mouse_orbit(false)


func _exit_tree() -> void:
	if _mouse_orbit:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Tab is handled in `_input` (not `_unhandled_input`) so a focused slider/button
## cannot swallow it for GUI focus navigation.
func _input(event: InputEvent) -> void:
	if not _allow_input:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_TAB:
			_set_mouse_orbit(not _mouse_orbit)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _allow_input:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by_notches(1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by_notches(-1.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT and not _mouse_orbit:
			var hit := _pick_ground_point(mb.position)
			if hit.is_finite():
				_begin_glide_to(hit)
	elif event is InputEventPanGesture:
		# macOS trackpad two-finger scroll arrives here, never as a wheel button.
		_zoom_by_notches(-(event as InputEventPanGesture).delta.y * _NOTCHES_PER_PAN_UNIT)
	elif event is InputEventMouseMotion and _mouse_orbit:
		var mm := event as InputEventMouseMotion
		_orbit_yaw -= mm.relative.x * _DRAG_RAD_PER_PIXEL
		_orbit_pitch = DebugCamera.clamp_pitch(
			_orbit_pitch - mm.relative.y * _DRAG_RAD_PER_PIXEL,
			_orbit_radius, _current_pivot().y)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var k := event as InputEventKey
		match k.keycode:
			KEY_LEFT, KEY_A:
				_orbit_yaw -= _KEY_RAD_PER_PRESS
			KEY_RIGHT, KEY_D:
				_orbit_yaw += _KEY_RAD_PER_PRESS
			KEY_UP, KEY_W:
				_orbit_pitch += _KEY_RAD_PER_PRESS
			KEY_DOWN, KEY_S:
				_orbit_pitch -= _KEY_RAD_PER_PRESS
			KEY_R, KEY_HOME:
				_reset_camera()


func _apply_cli_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="):
			_params.variant = int(arg.substr("--variant=".length()))
		elif arg.begins_with("--preset="):
			_params.apply_preset(arg.substr("--preset=".length()))
		elif arg.begins_with("--advance-sec="):
			_capture_advance_sec = float(arg.substr("--advance-sec=".length()))


static func _make_ground_grid_mesh(size_m: float, spacing_m: float) -> ArrayMesh:
	var half := size_m * 0.5
	var y := 0.015
	var verts: PackedVector3Array = []
	var min_i := int(floor(-half / spacing_m))
	var max_i := int(ceil(half / spacing_m))
	for i in range(min_i, max_i + 1):
		var x := float(i) * spacing_m
		if x < -half - 0.001 or x > half + 0.001:
			continue
		verts.append(Vector3(x, y, -half))
		verts.append(Vector3(x, y, half))
	for j in range(min_i, max_i + 1):
		var z := float(j) * spacing_m
		if z < -half - 0.001 or z > half + 0.001:
			continue
		verts.append(Vector3(-half, y, z))
		verts.append(Vector3(half, y, z))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _advance_clock_for_capture(sec: float) -> void:
	if sec <= 0.0:
		return
	var steps := maxi(1, int(ceil(sec / 0.033)))
	var dt := sec / float(steps)
	var gate := 1.0
	for _i in range(steps):
		_clock_state = GrassWindClock.advance(_clock_state, _params.to_clock_cfg(), dt, gate)


func _parse_out_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return ProjectSettings.globalize_path(arg.substr("--out=".length()))
	return ""


func _capture_png(out_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	_advance_clock_for_capture(_capture_advance_sec)
	for _i in range(45):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err == OK:
		print("[grass_wind_playground] saved ", out_path)
	else:
		printerr("[grass_wind_playground] save failed ", err)
	get_tree().quit(0)
