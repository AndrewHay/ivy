extends Node3D

## Minimal garden patch with eight backdrop flowers in a ring and prefilled insects.
##
## Open in the editor: `scenes/test_fauna/test_fauna.tscn` (root name **Test Fauna**).
## Run:
##   Godot res://scenes/test_fauna/test_fauna.tscn
## Move the mouse to orbit (right-click toggles stick/unstick); scroll wheel zooms.
## Top-left panel: insect counts with + / − (spawn inside flower box).
## Optional PNG:
##   Godot res://scenes/test_fauna/test_fauna.tscn -- --out=res://.tmp/fauna/test_fauna.png

const _FLOWER_SCENES := [
	"res://assets/backdrop/pieces/Flower_3_Group.gltf",
	"res://assets/backdrop/pieces/Flower_4_Group.gltf",
]

## Backdrop-local positions in the fauna garden ring (5.5–12 m); clustered on a small lawn.
const _PATCH_CENTER := Vector3(6.55, 0.0, 0.05)
const _FLOWER_COUNT := 8
## Ring around `_PATCH_CENTER`; kept ≤ ~1 m so anchors stay in the 5.5–12 m fauna garden band.
const _FLOWER_CIRCLE_RADIUS_M := 0.92
const _PREFILL_BEES := 4
const _PREFILL_BUTTERFLIES := 4
const _GROUND_SIZE_M := 2.6 * 4.0
const _ORBIT_AIM_HEIGHT := 0.35
const _MOUSE_ORBIT_RAD_PER_PIXEL := 0.004
const _OverlayStyle = preload("res://src/ui/overlay_style.gd")
const _FLOWER_BOX_PAD_M := 0.35

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _garden: Node3D = $GardenPatch
@onready var _fauna: FaunaController = $FaunaController
@onready var _wind: AmbientWind = $AmbientWind
@onready var _camera: Camera3D = $Camera3D
@onready var _pivot: Node3D = $FaunaPivot

var _game_day: float = 0.42
var _interactive: bool = true
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = 0.55
var _orbit_radius: float = 2.05
## When true, mouse motion drives orbit; right-click toggles.
var _mouse_orbit_stuck: bool = true
var _spawn_rng := RandomNumberGenerator.new()
var _bee_count_label: Label
var _butterfly_count_label: Label


func _ready() -> void:
	_spawn_rng.randomize()
	_interactive = _parse_out_arg().is_empty()
	_setup_environment()
	_build_garden_visuals()
	var env := _build_fauna_environment()
	_fauna.ambient_spawn_enabled = false
	_fauna.debug_spawn_near_pivot_only = false
	_fauna.console_log = true
	_fauna.bind_environment(env, _garden, "test_fauna")
	_seed_orbit_from_default_view()
	_apply_orbit_camera()
	await get_tree().process_frame
	var ctx := _make_context()
	_fauna.prefill_agents(_PREFILL_BEES, _PREFILL_BUTTERFLIES, ctx)
	_fauna.set_all_agent_lifetimes(600.0)
	_build_insect_count_ui()
	_refresh_insect_count_labels()
	var out := _parse_out_arg()
	if not out.is_empty():
		await _capture_png(out)


func _process(delta: float) -> void:
	_game_day += delta / 86400.0
	_fauna.tick(_make_context(), delta)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.74, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.52)
	env.ambient_light_energy = 1.1
	_world_env.environment = env


func _flower_local_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in range(_FLOWER_COUNT):
		var angle := (float(i) / float(_FLOWER_COUNT)) * TAU
		out.append(Vector3(
			_PATCH_CENTER.x + cos(angle) * _FLOWER_CIRCLE_RADIUS_M,
			0.0,
			_PATCH_CENTER.z + sin(angle) * _FLOWER_CIRCLE_RADIUS_M))
	return out


func _build_garden_visuals() -> void:
	var flower_positions := _flower_local_positions()
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	# Godot 4 PlaneMesh lies on XZ (normal +Y) — do not rotate like a vertical billboard.
	plane.size = Vector2(_GROUND_SIZE_M, _GROUND_SIZE_M)
	ground.mesh = plane
	ground.position = _PATCH_CENTER
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.07, 0.22, 0.09)
	gm.roughness = 1.0
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.set_surface_override_material(0, gm)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_garden.add_child(ground)

	for i in range(flower_positions.size()):
		var path: String = _FLOWER_SCENES[i % _FLOWER_SCENES.size()]
		var ps := load(path) as PackedScene
		if ps == null:
			push_warning("[test_fauna] missing flower scene ", path)
			continue
		var flower: Node3D = ps.instantiate()
		flower.name = "Flower_%d" % i
		var angle := (float(i) / float(_FLOWER_COUNT)) * TAU
		flower.basis = Basis.from_euler(Vector3(0.0, angle, 0.0)).scaled(Vector3.ONE * 0.2)
		flower.position = flower_positions[i]
		_garden.add_child(flower)


func _build_fauna_environment() -> FaunaEnvironment:
	var env := FaunaEnvironment.new()
	for i in range(_FLOWER_COUNT):
		var anchor := FaunaAnchor.new()
		anchor.kind = FaunaConstants.AnchorKind.FLOWER
		var angle := (float(i) / float(_FLOWER_COUNT)) * TAU
		var pos := Vector3(
			_PATCH_CENTER.x + cos(angle) * _FLOWER_CIRCLE_RADIUS_M,
			0.0,
			_PATCH_CENTER.z + sin(angle) * _FLOWER_CIRCLE_RADIUS_M)
		anchor.local_transform = Transform3D(Basis.from_euler(Vector3(0.0, angle, 0.0)), pos)
		anchor.hero_weight = 1.0
		env.anchors.append(anchor)
	return env


