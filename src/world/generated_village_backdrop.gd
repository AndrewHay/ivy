## GeneratedVillageBackdrop — seeded procedural backdrop (ivy-80z S4).
##
## Overrides _make_layout() to return VillageLayout.generate(village_seed) so the
## VillageBackdrop base class builds the two-ring cottage layout, wider lawn/treeline,
## and all scatter — with paths=[] / edges=[] until S3 lands the network.
##
## Set village_seed BEFORE add_child so that _make_layout() is called with the right seed
## from _ready() (AR-VG-WIRE). Use set_village_seed() for the explicit setter.
class_name GeneratedVillageBackdrop
extends VillageBackdrop

## Seeded LCG seed for this backdrop. Normalised to [0, 0x7FFFFFFF] by set_village_seed().
var _village_seed: int = 0


## Set the seed before the scene is added to the tree.
## Normalises to positive 31-bit range matching VillageLayout.generate() expectations.
func set_village_seed(seed: int) -> void:
	_village_seed = seed & 0x7FFFFFFF


## Virtual override — returns a generated layout for _village_seed.
## Called from VillageBackdrop._ready() via _make_layout().
func _make_layout() -> VillageLayout:
	return VillageLayout.generate(_village_seed)
