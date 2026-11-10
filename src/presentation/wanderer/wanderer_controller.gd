class_name WandererController
extends Node3D

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")
const WandererBrain = preload("res://src/presentation/wanderer/wanderer_brain.gd")
const WandererRouteGraph = preload("res://src/presentation/wanderer/wanderer_route_graph.gd")
const WandererContent = preload("res://src/presentation/wanderer/wanderer_content.gd")
const WandererFigure = preload("res://src/presentation/wanderer/wanderer_figure.gd")
const WandererImagePlacement = preload("res://src/presentation/wanderer/wanderer_image_placement.gd")
const WandererBubbleView = preload("res://src/presentation/wanderer/wanderer_bubble_view.gd")

var _params: WandererParams = null
var _brain: WandererBrain = WandererBrain.new()
var _graph: WandererRouteGraph = null
var _content: WandererContent = null
var _rng := RandomNumberGenerator.new()
var _backdrop: VillageBackdrop = null
var _mode_id: String = ""
var _layout_ref: VillageLayout = null
var _figure_root: Node3D = null
var _figure: Node3D = null
var _bubble: Label3D = null
var _bubble_panel: Sprite3D = null
var _image_mi: MeshInstance3D = null
var _image_mat: StandardMaterial3D = null
var _enabled: bool = true
var _bound: bool = false


func _init() -> void:
	_params = WandererParams.production()
	_content = WandererContent.load_from_dir(_params)
	_rng.seed = _params.rng_seed if _params.rng_seed != 0 else int(Time.get_ticks_usec())
	_figure_root = Node3D.new()
	_figure_root.name = "FigurePivot"
	add_child(_figure_root)
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
	_bubble.no_depth_test = true
	_bubble.render_priority = 1
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_figure_root.add_child(_bubble)
	var bubble_parts: Dictionary = WandererBubbleView.attach(_figure_root, _bubble)
	_bubble_panel = bubble_parts["panel"] as Sprite3D
	_bubble_panel.visible = false
	_image_mi = MeshInstance3D.new()
	_image_mi.name = "RevealImage"
	var qm := QuadMesh.new()
	_image_mi.mesh = qm
	_image_mat = StandardMaterial3D.new()
	_image_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_image_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_image_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_image_mat.albedo_color = Color(1, 1, 1, 0)
	_image_mi.material_override = _image_mat
	_image_mi.visible = false
	add_child(_image_mi)


func bind_backdrop(backdrop: VillageBackdrop, mode_id: String) -> void:
	var layout := backdrop.get_layout()
	var same_layout := layout != null and layout == _layout_ref
	_backdrop = backdrop
	_mode_id = mode_id
	_bound = true
	if same_layout:
		return
	_layout_ref = layout
	_graph = WandererRouteGraph.build(layout, _params)
	_brain.setup(_params, _graph, _content, _rng)
	_brain.start()
	_hide_presentation()


func unbind() -> void:
	_backdrop = null
	_bound = false
	_layout_ref = null
	visible = false


func tick(delta: float, sim_paused: bool) -> void:
	if not _bound or _backdrop == null or not _backdrop.visible:
		visible = false
		return
	if not _params.enabled or not _enabled:
		visible = false
		return
	visible = true
	global_transform = _backdrop.global_transform
	var dt := delta
	if sim_paused and _params.pause_with_sim:
		dt = 0.0
	if dt > 0.0:
		_brain.tick(dt)
	_apply_figure()
	_apply_bubble_scale()
	_sync_presentation()


func set_enabled(on: bool) -> void:
	_enabled = on


func reseed(seed: int) -> void:
	_rng.seed = seed
	if _graph != null:
		_brain.setup(_params, _graph, _content, _rng)
		_brain.start()
		_hide_presentation()


func get_figure_global_position() -> Vector3:
	return _figure_root.global_position


func get_brain() -> WandererBrain:
	return _brain


