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


## Forget everything drawn so far. Call whenever the plant data is replaced (Clear ivy, a new
## session): the high-water marks below are indices into the old plant, so leaving them set
## would hide a new, shorter vine until it outgrew the old one.
func reset() -> void:
	_seg_hw = 0
	_frozen_hw = 0
	_stem.reset()
	# Leaf buffers only exist once setup() has built them.
	for leaves in [_leaves_static, _leaves_growing]:
		if leaves.multimesh != null:
			leaves.multimesh.visible_instance_count = 0


func push_wind(wind: AmbientWind) -> void:
	if wind == null:
		return
	var dir := wind.get_horizontal_direction()
	var strength := wind.get_effective_strength() * 0.35
	var phase := wind.get_phase()
	for leaves in [_leaves_static, _leaves_growing]:
		if leaves == null or leaves.material_override == null:
			continue
		var mat := leaves.material_override as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("wind_direction_xz", dir)
		mat.set_shader_parameter("wind_strength", strength)
		mat.set_shader_parameter("wind_phase", phase)
		mat.set_shader_parameter("wind_freq_scale", 0.42)
		mat.set_shader_parameter("wind_amplitude", 0.06)


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
