extends Node3D

const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestKnobSpec = preload("res://src/playground/forest_knob_spec.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")
const KnobPanel = preload("res://src/playground/knob_panel.gd")
const PlaygroundKnobHost = preload("res://src/playground/playground_knob_host.gd")
const PlaygroundCheckboxStyle = preload("res://src/playground/playground_checkbox_style.gd")
const DebugCamera = preload("res://src/world/debug_camera.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const WorldFogParams = preload("res://src/world/world_fog_params.gd")
const WorldFogVolume = preload("res://src/world/world_fog_volume.gd")
const SkySun = preload("res://src/world/sky_sun.gd")

const _PINE_GLTF := "res://assets/backdrop/pieces/Pine_2.gltf"

@export var script_driven: bool = false
@export var capture_seed: int = -1
@export var capture_variant: int = -1
@export var capture_preset: String = ""
@export var force_show_ui: bool = false

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _camera: Camera3D = $Camera3D
@onready var _stage: Node3D = $Stage

var _params := ForestParams.production()
var _layout: VillageLayout
var _knob_panel: KnobPanel
var _show_ui := true
var _allow_input := true
var _trees_mm: MultiMeshInstance3D
var _pond_snapshot: Variant
var _rebuild_pending := false
var _orbit_yaw := 0.0
var _orbit_pitch := 0.031415927
var _orbit_radius := 8.01
var _pivot := Vector3.ZERO
var _mouse_orbit := false
var _last_preset := "camsun"
var _free_orbit := false
var _fog_model: HeroFog.FogModel = HeroFog.FogModel.WORLD_AROUND_HERO
var _world_fog_params: WorldFogParams = WorldFogParams.production()
var _world_fog_volume: FogVolume
var _fog_begin_m := -1.0
var _fog_end_m := -1.0
var _fog_marker: MeshInstance3D
var _fog_model_option: OptionButton

const _DRAG_RAD_PER_PIXEL := 0.3 * PI / 180.0
const _KEY_RAD_PER_PRESS := 3.0 * PI / 180.0
const _ZOOM_PER_NOTCH := 0.9
const _ZOOM_MIN_RADIUS := 4.0
const _ZOOM_MAX_RADIUS := 140.0
const _PICK_RANGE := 200.0


func _ready() -> void:
	_pond_snapshot = VillagePondShape.active()
	var out_path := _parse_out_arg()
	var capture_ui := _has_user_arg("--capture-ui")
	_show_ui = force_show_ui or capture_ui or (out_path.is_empty() and not script_driven)
	_allow_input = out_path.is_empty() and not script_driven
	_setup_environment()
	_apply_cli_overrides()
	if capture_seed >= 0:
		_params.layout_seed = capture_seed
	if capture_variant >= 0:
		_params.variant = capture_variant
	if not capture_preset.is_empty():
		_params.apply_preset(capture_preset)
	_rebuild_layout_and_stage()
	_build_ui()
	_apply_camera_preset(_parse_camera_arg())
	if _camera:
		_camera.current = true
	if not out_path.is_empty():
		await get_tree().process_frame
		await get_tree().process_frame
		await _capture_png(out_path)


func _exit_tree() -> void:
	if _pond_snapshot != null:
		VillagePondShape.set_active(_pond_snapshot)
	if _mouse_orbit:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	if _rebuild_pending:
		_rebuild_pending = false
		_rebuild_trees()
	if _free_orbit and (_show_ui or _allow_input):
		_apply_orbit_camera()
	_apply_playground_fog()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.74, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.52)
	env.ambient_light_energy = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 14.0
	env.fog_depth_end = 95.0
	env.fog_light_color = Color(0.58, 0.74, 0.90)
	_world_env.environment = env


func _apply_layout_fog() -> void:
	_apply_playground_fog()


func _fog_begin_end() -> Vector2:
	var b := _layout.fog_begin if _layout != null else 20.0
	var e := _layout.fog_end if _layout != null else 95.0
	if _fog_begin_m >= 0.0:
		b = _fog_begin_m
	if _fog_end_m >= 0.0:
		e = _fog_end_m
	return Vector2(b, e)


