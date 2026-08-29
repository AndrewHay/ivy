extends Node3D

const TowerSdfScript = preload("res://src/world/tower_sdf.gd")
const MeshSdfScript = preload("res://src/world/mesh_sdf.gd")
const SurfaceQueryScript = preload("res://src/world/surface_query.gd")
const StructureBodyScript = preload("res://src/world/structure_body.gd")
const StructureScenarioScript = preload("res://src/world/structure_scenario.gd")
const SeedAnchorsScript = preload("res://src/world/seed_anchors.gd")

@onready var _tower: Tower = $Tower
@onready var sky_sun: SkySun = $SkySun
@onready var _camera_rig: Node3D = $CameraRig

var surface: SurfaceQuery
var tower_spec: TowerSpec
var mesh_scenario  # StructureScenario
var seed_index: int = 0

var _structure  # StructureBody
var _mesh_sdf  # MeshSdf
var _tower_built: bool = false
var _seed_anchors  # SeedAnchors

## CamSun local origin y when the rig sits at the tower — horizontal cameras aim here.
const _CANONICAL_CAM_AIM_Y := 2.0


func _ready() -> void:
	tower_spec = load("res://src/world/tower_spec_default.tres") as TowerSpec
	ensure_mesh_scenario_loaded()


func ensure_mesh_scenario_loaded() -> void:
	if mesh_scenario != null:
		if _structure == null:
			_activate_mesh_scenario(mesh_scenario)
		return
	# SG-1: build the tower exactly once. `_structure` stays null on the procedural
	# path, so without this guard a second call reassigns the collision shape after
	# `main.gd` has already awaited its physics frame — the light bake then raycasts
	# a shape the physics server has not committed, and the canonical run loses ~4%
	# of its growth.
	if not _tower_built:
		_tower_built = true
		_tower.build_from_spec(tower_spec, true)


func get_sky_sun() -> SkySun:
	return sky_sun


func uses_mesh_backend() -> bool:
	return mesh_scenario != null


func get_mesh_scenario():
	return mesh_scenario


func get_seed_index() -> int:
	return seed_index


func get_seed_anchors():
	return _seed_anchors


func set_seed_index(index: int) -> void:
	seed_index = index


func get_surface_query(params: IvyParams) -> SurfaceQuery:
	if surface != null:
		return surface
	ensure_mesh_scenario_loaded()
	if _structure == null and mesh_scenario != null:
		push_error("World: mesh scenario failed to load")
		return null
	surface = SurfaceQueryScript.new()
	var space := get_world_3d().direct_space_state
	if mesh_scenario != null:
		var sdf := MeshSdfScript.new()
		sdf.load_from_file(mesh_scenario.sdf_path)
		if not sdf.verify_provenance(mesh_scenario.collision_glb):
			return null
		_mesh_sdf = sdf
		surface.setup(
			space,
			_structure,
			sdf,
			_structure.face_material,
			params
		)
	else:
		surface.setup(
			space,
			_tower,
			TowerSdfScript.new(tower_spec),
			_tower.face_material,
			params
		)
		if _seed_anchors == null:
			_seed_anchors = SeedAnchorsScript.new()
			_seed_anchors.build(surface, tower_spec)
	return surface


func _activate_mesh_scenario(scenario) -> void:
	if scenario.get_script() != StructureScenarioScript:
		push_error("World: expected StructureScenario")
		return
	# Halt on an invalid scenario instead of building a StructureBody from bad
	# paths: leaving `_structure` null (with `mesh_scenario` already set by the
	# caller) makes `get_surface_query`'s "mesh scenario failed to load" guard
	# fire cleanly, rather than surfacing a confusing failure deep inside
	# `StructureBody.build` on a missing collision_glb/sdf_path.
	var errors: PackedStringArray = scenario.validate()
	if not errors.is_empty():
		for err in errors:
			push_error("StructureScenario: %s" % err)
		return
	mesh_scenario = scenario
	seed_index = scenario.seed_index
	_tower.visible = false
	_tower.collision_layer = 0
	for child in _tower.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	_structure = StructureBodyScript.new()
	_structure.name = "Structure"
	add_child(_structure)
	_structure.build(scenario.collision_glb, scenario.hero_glb)
	_apply_scenario_camera_framing(scenario)


func _apply_scenario_camera_framing(scenario) -> void:
	if _camera_rig == null:
		return
	var pivot: Vector3 = scenario.resolve_camera_pivot()
	# Translate X/Z to centre the structure; lift the rig so CamSun (y=2 local) aims at pivot.y.
	_camera_rig.position = Vector3(pivot.x, pivot.y - _CANONICAL_CAM_AIM_Y, pivot.z)
