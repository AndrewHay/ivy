extends SceneTree

const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")

const SEEDS: Array[int] = [1, 7, 12, 240424020]


func _hash_positions(xf: Array) -> String:
	var parts: PackedStringArray = []
	for t in xf:
		var tr := t as Transform3D
		parts.append(
			"%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
				tr.origin.x, tr.origin.y, tr.origin.z,
				tr.basis.get_euler().y, tr.basis.get_scale().x, tr.basis.get_scale().y])
	parts.sort()
	var joined := ",".join(parts)
	return "%d|%s" % [xf.size(), joined.sha256_text()]


func _initialize() -> void:
	for seed in SEEDS:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			push_error("fallback seed %d" % seed)
			continue
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var xf := VillageScatterPositions.forest_tree_positions(layout)
		print("BASELINE seed=%d count=%d hash=%s" % [seed, xf.size(), _hash_positions(xf)])
	quit(0)