func _apply_playground_fog() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var fe := _fog_begin_end()
	var env := _world_env.environment
	var anchor := ForestPlaygroundCamera.hero_fog_anchor_world()
	match _fog_model:
		HeroFog.FogModel.WORLD_AROUND_HERO:
			env.fog_enabled = false
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.0
			env.volumetric_fog_length = 192.0
			env.volumetric_fog_sky_affect = _world_fog_params.sky_affect_cap
			env.volumetric_fog_albedo = env.fog_light_color
			var pale := SkySun.pale_horizon_haze_color(0.32, 1.0)
			if _world_fog_volume == null:
				_world_fog_volume = WorldFogVolume.create_volume(
					anchor, _world_fog_params, pale)
				add_child(_world_fog_volume)
			else:
				WorldFogVolume.apply_params(
					_world_fog_volume, anchor, _world_fog_params, pale)
		HeroFog.FogModel.CAMERA_DEPTH:
			if _world_fog_volume != null:
				_world_fog_volume.queue_free()
				_world_fog_volume = null
			env.volumetric_fog_enabled = false
			env.fog_enabled = true
			env.fog_mode = Environment.FOG_MODE_DEPTH
			env.fog_depth_begin = fe.x
			env.fog_depth_end = fe.y
		_:
			if _world_fog_volume != null:
				_world_fog_volume.queue_free()
				_world_fog_volume = null
			env.volumetric_fog_enabled = false
			env.fog_enabled = true
			env.fog_mode = Environment.FOG_MODE_DEPTH
			if _camera == null:
				env.fog_depth_begin = fe.x
				env.fog_depth_end = fe.y
				return
			HeroFog.apply_depth_fog_to_environment(
				env, _camera.global_transform, anchor, fe.x, fe.y, HeroFog.CentreMode.HERO)


func _apply_cli_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_params.layout_seed = int(arg.substr(7))
		elif arg.begins_with("--variant="):
			_params.variant = int(arg.substr(10))
		elif arg.begins_with("--preset="):
			_params.apply_preset(arg.substr(9))
		elif arg.begins_with("--fog-model="):
			var v := arg.substr(12).to_lower()
			if v == "camera":
				_fog_model = HeroFog.FogModel.CAMERA_DEPTH
			elif v == "hero-shift":
				_fog_model = HeroFog.FogModel.HERO_SHIFTED_DEPTH
			else:
				_fog_model = HeroFog.FogModel.WORLD_AROUND_HERO
		elif arg.begins_with("--fog-begin="):
			_fog_begin_m = float(arg.substr(12))
		elif arg.begins_with("--fog-end="):
			_fog_end_m = float(arg.substr(10))


func _rebuild_layout_and_stage() -> void:
	_layout = VillageLayout.generate(_params.layout_seed)
	if _layout.fallback:
		push_error("Forest playground: layout fallback for seed %d" % _params.layout_seed)
	VillagePondShape.set_active(VillagePondShape.at(_layout.pond_center))
	_stage.position = ForestPlaygroundCamera.backdrop_origin()
	_apply_layout_fog()
	_clear_stage_children()
	_build_far_ground()
	_build_ground()
	_build_markers()
	_build_fog_anchor_marker()
	_build_scale_post()
	_rebuild_trees()
	var hero := VillageLayout.HERO_DOOR_STOOP
	_pivot = Vector3(hero.x, 1.75, hero.y) + ForestPlaygroundCamera.backdrop_origin()


func _clear_stage_children() -> void:
	for c in _stage.get_children():
		c.queue_free()
	_trees_mm = null


func _build_far_ground() -> void:
	if get_node_or_null("FarGround") != null:
		get_node("FarGround").queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "FarGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(512.0, 512.0)
	mi.mesh = plane
	mi.position = Vector3(0.0, -0.02, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.48, 0.30)
	mi.material_override = mat
	add_child(mi)
	move_child(mi, 0)