## Backdrop-local XZ + image placement for QA cameras (does not require SHOWING).
func get_framing_local() -> Dictionary:
	var pl: Dictionary = _brain.image_placement
	if _brain.state == WandererBrain.State.SHOWING:
		pl = _brain.image_placement
	elif _content.image_count() > 0:
		var asp := _content.aspect(0)
		pl = _brain.preview_placement(asp)
	var fig_xz: Vector2 = pl.get("figure_xz", _brain.pos) if not pl.is_empty() else _brain.pos
	return {
		"figure_xz": fig_xz,
		"figure_head_y": _params.figure_height_m,
		"figure_yaw": _brain.yaw,
		"brain_state": _brain.state,
		"placement": pl,
		"hero_xz": _params.hero_xz,
		"has_bubble": not _brain.bubble_text.is_empty(),
	}


func debug_advance(seconds: float) -> void:
	var step := 1.0 / 30.0
	var left := seconds
	while left > 1e-6:
		var dt := minf(left, step)
		_brain.tick(dt)
		left -= dt
	_apply_figure()
	_sync_presentation()


func debug_advance_to(state_name: String, max_s: float = 900.0) -> bool:
	var target := -1
	for s in WandererBrain.State.values():
		if WandererBrain.state_name(s) == state_name:
			target = s
			break
	if target < 0:
		return false
	var elapsed := 0.0
	var step := 1.0 / 30.0
	while elapsed < max_s:
		if _brain.state == target:
			return true
		_brain.tick(step)
		elapsed += step
		_apply_figure()
		_sync_presentation()
	return _brain.state == target


func debug_dump() -> String:
	var b := _brain
	return "state=%s t=%.2f house=%d pos=%s present=%s yaw=%.1f bubble=\"%s\" alpha=%.2f image=%d quote_clock=%.1f cycles=%d" % [
		WandererBrain.state_name(b.state),
		b.state_t,
		b.target_house,
		b.pos,
		b.present_pos,
		rad_to_deg(b.yaw),
		b.bubble_text,
		b.bubble_alpha,
		b.image_index,
		b.quote_clock,
		b.cycles_completed,
	]


func _apply_figure() -> void:
	if not _brain.figure_visible:
		_figure_root.visible = false
		return
	_figure_root.visible = true
	_figure_root.position = Vector3(_brain.pos.x, 0.0, _brain.pos.y)
	_figure_root.rotation.y = _brain.yaw
	var pose := WandererFigure.pose(_params.walk_variant, _params, _brain.walk_phase, _brain.motion)
	WandererFigure.apply_pose(_figure, pose, _params)


func _apply_bubble_scale() -> void:
	var scale := VillagePresentationScale.camera_rig_scale_for_mode(_mode_id)
	_bubble.pixel_size = _params.bubble_pixel_size * scale


func _sync_presentation() -> void:
	var head_y := _params.figure_height_m
	_bubble.position = Vector3(0.0, head_y + _params.bubble_gap_m, 0.0)
	if _brain.bubble_text.is_empty():
		_bubble.text = ""
		_bubble.modulate.a = 0.0
		if _bubble_panel != null:
			_bubble_panel.visible = false
	else:
		_bubble.text = _brain.bubble_text
		WandererBubbleView.sync(_bubble_panel, _bubble, _brain.bubble_text, _brain.bubble_alpha)
	if _brain.state == WandererBrain.State.SHOWING and _brain.image_index >= 0 \
			and _brain.image_index < _content.image_count():
		var pl: Dictionary = _brain.image_placement
		var sz: Vector2 = pl.get("size", Vector2(4, 7))
		var centre: Vector3 = pl.get("centre", Vector3.ZERO)
		_image_mi.visible = true
		var qm := _image_mi.mesh as QuadMesh
		qm.size = sz
		_image_mi.position = centre
		_image_mi.rotation.y = float(pl.get("yaw", 0.0))
		_image_mat.albedo_texture = _content.textures[_brain.image_index]
		_image_mat.albedo_color.a = clampf(_brain.image_alpha, 0.0, 1.0)
		_image_mat.depth_draw_mode = StandardMaterial3D.DEPTH_DRAW_OPAQUE_ONLY if _params.image_depth_test \
			else StandardMaterial3D.DEPTH_DRAW_DISABLED
	else:
		_image_mi.visible = false
		_image_mat.albedo_color.a = 0.0


func _hide_presentation() -> void:
	_bubble.modulate.a = 0.0
	if _bubble_panel != null:
		_bubble_panel.visible = false
	_image_mi.visible = false
