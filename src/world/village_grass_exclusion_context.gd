class_name VillageGrassExclusionContext
extends RefCounted

## Path polylines: Array of Array[Vector2] — VillageBackdrop.path_polylines().
var path_segments: Array = []
var path_stones: Array[Transform3D] = []
var bush_transforms: Array[Transform3D] = []
## Callable(Vector2) -> bool; margin baked in (SD-GRASS-1 COTTAGE_MARGIN).
var is_inside_cottage: Callable


static func for_village(
		path_stones: Array[Transform3D],
		bush_transforms: Array[Transform3D]) -> VillageGrassExclusionContext:
	var ctx := VillageGrassExclusionContext.new()
	ctx.path_segments = VillageBackdrop.path_polylines()
	ctx.path_stones = path_stones
	ctx.bush_transforms = bush_transforms
	const MARGIN := 0.35  # SD-GRASS-1 COTTAGE_MARGIN
	ctx.is_inside_cottage = func(p: Vector2) -> bool:
		return VillageBackdrop.inside_any_cottage(p, MARGIN)
	return ctx
