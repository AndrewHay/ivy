class_name VillageGrassExclusionContext
extends RefCounted

## Path polylines: Array of Array[Vector2] — VillageBackdrop.path_polylines().
var path_segments: Array = []
var path_stones: Array[Transform3D] = []
var bush_transforms: Array[Transform3D] = []
## Callable(Vector2) -> bool; margin baked in (SD-GRASS-1 COTTAGE_MARGIN).
var is_inside_cottage: Callable
## Grass grid origin (classic pivot); generated hamlet uses VILLAGE_GREEN_G.
var grid_centre_xz: Vector2 = Vector2.ZERO
## Hero fringe / footprint reference (classic pivot; generated door stoop).
var hero_reference_xz: Vector2 = Vector2.ZERO
## When true, use generated blade budget (48k) and G-centred ring (ivy-3l6-C).
var generated_grass: bool = false
## Pre-grown cottage rects for hot-path rejection (falls back to is_inside_cottage when empty).
var cottage_exclusion_rects: Array[Rect2] = []


## Build a context from explicit layout data. Used by VillageBackdrop instance code
## so both classic and generated backdrops share the same construction path.
## Classic callers use for_village() which delegates here with the statics.
static func for_layout(
		path_segments: Array,
		is_inside_cottage: Callable,
		path_stones: Array[Transform3D],
		bush_transforms: Array[Transform3D],
		grid_centre_xz: Vector2 = Vector2.ZERO,
		hero_reference_xz: Vector2 = Vector2.ZERO,
		generated_grass: bool = false,
		cottages: Array = []) -> VillageGrassExclusionContext:
	var ctx := VillageGrassExclusionContext.new()
	ctx.path_segments = path_segments
	ctx.path_stones = path_stones
	ctx.bush_transforms = bush_transforms
	ctx.is_inside_cottage = is_inside_cottage
	ctx.grid_centre_xz = grid_centre_xz
	ctx.hero_reference_xz = hero_reference_xz
	ctx.generated_grass = generated_grass
	if not cottages.is_empty():
		const MARGIN := 0.35  # SD-GRASS-1 COTTAGE_MARGIN
		for spec in cottages:
			ctx.cottage_exclusion_rects.append(
				VillageBackdrop.cottage_exterior_rect(spec).grow(MARGIN))
	return ctx


## Unchanged convenience wrapper for classic callers (test_village_grass_scatter.gd, etc.).
## Delegates to for_layout with the COTTAGES + path_polylines() statics so the
## output is byte-identical to the pre-refactor implementation.
static func for_village(
		path_stones: Array[Transform3D],
		bush_transforms: Array[Transform3D]) -> VillageGrassExclusionContext:
	const MARGIN := 0.35  # SD-GRASS-1 COTTAGE_MARGIN
	return for_layout(
		VillageBackdrop.path_polylines(),
		func(p: Vector2) -> bool: return VillageBackdrop.inside_any_cottage(p, MARGIN),
		path_stones,
		bush_transforms,
		Vector2.ZERO,
		Vector2.ZERO,
		false,
		VillageBackdrop.COTTAGES)