func _build_scale_post() -> void:
	var hero := VillageLayout.HERO_DOOR_STOOP
	var post := MeshInstance3D.new()
	post.name = "ScalePost"
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 1.8, 0.08)
	post.mesh = box
	post.position = Vector3(hero.x + 3.5, 0.9, hero.y - 3.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.15, 0.15)
	post.material_override = mat
	_stage.add_child(post)


func _build_ground() -> void:
	var g := _layout.hamlet_centre_xz
	var r := _layout.lawn_radius
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = 0.08
	mesh.radial_segments = 96
	var mi := MeshInstance3D.new()
	mi.name = "LawnDisc"
	mi.mesh = mesh
	mi.position = Vector3(g.x, -0.04, g.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.52, 0.28)
	mi.material_override = mat
	_stage.add_child(mi)
	var gmi := MeshInstance3D.new()
	gmi.name = "GMarker"
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	gmi.mesh = sphere
	gmi.position = Vector3(g.x, 0.35, g.y)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.9, 0.85, 0.2)
	gmi.material_override = gmat
	_stage.add_child(gmi)


func _build_fog_anchor_marker() -> void:
	if _fog_marker != null:
		_fog_marker.queue_free()
		_fog_marker = null
	var h := VillageLayout.HERO_DOOR_STOOP
	_fog_marker = MeshInstance3D.new()
	_fog_marker.name = "FogAnchorMarker"
	var sph := SphereMesh.new()
	sph.radius = 0.45
	sph.height = 0.9
	_fog_marker.mesh = sph
	_fog_marker.position = Vector3(h.x, 1.2, h.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.35, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fog_marker.material_override = mat
	_stage.add_child(_fog_marker)


func _build_markers() -> void:
	var hero := VillageLayout.HERO_DOOR_STOOP
	var hero_box := MeshInstance3D.new()
	hero_box.name = "HeroStandIn"
	var box := BoxMesh.new()
	box.size = Vector3(5.0, 4.0, 5.0)
	hero_box.mesh = box
	hero_box.position = Vector3(hero.x, 2.0, hero.y - 1.5)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.75, 0.72, 0.68)
	hero_box.material_override = hmat
	_stage.add_child(hero_box)
	var ci := 0
	for spec: Dictionary in _layout.cottages:
		if ci >= 6:
			break
		var rect := VillageBackdrop.cottage_exterior_rect(spec)
		var c := Vector2(rect.get_center().x, rect.get_center().y)
		var sz := rect.size
		var cottage := MeshInstance3D.new()
		cottage.name = "Cottage_%d" % ci
		var cm := BoxMesh.new()
		cm.size = Vector3(sz.x, 3.5, sz.y)
		cottage.mesh = cm
		cottage.position = Vector3(c.x, 1.75, c.y)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.82, 0.78, 0.72)
		cottage.material_override = cmat
		_stage.add_child(cottage)
		ci += 1


func _rebuild_trees() -> void:
	if _trees_mm != null:
		_trees_mm.queue_free()
		_trees_mm = null
	var mesh := _extract_first_mesh(_PINE_GLTF)
	if mesh == null:
		return
	var xf: Array = ForestPlacement.forest_tree_positions(_layout, _params)
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = xf.size()
	var buf := PackedFloat32Array()
	buf.resize(xf.size() * 12)
	for i in range(xf.size()):
		var t: Transform3D = xf[i]
		var b := i * 12
		buf[b + 0] = t.basis.x.x; buf[b + 1] = t.basis.y.x; buf[b + 2] = t.basis.z.x
		buf[b + 3] = t.origin.x
		buf[b + 4] = t.basis.x.y; buf[b + 5] = t.basis.y.y; buf[b + 6] = t.basis.z.y
		buf[b + 7] = t.origin.y
		buf[b + 8] = t.basis.x.z; buf[b + 9] = t.basis.y.z; buf[b + 10] = t.basis.z.z
		buf[b + 11] = t.origin.z
	mm.buffer = buf
	_trees_mm = MultiMeshInstance3D.new()
	_trees_mm.name = "ForestMultiMesh"
	_trees_mm.multimesh = mm
	_trees_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_stage.add_child(_trees_mm)


