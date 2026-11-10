extends Node3D

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")
const WandererKnobSpec = preload("res://src/playground/wanderer_knob_spec.gd")
const WandererFigure = preload("res://src/presentation/wanderer/wanderer_figure.gd")
const WandererBrain = preload("res://src/presentation/wanderer/wanderer_brain.gd")
const WandererRouteGraph = preload("res://src/presentation/wanderer/wanderer_route_graph.gd")
const WandererContent = preload("res://src/presentation/wanderer/wanderer_content.gd")
const WandererImagePlacement = preload("res://src/presentation/wanderer/wanderer_image_placement.gd")
const WandererBubbleView = preload("res://src/presentation/wanderer/wanderer_bubble_view.gd")
const WandererRevealCamera = preload("res://src/presentation/wanderer/wanderer_reveal_camera.gd")
const KnobPanel = preload("res://src/playground/knob_panel.gd")
const PlaygroundKnobHost = preload("res://src/playground/playground_knob_host.gd")
const PlaygroundCheckboxStyle = preload("res://src/playground/playground_checkbox_style.gd")
const DebugCamera = preload("res://src/world/debug_camera.gd")

enum PlayMode {TREADMILL, CIRCUIT}

@export var script_driven: bool = false

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _camera: Camera3D = $Camera3D
@onready var _stage: Node3D = $Stage

var _params := WandererParams.production().duplicate_params()
var _knob_panel: KnobPanel
var _show_ui := true
var _allow_input := true
var _play_mode := PlayMode.TREADMILL
var _time_scale := 1.0
var _paused := false
var _short_inside := false
var _saved_mouse_mode := Input.MOUSE_MODE_VISIBLE

var _figure_root: Node3D
var _figure: Node3D
var _bubble: Label3D
var _bubble_panel: Sprite3D
var _image_mi: MeshInstance3D
var _image_mat: StandardMaterial3D
var _content: WandererContent
var _brain: WandererBrain
var _graph: WandererRouteGraph
var _rng := RandomNumberGenerator.new()

var _treadmill_phase := 0.0
var _treadmill_motion := 1.0
var _treadmill_yaw := 0.0
var _manual_bubble := ""
var _manual_bubble_alpha := 0.0
var _manual_image := false
var _manual_image_idx := 0
var _door_wall_azimuth_deg := 0.0
var _door_exterior := Vector2.ZERO
var _wall_root: Node3D
var _present_ring: MeshInstance3D

var _camera_mode := "side"
var _free_orbit := false
var _orbit_yaw := PI * 0.5
var _orbit_pitch := 0.12
var _orbit_radius := 9.0
var _pivot := Vector3.ZERO
var _mouse_orbit := false
var _capture_advance_sec := 0.0
var _capture_reveal := false
var _capture_mode := false

const _STAGE_M := 24.0
const _GRID_SPACING := 1.0
const _DRAG_RAD_PER_PIXEL := 0.3 * PI / 180.0
const _KEY_RAD_PER_PRESS := 3.0 * PI / 180.0
const _ZOOM_PER_NOTCH := 0.9
const _ZOOM_MIN_RADIUS := 3.0
const _ZOOM_MAX_RADIUS := 48.0
const _PICK_RANGE := 120.0
const _PLAYGROUND_HERO_XZ := Vector2(0.0, -18.0)


func playground_params() -> WandererParams:
	return _params


func playground_reset_production() -> void:
	_on_reset_production()


func playground_set_door_azimuth_deg(deg: float) -> void:
	_door_wall_azimuth_deg = deg
	_rebuild_door_wall()
	_setup_circuit_brain()


func playground_door_normal() -> Vector2:
	return _door_normal()


func _ready() -> void:
	_saved_mouse_mode = Input.get_mouse_mode()
	var out_path := _parse_capture_path()
	_capture_mode = not out_path.is_empty()
	_show_ui = out_path.is_empty() and not script_driven
	_allow_input = out_path.is_empty() and not script_driven
	_apply_cli_overrides()
	_setup_environment()
	_build_stage()
	_build_figure_presentation()
	_setup_circuit_brain()
	_build_ui()
	_apply_camera_preset(_parse_camera_arg())
	if _camera:
		_camera.current = true
	if not out_path.is_empty():
		await _run_capture_and_quit(out_path)


