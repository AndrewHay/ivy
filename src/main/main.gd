extends Node3D

@export var params: IvyParams

## Set by `tools/run_ui_script.gd` before the scene enters the tree. A scripted run
## drives ticks explicitly, so the clock must not also free-run on the frame delta.
var script_driven: bool = false

@onready var _world: Node3D = $World
@onready var _sim: Node = $Sim
@onready var _plant_render: Node3D = $PlantRender


func _ready() -> void:
	if params == null:
		params = load("res://src/params/ivy_params_default.tres") as IvyParams
	await get_tree().process_frame
	var surface: SurfaceQuery = _world.get_surface_query(params)
	_sim.setup(params, surface)
	_plant_render.setup(params)
	_world.get_sky_sun().setup(_sim.solar)
	if not script_driven:
		_sim.get_clock().set_speed(SimClock.Speed.GROW)


func _process(_delta: float) -> void:
	var clock: SimClock = _sim.get_clock()
	if clock == null:
		return
	_world.get_sky_sun().update(clock.game_day, clock.seconds_per_game_day())
