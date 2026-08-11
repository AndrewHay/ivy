class_name PlantData
extends RefCounted

var seg_a: PackedVector3Array = PackedVector3Array()
var seg_b: PackedVector3Array = PackedVector3Array()
var seg_normal: PackedVector3Array = PackedVector3Array()
var seg_tip: PackedInt32Array = PackedInt32Array()
var seg_order: PackedInt32Array = PackedInt32Array()
var seg_s: PackedFloat32Array = PackedFloat32Array()
var total_length: float = 0.0

var leaf_xform: PackedFloat32Array = PackedFloat32Array()
var leaf_color: PackedFloat32Array = PackedFloat32Array()
var leaf_custom: PackedFloat32Array = PackedFloat32Array()
var leaf_tip: PackedInt32Array = PackedInt32Array()
var leaf_s_at_node: PackedFloat32Array = PackedFloat32Array()
var leaf_area: PackedFloat32Array = PackedFloat32Array()
## Experienced accumulated-light f_L at leaf creation (AR-METRIC-2).  Ranking key for LG-2' layer (b).
## Equal to the f_l argument passed to LeafPlacer.advance — no RNG draw, no new hash channel.
var leaf_light: PackedFloat32Array = PackedFloat32Array()
var leaf_frozen_count: int = 0


func append_segment(a: Vector3, b: Vector3, normal: Vector3, tip_id: int, order: int, s: float) -> void:
	seg_a.append(a)
	seg_b.append(b)
	seg_normal.append(normal)
	seg_tip.append(tip_id)
	seg_order.append(order)
	seg_s.append(s)
	total_length += float(a.distance_to(b))


func append_leaf(
	xform: Transform3D, color: Color, custom: Vector4, tip_id: int, s_at: float,
	area: float, light: float
) -> void:
	var b := xform.basis
	leaf_xform.append_array([
		b.x.x, b.x.y, b.x.z, xform.origin.x,
		b.y.x, b.y.y, b.y.z, xform.origin.y,
		b.z.x, b.z.y, b.z.z, xform.origin.z,
	])
	leaf_color.append_array([color.r, color.g, color.b, color.a])
	leaf_custom.append_array([custom.x, custom.y, custom.z, custom.w])
	leaf_tip.append(tip_id)
	leaf_s_at_node.append(s_at)
	leaf_area.append(area)
	leaf_light.append(light)


func segment_count() -> int:
	return seg_a.size()


func leaf_count() -> int:
	return leaf_tip.size()
