## VillageTerrainGrassHost — production lawn grass on the terrain playground (ivy-82zn.14.7).
## A VillageBackdrop whose _ready builds nothing: the playground feeds it the layout and the 1 m
## terrain LUT, then calls the production grass steps (exclusion context, blade Y bake, 6 m blade
## chunks, wispy accents). No grass logic lives here, so the playground cannot drift from the game.
extends "res://src/world/village_backdrop.gd"


func _ready() -> void:
	pass  # The playground drives the build; no cottages, paths, hills or scatter.


func configure(layout: VillageLayout, terrain_lut: Dictionary) -> void:
	## terrain_lut: VillageTerrain.build_sample_lut at the production grass cell (1 m), or {} for
	## flat / classic (production then leaves blade Y at 0, same as here).
	_layout = layout
	_sample_lut = terrain_lut


func grass_context() -> VillageGrassExclusionContext:
	## Same path stones, bushes and context the game builds in VillageBackdrop._ready.
	var path_stones := VillageScatterPositions.path_stone_transforms(
		_layout.path_polylines(), Callable(self, "_reject_path_stone_xz"),
		_layout.stone_seed, _layout.min_stone_spacing)
	var filler_g := _layout.hamlet_centre_xz if _layout.is_generated else Vector2.ZERO
	var bushes := VillageScatterPositions.bush_common_positions(
		_layout.cottages, _layout.bush_filler_inner, _layout.bush_filler_outer, filler_g)
	return _lawn_grass_context(path_stones, bushes)


func add_blade_chunk(tufts: Array[Transform3D], generated_grass: bool) -> void:
	## One 6 m chunk's blades: production Y bake from the LUT, then the production chunk builder.
	_bake_grass_y_tilt(tufts)
	_add_grass_blade_chunks(tufts, generated_grass)


func add_accents(ctx: VillageGrassExclusionContext) -> void:
	_add_grass_accents(ctx)
