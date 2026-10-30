class_name VillageGrassExclusionContext
extends RefCounted

## Path polylines: Array of Array[Vector2] — VillageBackdrop.path_polylines().
var path_segments: Array = []
var path_stones: Array[Transform3D] = []
var bush_transforms: Array[Transform3D] = []
## Callable(Vector2) -> bool; margin baked in (SD-GRASS-1 COTTAGE_MARGIN).
var is_inside_cottage: Callable


## Build a context from explicit layout data. Used by VillageBackdrop instance code
## so both classic and generated backdrops share the same construction path.
## Classic callers use for_village() which delegates here with the statics.
static func for_layout(
		path_segments: Array,
		is_inside_cottage: Callable,
		path_stones: Array[Transform3D],
		bush_transforms: Array[Transform3D]) -> VillageGrassExclusionContext:
	var ctx := VillageGrassExclusionContext.new()
	ctx.path_segments = path_segments
	ctx.path_stones = path_stones
	ctx.bush_transforms = bush_transforms
	ctx.is_inside_cottage = is_inside_cottage
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
		bush_transforms)
