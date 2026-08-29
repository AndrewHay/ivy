class_name StemMeshBuilder
extends Node3D

const SIDES := 5
const CHUNK_SEGMENTS := 128
## SD-STEM / R-4: two interior subdivisions → three rings per logical segment.
const CR_SUBDIVS := 2

var _params: IvyParams
var _hot_st: SurfaceTool
var _hot_mesh: ArrayMesh
var _hot_instance: MeshInstance3D
var _hot_count: int = 0
var _mat: Material


func setup(params: IvyParams) -> void:
	_params = params
	_mat = StandardMaterial3D.new()
	(_mat as StandardMaterial3D).albedo_color = Color(0.25, 0.35, 0.18)
	_begin_hot_chunk()


## SD-STEM radius: branch-order taper (baked at emit) × tip-distance taper (frozen at segment s).
static func stem_radius(params: IvyParams, order: int, s_from_tip: float) -> float:
	var order_scale := 1.0 / (1.0 + params.stem_order_falloff * float(order))
	var tip_scale := clampf(s_from_tip / params.stem_tip_taper, 0.35, 1.0)
	return params.stem_radius_base * order_scale * tip_scale


static func catmull_rom_point(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


static func catmull_rom_tangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	return 0.5 * (
		(-p0 + p2)
		+ (4.0 * p0 - 10.0 * p1 + 8.0 * p2 - 2.0 * p3) * t
		+ (-3.0 * p0 + 9.0 * p1 - 9.0 * p2 + 3.0 * p3) * t2
	).normalized()


func sync_from(plant: PlantData, from_index: int) -> void:
	for i in range(from_index, plant.segment_count()):
		# Catmull-Rom needs the following segment; emit the previous one (AR-RENDER-2 lag).
		if i >= 1:
			_emit_segment(plant, i - 1)
	if _hot_count > 0:
		_hot_mesh = _hot_st.commit()
		_hot_instance.mesh = _hot_mesh
		_hot_instance.material_override = _mat


func _emit_segment(plant: PlantData, seg_idx: int) -> void:
	# Lag: the trailing segment of each live tip stays undrawn until the next one lands.
	if seg_idx + 1 >= plant.segment_count():
		return
	var tip_id := plant.seg_tip[seg_idx]
	var p1 := plant.seg_a[seg_idx]
	var p2 := plant.seg_b[seg_idx]
	var ctrl := _control_points(plant, seg_idx, tip_id, p1, p2)
	var p0: Vector3 = ctrl[0]
	var p3: Vector3 = ctrl[1]
	var order := plant.seg_order[seg_idx]
	var s_end := plant.seg_s[seg_idx]
	var seg_len := p1.distance_to(p2)
	var s_start := s_end - seg_len
	if seg_idx > 0 and plant.seg_tip[seg_idx - 1] == tip_id:
		s_start = plant.seg_s[seg_idx - 1]

	var ring_count := CR_SUBDIVS + 1
	var prev_right := Vector3.ZERO
	var prev_up := Vector3.ZERO
	var prev_center := Vector3.ZERO
	var prev_radius := 0.0
	for ring in range(ring_count + 1):
		var t := float(ring) / float(CR_SUBDIVS)
		var center := catmull_rom_point(p0, p1, p2, p3, t)
		var tangent := catmull_rom_tangent(p0, p1, p2, p3, t)
		var s_here := lerpf(s_start, s_end, t)
		var radius := stem_radius(_params, order, s_here)
		var frame := _transport_frame(tangent, prev_right, prev_up, ring == 0)
		prev_right = frame[0]
		prev_up = frame[1]
		if ring > 0:
			_add_ring_pair(prev_center, prev_right, prev_up, prev_radius, center, prev_right, prev_up, radius)
		prev_center = center
		prev_radius = radius
	_hot_count += 1
	if _hot_count >= CHUNK_SEGMENTS:
		_seal_hot_chunk()


static func _control_points(
	plant: PlantData, seg_idx: int, tip_id: int, p1: Vector3, p2: Vector3
) -> Array:
	var p0 := p1
	if seg_idx > 0 and plant.seg_tip[seg_idx - 1] == tip_id:
		p0 = plant.seg_a[seg_idx - 1]
	else:
		p0 = p1 - (p2 - p1)
	var p3 := p2
	if seg_idx + 1 < plant.segment_count() and plant.seg_tip[seg_idx + 1] == tip_id:
		p3 = plant.seg_b[seg_idx + 1]
	else:
		p3 = p2 + (p2 - p1)
	return [p0, p3]


static func _transport_frame(
	tangent: Vector3, prev_right: Vector3, prev_up: Vector3, first_ring: bool
) -> Array:
	if first_ring or prev_right.length_squared() < 1e-8:
		var up := Conv.UP
		if absf(tangent.dot(up)) > 0.95:
			up = Vector3.RIGHT
		var right := tangent.cross(up).normalized()
		up = right.cross(tangent).normalized()
		return [right, up]
	var right := prev_right
	var up := prev_up
	var axis := prev_right.cross(tangent)
	if axis.length_squared() > 1e-8:
		var angle := prev_right.angle_to(tangent)
		right = prev_right.rotated(axis.normalized(), angle).normalized()
		up = prev_up.rotated(axis.normalized(), angle).normalized()
	else:
		right = tangent.cross(up).normalized()
		up = right.cross(tangent).normalized()
	return [right, up]


func _add_ring_pair(
	a: Vector3, right_a: Vector3, up_a: Vector3, r_a: float,
	b: Vector3, right_b: Vector3, up_b: Vector3, r_b: float
) -> void:
	for i in range(SIDES):
		var ang0 := TAU * float(i) / float(SIDES)
		var ang1 := TAU * float(i + 1) / float(SIDES)
		var o0a := right_a * cos(ang0) * r_a + up_a * sin(ang0) * r_a
		var o1a := right_a * cos(ang1) * r_a + up_a * sin(ang1) * r_a
		var o0b := right_b * cos(ang0) * r_b + up_b * sin(ang0) * r_b
		var o1b := right_b * cos(ang1) * r_b + up_b * sin(ang1) * r_b
		var n0 := o0a.normalized()
		var n1 := o1a.normalized()
		_hot_st.set_normal(n0)
		_hot_st.add_vertex(a + o0a)
		_hot_st.set_normal(n1)
		_hot_st.add_vertex(a + o1a)
		_hot_st.set_normal(n1)
		_hot_st.add_vertex(b + o1b)
		_hot_st.set_normal(n0)
		_hot_st.add_vertex(a + o0a)
		_hot_st.set_normal(n1)
		_hot_st.add_vertex(b + o1b)
		_hot_st.set_normal(n0)
		_hot_st.add_vertex(b + o0b)


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
