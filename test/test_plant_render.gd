extends GutTest

const PlantRender = preload("res://src/render/plant_render.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")


func _append_dummy_leaf(plant: PlantData, tip_id: int, s_at: float) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT * 0.08, Vector3.UP * 0.1, Vector3.FORWARD), Vector3.ZERO)
	plant.append_leaf(xf, Color.WHITE, Vector4(0, 0, 0, 1), tip_id, s_at, 0.01, 1.0)


func test_promote_mature_leaves_respects_growing_cap() -> void:
	var params := IvyParams.new()
	var plant := PlantData.new()
	var expand := params.leaf_expand_distance
	for i in range(PlantRender.GROWING_LEAF_CAP + 5):
		_append_dummy_leaf(plant, i, 0.0)
	var pr := PlantRender.new()
	pr._params = params
	var tip_shoot := {}
	for i in range(plant.leaf_count()):
		tip_shoot[i] = expand * 0.25
	pr._promote_mature_leaves(plant, tip_shoot)
	assert_lte(plant.leaf_count() - plant.leaf_frozen_count, PlantRender.GROWING_LEAF_CAP,
		"force-freeze must keep the growing window within GROWING_LEAF_CAP")
