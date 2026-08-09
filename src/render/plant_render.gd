extends Node3D

@onready var _stem: StemMeshBuilder = $StemChunks
@onready var _leaves: LeafRenderer = $LeavesGrowing

var _params: IvyParams
var _seg_hw: int = 0
var _leaf_hw: int = 0


func setup(params: IvyParams) -> void:
	_params = params
	_stem.setup(params)
	_leaves.setup(params)


func sync(plant: PlantData) -> void:
	if plant.segment_count() > _seg_hw:
		_stem.sync_from(plant, _seg_hw)
		_seg_hw = plant.segment_count()
	if plant.leaf_count() > _leaf_hw:
		_leaves.sync_from(plant)
		_leaf_hw = plant.leaf_count()
