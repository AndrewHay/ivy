class_name PlantingTool
extends Node3D

signal planted

## Ground-click ivy placement with a glowing surface marker (M6).

const SEED_OFFSET := 0.01
const GROUND_BAND := 0.35

var _world: Node = null
var _sim: Node = null
var _params: IvyParams = null
var _camera: Camera3D = null
var _surface: SurfaceQuery = null
var _marker: MeshInstance3D
var _valid: bool = false
var _last_hit: SurfaceQuery.Hit
var _last_click_msg: String = "Left-click the green glow to plant"


func setup(world: Node, sim: Node, params: IvyParams, camera: Camera3D) -> void:
	_world = world
	_sim = sim
	_params = params
	_camera = camera
	_last_hit = SurfaceQuery.Hit.new()
	if world.has_method("get_surface_query"):
		_surface = world.get_surface_query(params)
	set_process_input(true)
	_build_marker()


func debug_status() -> String:
	var tip_n := 0
	if _sim != null and _sim.get("tips") != null:
		tip_n = (_sim.tips as TipManager).tips.size()
	var hover := "ok" if _valid else hover_reject_reason(_last_hit, _params)
	return "tips=%d | hover=%s | %s" % [tip_n, hover, _last_click_msg]


## Returns true when a seed was planted (caller should mark input handled).
func try_plant(event: InputEvent) -> bool:
	if _sim == null or _camera == null or _surface == null:
		_last_click_msg = "plant blocked: sim/camera/surface missing"
		return false
	if not event is InputEventMouseButton:
		return false
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or mb.is_echo():
		return false
	var hit := _raycast_at_screen(mb.position)
	var reason := hover_reject_reason(hit, _params)
	if not reason.is_empty():
		_last_click_msg = "rejected: %s" % reason
		print("[plant] ", _last_click_msg)
		return false
	if _sim.has_method("plant_at"):
		_sim.plant_at(hit.position, hit.normal)
		_last_click_msg = "planted at (%.2f, %.2f, %.2f)" % [hit.position.x, hit.position.y, hit.position.z]
		print("[plant] ", _last_click_msg)
		planted.emit()
		return true
	_last_click_msg = "sim has no plant_at()"
	return false


func poll_hover() -> void:
	if _camera == null or _surface == null or _params == null:
		return
	var mouse := _camera.get_viewport().get_mouse_position()
	_last_hit = _raycast_at_screen(mouse)
	_valid = hover_reject_reason(_last_hit, _params).is_empty()
	_update_marker(_valid, _last_hit)


func retire() -> void:
	set_process(false)
	set_process_input(false)
	if _marker != null:
		_marker.visible = false


func _input(event: InputEvent) -> void:
	if try_plant(event):
		get_viewport().set_input_as_handled()


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.name = "PlantMarker"
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	_marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 1.0, 0.45, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.9, 0.35)
	mat.emission_energy_multiplier = 2.2
	_marker.material_override = mat
	_marker.visible = false
	add_child(_marker)


func _process(_delta: float) -> void:
	poll_hover()


static func hover_reject_reason(hit: SurfaceQuery.Hit, params: IvyParams) -> String:
	if hit == null or params == null:
		return "not ready"
	if not hit.hit:
		return "no wall hit"
	if hit.position.y > params.ground_y_min + GROUND_BAND:
		return "too high (y=%.2f > %.2f)" % [hit.position.y, params.ground_y_min + GROUND_BAND]
	if hit.normal.y > 0.55:
		return "normal too flat"
	if not _is_climbable_material(hit.material_id):
		return "material %d not climbable" % hit.material_id
	return ""


static func _is_climbable_material(material_id: int) -> bool:
	match material_id:
		MaterialRegistry.GROUND, MaterialRegistry.OPENING_REVEAL, MaterialRegistry.INTERIOR, MaterialRegistry.GLASS:
			return false
		_:
			return true


func _raycast_at_screen(mouse: Vector2) -> SurfaceQuery.Hit:
	var miss := SurfaceQuery.Hit.new()
	if _surface == null or _camera == null:
		return miss
	var from := _camera.project_ray_origin(mouse)
	var to := from + _camera.project_ray_normal(mouse) * 80.0
	return _surface.raycast(from, to)


func _update_marker(valid: bool, hit: SurfaceQuery.Hit) -> void:
	if not valid or hit == null:
		_marker.visible = false
		return
	_marker.visible = true
	var mat := _marker.material_override as StandardMaterial3D
	if mat != null:
		var glow := Color(0.15, 0.95, 0.4)
		mat.albedo_color = Color(glow.r, glow.g, glow.b, 0.85)
		mat.emission = glow * 0.8
	_marker.global_position = hit.position + hit.normal * SEED_OFFSET
