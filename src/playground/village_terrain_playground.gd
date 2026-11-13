## VillageTerrainPlayground — G7 algorithm playground for in-village lawn terrain.
## SD-VILLAGE-TERRAIN-9 / AR-VT-PLAYGROUND.
## Structure mirrors hills_playground.gd: knob-host wiring, camera presets,
## variants, presets, Reset, Copy settings, and the _capture_done_fn quit-hook seam.
## WP8b additions: debug relief shader, VE, disc clip, HUD, markers at sample_y,
## pond water, fog-off for top view, raking oblique camera.
extends Node3D

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrainKnobSpec = preload("res://src/playground/village_terrain_knob_spec.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")
const VillagePondSite = preload("res://src/world/village_pond_site.gd")
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

const _DEBUG_SHADER_PATH := "res://src/playground/shaders/village_terrain_debug.gdshader"
const _PRODUCTION_SHADER_PATH := "res://src/render/shaders/village_ground.gdshader"

@export var script_driven: bool = false
## Set before _ready() to override the initial variant (used by tests).
@export var _initial_variant: int = -1

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _camera: Camera3D = $Camera3D
@onready var _stage: Node3D = $Stage

var _params := VillageTerrainParams.production()
var _layout: VillageLayout
var _knob_panel: KnobPanel
var _rebuild_pending := false
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
var _world_fog_volume: FogVolume

# ── Debug-only playground vars (NOT in VillageTerrainParams; never production) ──
## Debug relief shader on (height bands + contours + slope); off = production shader.
## @export so tests can pre-set before _ready().
@export var _debug_relief_on: bool = true
## Contour line spacing in metres (debug only).
@export var _debug_contour_m: float = 0.2
## Vertical exaggeration (debug only, 1.0 = true scale, label clearly in UI).
@export var _debug_ve: float = 1.0

var _hud_label: Label
var _debug_panel_container: Control

const _DRAG_RAD_PER_PIXEL := 0.3 * PI / 180.0
const _KEY_RAD_PER_PRESS := 3.0 * PI / 180.0
const _ZOOM_PER_NOTCH := 0.9
const _ZOOM_MIN_RADIUS := 4.0
const _ZOOM_MAX_RADIUS := 140.0

var _pond_snapshot: Variant
var _sky_sun: SkySun
## Callable(err: int) invoked after a capture save. Tests replace this to avoid
## calling get_tree().quit() from inside the GUT runner (AR-VT-PLAYGROUND §quit-hook).
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
	if _initial_variant >= 0:
		_params.variant = _initial_variant
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
		_rebuild_terrain()
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
		if arg.begins_with("--ve="):
			_debug_ve = float(arg.get_slice("=", 1))
		if arg.begins_with("--debug-relief="):
			_debug_relief_on = arg.get_slice("=", 1).to_lower() != "0"
		if arg.begins_with("--contour="):
			_debug_contour_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--base-amplitude="):
			_params.base_amplitude_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--base-feature="):
			_params.base_feature_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--knoll-height="):
			_params.knoll_height_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--knoll-radius="):
			_params.knoll_radius_m = float(arg.get_slice("=", 1))
		if arg.begins_with("--noise-octaves="):
			_params.noise_octaves = int(arg.get_slice("=", 1))
		if arg.begins_with("--noise-persistence="):
			_params.noise_persistence = float(arg.get_slice("=", 1))


func _rebuild_layout_and_stage() -> void:
	_layout = VillageLayout.generate(_params.layout_seed)
	VillagePondShape.set_active(VillagePondShape.at(_layout.pond_center))
	_stage.position = ForestPlaygroundCamera.backdrop_origin()
	_clear_stage()
	_rebuild_terrain()
	_build_markers()
	_apply_playground_fog()


func _clear_stage() -> void:
	for c in _stage.get_children():
		c.queue_free()


func _rebuild_terrain() -> void:
	VillageTerrain.clear_knoll_centres_cache()
	var old := _stage.get_node_or_null("LawnTerrain")
	if old:
		old.name = "_removing"
		old.queue_free()
	var mesh := VillageTerrain.build_mesh(_layout, _params)
	var mat := _make_terrain_material()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "LawnTerrain"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(mi)
	_update_hud()