func _exit_tree() -> void:
	Input.set_mouse_mode(_saved_mouse_mode)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.74, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.52)
	env.ambient_light_energy = 1.15
	_world_env.environment = env


func _build_stage() -> void:
	for c in _stage.get_children():
		c.queue_free()
	var half := _STAGE_M * 0.5
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(_STAGE_M, _STAGE_M)
	ground.mesh = plane
	ground.position = Vector3.ZERO
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.36, 0.52, 0.28)
	ground.material_override = gmat
	_stage.add_child(ground)
	var grid := MeshInstance3D.new()
	grid.name = "Grid"
	grid.mesh = _make_ground_grid_mesh(_STAGE_M, _GRID_SPACING)
	var grid_mat := StandardMaterial3D.new()
	grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_mat.albedo_color = Color(0.28, 0.34, 0.30, 0.65)
	grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	grid.material_override = grid_mat
	_stage.add_child(grid)
	var post := MeshInstance3D.new()
	post.name = "ScalePost"
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.08, 2.0, 0.08)
	post.mesh = post_box
	post.position = Vector3(half - 1.0, 1.0, -half + 1.0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.9, 0.15, 0.15)
	post.material_override = pm
	if not _capture_mode:
		_stage.add_child(post)
		_rebuild_door_wall()
	var hero := MeshInstance3D.new()
	hero.name = "HeroMarker"
	var hm := CylinderMesh.new()
	hm.top_radius = 0.35
	hm.bottom_radius = 0.35
	hm.height = 0.12
	hero.mesh = hm
	hero.position = Vector3(_PLAYGROUND_HERO_XZ.x, 0.06, _PLAYGROUND_HERO_XZ.y)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.2, 0.75, 0.95)
	hero.material_override = hmat
	_stage.add_child(hero)
	_pivot = Vector3(0.0, 1.0, 0.0)


func _door_normal() -> Vector2:
	var az := deg_to_rad(_door_wall_azimuth_deg)
	return Vector2(sin(az), cos(az))


func _rebuild_door_wall() -> void:
	if _wall_root != null:
		_wall_root.queue_free()
		_wall_root = null
	if _present_ring != null:
		_present_ring.queue_free()
		_present_ring = null
	_wall_root = Node3D.new()
	_wall_root.name = "DoorWall"
	_stage.add_child(_wall_root)
	var n := _door_normal()
	var left := Vector2(n.y, -n.x)
	var basis := Basis(
		Vector3(left.x, 0.0, left.y),
		Vector3.UP,
		Vector3(-n.x, 0.0, -n.y))
	_wall_root.transform = Transform3D(basis, Vector3.ZERO)
	var slab := MeshInstance3D.new()
	slab.name = "WallSlab"
	var slab_box := BoxMesh.new()
	slab_box.size = Vector3(12.0, 3.5, 0.25)
	slab.mesh = slab_box
	slab.position = Vector3(0.0, 1.75, -0.125)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.82, 0.78, 0.72)
	slab.material_override = smat
	_wall_root.add_child(slab)
	var eave := MeshInstance3D.new()
	eave.name = "EaveLedge"
	var eave_box := BoxMesh.new()
	eave_box.size = Vector3(12.0, 0.5, 0.7)
	eave.mesh = eave_box
	eave.position = Vector3(0.0, 3.25, 0.35)
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.75, 0.72, 0.68, 0.55)
	emat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	eave.material_override = emat
	_wall_root.add_child(eave)
	var door := MeshInstance3D.new()
	door.name = "DoorMarker"
	var door_box := BoxMesh.new()
	door_box.size = Vector3(1.0, 2.2, 0.08)
	door.mesh = door_box
	door.position = Vector3(0.0, 1.1, 0.04)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.35, 0.22, 0.15)
	door.material_override = dmat
	_wall_root.add_child(door)
	var P := _door_exterior + n * _params.present_standoff()
	_present_ring = MeshInstance3D.new()
	_present_ring.name = "PresentMarker"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.22
	ring.outer_radius = 0.32
	ring.ring_segments = 24
	_present_ring.mesh = ring
	_present_ring.rotation.x = PI * 0.5
	_present_ring.position = Vector3(P.x, 0.05, P.y)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.95, 0.85, 0.2)
	_present_ring.material_override = rmat
	_stage.add_child(_present_ring)


