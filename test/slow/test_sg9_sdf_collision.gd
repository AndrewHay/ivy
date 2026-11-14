## SG-9(c) — baked MeshSdf agrees with the collision mesh it was baked from (SD-OPEN-28).
extends GutTest

const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const StructureBody = preload("res://src/world/structure_body.gd")
const StructureScenario = preload("res://src/world/structure_scenario.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")

## DESIGN.md SG-9(c): |Φ| on collision faces; Φ negative 0.10 m inside solid.
const SG9C_SURFACE_PHI_TOL := 0.01
const SG9C_INSIDE_DEPTH := 0.10
const SG9C_RAY_SAMPLES := 400  ## Matches offline audit ray budget (ivy-b1e.3).
const SG9C_MIN_VALID_SAMPLES := 350
## An inward probe only counts where the solid is at least this thick behind the face:
## roof tiles, cone rims and sills are thinner than SG9C_INSIDE_DEPTH, so 0.10 m "in"
## is already out the other side (ivy-b1e.3).
const SG9C_MIN_SOLID_THICKNESS := 0.20

const _PLAYABLE_SCENARIOS: Array[String] = [
	"res://assets/structures/scenarios/ivy.tres",
	"res://assets/structures/scenarios/square.tres",
	"res://assets/structures/scenarios/tower.tres",
	"res://assets/structures/scenarios/surface_wall.tres",
]


func _make_scenario_fixture(scenario_path: String) -> Dictionary:
	var scenario := load(scenario_path) as StructureScenario
	assert_not_null(scenario, scenario_path)
	if not FileAccess.file_exists(scenario.collision_glb):
		return {"skip": true, "id": scenario.scenario_id}
	# Freed by the caller before the next scenario: the playable structures overlap in
	# world space, so a body left alive answers the next structure's rays (ivy-b1e.3).
	var body := StructureBody.new()
	add_child(body)
	body.build(scenario.collision_glb, "")
	await get_tree().physics_frame
	var sdf := MeshSdf.new()
	sdf.load_from_file(scenario.sdf_path)
	assert_true(
		sdf.verify_provenance(scenario.collision_glb),
		"%s provenance must match %s" % [scenario.sdf_path, scenario.collision_glb]
	)
	var sq := SurfaceQuery.new()
	sq.setup(
		body.get_world_3d().direct_space_state,
		body,
		sdf,
		body.face_material,
		IvyParams.new()
	)
	return {"skip": false, "id": scenario.scenario_id, "sq": sq, "sdf": sdf, "body": body}


func _free_fixture(fixture: Dictionary) -> void:
	var body: Node = fixture.get("body")
	if body != null and is_instance_valid(body):
		remove_child(body)
		body.free()
	await get_tree().physics_frame


## True when no other collision face lies within SG9C_MIN_SOLID_THICKNESS behind the hit,
## i.e. the inward probe is still inside the piece it entered.
func _solid_behind(sq: SurfaceQuery, position: Vector3, normal: Vector3) -> bool:
	var back := sq.raycast(
		position - normal * SG9C_MIN_SOLID_THICKNESS,
		position - normal * 0.002
	)
	return not back.hit


func _in_sdf_band(phi: float, band: float) -> bool:
	return absf(phi) < band - 0.02


func _refined_abs_phi(sq: SurfaceQuery, sdf: MeshSdf, hit) -> Dictionary:
	var n: Vector3 = hit.normal.normalized()
	var best_p: Vector3 = hit.position
	var best_abs: float = absf(sq.signed_distance(hit.position))
	for step in range(-200, 201):
		var p: Vector3 = hit.position + n * (float(step) * 0.0005)
		var phi: float = sq.signed_distance(p)
		if not _in_sdf_band(phi, sdf.band):
			continue
		var a: float = absf(phi)
		if a < best_abs:
			best_abs = a
			best_p = p
	return {"position": best_p, "normal": n, "abs_phi": best_abs}