func _extract_first_mesh(path: String) -> Mesh:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var meshes: Array = []
	_collect_mesh_nodes(inst, meshes)
	var result: Mesh = null
	if not meshes.is_empty():
		result = (meshes[0] as MeshInstance3D).mesh
	inst.queue_free()
	return result


func _collect_mesh_nodes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_nodes(child, out)


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
	var host := PlaygroundKnobHost.forest()
	_knob_panel = KnobPanel.new()
	_knob_panel.build_from_spec(
		ForestKnobSpec.all_knobs(), _params, ForestParams.presets(), host)
	margin.add_child(_knob_panel)
	_knob_panel.knob_changed.connect(_on_knob_changed)
	_knob_panel.variant_changed.connect(_on_variant_changed)
	_knob_panel.preset_selected.connect(_on_preset_selected)
	_knob_panel.reset_requested.connect(_on_reset_production)
	_knob_panel.copy_requested.connect(_on_copy_settings)
	layer.add_child(_make_camera_panel())
	layer.add_child(_make_fog_panel())


func _make_fog_panel() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Fog"
	col.add_child(title)
	_fog_model_option = OptionButton.new()
	_fog_model_option.add_item("World fog around hero (new)", HeroFog.FogModel.WORLD_AROUND_HERO)
	_fog_model_option.add_item("Camera depth fog (old production)", HeroFog.FogModel.CAMERA_DEPTH)
	_fog_model_option.add_item("Hero-shifted depth fog (previous)", HeroFog.FogModel.HERO_SHIFTED_DEPTH)
	_fog_model_option.select(int(_fog_model))
	_fog_model_option.item_selected.connect(func(idx: int) -> void:
		_fog_model = idx as HeroFog.FogModel
		_apply_playground_fog())
	col.add_child(_fog_model_option)
	var row_cr := _fog_spin_row("Clear radius (m)", _world_fog_params.clear_radius_m, 0.0, 60.0, 1.0,
		func(v: float) -> void:
			_world_fog_params.clear_radius_m = v
			_apply_playground_fog())
	col.add_child(row_cr)
	var row_tr := _fog_spin_row("Thick radius (m)", _world_fog_params.thick_radius_m, 40.0, 120.0, 1.0,
		func(v: float) -> void:
			_world_fog_params.thick_radius_m = v
			_apply_playground_fog())
	col.add_child(row_tr)
	var row_or := _fog_spin_row("Outer radius (m)", _world_fog_params.outer_radius_m, 120.0, 400.0, 5.0,
		func(v: float) -> void:
			_world_fog_params.outer_radius_m = v
			_apply_playground_fog())
	col.add_child(row_or)
	var row_md := _fog_spin_row("Max density", _world_fog_params.max_density, 0.01, 0.6, 0.01,
		func(v: float) -> void:
			_world_fog_params.max_density = v
			_apply_playground_fog())
	col.add_child(row_md)
	var row_sky := _fog_spin_row("Sky haze cap", _world_fog_params.sky_affect_cap, 0.0, 1.0, 0.05,
		func(v: float) -> void:
			_world_fog_params.sky_affect_cap = v
			_apply_playground_fog())
	col.add_child(row_sky)
	var row_b := HBoxContainer.new()
	var lb := Label.new()
	lb.text = "Begin (m)"
	row_b.add_child(lb)
	var sb := SpinBox.new()
	sb.min_value = 0.0
	sb.max_value = 80.0
	sb.step = 0.5
	sb.value = _fog_begin_end().x
	sb.value_changed.connect(func(v: float) -> void:
		_fog_begin_m = v
		_apply_playground_fog())
	row_b.add_child(sb)
	col.add_child(row_b)
	var row_e := HBoxContainer.new()
	var le := Label.new()
	le.text = "End (m)"
	row_e.add_child(le)
	var se := SpinBox.new()
	se.min_value = 40.0
	se.max_value = 160.0
	se.step = 1.0
	se.value = _fog_begin_end().y
	se.value_changed.connect(func(v: float) -> void:
		_fog_end_m = v
		_apply_playground_fog())
	row_e.add_child(se)
	col.add_child(row_e)
	return margin