func _playground_placement(aspect: float) -> Dictionary:
	return WandererImagePlacement.compute(_door_exterior, _door_normal(), _params, aspect)


func _build_figure_presentation() -> void:
	_content = WandererContent.load_from_dir(_params)
	_rng.seed = 12001
	_figure_root = Node3D.new()
	_figure_root.name = "FigurePivot"
	_stage.add_child(_figure_root)
	_figure = WandererFigure.build(_params)
	_figure_root.add_child(_figure)
	_bubble = Label3D.new()
	_bubble.name = "Bubble"
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.font_size = _params.bubble_font_size
	_bubble.pixel_size = _params.bubble_pixel_size
	_bubble.outline_size = 8
	_bubble.modulate = Color(1, 1, 1, 0)
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_figure_root.add_child(_bubble)
	var bubble_parts := WandererBubbleView.attach(_figure_root, _bubble)
	_bubble_panel = bubble_parts["panel"] as Sprite3D
	_bubble_panel.visible = false
	_image_mi = MeshInstance3D.new()
	_image_mi.name = "RevealImage"
	_image_mi.mesh = QuadMesh.new()
	_image_mat = StandardMaterial3D.new()
	_image_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_image_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_image_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_image_mat.albedo_color = Color(1, 1, 1, 0)
	_image_mi.material_override = _image_mat
	_image_mi.visible = false
	_stage.add_child(_image_mi)


func _setup_circuit_brain() -> void:
	_params.hero_xz = _PLAYGROUND_HERO_XZ
	var n := _door_normal()
	var houses: Array[Dictionary] = [
		{"name": "Yard", "door": Vector2(-6.0, -6.0), "normal": Vector2(0.707, 0.707)},
		{"name": "Stage", "door": _door_exterior, "normal": n},
	]
	var paths: Array = [[
		Vector2(-6.0, -6.0), Vector2(-6.0, 6.0), Vector2(6.0, 6.0),
		Vector2(6.0, -6.0), Vector2(0.0, -6.0), Vector2(_door_exterior.x, _door_exterior.y),
	]]
	_graph = WandererRouteGraph.from_raw(houses, paths, _params)
	_brain = WandererBrain.new()
	_brain.setup(_params, _graph, _content, _rng)
	_brain.start()


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
	var host := PlaygroundKnobHost.wanderer()
	_knob_panel = KnobPanel.new()
	_knob_panel.build_from_spec(
		WandererKnobSpec.all_knobs(), _params, WandererParams.presets(), host)
	margin.add_child(_knob_panel)
	_knob_panel.knob_changed.connect(_on_knob_changed)
	_knob_panel.variant_changed.connect(_on_variant_changed)
	_knob_panel.preset_selected.connect(_on_preset_selected)
	_knob_panel.reset_requested.connect(_on_reset_production)
	_knob_panel.copy_requested.connect(_on_copy_settings)
	layer.add_child(_make_transport_panel())
	layer.add_child(_make_camera_panel())


func _make_transport_panel() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	col.add_child(_labeled_button("Mode: Treadmill", func(): _set_mode(PlayMode.TREADMILL)))
	col.add_child(_labeled_button("Mode: Circuit", func(): _set_mode(PlayMode.CIRCUIT)))
	col.add_child(_labeled_button("Pause", func(): _paused = true))
	col.add_child(_labeled_button("Resume 1×", func():
		_paused = false
		_time_scale = 1.0))
	col.add_child(_labeled_button("Slow-mo 0.25×", func():
		_paused = false
		_time_scale = 0.25))
	col.add_child(_make_stage_toggle("Short inside (1 s)", _short_inside, func(on: bool):
		_short_inside = on
		if on:
			_params.inside_s = 1.0
		elif _knob_panel:
			_knob_panel.refresh_values()))
	col.add_child(_labeled_button("Show bubble", _preview_bubble))
	col.add_child(_labeled_button("Show image reveal", _preview_image))
	col.add_child(_labeled_button("Step out (brain)", _step_out_brain))
	col.add_child(_door_azimuth_row())
	return margin