func _collect_collision_ray_hits(sq: SurfaceQuery, sdf: MeshSdf, target: int) -> Array:
	var hits: Array = []
	var seen: Dictionary = {}
	var center: Vector3 = sdf.mesh_aabb.get_center()
	var extent: float = sdf.mesh_aabb.size.length() * 0.65
	const GOLDEN := PI * (3.0 - sqrt(5.0))
	var attempts: int = maxi(target * 80, 800)
	for i in attempts:
		if hits.size() >= target:
			break
		var t: float = float(i) / float(attempts)
		var y: float = 1.0 - 2.0 * t
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var theta: float = GOLDEN * float(i)
		var dir := Vector3(cos(theta) * r, y, sin(theta) * r).normalized()
		var hit := sq.raycast(center + dir * extent, center - dir * extent)
		if not hit.hit:
			continue
		var view := (center + dir * extent - hit.position).normalized()
		if hit.normal.dot(view) < 0.0:
			hit.normal = -hit.normal
		var key := Vector3(
			snappedf(hit.position.x, 0.04),
			snappedf(hit.position.y, 0.04),
			snappedf(hit.position.z, 0.04)
		)
		if seen.has(key):
			continue
		seen[key] = true
		hits.append(hit)
	var aabb: AABB = sdf.mesh_aabb
	for face in 6:
		for u in range(0, 21):
			for v in range(0, 21):
				if hits.size() >= target:
					return hits
				var fu: float = float(u) / 10.0
				var fv: float = float(v) / 10.0
				var from: Vector3
				var to: Vector3
				match face:
					0:
						from = Vector3(aabb.position.x + aabb.size.x + 2.0, aabb.position.y + aabb.size.y * fu, aabb.position.z + aabb.size.z * fv)
						to = Vector3(aabb.position.x - 2.0, from.y, from.z)
					1:
						from = Vector3(aabb.position.x - 2.0, aabb.position.y + aabb.size.y * fu, aabb.position.z + aabb.size.z * fv)
						to = Vector3(aabb.position.x + aabb.size.x + 2.0, from.y, from.z)
					2:
						from = Vector3(aabb.position.x + aabb.size.x * fu, aabb.position.y + aabb.size.y + 2.0, aabb.position.z + aabb.size.z * fv)
						to = Vector3(from.x, aabb.position.y - 2.0, from.z)
					3:
						from = Vector3(aabb.position.x + aabb.size.x * fu, aabb.position.y - 2.0, aabb.position.z + aabb.size.z * fv)
						to = Vector3(from.x, aabb.position.y + aabb.size.y + 2.0, from.z)
					4:
						from = Vector3(aabb.position.x + aabb.size.x * fu, aabb.position.y + aabb.size.y * fv, aabb.position.z + aabb.size.z + 2.0)
						to = Vector3(from.x, from.y, aabb.position.z - 2.0)
					_:
						from = Vector3(aabb.position.x + aabb.size.x * fu, aabb.position.y + aabb.size.y * fv, aabb.position.z - 2.0)
						to = Vector3(from.x, from.y, aabb.position.z + aabb.size.z + 2.0)
				var hit := sq.raycast(from, to)
				if not hit.hit:
					continue
				var view := (from - hit.position).normalized()
				if hit.normal.dot(view) < 0.0:
					hit.normal = -hit.normal
				var key := Vector3(
					snappedf(hit.position.x, 0.04),
					snappedf(hit.position.y, 0.04),
					snappedf(hit.position.z, 0.04)
				)
				if seen.has(key):
					continue
				seen[key] = true
				hits.append(hit)
	return hits


func _audit_sg9c(sq: SurfaceQuery, sdf: MeshSdf) -> Dictionary:
	var face_samples: Array = []
	var inside_probes: int = 0
	var worst_surface: float = 0.0
	var worst_inside: float = -INF
	for hit in _collect_collision_ray_hits(sq, sdf, SG9C_RAY_SAMPLES):
		var refined: Dictionary = _refined_abs_phi(sq, sdf, hit)
		if not _in_sdf_band(sq.signed_distance(refined.position), sdf.band):
			continue
		worst_surface = maxf(worst_surface, refined.abs_phi)
		face_samples.append(refined)
		if not _solid_behind(sq, hit.position, refined.normal):
			continue
		var p_in: Vector3 = hit.position - refined.normal * SG9C_INSIDE_DEPTH
		var phi_in: float = sq.signed_distance(p_in)
		if not _in_sdf_band(phi_in, sdf.band):
			continue
		inside_probes += 1
		worst_inside = maxf(worst_inside, phi_in)
	return {
		"face_count": face_samples.size(),
		"worst_surface": worst_surface,
		"inside_probes": inside_probes,
		"worst_inside": worst_inside,
	}


func test_sg9c_sdf_agrees_with_collision_mesh_on_all_playable_structures() -> void:
	for scenario_path in _PLAYABLE_SCENARIOS:
		var fixture: Dictionary = await _make_scenario_fixture(scenario_path)
		if fixture.get("skip", false):
			pending("%s assets missing" % fixture.get("id", scenario_path))
			continue
		var sq: SurfaceQuery = fixture.sq
		var sdf: MeshSdf = fixture.sdf
		var report: Dictionary = _audit_sg9c(sq, sdf)
		var sid: String = fixture.id
		await _free_fixture(fixture)
		print(
			"[SG-9c] %s — face samples: %d, worst |Φ|: %.4f m, inside probes: %d, worst Φ@%.2f m: %.4f"
			% [
				sid,
				report.face_count,
				report.worst_surface,
				report.inside_probes,
				SG9C_INSIDE_DEPTH,
				report.worst_inside,
			]
		)
		assert_gte(
			report.face_count,
			SG9C_MIN_VALID_SAMPLES,
			"%s: need ≥%d band-valid collision-face samples (got %d)"
			% [sid, SG9C_MIN_VALID_SAMPLES, report.face_count]
		)
		assert_lte(
			report.worst_surface,
			SG9C_SURFACE_PHI_TOL,
			"%s: |Φ| on collision faces must be ≤ %.3f m (worst %.4f m)"
			% [sid, SG9C_SURFACE_PHI_TOL, report.worst_surface]
		)
		assert_gte(
			report.inside_probes,
			50,
			"%s: need ≥50 inward probes still in band at %.2f m (got %d)"
			% [sid, SG9C_INSIDE_DEPTH, report.inside_probes]
		)
		assert_lt(
			report.worst_inside,
			0.0,
			"%s: Φ must be negative %.2f m inside solid (worst inside probe %.4f m)"
			% [sid, SG9C_INSIDE_DEPTH, report.worst_inside]
		)
