class_name SnapshotAnnotationModel
extends RefCounted

## Pure annotation list + normalised geometry (AR-SNAP-6). UI writes through this for tests.

const HIGHLIGHT := Color(1.0, 0.2, 0.75, 0.35)
const STROKE_WIDTH_PX := 8.0

var _entries: Array = []
var _next_id: int = 1


func entry_count() -> int:
	return _entries.size()


func add_box(norm_rect: Rect2, comment: String = "") -> void:
	_entries.append({
		"id": _next_id,
		"kind": "box",
		"comment": comment,
		"rect": rect_to_norm_dict(norm_rect),
	})
	_next_id += 1


func add_stroke(norm_points: PackedVector2Array, comment: String = "") -> void:
	var simplified := _simplify_stroke(norm_points)
	_entries.append({
		"id": _next_id,
		"kind": "stroke",
		"comment": comment,
		"points": _points_to_norm_arrays(simplified),
	})
	_next_id += 1


func undo() -> void:
	if _entries.is_empty():
		return
	_entries.pop_back()
	if _entries.is_empty():
		_next_id = 1
	else:
		_next_id = int(_entries[-1]["id"]) + 1


func clear() -> void:
	_entries.clear()
	_next_id = 1


func to_array() -> Array:
	return _entries.duplicate(true)


static func norm_point(p: Vector2, viewport_size: Vector2) -> Vector2:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ZERO
	return Vector2(p.x / viewport_size.x, p.y / viewport_size.y)


static func denorm_point(p: Vector2, viewport_size: Vector2) -> Vector2:
	return Vector2(p.x * viewport_size.x, p.y * viewport_size.y)


static func norm_rect_from_pixels(rect: Rect2, viewport_size: Vector2) -> Rect2:
	var p0 := norm_point(rect.position, viewport_size)
	var p1 := norm_point(rect.end, viewport_size)
	return Rect2(p0, p1 - p0)


static func pixel_rect_from_norm(norm: Rect2, viewport_size: Vector2) -> Rect2:
	var p0 := denorm_point(norm.position, viewport_size)
	var p1 := denorm_point(norm.end, viewport_size)
	return Rect2(p0, p1 - p0)


static func remap_norm_rect(norm: Rect2, from_size: Vector2, to_size: Vector2) -> Rect2:
	return norm_rect_from_pixels(pixel_rect_from_norm(norm, from_size), to_size)


static func rect_to_norm_dict(rect: Rect2) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


static func dict_to_norm_rect(d: Dictionary) -> Rect2:
	return Rect2(float(d.get("x", 0.0)), float(d.get("y", 0.0)),
		float(d.get("w", 0.0)), float(d.get("h", 0.0)))


static func _points_to_norm_arrays(points: PackedVector2Array) -> Array:
	var out: Array = []
	for p in points:
		out.append([p.x, p.y])
	return out


static func _norm_arrays_to_points(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for item in arr:
		if item is Array and item.size() >= 2:
			out.append(Vector2(float(item[0]), float(item[1])))
	return out


static func _simplify_stroke(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 64:
		return points
	var out := PackedVector2Array()
	var step := maxi(1, points.size() / 64)
	for i in range(0, points.size(), step):
		out.append(points[i])
	if out[-1] != points[-1]:
		out.append(points[-1])
	return out
