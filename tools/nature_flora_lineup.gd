extends Node3D

## Numbered single-row catalog of Quaternius nature flora pieces (audition).
##
##   Godot res://tools/nature_flora_lineup.tscn
## Same camera as the main game (DebugCamera): Tab, WASD/arrows, scroll, left-click origin.
##   Godot res://tools/nature_flora_lineup.tscn -- --out=res://.tmp/nature_flora/lineup.png
##
## Index → piece name map is written beside the PNG as lineup_manifest.txt.

const DebugCameraScript = preload("res://src/world/debug_camera.gd")

const _PIECE_DIR := "res://assets/backdrop/pieces/"
const _DISPLAY_SCALE := 0.32
const _SPACING_M := 1.75
const _LABEL_HEIGHT_M := 0.85
## Wider zoom-out than the default cylinder so the full row fits.
const _ZOOM_BOUNDS := Vector2(0.75, 55.0)

## Order matches import_nature_backdrop_pieces.py ALL_FLORA.
const _PIECES: Array[String] = [
	"Bush_Common",
	"Bush_Common_Flowers",
	"Clover_1",
	"Clover_2",
	"Fern_1",
	"Flower_3_Group",
	"Flower_3_Single",
	"Flower_4_Group",
	"Flower_4_Single",
	"Grass_Common_Short",
	"Grass_Common_Tall",
	"Grass_Wispy_Short",
	"Grass_Wispy_Tall",
	"Mushroom_Common",
	"Mushroom_Laetiporus",
	"Petal_1",
	"Petal_2",
	"Petal_3",
	"Petal_4",
	"Petal_5",
	"Plant_1",
	"Plant_1_Big",
	"Plant_7",
	"Plant_7_Big",
]

@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _lineup: Node3D = $LineupPatch
@onready var _debug_camera: DebugCamera = $DebugCamera


func _ready() -> void:
	var interactive := _parse_out_arg().is_empty()
	_setup_environment()
	_build_ground_physics()
	_build_lineup()
	_setup_debug_camera(interactive)
	if interactive:
		_build_hint_ui()
	else:
		_frame_debug_camera_for_catalog()
		await _capture_png(_parse_out_arg())


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.74, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.52)
	env.ambient_light_energy = 1.1
	_world_env.environment = env


func _line_center_x() -> float:
	return float(maxi(_PIECES.size(), 1) - 1) * _SPACING_M * 0.5


func _build_ground_physics() -> void:
	var count := maxi(_PIECES.size(), 1)
	var line_len := float(count - 1) * _SPACING_M + 4.0
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 2
	body.position = Vector3(_line_center_x(), 0.0, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(line_len, 0.05, 5.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.025, 0.0)
	body.add_child(shape)
	add_child(body)


func _build_lineup() -> void:
	var count := maxi(_PIECES.size(), 1)
	var line_len := float(count - 1) * _SPACING_M + 4.0

	var ground := MeshInstance3D.new()
	ground.name = "GroundVisual"
	var plane := PlaneMesh.new()
	plane.size = Vector2(line_len, 5.0)
	ground.mesh = plane
	ground.position = Vector3(_line_center_x(), 0.0, 0.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.07, 0.22, 0.09)
	gm.roughness = 1.0
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.set_surface_override_material(0, gm)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lineup.add_child(ground)

	var x := 0.0
	for i in range(_PIECES.size()):
		var basename: String = _PIECES[i]
		var path := _PIECE_DIR + basename + ".gltf"
		var inst := _load_gltf_scene(path)
		if inst == null:
			push_warning("[nature_flora_lineup] missing ", path)
			x += _SPACING_M
			continue

		var slot := Node3D.new()
		slot.name = "Slot_%d" % (i + 1)
		slot.position = Vector3(x, 0.0, 0.0)
		_lineup.add_child(slot)
		inst.scale = Vector3.ONE * _DISPLAY_SCALE
		slot.add_child(inst)

		var label := Label3D.new()
		label.text = str(i + 1)
		label.font_size = 96
		label.modulate = Color(1.0, 0.95, 0.2)
		label.outline_modulate = Color(0.05, 0.05, 0.08)
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, _LABEL_HEIGHT_M, 0.0)
		label.no_depth_test = true
		slot.add_child(label)

		x += _SPACING_M


func _load_gltf_scene(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_warning("[nature_flora_lineup] glTF load failed ", path, " err=", err)
		return null
	return doc.generate_scene(state) as Node3D


func _setup_debug_camera(interactive: bool) -> void:
	_debug_camera.script_driven = not interactive
	if not interactive:
		_debug_camera.set_process_unhandled_input(false)
		_debug_camera.set_process(false)
	var spec := TowerSpec.new()
	_debug_camera.setup(spec, _ZOOM_BOUNDS)
	_debug_camera.set_orbit_pivot(Vector3(0.0, 0.35, 0.0))
	if interactive:
		_debug_camera.activate_for_planting()
		_debug_camera.finish_planting()


func _frame_debug_camera_for_catalog() -> void:
	var line_span := float(maxi(_PIECES.size(), 1) - 1) * _SPACING_M
	var pivot := Vector3(_line_center_x(), 0.35, 0.0)
	var offset := Vector3(-line_span * 0.15, line_span * 0.22 + 2.0, line_span * 0.42 + 3.0)
	var radius := offset.length()
	var yaw := atan2(offset.x, offset.z)
	var pitch := asin(clampf(offset.y / radius, -1.0, 1.0))
	pitch = DebugCameraScript.clamp_pitch(pitch, radius, pivot.y)
	radius = DebugCameraScript.clamp_radius_with_bounds(radius, _ZOOM_BOUNDS.x, _ZOOM_BOUNDS.y)
	_debug_camera.set_orbit_pivot(pivot)
	_debug_camera.restore_state({
		"yaw": yaw,
		"pitch": pitch,
		"radius": radius,
		"pivot": [pivot.x, pivot.y, pivot.z],
	})
	_debug_camera.current = true
	_debug_camera.global_transform = DebugCameraScript.solve(pivot, yaw, pitch, radius)


func _build_hint_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HintUI"
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	layer.add_child(margin)
	var label := Label.new()
	label.text = "Nature flora lineup — numbers match lineup_manifest.txt\nCamera matches main game (see ? in session for keys)"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	margin.add_child(label)


func _parse_out_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return ProjectSettings.globalize_path(arg.substr("--out=".length()))
	return ""


func _capture_png(out_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var manifest_path := out_path.get_base_dir().path_join("lineup_manifest.txt")
	var lines: PackedStringArray = PackedStringArray()
	for i in range(_PIECES.size()):
		lines.append("%d\t%s" % [i + 1, _PIECES[i]])
	var mf := FileAccess.open(manifest_path, FileAccess.WRITE)
	if mf != null:
		mf.store_string("\n".join(lines) + "\n")
		mf.close()

	for _i in range(45):
		await get_tree().process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	if err == OK:
		print("[nature_flora_lineup] saved ", out_path)
		print("[nature_flora_lineup] manifest ", manifest_path)
	else:
		printerr("[nature_flora_lineup] save failed ", err)
	get_tree().quit(0)
