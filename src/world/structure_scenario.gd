class_name StructureScenario
extends Resource

## W-089 — binds one structure's hero mesh, collision proxy, baked SDF, and seed points.

const MeshSdf = preload("res://src/world/mesh_sdf.gd")

@export var scenario_id: String = "square"
@export var display_name: String = "Square building"
@export var collision_glb: String = ""
@export var hero_glb: String = ""
@export var sdf_path: String = ""
@export var seed_positions: PackedVector3Array = PackedVector3Array()
@export var seed_normals: PackedVector3Array = PackedVector3Array()
@export var seed_index: int = 0
## World-space pivot the canonical CameraRig translates to (AR-SCENE-3). When zero,
## resolve_camera_pivot() falls back to the baked SDF mesh_aabb centre.
@export var camera_pivot: Vector3 = Vector3.ZERO


func resolve_camera_pivot() -> Vector3:
	if camera_pivot != Vector3.ZERO:
		return camera_pivot
	if sdf_path.is_empty() or not FileAccess.file_exists(sdf_path):
		return Vector3.ZERO
	var sdf := MeshSdf.new()
	sdf.load_from_file(sdf_path)
	return sdf.mesh_aabb.get_center()


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if collision_glb.is_empty():
		errors.append("collision_glb is required")
	elif not FileAccess.file_exists(collision_glb):
		errors.append("collision_glb missing: %s" % collision_glb)
	if sdf_path.is_empty():
		errors.append("sdf_path is required")
	elif not FileAccess.file_exists(sdf_path):
		errors.append("sdf_path missing: %s" % sdf_path)
	if seed_positions.size() < 2:
		errors.append("need at least two seed_positions (SG-5)")
	if seed_normals.size() != seed_positions.size():
		errors.append("seed_normals must match seed_positions count")
	return errors