func _make_camera_panel() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	col.add_child(_labeled_button("Cam: Side", func(): _apply_camera_preset("side")))
	col.add_child(_labeled_button("Cam: ¾", func(): _apply_camera_preset("three_quarter")))
	col.add_child(_labeled_button("Cam: Follow", func(): _apply_camera_preset("follow")))
	col.add_child(_labeled_button("Cam: Reveal front", func(): _apply_camera_preset("reveal_front")))
	col.add_child(_labeled_button("Cam: Reveal oblique", func(): _apply_camera_preset("reveal_oblique")))
	col.add_child(_labeled_button("Cam: Free orbit", func(): _apply_camera_preset("orbit")))
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


func _door_azimuth_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Door wall azimuth"
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 360.0
	sl.step = 1.0
	sl.value = _door_wall_azimuth_deg
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v: float):
		playground_set_door_azimuth_deg(v))
	row.add_child(sl)
	return row


func _step_out_brain() -> void:
	_play_mode = PlayMode.CIRCUIT
	_manual_image = false
	_manual_bubble = ""
	_setup_circuit_brain()
	_brain.debug_begin_exit(1)


func _set_mode(mode: PlayMode) -> void:
	_play_mode = mode
	_manual_bubble = ""
	_manual_image = false
	if mode == PlayMode.CIRCUIT:
		_setup_circuit_brain()


func _on_knob_changed(name: String, value: Variant) -> void:
	_params.set(name, value)
	if name == "present_standoff_m":
		_rebuild_door_wall()
	if name.begins_with("bubble_") and _bubble:
		if name == "bubble_font_size":
			_bubble.font_size = int(value)
		elif name == "bubble_pixel_size":
			_bubble.pixel_size = float(value)


func _on_variant_changed(v: int) -> void:
	_params.variant = v
	if _knob_panel:
		_knob_panel.set_variant(v)


func _on_preset_selected(name: String) -> void:
	if name == WandererParams.CUSTOM_PRESET:
		return
	_params.apply_preset(name)
	if _knob_panel:
		_knob_panel.set_variant(_params.variant)
		_knob_panel.refresh_values()
	_setup_circuit_brain()


func _on_reset_production() -> void:
	_params.reset_to_production()
	_params.hero_xz = _PLAYGROUND_HERO_XZ
	if _knob_panel:
		_knob_panel.set_variant(0)
		_knob_panel.refresh_values()
	_setup_circuit_brain()


func _on_copy_settings() -> void:
	DisplayServer.clipboard_set(_params.to_json_block())


func _preview_bubble() -> void:
	if _content.quote_count() == 0:
		_manual_bubble = "A pleasant stroll."
	else:
		_manual_bubble = _content.quote(_rng.randi_range(0, _content.quote_count() - 1))
	_manual_bubble_alpha = 1.0


func _preview_image() -> void:
	if _content.image_count() == 0:
		return
	_manual_image = true
	_manual_image_idx = _rng.randi_range(0, _content.image_count() - 1)
	_play_mode = PlayMode.TREADMILL
	_sync_manual_figure_at_present()


func _process(delta: float) -> void:
	var dt := 0.0 if _paused else delta * _time_scale
	if _play_mode == PlayMode.TREADMILL:
		_tick_treadmill(dt)
	else:
		if dt > 0.0:
			_brain.tick(dt)
	_sync_figure()
	_sync_presentation()
	if _camera_mode == "follow":
		_pivot = _figure_root.position + Vector3(0.0, 1.0, 0.0)
		_apply_orbit_camera()
	elif _free_orbit and (_show_ui or _allow_input):
		_apply_orbit_camera()


func _tick_treadmill(dt: float) -> void:
	var v := maxf(_params.walk_speed_mps, 0.0)
	_treadmill_motion = 1.0 if v > 1e-4 else 0.0
	_treadmill_phase += TAU * v * dt / maxf(_params.stride_length_m, 0.2)
	_figure_root.position = Vector3.ZERO
	_figure_root.rotation.y = _treadmill_yaw


