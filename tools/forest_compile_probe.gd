extends SceneTree


func _initialize() -> void:
	var fp := load("res://src/playground/forest_placement.gd")
	var fpr := load("res://src/playground/forest_params.gd")
	print("fp=", fp, " fpr=", fpr)
	if fp == null or fpr == null:
		quit(1)
		return
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var params = fpr.call("production")
	var xf = fp.call("forest_tree_positions", layout, params)
	print("count=", (xf as Array).size())
	quit(0)
