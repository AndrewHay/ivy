class_name FieldViz
extends Node3D

## W-013 — per-cell D_L / crowding debug quads on the tower shell (AR-UI-2).

enum Mode { OFF, D_L, CROWDING }

const _DL_MAX := 30.0

var _sim: Node = null
var _mesh: MultiMeshInstance3D = null
var _mode: Mode = Mode.OFF
var _refresh_accum: float = 0.0


func setup(sim: Node) -> void:
	_sim = sim
	_mesh = MultiMeshInstance3D.new()
	_mesh.name = "FieldVizMesh"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = QuadMesh.new()
	(mm.mesh as QuadMesh).size = Vector2(0.05, 0.05)
	_mesh.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat
	add_child(_mesh)
	_mesh.visible = false


func toggle() -> void:
	match _mode:
		Mode.OFF:
			set_mode(Mode.D_L)
		Mode.D_L:
			set_mode(Mode.CROWDING)
		Mode.CROWDING:
			set_mode(Mode.OFF)


func set_mode(mode: Mode) -> void:
	_mode = mode
	_mesh.visible = mode != Mode.OFF
	if _mesh.visible:
		_refresh_mesh()


func get_mode() -> Mode:
	return _mode


func _process(delta: float) -> void:
	if _mode == Mode.OFF or _sim == null:
		return
	_refresh_accum += delta
	if _refresh_accum < 0.5:
		return
	_refresh_accum = 0.0
	_refresh_mesh()


func _refresh_mesh() -> void:
	var env = _sim.get("env")
	if env == null or not env.has_method("debug_field_cells"):
		return
	var cells: Array = env.debug_field_cells()
	var mm := _mesh.multimesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var row: Dictionary = cells[i]
		var pos: Vector3 = row["position"]
		var normal: Vector3 = row["normal"]
		var basis := Basis(Conv.tangent_basis(normal))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_color(i, _color_for(row))


func _color_for(row: Dictionary) -> Color:
	match _mode:
		Mode.D_L:
			var t := clampf(float(row["d_l"]) / _DL_MAX, 0.0, 1.0)
			return Color(t, 0.2, 1.0 - t, 0.85)
		Mode.CROWDING:
			var c := clampf(float(row["crowding"]), 0.0, 1.0)
			return Color(0.15, c, 0.15, 0.85)
		_:
			return Color.WHITE
