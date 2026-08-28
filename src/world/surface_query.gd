class_name SurfaceQuery
extends RefCounted

const MeshSdfScript = preload("res://src/world/mesh_sdf.gd")
const StructureBodyScript = preload("res://src/world/structure_body.gd")

class Hit:
	var hit: bool = false
	var position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var distance: float = INF
	var material_id: int = MaterialRegistry.BRICK_WALL
	var face_index: int = -1
	var refined: bool = true


var _space: PhysicsDirectSpaceState3D
var _body: CollisionObject3D
var _backend  # TowerSdf or MeshSdf — SD-MESH-1
var _backend_tag: String = "TowerSdf"
var _face_material: PackedByteArray
var _material_by_shape_index: bool = false
var _params: IvyParams


func setup(
	space: PhysicsDirectSpaceState3D,
	body: CollisionObject3D,
	backend,
	face_material: PackedByteArray,
	params: IvyParams
) -> void:
	_space = space
	_body = body
	_backend = backend
	_backend_tag = "MeshSdf" if backend.get_script() == MeshSdfScript else "TowerSdf"
	_face_material = face_material
	_material_by_shape_index = body != null and body.get_script() == StructureBodyScript
	_params = params


func backend_tag() -> String:
	return _backend_tag


func mesh_provenance() -> PackedByteArray:
	if _backend_tag == "MeshSdf":
		return (_backend as MeshSdf).provenance
	return PackedByteArray()


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
	result.material_id = _material_from_physics_hit(hit)
	return result


## Light-bake occlusion: MeshSdf marches the narrow-band field so open apertures
## without physics panels still leak; TowerSdf keeps physics raycasts (SG-1).
func occludes_bake_ray(from: Vector3, to: Vector3) -> bool:
	if _backend_tag == "MeshSdf":
		return _sdf_ray_occluded(from, to)
	return raycast(from, to).hit


func _sdf_ray_occluded(from: Vector3, to: Vector3) -> bool:
	var delta := to - from
	var dist := delta.length()
	if dist < 1e-5:
		return false
	var dir := delta / dist
	var t := 0.0
	var eps: float = _backend.h * 0.25
	var steps := 128
	while t < dist and steps > 0:
		var p := from + dir * t
		var phi: float = _backend.signed_distance(p)
		if phi < eps:
			return true
		var step := maxf(phi, eps)
		if step > dist - t:
			break
		t += step
		steps -= 1
	return false


func _material_from_physics_hit(physics_hit: Dictionary) -> int:
	var shape_idx := int(physics_hit.get("shape", 0))
	var face_idx := int(physics_hit.get("face_index", -1))
	if _material_by_shape_index:
		return material_at_face(shape_idx)
	return material_at_face(face_idx)


func signed_distance(p: Vector3) -> float:
	return _backend.signed_distance(p)


func surface_normal(p: Vector3) -> Vector3:
	if _backend_tag == "MeshSdf" and _space != null:
		var near := nearest(p)
		if near.hit:
			return near.normal
	return _backend.gradient_normalized(p)


func _orient_outward_normal(p: Vector3, n: Vector3) -> Vector3:
	var phi_out: float = _backend.signed_distance(p + n * 0.02)
	var phi_in: float = _backend.signed_distance(p - n * 0.02)
	if phi_out < phi_in:
		return -n
	return n


func nearest(p: Vector3) -> Hit:
	var result := Hit.new()
	var phi: float = _backend.signed_distance(p)
	var n: Vector3 = _backend.gradient_normalized(p)
	var q0: Vector3 = p - n * phi
	result.position = q0
	result.normal = n
	result.distance = absf(phi)
	result.hit = true
	result.material_id = MaterialRegistry.BRICK_WALL
	result.refined = false

	if _backend_tag == "MeshSdf" and _space != null:
		var ray_hit := _closest_mesh_hit(p, n)
		if ray_hit.hit:
			result.position = ray_hit.position
			result.normal = ray_hit.normal
			result.distance = p.distance_to(ray_hit.position)
			result.face_index = ray_hit.face_index
			result.material_id = ray_hit.material_id
			result.refined = true
	elif _space != null:
		var mat_hit := _material_probe_ray(p, n, phi)
		if mat_hit.hit:
			result.material_id = mat_hit.material_id
			result.face_index = mat_hit.face_index
	return result


