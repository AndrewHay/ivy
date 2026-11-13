extends Node3D

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsKnobSpec = preload("res://src/playground/hills_knob_spec.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const HillsFogTint = preload("res://src/playground/hills_fog_tint.gd")
const HillsPineMesh = preload("res://src/playground/hills_pine_mesh.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")
const KnobPanel = preload("res://src/playground/knob_panel.gd")
const PlaygroundKnobHost = preload("res://src/playground/playground_knob_host.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const DebugCamera = preload("res://src/world/debug_camera.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")
const WorldFogParams = preload("res://src/world/world_fog_params.gd")
const WorldFogVolume = preload("res://src/world/world_fog_volume.gd")
const SkySun = preload("res://src/world/sky_sun.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const Solar = preload("res://src/env/solar.gd")

const _PINE_GLTF := "res://assets/backdrop/pieces/Pine_2.gltf"

@export var script_driven: bool = false

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _camera: Camera3D = $Camera3D
@onready var _stage: Node3D = $Stage

var _params := HillsParams.production()
var _layout: VillageLayout
var _knob_panel: KnobPanel
var _rebuild_pending := false
var _world_fog_volume: FogVolume
var _world_fog_params: WorldFogParams = WorldFogParams.production()
var _show_ui := true
var _allow_input := true
var _free_orbit := false
var _last_preset := "camsun"
var _orbit_yaw := 0.0
var _orbit_pitch := 0.031415927
var _orbit_radius := 8.01 * ForestPlaygroundCamera.GENERATED_RIG_SCALE
var _pivot := Vector3.ZERO
var _mouse_orbit := false

const _DRAG_RAD_PER_PIXEL := 0.3 * PI / 180.0
const _KEY_RAD_PER_PRESS := 3.0 * PI / 180.0
const _ZOOM_PER_NOTCH := 0.9
const _ZOOM_MIN_RADIUS := 4.0
const _ZOOM_MAX_RADIUS := 140.0

var _pond_snapshot: Variant
var _sky_sun: SkySun
## Callable(err: int) invoked after a capture save. Tests replace this to avoid
## calling get_tree().quit() from inside the GUT runner.
var _capture_done_fn: Callable


func _ready() -> void:
	_capture_done_fn = func(err: int) -> void: get_tree().quit(0 if err == OK else err)
	_pond_snapshot = VillagePondShape.active()
	var out_path := _parse_out_arg()
	var capture_ui := _has_user_arg("--capture-ui")
	_show_ui = capture_ui or (out_path.is_empty() and not script_driven)
	_allow_input = out_path.is_empty() and not script_driven
	_setup_environment()
	_apply_cli_overrides()
	_rebuild_layout_and_stage()
	if _show_ui:
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
		_rebuild_hills()
	if _free_orbit and (_show_ui or _allow_input):
		_apply_orbit_camera()
		_apply_playground_fog()


func _unhandled_input(event: InputEvent) -> void:
	if not _allow_input or not _free_orbit:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_mouse_orbit = not _mouse_orbit
			Input.set_mouse_mode(
				Input.MOUSE_MODE_CAPTURED if _mouse_orbit else Input.MOUSE_MODE_VISIBLE)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_orbit_radius = clampf(_orbit_radius * _ZOOM_PER_NOTCH, _ZOOM_MIN_RADIUS, _ZOOM_MAX_RADIUS)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_orbit_radius = clampf(_orbit_radius / _ZOOM_PER_NOTCH, _ZOOM_MIN_RADIUS, _ZOOM_MAX_RADIUS)
	elif event is InputEventMouseMotion and _mouse_orbit:
		var mm := event as InputEventMouseMotion
		_orbit_yaw -= mm.relative.x * _DRAG_RAD_PER_PIXEL
		_orbit_pitch = DebugCamera.clamp_pitch(
			_orbit_pitch - mm.relative.y * _DRAG_RAD_PER_PIXEL,
			_orbit_radius, _pivot.y)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_LEFT:
				_orbit_yaw -= _KEY_RAD_PER_PRESS
			KEY_RIGHT:
				_orbit_yaw += _KEY_RAD_PER_PRESS
			KEY_UP:
				_orbit_pitch = DebugCamera.clamp_pitch(
					_orbit_pitch - _KEY_RAD_PER_PRESS, _orbit_radius, _pivot.y)
			KEY_DOWN:
				_orbit_pitch = DebugCamera.clamp_pitch(
					_orbit_pitch + _KEY_RAD_PER_PRESS, _orbit_radius, _pivot.y)


func _setup_environment() -> void:
	_install_production_sky_sun()


func _install_production_sky_sun() -> void:
	if _sky_sun != null:
		return
	var sky := SkySun.new()
	sky.name = "SkySun"
	add_child(sky)
	var sun := get_node("DirectionalLight3D") as DirectionalLight3D
	remove_child(sun)
	sky.add_child(sun)
	sun.name = "Sun"
	remove_child(_world_env)
	sky.add_child(_world_env)
	_sky_sun = sky
	var env := _main_like_environment()
	_world_env.environment = env
	var solar := Solar.new(IvyParams.new())
	sky.setup(solar)
	sky.set_fog_model(HeroFog.FogModel.WORLD_AROUND_HERO)


func _main_like_environment() -> Environment:
	var sky_shader := load("res://src/render/sky/atmospheric_sky.gdshader") as Shader
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader
	sky_mat.set_shader_parameter("sky_top_color", Color(0.361, 0.561, 0.722))
	sky_mat.set_shader_parameter("sky_horizon_color", Color(0.784, 0.851, 0.91))
	sky_mat.set_shader_parameter("sky_energy", 1.4)
	sky_mat.set_shader_parameter("ground_horizon_color", Color(0.784, 0.851, 0.91))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.72)
	env.ambient_light_energy = 0.8
	return env


func _apply_cli_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_params.layout_seed = int(arg.get_slice("=", 1))
		if arg.begins_with("--variant="):
			_params.variant = int(arg.get_slice("=", 1))
		if arg.begins_with("--preset="):
			_params.apply_preset(arg.get_slice("=", 1))


func _rebuild_layout_and_stage() -> void:
	_layout = VillageLayout.generate(_params.layout_seed)
	VillagePondShape.set_active(VillagePondShape.at(_layout.pond_center))
	_stage.position = ForestPlaygroundCamera.backdrop_origin()
	_clear_stage()
	_build_ground_ref()
	_rebuild_hills()
	_apply_playground_fog()


func _clear_stage() -> void:
	for c in _stage.get_children():
		c.queue_free()


func _build_ground_ref() -> void:
	var g := _layout.hamlet_centre_xz
	var r := _layout.lawn_radius
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(r * 2.05, r * 2.05)
	mesh.subdivide_width = 8
	mesh.subdivide_depth = 8
	var mi := MeshInstance3D.new()
	mi.name = "LawnDisc"
	mi.mesh = mesh
	mi.position = Vector3(g.x, VillageBackdrop.LAWN_GROUND_Y_OFFSET, g.y)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/render/shaders/village_ground.gdshader") as Shader
	mi.material_override = mat
	_stage.add_child(mi)


func _rebuild_hills() -> void:
	var old_terrain := _stage.get_node_or_null("HillTerrain")
	if old_terrain:
		old_terrain.queue_free()
	var old_forest := _stage.get_node_or_null("HillForest")
	if old_forest:
		old_forest.queue_free()
	var mesh := HillsHeightfield.build_mesh(_layout, _params)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/render/shaders/village_ground_hills.gdshader") as Shader
	HillsFogTint.apply_terrain_shader(mat, _layout, _params)
	if not _params.ridge_fog_tint_on:
		mat.shader = load("res://src/render/shaders/village_ground.gdshader") as Shader
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "HillTerrain"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(mi)
	if _params.variant == 1:
		return
	var t_seed := HillsHeightfield.terrain_seed(_layout, _params)
	var backdrop := ForestPlacement.forest_tree_xz(_layout, ForestParams.production())
	var xforms := HillsForestPlacement.hill_forest_transforms(_layout, _params, t_seed, backdrop)
	if xforms.is_empty():
		return
	var pine := _extract_mesh(_PINE_GLTF)
	var mm := MultiMesh.new()
	mm.mesh = HillsPineMesh.prepare(pine)
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = xforms.size()
	var fog_b := _params.effective_fog_begin(_layout)
	var fog_e := _params.effective_fog_end(_layout)
	var cam := _camera.global_position if _camera else HillsFogTint.reference_camera_pos()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, HillsFogTint.tree_instance_color(
			xforms[i].origin, _params, _layout, fog_b, fog_e, cam))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "HillForest"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(mmi)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	layer.add_child(margin)
	var host := PlaygroundKnobHost.hills()
	_knob_panel = KnobPanel.new()
	_knob_panel.build_from_spec(
		HillsKnobSpec.all_knobs(), _params, HillsParams.presets(), host)
	margin.add_child(_knob_panel)
	_knob_panel.knob_changed.connect(_on_knob_changed)
	_knob_panel.variant_changed.connect(_on_variant_changed)
	_knob_panel.preset_selected.connect(_on_preset_selected)
	_knob_panel.reset_requested.connect(_on_reset_production)
	_knob_panel.copy_requested.connect(_on_copy_settings)
	layer.add_child(_make_camera_panel())


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
	var title := Label.new()
	title.text = "Camera"
	col.add_child(title)
	col.add_child(_labeled_button("CamSun", func(): _apply_camera_preset("camsun")))
	col.add_child(_labeled_button("Edge outward", func(): _apply_camera_preset("edge_outward")))
	col.add_child(_labeled_button("Edge inward", func(): _apply_camera_preset("edge_inward")))
	col.add_child(_labeled_button("CamTop", func(): _apply_camera_preset("top")))
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
	# _sync_layer_arrays_from_knobs was here; removed in rework7 — the arrays
	# layer_amplitude_m / layer_wavelength_m are legacy JSON aliases, not read by
	# any active code path (amplitude_at / wavelength_at were also removed).
	_rebuild_pending = true


func _on_variant_changed(v: int) -> void:
	_params.variant = v
	if _knob_panel:
		_knob_panel.set_variant(v)
	_rebuild_pending = true


func _on_preset_selected(name: String) -> void:
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


func _apply_playground_fog() -> void:
	if _layout == null:
		return
	if _sky_sun != null:
		_sky_sun.set_fog_depth(_layout.fog_begin, _layout.fog_end)
		_sky_sun.set_fog_anchor(ForestPlaygroundCamera.hero_fog_anchor_world())
		return
	if _world_env == null or _world_env.environment == null:
		return
	var env := _world_env.environment
	env.fog_enabled = false
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_length = 192.0
	env.volumetric_fog_sky_affect = _world_fog_params.sky_affect_cap
	env.volumetric_fog_albedo = env.fog_light_color
	var anchor := ForestPlaygroundCamera.hero_fog_anchor_world()
	var pale := SkySun.pale_horizon_haze_color(0.32, 1.0)
	if _world_fog_volume == null:
		_world_fog_volume = WorldFogVolume.create_volume(anchor, _world_fog_params, pale)
		add_child(_world_fog_volume)
	else:
		WorldFogVolume.apply_params(_world_fog_volume, anchor, _world_fog_params, pale)


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
		"edge_outward", "edge-outward":
			_apply_edge_outward()
		"edge_inward", "edge-inward":
			_apply_edge_inward()
		"top", "camtop":
			var g := _layout.hamlet_centre_xz
			var gc := Vector3(g.x + off.x, 0.0, g.y + off.z)
			_camera.global_position = gc + Vector3(0.0, 95.0, 0.0)
			_camera.look_at(gc, Vector3.UP)
		_:
			ForestPlaygroundCamera.apply_camsun(_camera)


func _apply_orbit_camera() -> void:
	var pivot := _pivot
	_orbit_pitch = DebugCamera.clamp_pitch(_orbit_pitch, _orbit_radius, pivot.y)
	_camera.global_transform = DebugCamera.solve(pivot, _orbit_yaw, _orbit_pitch, _orbit_radius)


func _apply_edge_outward() -> void:
	var off := ForestPlaygroundCamera.backdrop_origin()
	var hero := VillageLayout.HERO_DOOR_STOOP
	var g := _layout.hamlet_centre_xz
	var lawn_r := _layout.lawn_radius
	var margin := 2.0
	var allowed := maxf(lawn_r - margin, 2.0)
	var dir_in := (hero - g).normalized() if hero.distance_to(g) > 0.1 else Vector2(0, -1)
	var dir_out := -dir_in
	var edge := Vector3(
		g.x + dir_out.x * allowed, 5.0, g.y + dir_out.y * allowed) + off
	var look := Vector3(
		edge.x + dir_out.x * 150.0, 1.5, edge.z + dir_out.y * 150.0)
	_camera.global_position = edge
	_camera.look_at(look, Vector3.UP)


func _apply_edge_inward() -> void:
	var off := ForestPlaygroundCamera.backdrop_origin()
	var hero := VillageLayout.HERO_DOOR_STOOP
	var g := _layout.hamlet_centre_xz
	var dir_in := (hero - g).normalized()
	var lawn_r := _layout.lawn_radius
	var edge := Vector3(g.x + dir_in.x * (lawn_r - 2.0), 5.0, g.y + dir_in.y * (lawn_r - 2.0)) + off
	var look := Vector3(hero.x, 1.2, hero.y) + off
	_camera.global_position = edge
	_camera.look_at(look, Vector3.UP)


func _has_user_arg(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


func _parse_out_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return arg.get_slice("=", 1)
	return ""


func _parse_camera_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="):
			return arg.get_slice("=", 1).to_lower()
	return "camsun"


func _capture_png(path: String) -> void:
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var err: Error = ERR_CANT_CREATE
	if img != null:
		err = img.save_png(path)
	if err == OK:
		print("[hills-playground] saved ", path)
	else:
		printerr("[hills-playground] save failed ", err)
	_capture_done_fn.call(err)


func _extract_mesh(path: String) -> Mesh:
	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var m := (n as MeshInstance3D).mesh
			inst.queue_free()
			return m
		for child in n.get_children():
			stack.append(child)
	inst.queue_free()
	return null