func _sync_figure() -> void:
	if _play_mode == PlayMode.CIRCUIT and not _brain.figure_visible:
		_figure_root.visible = false
		return
	_figure_root.visible = true
	var phase := _brain.walk_phase if _play_mode == PlayMode.CIRCUIT else _treadmill_phase
	var motion := _brain.motion if _play_mode == PlayMode.CIRCUIT else _treadmill_motion
	if _play_mode == PlayMode.CIRCUIT:
		_figure_root.position = Vector3(_brain.pos.x, 0.0, _brain.pos.y)
		_figure_root.rotation.y = _brain.yaw
	var pose := WandererFigure.pose(_params.walk_variant, _params, phase, motion)
	WandererFigure.apply_pose(_figure, pose, _params)


func _sync_presentation() -> void:
	var head_y := _params.figure_height_m
	_bubble.position = Vector3(0.0, head_y + _params.bubble_gap_m, 0.0)
	var bubble_text := ""
	var bubble_alpha := 0.0
	if _play_mode == PlayMode.CIRCUIT and not _brain.bubble_text.is_empty():
		bubble_text = _brain.bubble_text
		bubble_alpha = _brain.bubble_alpha
	elif not _manual_bubble.is_empty():
		bubble_text = _manual_bubble
		bubble_alpha = _manual_bubble_alpha
	if bubble_text.is_empty():
		_bubble.text = ""
		_bubble.modulate.a = 0.0
		_bubble_panel.visible = false
	else:
		_bubble.text = bubble_text
		WandererBubbleView.sync(_bubble_panel, _bubble, bubble_text, bubble_alpha)
	var show_image := false
	if _play_mode == PlayMode.CIRCUIT \
			and _brain.state == WandererBrain.State.SHOWING and _brain.image_index >= 0:
		show_image = true
	elif _manual_image:
		show_image = true
	if show_image and _content.image_count() > 0:
		var idx := _brain.image_index if _play_mode == PlayMode.CIRCUIT else _manual_image_idx
		idx = clampi(idx, 0, _content.image_count() - 1)
		var pl: Dictionary
		if _play_mode == PlayMode.CIRCUIT:
			pl = _brain.image_placement
			_figure_root.position = Vector3(_brain.pos.x, 0.0, _brain.pos.y)
			_figure_root.rotation.y = _brain.yaw
		else:
			pl = _playground_placement(_content.aspect(idx))
			_sync_manual_figure_at_present()
		var sz: Vector2 = pl.get("size", Vector2(4, 7))
		_image_mi.visible = true
		(_image_mi.mesh as QuadMesh).size = sz
		_image_mi.position = pl.get("centre", Vector3.ZERO)
		_image_mi.rotation.y = float(pl.get("yaw", 0.0))
		_image_mat.albedo_texture = _content.textures[idx]
		var alpha := _brain.image_alpha if _play_mode == PlayMode.CIRCUIT else 1.0
		_image_mat.albedo_color.a = clampf(alpha, 0.0, 1.0)
	else:
		_image_mi.visible = false
		_image_mat.albedo_color.a = 0.0


func _sync_manual_figure_at_present() -> void:
	var n := _door_normal()
	var P := _door_exterior + n * _params.present_standoff()
	_figure_root.position = Vector3(P.x, 0.0, P.y)
	_figure_root.rotation.y = atan2(n.x, n.y)


func _set_camera_eye_look(eye: Vector3, look: Vector3) -> void:
	_free_orbit = false
	_camera.global_position = eye
	_camera.look_at(look, Vector3.UP)


