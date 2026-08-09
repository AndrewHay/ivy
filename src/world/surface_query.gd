class_name SurfaceQuery
extends RefCounted

class Hit:
	var hit: bool = false
	var position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var distance: float = INF
	var material_id: int = MaterialRegistry.BRICK_WALL
	var face_index: int = -1


var _space: PhysicsDirectSpaceState3D
var _tower_body: CollisionObject3D
var _sdf: TowerSdf
var _face_material: PackedByteArray
var _params: IvyParams


func setup(
	space: PhysicsDirectSpaceState3D,
	tower_body: CollisionObject3D,
	sdf: TowerSdf,
	face_material: PackedByteArray,
	params: IvyParams
) -> void:
	_space = space
	_tower_body = tower_body
	_sdf = sdf
	_face_material = face_material
	_params = params


func raycast(from: Vector3, to: Vector3) -> Hit:
	var result := Hit.new()
	if _space == null:
		return result
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	var hit := _space.intersect_ray(query)
	if hit.is_empty():
		return result
	result.hit = true
	result.position = hit.position
	result.normal = hit.normal
	result.distance = from.distance_to(hit.position)
	result.face_index = int(hit.face_index)
	result.material_id = material_at_face(result.face_index)
	return result


func signed_distance(p: Vector3) -> float:
	return _sdf.signed_distance(p)


func surface_normal(p: Vector3) -> Vector3:
	return _sdf.gradient_normalized(p)


func nearest(p: Vector3) -> Hit:
	var result := Hit.new()
	var phi := _sdf.signed_distance(p)
	var n := _sdf.gradient_normalized(p)
	result.position = p - n * phi
	result.normal = n
	result.distance = absf(phi)
	result.hit = true
	result.material_id = MaterialRegistry.BRICK_WALL
	return result


func tangent_basis_at(p: Vector3) -> Basis:
	return Conv.tangent_basis(surface_normal(p))


func material_at_face(face_index: int) -> int:
	if face_index < 0 or face_index >= _face_material.size():
		return MaterialRegistry.BRICK_WALL
	return _face_material[face_index]


func adhesion_suitability(material_id: int) -> float:
	return MaterialRegistry.adhesion(material_id)


## World region the environment field must allocate over, given a shell margin.
func shell_bounds(margin: float) -> AABB:
	return _sdf.bounds().grow(margin)


func project_to_shell(p: Vector3, _offset: float = 0.0) -> Vector3:
	var phi := _sdf.signed_distance(p)
	var n := _sdf.gradient_normalized(p)
	return p - n * phi
