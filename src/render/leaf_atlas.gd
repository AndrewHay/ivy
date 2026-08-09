class_name LeafAtlas
extends RefCounted

var _data: Dictionary = {}
var _by_id: Dictionary = {}


func _init() -> void:
	var txt := FileAccess.get_file_as_string("res://assets/plants/ivy/LeafSet017/leaf_atlas.json")
	_data = JSON.parse_string(txt)
	for leaf in _data.leaves:
		_by_id[leaf.id] = leaf


func rect_for(id: String) -> Vector4:
	var leaf: Dictionary = _by_id[id]
	var uv: Array = leaf.rect_uv
	return Vector4(uv[0], uv[1], uv[2], uv[3])


func aspect_for(id: String) -> float:
	return float(_by_id[id].aspect)


func alpha_fill_for(id: String) -> float:
	return float(_by_id[id].alpha_fill)