func _make_terrain_material() -> Material:
	if _debug_relief_on:
		return _make_debug_material()
	return _make_production_material()


func _make_production_material() -> ShaderMaterial:
	## Production-like look: uses village_ground.gdshader.
	## WP2 FINDING: village_ground.gdshader sets ROUGHNESS/METALLIC but does NOT write NORMAL,
	## so Godot's Forward+ PBR will apply directional lighting using vertex normals. However
	## the mesh heights are ≤0.8 m over a ~40 m radius so normal deviation from Vector3.UP is
	## ≤~9°; with ambient_light_energy=0.8 this produces only ~2-3% luminance variation — not
	## perceptible. WP2 must either: (a) write a steeper falloff / larger h_range in the lawn
	## shader so micro-slope differences are amplified via NORMAL or a custom light model, or
	## (b) add a slope-darkening or AO term directly in village_ground.gdshader (vertex ALBEDO
	## *= slope factor). The mesh normals are correct; the shader doesn't exploit them.
	var mat := ShaderMaterial.new()
	mat.shader = load(_PRODUCTION_SHADER_PATH) as Shader
	return mat


func _make_debug_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(_DEBUG_SHADER_PATH) as Shader
	if mat.shader == null:
		printerr("[vt-playground] debug shader not found, falling back to production")
		return _make_production_material()
	# Pass disc clip params so edge is a clean circle, not the Cartesian stair-step.
	var g := _layout.hamlet_centre_xz
	var off := ForestPlaygroundCamera.backdrop_origin()
	# g_x/g_z are in world space (stage offset applied).
	mat.set_shader_parameter("g_x", g.x + off.x)
	mat.set_shader_parameter("g_z", g.y + off.z)
	mat.set_shader_parameter("disc_r", _layout.lawn_radius)
	mat.set_shader_parameter("ve_scale", _debug_ve)
	mat.set_shader_parameter("contour_m", _debug_contour_m)
	mat.set_shader_parameter("h_range", _params.max_rise_m + 0.1)
	return mat


# ── Terrain stats / HUD ───────────────────────────────────────────────────────

func compute_terrain_stats() -> Dictionary:
	## Samples a grid over the lawn to compute min/max height, max slope, hero-pad h, pond depth.
	## Public so tests can call it.
	if _layout == null:
		return {}
	var t_seed := VillageTerrain.terrain_seed(_layout, _params)
	var g := _layout.hamlet_centre_xz
	var r := _layout.lawn_radius
	var step := maxf(_params.terrain_mesh_step_m * 2.0, 2.0)
	var min_h := INF
	var max_h := -INF
	var max_slope := 0.0
	var x := g.x - r
	while x <= g.x + r:
		var z := g.y - r
		while z <= g.y + r:
			var xz := Vector2(x, z)
			if xz.distance_to(g) < r:
				var h := VillageTerrain.sample_y(xz, _layout, _params, t_seed)
				var s := VillageTerrain.sample_slope_deg(xz, _layout, _params, t_seed)
				min_h = minf(min_h, h)
				max_h = maxf(max_h, h)
				max_slope = maxf(max_slope, s)
			z += step
		x += step
	var hero := VillageLayout.HERO_DOOR_STOOP
	var hero_h := VillageTerrain.sample_y(hero, _layout, _params, t_seed)
	var pond_h := VillageTerrain.sample_y(_layout.pond_center, _layout, _params, t_seed)
	return {
		"min_h": min_h if is_finite(min_h) else 0.0,
		"max_h": max_h if is_finite(max_h) else 0.0,
		"max_slope_deg": max_slope,
		"hero_h": hero_h,
		"pond_basin_h": pond_h,
	}


func _update_hud() -> void:
	if _hud_label == null:
		return
	var s := compute_terrain_stats()
	if s.is_empty():
		_hud_label.text = "(no stats)"
		return
	_hud_label.text = (
		"h: %.3f … %.3f m  |  slope_max: %.1f°\nhero pad: %.3f m  |  pond basin: %.3f m"
		% [s["min_h"], s["max_h"], s["max_slope_deg"], s["hero_h"], s["pond_basin_h"]]
	)


# ── Markers ───────────────────────────────────────────────────────────────────

