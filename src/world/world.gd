extends Node3D

const TowerScript = preload("res://src/world/tower.gd")
const TowerSdfScript = preload("res://src/world/tower_sdf.gd")
const SurfaceQueryScript = preload("res://src/world/surface_query.gd")
const TowerSpecScript = preload("res://src/world/tower_spec.gd")

@onready var _camera: Camera3D = $CameraRig/CamSun
@onready var sky_sun: SkySun = $SkySun

var surface: SurfaceQuery
var tower_spec: TowerSpec


func _ready() -> void:
	tower_spec = load("res://src/world/tower_spec_default.tres") as TowerSpec
	var tower := $Tower
	tower.build_from_spec(tower_spec, true)
	_camera.current = true


func get_sky_sun() -> SkySun:
	return sky_sun


func get_surface_query(params: IvyParams) -> SurfaceQuery:
	if surface == null:
		surface = SurfaceQuery.new()
		var tower := $Tower
		surface.setup(
			get_world_3d().direct_space_state,
			tower,
			TowerSdf.new(tower_spec),
			tower.face_material,
			params
		)
	return surface
