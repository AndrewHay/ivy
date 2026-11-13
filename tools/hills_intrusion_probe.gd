## QA probe: hill heights on lawn grid + hill-forest site_ok for seeds 1/7/12/240424020.
extends Node

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

const SEEDS: Array[int] = [1, 7, 12, 240424020]


func _ready() -> void:
	var any_fail := false
	for seed in SEEDS:
		if _probe_seed(seed):
			any_fail = true
	print("=== INTRUSION_PROBE %s ===" % ("FAIL" if any_fail else "PASS"))
	get_tree().quit(1 if any_fail else 0)


func _probe_seed(seed: int) -> bool:
	var layout := VillageLayout.generate(seed)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	if layout.fallback:
		print("seed %d: FALLBACK layout — skipped" % seed)
		return false
	var params := HillsParams.production()
	var t_seed := HillsHeightfield.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var y_lawn := VillageBackdrop.LAWN_GROUND_Y_OFFSET
	var failed := false
	for ix in range(9):
		for iz in range(9):
			var fx := float(ix) / 8.0
			var fz := float(iz) / 8.0
			var r := layout.lawn_radius * fx * 0.98
			var p := g + Vector2(sin(fz * TAU) * r, cos(fz * TAU) * r)
			var y := HillsHeightfield.sample_y(p, layout, params, t_seed)
			if y > y_lawn + 0.15:
				print("  LAWN spike seed=%d p=%s y=%.3f" % [seed, p, y])
				failed = true
	var backdrop := ForestPlacement.forest_tree_xz(layout, ForestParams.production())
	var xforms := HillsForestPlacement.hill_forest_transforms(layout, params, t_seed, backdrop)
	for t in xforms:
		var xz := Vector2(t.origin.x, t.origin.z)
		if not HillsForestPlacement.site_ok_hill(xz, layout, params, backdrop):
			print("  FOREST site_ok FAIL seed=%d at %s" % [seed, xz])
			failed = true
	print(
		"seed %d: lawn=%s forest_n=%d site_ok=%s"
		% [seed, ("FAIL" if failed else "ok"), xforms.size(), ("FAIL" if failed else "ok")])
	return failed
