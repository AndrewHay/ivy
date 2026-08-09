class_name Hash64
extends RefCounted


static func mix(a: int, b: int) -> int:
	var x: int = a ^ (b + 0x9E3779B9 + ((a << 6) & 0x7FFFFFFF) + (a >> 2))
	x = (x ^ (x >> 16)) * 0x85EBCA6B
	x = (x ^ (x >> 13)) * 0xC2B2AE35
	return x ^ (x >> 16)


static func unit_float(a: int, b: int = 0, c: int = 0) -> float:
	var h := mix(mix(a, b), c)
	return float(h & 0xFFFFFF) / float(0x1000000)


static func jitter_vec3(tip_id: int, seg: int, channel: int) -> Vector3:
	var jx := unit_float(tip_id, seg, channel * 3 + 0) * 2.0 - 1.0
	var jy := unit_float(tip_id, seg, channel * 3 + 1) * 2.0 - 1.0
	var jz := unit_float(tip_id, seg, channel * 3 + 2) * 2.0 - 1.0
	var v := Vector3(jx, jy, jz)
	if v.length_squared() < 1e-8:
		return Vector3.ZERO
	var mag := unit_float(tip_id, seg, channel * 3 + 99)
	return v.normalized() * mag
