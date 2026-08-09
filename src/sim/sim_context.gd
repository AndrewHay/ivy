class_name SimContext
extends RefCounted

var params: IvyParams
var env: IvyEnvironment
var surface: SurfaceQuery
var plant: PlantData
var tips: TipManager
var clock: SimClock


func _init(
	p: IvyParams,
	e: IvyEnvironment,
	s: SurfaceQuery,
	pl: PlantData,
	t: TipManager,
	c: SimClock
) -> void:
	params = p
	env = e
	surface = s
	plant = pl
	tips = t
	clock = c
