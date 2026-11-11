extends SceneTree

const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestPlacement = preload("res://src/playground/forest_placement.gd")
const ForestPlaygroundCamera = preload("res://src/playground/forest_playground_camera.gd")
const HeroFog = preload("res://src/world/hero_fog.gd")


func _initialize() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var fb := layout.fog_begin
	var fe := layout.fog_end
	var prod := ForestPlaygroundCamera.count_trees_visible_in_camsun(
		ForestPlacement.forest_tree_xz(layout, ForestParams.production()),
		fb, fe, HeroFog.FogModel.WORLD_AROUND_HERO, 0.5)
	var old := ForestParams.production()
	old.variant = 5
	var leg := ForestPlaygroundCamera.count_trees_visible_in_camsun(
		ForestPlacement.forest_tree_xz(layout, old), fb, fe, HeroFog.FogModel.WORLD_AROUND_HERO, 0.5)
	print("=== v2 visibility seed=7 fog=%.1f..%.1f hero<=50%% ===" % [fb, fe])
	print("production: in_fov=%d visible=%d mean_haze=%.2f count=%d"
		% [prod["in_fov"], prod["visible"], prod["mean_haze"],
		ForestPlacement.forest_tree_xz(layout, ForestParams.production()).size()])
	print("legacy_v5: in_fov=%d visible=%d" % [leg["in_fov"], leg["visible"]])
	quit()
