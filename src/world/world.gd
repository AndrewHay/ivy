extends Node3D

const TowerSdfScript = preload("res://src/world/tower_sdf.gd")
const WallSdfScript = preload("res://src/world/wall_sdf.gd")
const MeshSdfScript = preload("res://src/world/mesh_sdf.gd")
const OverhangSdfScript = preload("res://src/world/overhang_sdf.gd")
const OverhangWallScript = preload("res://src/world/overhang_wall.gd")
const OverhangSpecScript = preload("res://src/world/overhang_spec.gd")
const SurfaceQueryScript = preload("res://src/world/surface_query.gd")
const StructureBodyScript = preload("res://src/world/structure_body.gd")
const StructureScenarioScript = preload("res://src/world/structure_scenario.gd")
const SeedAnchorsScript = preload("res://src/world/seed_anchors.gd")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")

@onready var _tower: Tower = $Tower
@onready var _wall: Wall = $Wall
@onready var sky_sun: SkySun = $SkySun
@onready var _camera_rig: Node3D = $CameraRig
@onready var _village_backdrop: Node3D = $VillageBackdrop

var surface: SurfaceQuery
var tower_spec: TowerSpec
var wall_spec: WallSpec
var mesh_scenario  # StructureScenario
var seed_index: int = 0

var _structure  # StructureBody
var _mesh_sdf  # MeshSdf
var _procedural_id: String = "cylinder"
var _tower_built: bool = false
var _wall_built: bool = false
var _seed_anchors  # SeedAnchors
var _overhang_wall: StaticBody3D = null  # dynamically created for "overhang"
var _overhang_spec = null  # OverhangSpec instance
var _overhang_built: bool = false

## CamSun local origin y when the rig sits at the tower — horizontal cameras aim here.
const _CANONICAL_CAM_AIM_Y := 2.0


func _ready() -> void:
	tower_spec = load("res://src/world/tower_spec_default.tres") as TowerSpec
	wall_spec = load("res://src/world/wall_spec_default.tres") as WallSpec
	# Tower/structure geometry is built when the player picks a building (M6 picker).


func ensure_mesh_scenario_loaded() -> void:
	if mesh_scenario != null:
		if _structure == null:
			_activate_mesh_scenario(mesh_scenario)
		return
	# SG-1: build procedural geometry exactly once. `_structure` stays null on the
	# procedural path, so without this guard a second call reassigns the collision
	# shape after `main.gd` has already awaited its physics frame — the light bake
	# then raycasts a shape the physics server has not committed, and the canonical
	# run loses ~4% of its growth.
	if _procedural_id == "test_wall":
		if not _wall_built:
			_wall_built = true
			_wall.build_from_spec(wall_spec, true)
	elif _is_overhang_id(_procedural_id):
		if not _overhang_built:
			_overhang_built = true
			_ensure_overhang_wall()
			_overhang_wall.build_from_spec(_overhang_spec, true)
	else:
		if not _tower_built:
			_tower_built = true
			_tower.build_from_spec(tower_spec, true)


func load_building(building_id: String) -> void:
	_teardown_active_building()
	if BuildingCatalog.is_procedural(building_id):
		_procedural_id = building_id
		if building_id == "test_wall":
			_show_procedural_wall()
		elif _is_overhang_id(building_id):
			_show_procedural_overhang()
		else:
			_show_procedural_tower()
		_camera_rig.position = Vector3.ZERO
		return
	var scenario := BuildingCatalog.scenario_for(building_id)
	if scenario == null:
		push_error("World: unknown building '%s'" % building_id)
		_show_procedural_tower()
		return
	_activate_mesh_scenario(scenario)


func _teardown_active_building() -> void:
	surface = null
	_mesh_sdf = null
	_seed_anchors = null
	if _structure != null:
		_structure.queue_free()
		_structure = null
	mesh_scenario = null
	seed_index = 0
	if _village_backdrop != null:
		_village_backdrop.visible = false


func _show_procedural_wall() -> void:
	_tower.visible = false
	_tower.collision_layer = 0
	for child in _tower.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	_wall.visible = true
	_wall.collision_layer = 1
	for child in _wall.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = false
	if not _wall_built:
		_wall_built = true
		_wall.build_from_spec(wall_spec, true)
	if _overhang_wall != null:
		_overhang_wall.visible = false
		_overhang_wall.collision_layer = 0
		for child in _overhang_wall.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = true


func _show_procedural_overhang() -> void:
	_tower.visible = false
	_tower.collision_layer = 0
	for child in _tower.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	_wall.visible = false
	_wall.collision_layer = 0
	for child in _wall.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	_ensure_overhang_wall()
	_overhang_wall.visible = true
	_overhang_wall.collision_layer = 1
	for child in _overhang_wall.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = false
	if not _overhang_built:
		_overhang_built = true
		_overhang_wall.build_from_spec(_overhang_spec, true)