func _material_probe_ray(p: Vector3, n: Vector3, phi: float) -> Hit:
	## W-044: resolve material_id via physics without moving the SDF nearest point
	## (TowerSdf path must keep position/normal for SG-1 bit identity).
	var toward_surface: Vector3 = n.normalized() if phi < 0.0 else -n.normalized()
	var reach := _primary_ray_reach(phi)
	var primary := raycast(p, p + toward_surface * reach)
	if primary.hit:
		return primary
	var sweep_reach := _axis_sweep_reach()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		var hit := raycast(p, p + axis * sweep_reach)
		if hit.hit:
			return hit
		hit = raycast(p, p - axis * sweep_reach)
		if hit.hit:
			return hit
	return Hit.new()


func _primary_ray_reach(phi: float) -> float:
	if _backend_tag == "MeshSdf":
		return absf(phi) + 2.0 * _backend.h
	return absf(phi) + 0.2


func _axis_sweep_reach() -> float:
	if _backend_tag == "MeshSdf":
		return maxf(_backend.h * 4.0, 0.2)
	return 0.2


func _closest_mesh_hit(p: Vector3, seed: Vector3) -> Hit:
	# SD-MESH-6: primary targeted ray from p toward q₀ = p − Φ·∇̂Φ, length |Φ| + 2h,
	# then axis sweep for best-accuracy and coverage of corners / mesh openings.
	# The fixed reach (0.2 m) undershoots when |Φ| > 0.10 m; the adaptive targeted ray
	# fixes that. The axis sweep still runs so the closest hit wins (the gradient can
	# be off-axis at corners, making the targeted ray slightly less accurate there).
	var phi: float = _backend.signed_distance(p)
	var n: Vector3 = seed if seed.length_squared() > 1e-8 else _backend.gradient_normalized(p)
	n = n.normalized()
	# Direction from p toward SDF-projected surface (q₀).
	var toward_surface: Vector3 = n if phi < 0.0 else -n

	var best := Hit.new()
	var best_d := INF

	# SD-MESH-6 targeted ray — adaptive length ensures the surface is always within reach.
	var primary := raycast(p, p + toward_surface * _primary_ray_reach(phi))
	if primary.hit and primary.distance < best_d:
		best_d = primary.distance
		best = primary

	# Axis sweep — covers corners/openings where the gradient is unreliable and provides
	# a more accurate hit when the axis aligns with the face normal.
	var reach: float = _axis_sweep_reach()
	var dirs: Array[Vector3] = []
	if seed.length_squared() > 1e-8:
		dirs.append(seed.normalized())
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		dirs.append(axis)
		dirs.append(-axis)
	for d in dirs:
		var dir := d.normalized()
		var hit := raycast(p, p + dir * reach)
		if hit.hit and hit.distance < best_d:
			best_d = hit.distance
			best = hit
		hit = raycast(p, p - dir * reach)
		if hit.hit and hit.distance < best_d:
			best_d = hit.distance
			best = hit

	if best.hit:
		best.normal = _orient_outward_normal(p, best.normal)
	return best


func tangent_basis_at(p: Vector3) -> Basis:
	return Conv.tangent_basis(surface_normal(p))


func material_at_face(face_index: int) -> int:
	if face_index < 0 or face_index >= _face_material.size():
		return MaterialRegistry.BRICK_WALL
	return _face_material[face_index]


func adhesion_suitability(material_id: int) -> float:
	return MaterialRegistry.adhesion(material_id)


## SD-MESH-7: physics distance to a mesh face can exceed the SDF phi by up to h/2
## due to discrete tessellation (vertices are not at exact SDF-zero locations).
## Add h/2 to the base contact threshold so a tip sitting on the mesh is never
## misclassified as FLOATING. For TowerSdf the analytical SDF is exact — no padding.
func effective_contact(base: float) -> float:
	if _backend_tag == "MeshSdf":
		return base + _backend.h * 0.5
	return base


func shell_bounds(margin: float) -> AABB:
	return _backend.bounds().grow(margin)


func project_to_shell(p: Vector3, _offset: float = 0.0) -> Vector3:
	var q := p
	var steps := 2 if _backend_tag == "MeshSdf" else 1
	for _i in steps:
		var phi: float = _backend.signed_distance(q)
		var n: Vector3 = _backend.gradient_normalized(q)
		q = q - n * phi
	return q
