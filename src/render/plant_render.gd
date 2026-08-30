extends Node3D

const GROWING_LEAF_CAP := 600

@onready var _stem: StemMeshBuilder = $StemChunks
@onready var _leaves_static: LeafRenderer = $LeavesStatic
@onready var _leaves_growing: LeafRenderer = $LeavesGrowing

var _params: IvyParams
var _seg_hw: int = 0
var _frozen_hw: int = 0


func setup(params: IvyParams) -> void:
	_params = params
	_seg_hw = 0
	_frozen_hw = 0
	_stem.setup(params)
	_leaves_static.setup(params, params.leaf_cap, false)
	_leaves_growing.setup(params, GROWING_LEAF_CAP, true)


func sync(plant: PlantData, tip_shoot: Dictionary = {}) -> void:
	if plant.segment_count() > _seg_hw:
		_stem.sync_from(plant, _seg_hw)
		_seg_hw = plant.segment_count()
	_promote_mature_leaves(plant, tip_shoot)
	_leaves_static.sync_static_from(plant, _frozen_hw, tip_shoot)
	_frozen_hw = plant.leaf_frozen_count
	_leaves_growing.sync_growing_from(plant, tip_shoot, plant.leaf_frozen_count)


func _promote_mature_leaves(plant: PlantData, tip_shoot: Dictionary) -> void:
	var expand := _params.leaf_expand_distance
	while plant.leaf_count() - plant.leaf_frozen_count > GROWING_LEAF_CAP:
		plant.leaf_frozen_count += 1
	var i := plant.leaf_frozen_count
	while i < plant.leaf_count():
		var shoot: float = tip_shoot.get(
			plant.leaf_tip[i], plant.leaf_s_at_node[i] + expand)
		if LeafRenderer.should_freeze(shoot - plant.leaf_s_at_node[i], expand):
			plant.leaf_frozen_count += 1
			i += 1
		else:
			break
