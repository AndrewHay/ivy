extends Node3D

const _StructureScenario = preload("res://src/world/structure_scenario.gd")
const _Hud = preload("res://src/ui/hud.gd")

@export var params: IvyParams
@export var mesh_scenario: Resource

## Set by `tools/run_ui_script.gd` before the scene enters the tree. A scripted run
## drives ticks explicitly, so the clock must not also free-run on the frame delta.
var script_driven: bool = false

@onready var _world: Node3D = $World
@onready var _sim: Node = $Sim
@onready var _plant_render: Node3D = $PlantRender
@onready var _ui: CanvasLayer = $UI

var _hud: Control


func _enter_tree() -> void:
	if mesh_scenario == null:
		return
	var world := get_node_or_null("World")
	if world == null:
		return
	world.mesh_scenario = mesh_scenario


func _ready() -> void:
	if params == null:
		params = load("res://src/params/ivy_params_default.tres") as IvyParams
	if mesh_scenario != null and _world.mesh_scenario == null:
		_world.mesh_scenario = mesh_scenario
		_world.ensure_mesh_scenario_loaded()
	await get_tree().process_frame
	var surface: SurfaceQuery = _world.get_surface_query(params)
	_sim.setup(
		params,
		surface,
		_world.get_mesh_scenario(),
		_world.get_seed_index(),
		_world.get_seed_anchors()
	)
	_plant_render.setup(params)
	_world.get_sky_sun().setup(_sim.solar)
	if not script_driven:
		_sim.get_clock().set_speed(SimClock.Speed.GROW)
		_hud = _Hud.new() as Control
		_hud.name = "Hud"
		_ui.add_child(_hud)
		_hud.setup(_world, _sim, params)


func _process(_delta: float) -> void:
	var clock: SimClock = _sim.get_clock()
	if clock == null:
		return
	_world.get_sky_sun().update(clock.game_day, clock.seconds_per_game_day())
	if _hud != null:
		_hud.refresh(clock, _world.get_sky_sun())