func _fog_spin_row(
		label: String, value: float, min_v: float, max_v: float, step: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lb := Label.new()
	lb.text = label
	row.add_child(lb)
	var sb := SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step
	sb.value = value
	sb.value_changed.connect(on_change)
	row.add_child(sb)
	return row


func _make_camera_panel() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(_labeled_button("CamSun", func(): _apply_camera_preset("camsun")))
	col.add_child(_labeled_button("Top", func(): _apply_camera_preset("top")))
	col.add_child(_labeled_button("Wide (~90 m)", func(): _apply_camera_preset("wide")))
	col.add_child(_labeled_button("Oblique", func(): _apply_camera_preset("oblique")))
	col.add_child(_labeled_button("Free orbit", func(): _apply_camera_preset("orbit")))
	return margin


func _labeled_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _on_knob_changed(name: String, value: Variant) -> void:
	if name == "layout_seed":
		_params.layout_seed = int(value)
		_rebuild_layout_and_stage()
		if _knob_panel:
			_knob_panel.refresh_values()
		return
	_params.set(name, value)
	_rebuild_pending = true


func _on_variant_changed(v: int) -> void:
	_params.variant = v
	if _knob_panel:
		_knob_panel.set_variant(v)
	_rebuild_pending = true


func _on_preset_selected(name: String) -> void:
	if name == ForestParams.CUSTOM_PRESET:
		return
	_params.apply_preset(name)
	if _knob_panel:
		_knob_panel.set_variant(_params.variant)
		_knob_panel.refresh_values()
	_rebuild_layout_and_stage()


func _on_reset_production() -> void:
	var seed := _params.layout_seed
	_params.reset_to_production()
	_params.layout_seed = seed
	if _knob_panel:
		_knob_panel.set_variant(0)
		_knob_panel.refresh_values()
	_rebuild_layout_and_stage()


func _on_copy_settings() -> void:
	DisplayServer.clipboard_set(_params.to_json_block())


func _apply_camera_preset(name: String) -> void:
	_last_preset = name
	_free_orbit = name == "orbit"
	var off := ForestPlaygroundCamera.backdrop_origin()
	var aim := ForestPlaygroundCamera.aim_point()
	if _free_orbit:
		_orbit_yaw = 0.0
		_orbit_pitch = 0.031415927
		_orbit_radius = 8.01 * ForestPlaygroundCamera.GENERATED_RIG_SCALE
		_pivot = aim
		_apply_orbit_camera()
		return
	match name:
		"camsun":
			ForestPlaygroundCamera.apply_camsun(_camera)
		"top":
			var g := _layout.hamlet_centre_xz
			var gc := Vector3(g.x + off.x, 0.0, g.y + off.z)
			_camera.global_position = gc + Vector3(0.0, 95.0, 0.0)
			_camera.look_at(gc, Vector3.UP)
		"wide":
			ForestPlaygroundCamera.apply_wide(_camera)
		"oblique":
			_camera.global_position = aim + Vector3(42.0, 32.0, 38.0) * ForestPlaygroundCamera.GENERATED_RIG_SCALE
			_camera.look_at(aim, Vector3.UP)
		_:
			ForestPlaygroundCamera.apply_camsun(_camera)


func _apply_orbit_camera() -> void:
	var pivot := _pivot
	_orbit_pitch = DebugCamera.clamp_pitch(_orbit_pitch, _orbit_radius, pivot.y)
	_camera.global_transform = DebugCamera.solve(pivot, _orbit_yaw, _orbit_pitch, _orbit_radius)


func _parse_out_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return ProjectSettings.globalize_path(arg.substr(6))
	return ""


func _has_user_arg(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


func _parse_camera_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="):
			return arg.substr(9)
	return "camsun"


func _capture_png(out_path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err == OK:
		print("[forest_playground] saved ", out_path)
	else:
		printerr("[forest_playground] save failed ", err)
	get_tree().quit(err if err != OK else 0)
