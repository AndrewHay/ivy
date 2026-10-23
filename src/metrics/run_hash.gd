class_name RunHash
extends RefCounted

## AS-4 / SD-RNG-5 canonical run fingerprint (AR-RNG-5).


static func of(plant: PlantData, tips: TipManager) -> String:
	var h := 0
	h = Hash64.mix(h, tips.live_count())
	h = Hash64.mix(h, tips.tips.size())
	h = Hash64.mix(h, plant.segment_count())
	h = Hash64.mix(h, plant.leaf_count())
	h = Hash64.mix(h, _f64_bits(plant.total_length))
	for i in plant.leaf_count():
		var origin := Vector3(
			plant.leaf_xform[i * 12 + 3],
			plant.leaf_xform[i * 12 + 7],
			plant.leaf_xform[i * 12 + 11],
		)
		h = Hash64.mix(h, _f64_bits(origin.x))
		h = Hash64.mix(h, _f64_bits(origin.y))
		h = Hash64.mix(h, _f64_bits(origin.z))
	return "%08x" % (h & 0xFFFFFFFF)


static func _f64_bits(v: float) -> int:
	var arr := PackedFloat64Array([v])
	var bytes := arr.to_byte_array()
	var bits := 0
	for i in mini(bytes.size(), 8):
		bits = (bits << 8) | bytes[i]
	return bits