func _build_markers() -> void:
	## Context markers placed ON the terrain (sample_y heights).
	## Hero stoop box, pond water disc, cottage footprints.
	var t_seed := VillageTerrain.terrain_seed(_layout, _params)

	# Hero stoop marker.
	var hero := VillageLayout.HERO_DOOR_STOOP
	var hero_y := VillageTerrain.sample_y(hero, _layout, _params, t_seed)
	var hero_box := MeshInstance3D.new()
	hero_box.name = "HeroStandIn"
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 2.2, 1.2)
	hero_box.mesh = box
	hero_box.position = Vector3(hero.x, hero_y + 1.1, hero.y)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.88, 0.72, 0.50)
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	hero_box.material_override = hmat
	_stage.add_child(hero_box)

	# Pond: water disc at water level, bank ring.
	var pond := _layout.pond_center
	if pond != Vector2.ZERO:
		_build_pond_marker(pond, t_seed)

	# Cottage footprint slabs at pad height.
	var ci := 0
	for spec: Dictionary in _layout.cottages:
		if ci >= 6:
			break
		var rect := VillageBackdrop.cottage_exterior_rect(spec)
		var centre := Vector2(rect.get_center().x, rect.get_center().y)
		var sz := rect.size
		var pad_y := VillageTerrain.sample_y(centre, _layout, _params, t_seed)
		var cottage := MeshInstance3D.new()
		cottage.name = "Cottage_%d" % ci
		var cm := BoxMesh.new()
		cm.size = Vector3(sz.x, 0.12, sz.y)
		cottage.mesh = cm
		cottage.position = Vector3(centre.x, pad_y + 0.06, centre.y)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.82, 0.78, 0.70)
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		cottage.material_override = cmat
		_stage.add_child(cottage)
		ci += 1


func _build_pond_marker(pond: Vector2, t_seed: int) -> void:
	## Renders the pond basin context:
	## - Water disc at water level (visible below rim, above basin floor).
	## - Bank ring outline at sample_y of bank.
	var water_y := _compute_pond_water_y(pond, t_seed)

	# Water disc.
	var water_r := VillagePondSite.MEAN_WATER_RADIUS_M
	var water_disc := MeshInstance3D.new()
	water_disc.name = "PondWater"
	var cyl := CylinderMesh.new()
	cyl.height = 0.06
	cyl.top_radius = water_r
	cyl.bottom_radius = water_r
	cyl.radial_segments = 48
	water_disc.mesh = cyl
	water_disc.position = Vector3(pond.x, water_y, pond.y)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.20, 0.45, 0.72, 0.82)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_disc.material_override = wmat
	_stage.add_child(water_disc)

	# Bank ring (thin outline at bank_outer height to show basin edge).
	var bank_r := VillagePondSite.BANK_OUTER_M
	var rim_pt := pond + Vector2(bank_r * 0.9, 0.0)
	var rim_y := VillageTerrain.sample_y(rim_pt, _layout, _params, t_seed)
	var bank_ring := MeshInstance3D.new()
	bank_ring.name = "PondBank"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = bank_r - 0.3
	ring_mesh.outer_radius = bank_r + 0.3
	ring_mesh.rings = 64
	bank_ring.mesh = ring_mesh
	bank_ring.position = Vector3(pond.x, rim_y + 0.08, pond.y)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.60, 0.50, 0.35)
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	bank_ring.material_override = rmat
	_stage.add_child(bank_ring)


func _compute_pond_water_y(pond: Vector2, t_seed: int) -> float:
	## AR-VT-GAP-1: water level from base field near rim, minus inset.
	## Approximate: sample at 80% of bank_outer radius to get rim height, subtract inset.
	var rim_pt := pond + Vector2(VillagePondSite.BANK_OUTER_M * 0.8, 0.0)
	var rim_y := VillageTerrain.sample_y(rim_pt, _layout, _params, t_seed)
	return rim_y - _params.pond_water_inset_m


# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	# Left panel: knob panel.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	layer.add_child(margin)
	var host := PlaygroundKnobHost.village_terrain()
	_knob_panel = KnobPanel.new()
	_knob_panel.build_from_spec(
		VillageTerrainKnobSpec.all_knobs(), _params, VillageTerrainParams.presets(), host)
	margin.add_child(_knob_panel)
	_knob_panel.knob_changed.connect(_on_knob_changed)
	_knob_panel.variant_changed.connect(_on_variant_changed)
	_knob_panel.preset_selected.connect(_on_preset_selected)
	_knob_panel.reset_requested.connect(_on_reset_production)
	_knob_panel.copy_requested.connect(_on_copy_settings)

	# Right panel: camera presets.
	layer.add_child(_make_camera_panel())

	# Bottom-left: debug controls.
	layer.add_child(_make_debug_panel())

	# Bottom strip: HUD stats.
	layer.add_child(_make_hud_panel())


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
	col.add_child(_labeled_button("Raking light", func(): _apply_camera_preset("raking")))
	col.add_child(_labeled_button("CamTop", func(): _apply_camera_preset("top")))
	col.add_child(_labeled_button("Hero approach", func(): _apply_camera_preset("hero_approach")))
	col.add_child(_labeled_button("Pond oblique", func(): _apply_camera_preset("pond_oblique")))
	col.add_child(_labeled_button("Free orbit", func(): _apply_camera_preset("orbit")))
	return margin


func _make_debug_panel() -> Control:
	## Debug-only controls: relief mode, contour spacing, vertical exaggeration.
	## These are NOT in VillageTerrainParams and do NOT appear in Copy Settings JSON.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Debug (playground only)"
	col.add_child(title)

	# Relief debug toggle.
	var chk := CheckBox.new()
	chk.text = "Relief debug view"
	chk.button_pressed = _debug_relief_on
	chk.toggled.connect(func(v: bool) -> void:
		_debug_relief_on = v
		_rebuild_pending = true)
	col.add_child(chk)

	# Contour spacing slider.
	var contour_row := HBoxContainer.new()
	var contour_lbl := Label.new()
	contour_lbl.text = "Contour (m):"
	contour_row.add_child(contour_lbl)
	var contour_sl := HSlider.new()
	contour_sl.min_value = 0.05
	contour_sl.max_value = 1.0
	contour_sl.step = 0.05
	contour_sl.value = _debug_contour_m
	contour_sl.custom_minimum_size = Vector2(120, 0)
	contour_sl.value_changed.connect(func(v: float) -> void:
		_debug_contour_m = v
		_rebuild_pending = true)
	contour_row.add_child(contour_sl)
	col.add_child(contour_row)

	# Vertical exaggeration slider (clearly labeled debug-only).
	var ve_row := HBoxContainer.new()
	var ve_lbl := Label.new()
	ve_lbl.text = "VE (debug!):"
	ve_row.add_child(ve_lbl)
	var ve_sl := HSlider.new()
	ve_sl.min_value = 1.0
	ve_sl.max_value = 8.0
	ve_sl.step = 0.5
	ve_sl.value = _debug_ve
	ve_sl.custom_minimum_size = Vector2(120, 0)
	ve_sl.value_changed.connect(func(v: float) -> void:
		_debug_ve = v
		_rebuild_pending = true)
	ve_row.add_child(ve_sl)
	col.add_child(ve_row)

	_debug_panel_container = margin
	return margin


func _make_hud_panel() -> Control:
	## Bottom strip: terrain stats HUD.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var lbl := Label.new()
	lbl.name = "HUDLabel"
	panel.add_child(lbl)
	_hud_label = lbl
	_update_hud()
	return margin


func _labeled_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


# ── Knob callbacks ────────────────────────────────────────────────────────────

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


# ── Fog ───────────────────────────────────────────────────────────────────────

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


func _disable_fog_for_top_view() -> void:
	## CamTop should not be fogged — fog distance is < lawn_radius from top.
	if _sky_sun != null:
		_sky_sun.set_fog_depth(500.0, 1000.0)
		return
	if _world_env != null and _world_env.environment != null:
		_world_env.environment.fog_enabled = false
		_world_env.environment.volumetric_fog_enabled = false


# ── Cameras ───────────────────────────────────────────────────────────────────

