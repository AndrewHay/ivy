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


## W-062 — SD-LEAF-6 tier accessors.
## Returns the health tier ("H" = healthy, "W" = weathered) for a given leaf id.
func tier_for(id: String) -> String:
	return str(_by_id[id].tier)


## Returns the fixed ordered list of ids in a tier.
## H = ["a","c","e"]  W = ["b","d","f"]  — fixed order is required for reproducibility
## (SD-RNG-6: tier and variant draws are hash-based; the id order must not change between runs).
func ids_in_tier(tier: String) -> PackedStringArray:
	if tier == "H":
		return PackedStringArray(["a", "c", "e"])
	return PackedStringArray(["b", "d", "f"])


## Reverse-lookup: given an atlas UV rect (as stored in PlantData.leaf_custom), return the
## leaf id. Used by LG-2b to recover the tier from simulation output (SD-METRIC-7f).
## Comparison uses is_equal_approx() to tolerate float32 round-trip in PlantData.
## Returns "" if no id matches.
func id_for_rect(rect: Vector4) -> String:
	for leaf: Dictionary in _data.leaves:
		var lid: String = str(leaf.id)
		var r := rect_for(lid)
		if rect.is_equal_approx(r):
			return lid
	return ""
