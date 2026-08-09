class_name StemMeshBuilder
extends Node3D

const SIDES := 5
const CHUNK_SEGMENTS := 128

var _params: IvyParams
var _hot_st: SurfaceTool
var _hot_mesh: ArrayMesh
var _hot_instance: MeshInstance3D
var _hot_count: int = 0
var _radius: float = 0.006
var _mat: Material


func setup(params: IvyParams) -> void:
	_params = params
	_radius = params.stem_radius_base
	_mat = StandardMaterial3D.new()
	(_mat as StandardMaterial3D).albedo_color = Color(0.25, 0.35, 0.18)
	_begin_hot_chunk()


func sync_from(plant: PlantData, from_index: int) -> void:
	for i in range(from_index, plant.segment_count()):
		_append_segment(plant.seg_a[i], plant.seg_b[i])
	# Flush the partial hot chunk every call so growing tip segments are visible.
	# Completed chunks were already sealed by _append_segment; only the hot tail needs
	# an explicit commit.  SurfaceTool.commit() in Godot 4 preserves the accumulated
	# data, so subsequent appends continue cleanly.
	if _hot_count > 0:
		_hot_mesh = _hot_st.commit()
		_hot_instance.mesh = _hot_mesh
		_hot_instance.material_override = _mat


func _append_segment(a: Vector3, b: Vector3) -> void:
	var dir := (b - a).normalized()
	var up := Conv.UP
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var right := dir.cross(up).normalized()
	up = right.cross(dir).normalized()
	for i in range(SIDES):
		var ang0 := TAU * float(i) / float(SIDES)
		var ang1 := TAU * float(i + 1) / float(SIDES)
		var o0 := right * cos(ang0) * _radius + up * sin(ang0) * _radius
		var o1 := right * cos(ang1) * _radius + up * sin(ang1) * _radius
		var n0 := o0.normalized()
		var n1 := o1.normalized()
		# triangle 1
		_hot_st.set_normal(n0)
		_hot_st.add_vertex(a + o0)
		_hot_st.set_normal(n1)
		_hot_st.add_vertex(a + o1)
		_hot_st.set_normal(n1)
		_hot_st.add_vertex(b + o1)
		# triangle 2
		_hot_st.set_normal(n0)
		_hot_st.add_vertex(a + o0)
		_hot_st.set_normal(n1)
		_hot_st.add_vertex(b + o1)
		_hot_st.set_normal(n0)
		_hot_st.add_vertex(b + o0)
	_hot_count += 1
	if _hot_count >= CHUNK_SEGMENTS:
		_seal_hot_chunk()


func _begin_hot_chunk() -> void:
	_hot_st = SurfaceTool.new()
	_hot_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_hot_count = 0
	_hot_instance = MeshInstance3D.new()
	add_child(_hot_instance)


func _seal_hot_chunk() -> void:
	_hot_mesh = _hot_st.commit()
	_hot_instance.mesh = _hot_mesh
	_hot_instance.material_override = _mat
	_begin_hot_chunk()