func _apply_camera_preset(name: String) -> void:
	_last_preset = name
	_free_orbit = name == "orbit"
	var off := ForestPlaygroundCamera.backdrop_origin()
	var aim := ForestPlaygroundCamera.aim_point()

	# Restore normal fog for most presets; disable for top.
	if name != "top":
		_apply_playground_fog()
	else:
		_disable_fog_for_top_view()

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
			_apply_top_camera()
		"raking", "raking_light", "rake":
			_apply_raking_camera()
		"hero_approach", "hero-approach":
			_apply_hero_approach()
		"pond_oblique", "pond-oblique":
			_apply_pond_oblique()
		_:
			ForestPlaygroundCamera.apply_camsun(_camera)


func _apply_orbit_camera() -> void:
	var pivot := _pivot
	_orbit_pitch = DebugCamera.clamp_pitch(_orbit_pitch, _orbit_radius, pivot.y)
	_camera.global_transform = DebugCamera.solve(pivot, _orbit_yaw, _orbit_pitch, _orbit_radius)


func _apply_top_camera() -> void:
	var off := ForestPlaygroundCamera.backdrop_origin()
	var g := _layout.hamlet_centre_xz
	var gc := Vector3(g.x + off.x, 0.0, g.y + off.z)
	_camera.global_position = gc + Vector3(0.0, 75.0, 0.001)
	_camera.look_at(gc, Vector3.FORWARD)
	_camera.fov = 45.0


func _apply_raking_camera() -> void:
	## Low-angle oblique: eye at lawn edge ~3 m high, looking across the centre.
	## Long shadows make even subtle bumps obvious (primary feel-judging view).
	var off := ForestPlaygroundCamera.backdrop_origin()
	var g := _layout.hamlet_centre_xz
	var lawn_r := _layout.lawn_radius
	# Eye from south-west (azimuth ~225°, low elevation).
	var az_rad := deg_to_rad(225.0)
	var eye_xz := g + Vector2(sin(az_rad), cos(az_rad)) * (lawn_r - 2.0)
	var eye := Vector3(eye_xz.x + off.x, 3.5, eye_xz.y + off.z)
	var centre := Vector3(g.x + off.x, 0.0, g.y + off.z)
	# Look toward the opposite (north-east) edge for maximum cross-terrain view.
	var look_xz := g + Vector2(sin(az_rad + PI), cos(az_rad + PI)) * lawn_r * 0.5
	var look := Vector3(look_xz.x + off.x, 0.5, look_xz.y + off.z)
	_camera.global_position = eye
	_camera.look_at(look, Vector3.UP)
	_camera.fov = 75.0


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


func _apply_hero_approach() -> void:
	## Eye on hero approach path ~12 m out, 1.6 m high, looking at stoop.
	var off := ForestPlaygroundCamera.backdrop_origin()
	var hero := VillageLayout.HERO_DOOR_STOOP
	var g := _layout.hamlet_centre_xz
	var to_hero := (hero - g).normalized() if hero.distance_to(g) > 0.1 else Vector2(0, -1)
	var eye_xz := hero - to_hero * 12.0
	var eye := Vector3(eye_xz.x + off.x, 1.6, eye_xz.y + off.z)
	var target := Vector3(hero.x + off.x, 0.8, hero.y + off.z)
	_camera.global_position = eye
	_camera.look_at(target, Vector3.UP)
	_camera.fov = 60.0


func _apply_pond_oblique() -> void:
	## 30° oblique view looking into the basin from ~20 m out at 4 m height.
	var off := ForestPlaygroundCamera.backdrop_origin()
	var pond := _layout.pond_center
	if pond == Vector2.ZERO:
		_apply_camera_preset("top")
		return
	var hero := VillageLayout.HERO_DOOR_STOOP
	var dir := (pond - hero).normalized() if pond.distance_to(hero) > 0.1 else Vector2(1, 0)
	var dist := 22.0
	var eye_xz := pond - dir * dist
	var eye := Vector3(eye_xz.x + off.x, 4.0, eye_xz.y + off.z)
	var target := Vector3(pond.x + off.x, -0.3, pond.y + off.z)
	_camera.global_position = eye
	_camera.look_at(target, Vector3.UP)
	_camera.fov = 55.0


# ── CLI helpers ───────────────────────────────────────────────────────────────

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
		print("[village-terrain-playground] saved ", path)
	else:
		printerr("[village-terrain-playground] save failed ", err)
	_capture_done_fn.call(err)
