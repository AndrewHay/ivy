class_name DebugSessionLog
extends RefCounted

## Append-only plant/param events for debug snapshot replay (AR-SNAP-2).

var plant_log: Array = []
var param_log: Array = []


func clear() -> void:
	plant_log.clear()
	param_log.clear()


func record_plant(tick: int, position: Vector3, normal: Vector3) -> void:
	plant_log.append({
		"tick": tick,
		"position": _vec3_array(position),
		"normal": _vec3_array(normal),
	})


func record_param(tick: int, name: String, value: Variant) -> void:
	param_log.append({
		"tick": tick,
		"name": name,
		"value": _encode_value(value),
	})


static func _vec3_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _encode_value(value: Variant) -> Variant:
	if value is Color:
		var c := value as Color
		return [c.r, c.g, c.b, c.a]
	return value
