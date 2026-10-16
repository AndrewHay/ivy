class_name OverhangSpec
extends Resource

## Geometry parameters for the procedural eave-wall fixture (ivy-9us).
## Wall: 16×5×0.4 m (length × height × thickness).
## Eave slab: 1.0 m projection beyond the front face, 0.3 m thick.
## All faces are brick; seeds at the wall base, x in {-4,-2,0,2,4}.

@export var wall_length: float = 16.0
@export var wall_height: float = 5.0   # also the soffit height
@export var wall_thickness: float = 0.4
@export var slab_projection: float = 1.0
@export var slab_thickness: float = 0.3
@export var brick_physical_size: Vector2 = Vector2(1.80, 0.90)