func _orbit_aim() -> Vector3:
	return _pivot.global_position + Vector3(0.0, _ORBIT_AIM_HEIGHT, 0.0)


func _seed_orbit_from_default_view() -> void:
	var aim := _orbit_aim()
	var offset := Vector3(-1.35, 1.05, 1.25)
	_orbit_radius = offset.length()
	_orbit_yaw = atan2(offset.x, offset.z)
	_orbit_pitch = asin(clampf(offset.y / _orbit_radius, -1.0, 1.0))


func _apply_orbit_camera() -> void:
	var aim := _orbit_aim()
	var cp := cos(_orbit_pitch)
	var horizontal := _orbit_radius * cp
	var pos := aim + Vector3(
		sin(_orbit_yaw) * horizontal,
		sin(_orbit_pitch) * _orbit_radius,
		cos(_orbit_yaw) * horizontal)
	_camera.global_position = pos
	_camera.look_at(aim, Vector3.UP)


func _build_insect_count_ui() -> void:
	if not _interactive:
		return
	var layer := CanvasLayer.new()
	layer.name = "InsectCountUI"
	add_child(layer)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	layer.add_child(margin)

	var panel := PanelContainer.new()
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(0.06, 0.08, 0.10, 0.88)
	panel_box.set_corner_radius_all(8)
	panel_box.content_margin_left = 14.0
	panel_box.content_margin_right = 14.0
	panel_box.content_margin_top = 10.0
	panel_box.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", panel_box)
	margin.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Insects"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	col.add_child(title)

	col.add_child(_make_species_row("Bees", FaunaConstants.Species.BEE))
	col.add_child(_make_species_row("Butterflies", FaunaConstants.Species.BUTTERFLY))


func _make_species_row(species_name: String, species: FaunaConstants.Species) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_lbl := Label.new()
	name_lbl.text = species_name
	name_lbl.custom_minimum_size = Vector2(88, 0)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.90))
	row.add_child(name_lbl)
	var count_lbl := Label.new()
	count_lbl.custom_minimum_size = Vector2(28, 0)
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0))
	row.add_child(count_lbl)
	if species == FaunaConstants.Species.BEE:
		_bee_count_label = count_lbl
	else:
		_butterfly_count_label = count_lbl
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(36, 36)
	_OverlayStyle.style_button(minus)
	minus.pressed.connect(_on_remove_insect.bind(species))
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(36, 36)
	_OverlayStyle.style_button(plus)
	plus.pressed.connect(_on_add_insect.bind(species))
	row.add_child(plus)
	return row


func _flower_spawn_rect_xz() -> Rect2:
	var positions := _flower_local_positions()
	var min_x := positions[0].x
	var max_x := min_x
	var min_z := positions[0].z
	var max_z := min_z
	for p in positions:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var pad := _FLOWER_BOX_PAD_M
	return Rect2(min_x - pad, min_z - pad, (max_x - min_x) + pad * 2.0, (max_z - min_z) + pad * 2.0)


func _random_hover_in_flower_box() -> Vector2:
	var r := _flower_spawn_rect_xz()
	return Vector2(
		_spawn_rng.randf_range(r.position.x, r.position.x + r.size.x),
		_spawn_rng.randf_range(r.position.y, r.position.y + r.size.y))


func _on_add_insect(species: FaunaConstants.Species) -> void:
	var hover := _random_hover_in_flower_box()
	if _fauna.spawn_at_hover_local(species, _make_context(), hover):
		_refresh_insect_count_labels()


func _on_remove_insect(species: FaunaConstants.Species) -> void:
	if _fauna.despawn_one(species):
		_refresh_insect_count_labels()


func _refresh_insect_count_labels() -> void:
	if _bee_count_label != null:
		_bee_count_label.text = str(_fauna.count_species(FaunaConstants.Species.BEE))
	if _butterfly_count_label != null:
		_butterfly_count_label.text = str(_fauna.count_species(FaunaConstants.Species.BUTTERFLY))


func _unhandled_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseMotion and _mouse_orbit_stuck:
		var mm := event as InputEventMouseMotion
		if mm.relative.length_squared() <= 0.0:
			return
		_orbit_yaw -= mm.relative.x * _MOUSE_ORBIT_RAD_PER_PIXEL
		_orbit_pitch = clampf(
			_orbit_pitch - mm.relative.y * _MOUSE_ORBIT_RAD_PER_PIXEL,
			deg_to_rad(-12.0),
			deg_to_rad(78.0))
		_apply_orbit_camera()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_orbit_stuck = not _mouse_orbit_stuck
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_radius = maxf(0.6, _orbit_radius * 0.92)
			_apply_orbit_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_radius = minf(12.0, _orbit_radius / 0.92)
			_apply_orbit_camera()


func _make_context() -> FaunaPresentationContext:
	var ctx := FaunaPresentationContext.new()
	ctx.game_day = _game_day
	ctx.local_solar_hour = 11.0
	ctx.lit = 1.0
	ctx.render_blend = 1.0
	ctx.weather_activity_scale = 1.0
	ctx.wind = _wind
	ctx.pivot_global_position = _pivot.global_position
	ctx.camera_global_position = _camera.global_position
	ctx.backdrop_global_transform = _garden.global_transform
	ctx.paused = false
	return ctx


func _parse_out_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return ProjectSettings.globalize_path(arg.substr("--out=".length()))
	return ""


func _capture_png(out_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	for _i in range(45):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err == OK:
		print("[test_fauna] saved ", out_path)
	else:
		printerr("[test_fauna] save failed ", err)
	get_tree().quit(0)