func _ensure_overhang_wall() -> void:
	if _overhang_wall != null:
		return
	_overhang_spec = OverhangSpecScript.new()
	var ow := OverhangWallScript.new()
	ow.name = "OverhangWall"
	add_child(ow)
	_overhang_wall = ow


## Returns true for any building id that uses the OverhangSdf geometry.
## Both 'overhang' (traversal ON) and 'overhang_spread' (traversal OFF) share the same wall.
func _is_overhang_id(id: String) -> bool:
	return id == "overhang" or id == "overhang_spread"


func _show_procedural_tower() -> void:
	_wall.visible = false
	_wall.collision_layer = 0
	for child in _wall.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	_tower.visible = true
	_tower.collision_layer = 1
	for child in _tower.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = false
	if not _tower_built:
		_tower_built = true
		_tower.build_from_spec(tower_spec, true)
	if _overhang_wall != null:
		_overhang_wall.visible = false
		_overhang_wall.collision_layer = 0
		for child in _overhang_wall.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = true


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


func get_orbit_pivot() -> Vector3:
	if mesh_scenario != null:
		return mesh_scenario.resolve_camera_pivot()
	if _procedural_id == "test_wall":
		return Vector3(0.0, wall_spec.height * 0.5, 0.0)
	if _is_overhang_id(_procedural_id):
		if _overhang_spec != null:
			return Vector3(0.0, _overhang_spec.wall_height * 0.5, 0.0)
		return Vector3(0.0, 2.5, 0.0)
	return Vector3(0.0, tower_spec.height * 0.5, 0.0)


func get_debug_camera_zoom_bounds() -> Vector2:
	if _procedural_id == "test_wall":
		return DebugCamera.wall_zoom_bounds(wall_spec)
	if _is_overhang_id(_procedural_id):
		## L-1: derive zoom bounds from the overhang spec dimensions (16×5 m)
		## rather than the default wall_spec (20×10 m).
		if _overhang_spec != null:
			var ow_spec := WallSpec.new()
			ow_spec.length = _overhang_spec.wall_length
			ow_spec.height = _overhang_spec.wall_height
			ow_spec.thickness = _overhang_spec.wall_thickness
			return DebugCamera.wall_zoom_bounds(ow_spec)
		return DebugCamera.wall_zoom_bounds(wall_spec)
	return DebugCamera.tower_zoom_bounds(tower_spec)


func set_seed_index(index: int) -> void:
	seed_index = index


func get_surface_query(params: IvyParams) -> SurfaceQuery:
	# Set eave traversal flags unconditionally on every call so an external params
	# mutation (e.g. dev overlay between two get_surface_query calls) is always
	# corrected — even when the cached surface is returned by the early-return below.
	# 'overhang' is the only id with traversal true; all others stay false.
	var want_traversal := BuildingCatalog.traversal_for(_procedural_id)
	params.eave_traversal_enabled = want_traversal
	params.feeler_thinning_enabled = want_traversal
	if surface != null:
		return surface
	ensure_mesh_scenario_loaded()
	if _structure == null and mesh_scenario != null:
		push_error("World: mesh scenario failed to load")
		return null
	var sq: SurfaceQuery = SurfaceQueryScript.new()
	var space := get_world_3d().direct_space_state
	if mesh_scenario != null:
		var sdf := MeshSdfScript.new()
		sdf.load_from_file(mesh_scenario.sdf_path)
		if not sdf.verify_provenance(mesh_scenario.collision_glb):
			push_error("World: SDF provenance mismatch for %s" % mesh_scenario.collision_glb)
			return null
		_mesh_sdf = sdf
		sq.setup(
			space,
			_structure,
			sdf,
			_structure.face_material,
			params
		)
	else:
		if _procedural_id == "test_wall":
			sq.setup(
				space,
				_wall,
				WallSdfScript.new(wall_spec),
				_wall.face_material,
				params
			)
		elif _is_overhang_id(_procedural_id):
			if _overhang_wall == null or _overhang_spec == null:
				push_error("World: overhang not built; call load_building('overhang') first")
				return null
			sq.setup(
				space,
				_overhang_wall,
				OverhangSdfScript.new(_overhang_spec),
				_overhang_wall.face_material,
				params
			)
		else:
			sq.setup(
				space,
				_tower,
				TowerSdfScript.new(tower_spec),
				_tower.face_material,
				params
			)
			if _seed_anchors == null:
				_seed_anchors = SeedAnchorsScript.new()
				_seed_anchors.build(sq, tower_spec)
	surface = sq
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
	_wall.visible = false
	_wall.collision_layer = 0
	for child in _wall.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	if _overhang_wall != null:
		_overhang_wall.visible = false
		_overhang_wall.collision_layer = 0
		for child in _overhang_wall.get_children():
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
	# Reposition the shared backdrop to the active hero pivot (x, z; y=0 stays on ground).
	if _village_backdrop != null:
		_village_backdrop.position = Vector3(pivot.x, 0.0, pivot.z)
		_village_backdrop.visible = true
