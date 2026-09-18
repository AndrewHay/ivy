class_name WallSdf
extends RefCounted

var spec: WallSpec


func _init(s: WallSpec) -> void:
	spec = s


func signed_distance(p: Vector3) -> float:
	var center := Vector3(0.0, spec.height * 0.5, -spec.thickness * 0.5)
	var half_extents := Vector3(spec.length * 0.5, spec.height * 0.5, spec.thickness * 0.5)
	var q := (p - center).abs() - half_extents
	var outside := q.max(Vector3.ZERO).length()
	var inside := minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
	return outside + inside


func bounds() -> AABB:
	return AABB(
		Vector3(-spec.length * 0.5, 0.0, -spec.thickness),
		Vector3(spec.length, spec.height, spec.thickness)
	)


func gradient(p: Vector3) -> Vector3:
	const EPS := 0.001
	return Vector3(
		signed_distance(p + Vector3(EPS, 0, 0)) - signed_distance(p - Vector3(EPS, 0, 0)),
		signed_distance(p + Vector3(0, EPS, 0)) - signed_distance(p - Vector3(0, EPS, 0)),
		signed_distance(p + Vector3(0, 0, EPS)) - signed_distance(p - Vector3(0, 0, EPS))
	) / (2.0 * EPS)


func gradient_normalized(p: Vector3) -> Vector3:
	var g := gradient(p)
	if g.length_squared() < 1e-10:
		return Conv.UP
	return g.normalized()