func _apply_camera_preset(name: String) -> void:
	_camera_mode = name
	_free_orbit = name == "orbit"
	if name == "reveal_front" or name == "reveal_oblique":
		var asp := 16.0 / 9.0
		if _content.image_count() > 0:
			var idx := _manual_image_idx if _manual_image else maxi(0, _brain.image_index)
			asp = _content.aspect(idx)
		var pl := _playground_placement(asp)
		var fov := deg_to_rad(60.0)
		var shot: Dictionary
		if name == "reveal_front":
			shot = WandererRevealCamera.compute_reveal_front(pl, [], fov, asp, _door_exterior)
		else:
			shot = WandererRevealCamera.compute_reveal_oblique(pl, [], fov, asp, _door_exterior)
		_set_camera_eye_look(shot["eye"], shot["look"])
		return
	match name:
		"front":
			_orbit_yaw = 0.0
			_orbit_pitch = 0.08
			_orbit_radius = 4.0
			_pivot = _figure_root.position + Vector3(0.0, 1.6, 0.0)
		"side":
			_orbit_yaw = PI * 0.5
			_orbit_pitch = 0.08
			_orbit_radius = 4.2
			_pivot = _figure_root.position + Vector3(0.0, 1.6, 0.0)
		"three_quarter":
			_orbit_yaw = PI * 0.75
			_orbit_pitch = 0.10
			_orbit_radius = 4.2
			_pivot = _figure_root.position + Vector3(0.0, 1.6, 0.0)
		"follow":
			_orbit_yaw = PI * 0.35
			_orbit_pitch = 0.18
			_orbit_radius = 8.5
		_:
			_orbit_yaw = 0.35
			_orbit_pitch = 0.25
			_orbit_radius = 9.0
	if not _free_orbit:
		_apply_orbit_camera()


func _apply_orbit_camera() -> void:
	_orbit_pitch = DebugCamera.clamp_pitch(_orbit_pitch, _orbit_radius, _pivot.y)
	_camera.global_transform = DebugCamera.solve(_pivot, _orbit_yaw, _orbit_pitch, _orbit_radius)


func _apply_cli_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_play_mode = PlayMode.CIRCUIT if arg.substr(7) == "circuit" else PlayMode.TREADMILL
		elif arg.begins_with("--camera="):
			pass  # applied after build
		elif arg.begins_with("--advance-sec="):
			_capture_advance_sec = float(arg.substr(14))
		elif arg == "--capture-reveal":
			_capture_reveal = true
		elif arg.begins_with("--short-inside"):
			_short_inside = true
			_params.inside_s = 1.0
		elif arg.begins_with("--door-azimuth="):
			_door_wall_azimuth_deg = float(arg.substr(15))


func _parse_camera_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="):
			return arg.substr(9)
	return "side"


func _parse_capture_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return ProjectSettings.globalize_path(arg.substr(6))
		if arg.begins_with("--screenshot="):
			return ProjectSettings.globalize_path(arg.substr(13))
	return ""


static func _make_ground_grid_mesh(size_m: float, spacing_m: float) -> ArrayMesh:
	var half := size_m * 0.5
	var y := 0.015
	var verts: PackedVector3Array = []
	var min_i := int(floor(-half / spacing_m))
	var max_i := int(ceil(half / spacing_m))
	for i in range(min_i, max_i + 1):
		var x := float(i) * spacing_m
		verts.append(Vector3(x, y, -half))
		verts.append(Vector3(x, y, half))
	for j in range(min_i, max_i + 1):
		var z := float(j) * spacing_m
		verts.append(Vector3(-half, y, z))
		verts.append(Vector3(half, y, z))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _advance_simulation(sec: float) -> void:
	if sec <= 0.0:
		return
	if _capture_reveal:
		_play_mode = PlayMode.CIRCUIT
		_params.inside_s = 1.0
		_setup_circuit_brain()
	var step := 1.0 / 30.0
	var left := sec
	while left > 1e-6:
		var dt := minf(left, step)
		if _play_mode == PlayMode.CIRCUIT:
			_brain.tick(dt)
		else:
			_tick_treadmill(dt)
		_sync_figure()
		_sync_presentation()
		left -= dt
		await get_tree().process_frame


func _run_capture_and_quit(out_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	await get_tree().process_frame
	if _capture_advance_sec > 0.0 or _capture_reveal:
		await _advance_simulation(_capture_advance_sec)
	if _capture_reveal and _brain.state != WandererBrain.State.SHOWING:
		_play_mode = PlayMode.TREADMILL
		_preview_bubble()
		_preview_image()
		_apply_camera_preset("reveal_front")
		_sync_figure()
		_sync_presentation()
	for _i in range(30):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err == OK:
		print("[wanderer_playground] saved ", out_path)
	else:
		printerr("[wanderer_playground] save failed ", err)
	get_tree().quit(err if err != OK else 0)
