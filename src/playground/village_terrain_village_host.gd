## VillageTerrainVillageHost — the production village on the terrain playground (ivy-82zn.14.8).
## A VillageBackdrop whose _ready builds nothing: the playground hands it the layout, the
## playground terrain params / seed and the 1 m terrain LUT, then runs the production build steps
## of VillageBackdrop._ready one per frame (cottages, path stones, pond water + bank, bushes,
## flowers / plants / clover). Outer hills, pine forest and fog are left out. No village logic
## lives here, so the playground cannot drift from the game.
extends "res://src/world/village_backdrop.gd"

## Build steps in VillageBackdrop._ready order, one per frame. "pond_heights" is the only sliced
## step: it evaluates, a budget at a time, the exact sample_y along the bank outer outline that
## the production water level needs (VillageTerrain.pond_bank_outline_min_y, ~0.5 s in one go), so
## "pond" then runs the production _add_village_pond without the freeze. ivy-82zn.14.10: the bank
## ring itself is draped on the rendered lawn (LUT reads), so it needs no exact heights any more.
const STEPS := ["cottages", "paths", "pond_heights", "pond", "bushes", "flowers"]

var _path_stones: Array[Transform3D] = []
var _path_stones_next := -1
var _bank_pts: PackedVector2Array = PackedVector2Array()
var _bank_next := 0
var _bank_min := INF


func _ready() -> void:
	pass  # The playground drives the build.


func configure(layout: VillageLayout, params: VillageTerrainParams, t_seed: int,
		terrain_lut: Dictionary) -> void:
	## terrain_lut: VillageTerrain build_sample_lut at the production 1 m cell (same as
	## _ensure_terrain_sample_lut), or {} for flat / classic.
	_layout = layout
	_terrain_params = params
	_terrain_seed = t_seed
	_sample_lut = terrain_lut


func step_count() -> int:
	return STEPS.size()


func build_step(i: int, budget_usec: int = -1) -> bool:
	## Runs step i; returns true when it is finished (paths and pond_heights can need more frames).
	## budget_usec < 0 = no limit.
	match STEPS[i]:
		"pond_heights":
			return _step_pond_heights(budget_usec)
		"cottages":
			_build_cottages()
		"paths":
			# Sliced: production bakes stone Y on the exact sample_y (ivy-82zn.14.10).
			if _path_stones_next < 0:
				_path_stones = VillageScatterPositions.path_stone_transforms(
					_layout.path_polylines(), Callable(self, "_reject_path_stone_xz"),
					_layout.stone_seed, _layout.min_stone_spacing)
				_path_stones_next = 0
			_path_stones_next = _lift_transforms_y(_path_stones, _path_stones_next, budget_usec)
			if _path_stones_next < _path_stones.size():
				return false
			_create_paths_from_transforms(_path_stones)
		"pond":
			_add_village_pond()
		"bushes":
			var filler_g := _layout.hamlet_centre_xz if _layout.is_generated else Vector2.ZERO
			var bushes := VillageScatterPositions.bush_common_positions(
				_layout.cottages, _layout.bush_filler_inner, _layout.bush_filler_outer, filler_g)
			_bake_y_lut(bushes)
			_create_scatter("res://assets/backdrop/pieces/Bush_Common.gltf",
				"Scatter_Bush_Common", bushes, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			_patch_bush_green_material()
		"flowers":
			var flower_layers := VillageScatterPositions.flower_cluster_layers()
			_bake_y_lut_dict(flower_layers)
			_scatter_piece_layers(flower_layers, "Scatter_Flower",
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var petal_layers := VillageScatterPositions.petal_layers(_path_stones)
			_bake_y_lut_dict(petal_layers)
			_scatter_piece_layers(petal_layers, "Scatter_Petal",
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var plant_layers := VillageScatterPositions.plant_layers()
			_bake_y_lut_dict(plant_layers)
			_scatter_piece_layers(plant_layers, "Scatter_Plant",
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var clover_layers := VillageScatterPositions.clover_layers()
			_bake_y_lut_dict(clover_layers)
			_scatter_piece_layers(clover_layers, "Scatter_Clover",
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			_sample_lut = {}  # as production: not needed after the build
	return true


func _step_pond_heights(budget_usec: int) -> bool:
	if not _layout.is_generated or _terrain_params == null or _terrain_params.variant == 1:
		return true  # production bank is flat here: no per-vertex sampling
	if _bank_pts.is_empty():
		# Same outline pond_bank_outline_min_y walks (the layout's pond, not the active shape).
		_bank_pts = VillagePondShape.at(_layout.pond_center).bank_outer_outline_world_xz()
		_bank_next = 0
		_bank_min = INF
	var t_end := Time.get_ticks_usec() + budget_usec
	while _bank_next < _bank_pts.size():
		_bank_min = minf(_bank_min,
			VillageTerrain.sample_y(_bank_pts[_bank_next], _layout, _terrain_params, _terrain_seed))
		_bank_next += 1
		if budget_usec >= 0 and Time.get_ticks_usec() >= t_end:
			return _bank_next >= _bank_pts.size()
	return true


func _pond_outline_min_y() -> float:
	## The lowest bank-outline height the pond_heights step gathered (same sample_y calls as
	## VillageTerrain.pond_bank_outline_min_y); NAN (compute in one go) if the step did not run.
	return _bank_min if _bank_next > 0 and _bank_next >= _bank_pts.size() and is_finite(_bank_min) else NAN
