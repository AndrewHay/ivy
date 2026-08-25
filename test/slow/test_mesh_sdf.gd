## SG-2 / SD-MESH-4 / SD-MESH-15 — mesh-backed SurfaceQuery contract on square_sim.
extends GutTest

const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const StructureBody = preload("res://src/world/structure_body.gd")
const StructureScenario = preload("res://src/world/structure_scenario.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const IvyEnvironment = preload("res://src/env/environment.gd")
const LightBakeCache = preload("res://src/env/light_bake_cache.gd")
const MainScene = preload("res://src/main/main.tscn")

const SQUARE_SDF := "res://assets/structures/square_sim.sdf"
const SQUARE_GLB := "res://assets/structures/square_sim.glb"
const MESH_SDF_PATH := "res://src/world/mesh_sdf.gd"
const WORLD_PATH := "res://src/world/world.gd"

## SG-2(a): ~0.5·h at h = 0.05 m.
const SURFACE_PHI_TOL := 0.025
## SG-2(c): nearest() vs raycast ground truth.
const NEAREST_DIST_TOL := 0.005
## SG-2(d): project_to_shell band (half field_shell_halfwidth).
const PROJECT_PHI_TOL := 0.045
const STRATIFIED_SAMPLE_TARGET := 50
const BAND_VALID_SURFACE_MIN := 25  # first-pass floor; square_sim yields ~31 at h=0.05
## SG-2(b) explicit requirement: ≥200 stratified sample points per spec.
const SG2B_SAMPLE_MIN := 200
const NORMAL_DOT_MIN := 0.80
const INSIDE_OFFSET := 0.03
const OUTSIDE_OFFSET := 0.03
const QUERY_OUTSIDE_OFFSET := 0.08


func _load_square_sdf() -> MeshSdf:
	var sdf := MeshSdf.new()
	sdf.load_from_file(SQUARE_SDF)
	return sdf


func _make_square_surface_query() -> Dictionary:
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(SQUARE_GLB, "")
	await get_tree().physics_frame
	var sdf := _load_square_sdf()
	assert_true(sdf.verify_provenance(SQUARE_GLB))
	var sq := SurfaceQuery.new()
	sq.setup(
		body.get_world_3d().direct_space_state,
		body,
		sdf,
		body.face_material,
		IvyParams.new()
	)
	return {"sq": sq, "sdf": sdf, "body": body}


func _collect_stratified_hits(sq: SurfaceQuery, sdf: MeshSdf, min_count: int) -> Array:
	var hits: Array = []
	var seen: Dictionary = {}
	var center: Vector3 = sdf.mesh_aabb.get_center()
	var extent: float = sdf.mesh_aabb.size.length() * 0.65
	const GOLDEN := PI * (3.0 - sqrt(5.0))
	var attempts: int = max(min_count * 80, 800)
	for i in attempts:
		if hits.size() >= min_count:
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
	# Face-grid rays catch flat walls the sphere sampler misses.
	var aabb: AABB = sdf.mesh_aabb
	for face in 6:
		for u in range(0, 21):
			for v in range(0, 21):
				if hits.size() >= min_count:
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


func _refined_surface_point(sq: SurfaceQuery, sdf: MeshSdf, hit) -> Dictionary:
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
	return {
		"position": best_p,
		"abs_phi": best_abs,
		"normal": hit.normal,
		"raycast": hit,
	}


func _collect_band_valid_surface_hits(
	sq: SurfaceQuery,
	sdf: MeshSdf,
	min_count: int
) -> Array:
	var valid: Array = []
	var seen: Dictionary = {}
	for hit in _collect_stratified_hits(sq, sdf, min_count * 12):
		var refined: Dictionary = _refined_surface_point(sq, sdf, hit)
		if refined.abs_phi > SURFACE_PHI_TOL:
			continue
		var key := Vector3(
			snappedf(refined.position.x, 0.04),
			snappedf(refined.position.y, 0.04),
			snappedf(refined.position.z, 0.04)
		)
		if seen.has(key):
			continue
		seen[key] = true
		valid.append(refined)
		if valid.size() >= min_count:
			break
	return valid


func _collect_inside_solid_points(sdf: MeshSdf, min_count: int) -> Array:
	var points: Array = []
	var aabb: AABB = sdf.mesh_aabb
	for ix in range(0, 21):
		for iy in range(0, 21):
			for iz in range(0, 21):
				var p: Vector3 = aabb.position + aabb.size * Vector3(
					float(ix) / 20.0,
					float(iy) / 20.0,
					float(iz) / 20.0
				)
				var phi: float = sdf.signed_distance(p)
				if phi < -0.01 and _in_sdf_band(phi, sdf.band):
					points.append(p)
					if points.size() >= min_count:
						return points
	return points


func _find_flat_wall_discrimination_hit(sq: SurfaceQuery, sdf: MeshSdf):
	# East/west walls give the clearest separation from TowerSdf's radial normals.
	var aabb: AABB = sdf.mesh_aabb
	var best = null
	var best_sep := 1.0
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var tower := TowerSdf.new(spec)
	for use_max_x in [true, false]:
		for y_step in range(0, 21):
			for z_step in range(0, 21):
				var y: float = aabb.position.y + aabb.size.y * float(y_step) / 20.0
				var z: float = aabb.position.z + aabb.size.z * float(z_step) / 20.0
				var from: Vector3
				var to: Vector3
				if use_max_x:
					from = Vector3(aabb.position.x + aabb.size.x + 2.0, y, z)
					to = Vector3(aabb.position.x - 2.0, y, z)
				else:
					from = Vector3(aabb.position.x - 2.0, y, z)
					to = Vector3(aabb.position.x + aabb.size.x + 2.0, y, z)
				var hit := sq.raycast(from, to)
				if not hit.hit:
					continue
				var view := (from - hit.position).normalized()
				if hit.normal.dot(view) < 0.0:
					hit.normal = -hit.normal
				var refined: Dictionary = _refined_surface_point(sq, sdf, hit)
				if refined.abs_phi > SURFACE_PHI_TOL:
					continue
				var mesh_n: Vector3 = sdf.gradient_normalized(refined.position)
				var ray_n: Vector3 = hit.normal.normalized()
				if absf(mesh_n.dot(ray_n)) < 0.65:
					continue
				var tower_n: Vector3 = tower.gradient_normalized(refined.position)
				var sep: float = absf(mesh_n.dot(tower_n))
				if sep < best_sep:
					best_sep = sep
					best = refined
	return best


func _newton_project(backend, p: Vector3, steps: int) -> Vector3:
	var q := p
	for _i in steps:
		var phi: float = backend.signed_distance(q)
		var n: Vector3 = backend.gradient_normalized(q)
		q = q - n * phi
	return q


func _in_sdf_band(phi: float, band: float) -> bool:
	return absf(phi) < band - 0.02


func test_mesh_sdf_loads_square_volume() -> void:
	var sdf := _load_square_sdf()
	assert_gt(sdf.dims.x, 0, "dims.x")
	assert_gt(sdf.dims.y, 0, "dims.y")
	assert_gt(sdf.dims.z, 0, "dims.z")
	assert_almost_eq(sdf.h, 0.05, 1e-6)
	assert_almost_eq(sdf.band, 0.55, 1e-6)


func test_mesh_sdf_sign_outside_is_positive() -> void:
	var sdf := _load_square_sdf()
	var outside := sdf.mesh_aabb.position + sdf.mesh_aabb.size + Vector3(1.0, 1.0, 1.0)
	assert_gt(sdf.signed_distance(outside), 0.0, "far outside should be positive")


func test_surface_query_tower_backend_tag_unchanged() -> void:
	var params := IvyParams.new()
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var sq := SurfaceQuery.new()
	sq.setup(null, null, TowerSdf.new(spec), PackedByteArray(), params)
	assert_eq(sq.backend_tag(), "TowerSdf")


func test_surface_query_mesh_backend_tag() -> void:
	var params := IvyParams.new()
	var sq := SurfaceQuery.new()
	sq.setup(null, null, _load_square_sdf(), PackedByteArray(), params)
	assert_eq(sq.backend_tag(), "MeshSdf")


func test_mesh_sdf_verify_provenance_matches_collision_glb() -> void:
	var sdf := _load_square_sdf()
	assert_true(
		sdf.verify_provenance(SQUARE_GLB),
		"square_sim.sdf must match square_sim.glb"
	)


func test_mesh_sdf_verify_provenance_rejects_wrong_glb() -> void:
	var sdf := _load_square_sdf()
	assert_false(
		sdf.verify_provenance("res://assets/structures/square_hero.glb"),
		"hero glb must not match sim sdf provenance"
	)


func test_structure_body_trimesh_raycast_hits_square() -> void:
	var fixture: Dictionary = await _make_square_surface_query()
	var sq: SurfaceQuery = fixture.sq
	var sdf: MeshSdf = fixture.sdf
	var col_count := 0
	for child in fixture.body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			col_count += 1
	assert_gt(col_count, 0, "expected trimesh collision shapes")
	var center: Vector3 = sdf.mesh_aabb.get_center()
	var hit := sq.raycast(center + Vector3(0.0, 0.0, 8.0), center)
	assert_true(hit.hit, "raycast should hit square collision mesh")


func test_sg2_signed_distance_sign_and_surface_tolerance() -> void:
	# SG-2(a): negative inside solid, positive outside, |Φ| ≤ 0.5·h on surface.
	var fixture: Dictionary = await _make_square_surface_query()
	var sq: SurfaceQuery = fixture.sq
	var sdf: MeshSdf = fixture.sdf
	var surface_hits: Array = _collect_band_valid_surface_hits(sq, sdf, STRATIFIED_SAMPLE_TARGET)
	assert_gte(surface_hits.size(), BAND_VALID_SURFACE_MIN,
		"need ≥%d band-valid on-surface hits (|Φ| ≤ %.3f); got %d — rebake square_sim.sdf or widen band"
		% [BAND_VALID_SURFACE_MIN, SURFACE_PHI_TOL, surface_hits.size()])
	for hit in surface_hits:
		var pos: Vector3 = hit.position
		var n: Vector3 = hit.normal.normalized()
		assert_lte(hit.abs_phi, SURFACE_PHI_TOL,
			"|Φ| on surface must be ≤ 0.5·h at %s (got %.4f)" % [pos, hit.abs_phi])
		var phi_out: float = sq.signed_distance(pos + n * OUTSIDE_OFFSET)
		if _in_sdf_band(phi_out, sdf.band):
			assert_gt(phi_out, 0.0, "outside air must be positive at %s (got %.4f)" % [pos, phi_out])
	var inside_pts: Array = _collect_inside_solid_points(sdf, 5)
	assert_gte(inside_pts.size(), 5,
		"grid must find ≥5 band-valid points inside solid (Φ < 0)")
	for p in inside_pts:
		assert_lt(sq.signed_distance(p), 0.0, "inside solid must be negative at %s" % p)


func test_sg2_surface_normal_agrees_with_raycast() -> void:
	# SG-2(b): surface_normal() agrees with exterior raycast normals (mesh uses ray-backed read).
	# Spec requires ≥200 stratified sample points; agreement floor scales proportionally.
	var fixture: Dictionary = await _make_square_surface_query()
	var sq: SurfaceQuery = fixture.sq
	var sdf: MeshSdf = fixture.sdf
	var stratified: Array = _collect_stratified_hits(sq, sdf, SG2B_SAMPLE_MIN)
	assert_gte(stratified.size(), SG2B_SAMPLE_MIN,
		"SG-2(b) requires ≥%d stratified raycast samples; got %d" % [SG2B_SAMPLE_MIN, stratified.size()])
	var agree := 0
	var worst_dot := 1.0
	for hit in stratified:
		var mesh_n: Vector3 = sq.surface_normal(hit.position)
		var dot: float = absf(mesh_n.dot(hit.normal.normalized()))
		worst_dot = minf(worst_dot, dot)
		if dot >= NORMAL_DOT_MIN:
			agree += 1
	assert_gte(agree, BAND_VALID_SURFACE_MIN * 2,
		"≥%d surface normals must agree with raycast (dot ≥ %.2f); got %d/%d, worst dot %.3f"
		% [BAND_VALID_SURFACE_MIN * 2, NORMAL_DOT_MIN, agree, stratified.size(), worst_dot])


func test_sg2_nearest_within_raycast_ground_truth() -> void:
	# SG-2(c): nearest() within 5 mm of physics raycast ground truth.
	var fixture: Dictionary = await _make_square_surface_query()
	var sq: SurfaceQuery = fixture.sq
	var sdf: MeshSdf = fixture.sdf
	var hits: Array = _collect_band_valid_surface_hits(sq, sdf, STRATIFIED_SAMPLE_TARGET)
	assert_gte(hits.size(), BAND_VALID_SURFACE_MIN,
		"need ≥%d band-valid samples for nearest(); got %d"
		% [BAND_VALID_SURFACE_MIN, hits.size()])
	var ok := 0
	var worst_err := 0.0
	for hit in hits:
		var n: Vector3 = hit.normal.normalized()
		var query: Vector3 = hit.position + n * QUERY_OUTSIDE_OFFSET
		var truth := sq.raycast(query, query - n * 0.6)
		assert_true(truth.hit, "ground-truth ray must hit near %s" % hit.position)
		var near := sq.nearest(query)
		assert_true(near.hit, "nearest() must return a hit")
		var err: float = near.position.distance_to(truth.position)
		worst_err = maxf(worst_err, err)
		if err <= NEAREST_DIST_TOL:
			ok += 1
	assert_gte(ok, BAND_VALID_SURFACE_MIN,
		"≥%d nearest() results within 5 mm (of %d band-valid); worst error %.4f m"
		% [BAND_VALID_SURFACE_MIN, hits.size(), worst_err])


func test_sg2_project_to_shell_one_and_two_newton_steps() -> void:
	# SG-2(d): |Φ(result)| ≤ 0.045 m after one and two Newton steps — report worst case.
	var fixture: Dictionary = await _make_square_surface_query()
	var sq: SurfaceQuery = fixture.sq
	var sdf: MeshSdf = fixture.sdf
	var hits: Array = _collect_band_valid_surface_hits(sq, sdf, STRATIFIED_SAMPLE_TARGET)
	assert_gte(hits.size(), BAND_VALID_SURFACE_MIN,
		"need ≥%d band-valid samples for project_to_shell; got %d"
		% [BAND_VALID_SURFACE_MIN, hits.size()])
	var worst_one := 0.0
	var worst_two := 0.0
	var offsets := [0.12, 0.25]
	for hit in hits:
		var n: Vector3 = hit.normal.normalized()
		for off in offsets:
			var start: Vector3 = hit.position + n * off
			var one := _newton_project(sdf, start, 1)
			var two := _newton_project(sdf, start, 2)
			worst_one = maxf(worst_one, absf(sdf.signed_distance(one)))
			worst_two = maxf(worst_two, absf(sdf.signed_distance(two)))
			var shipped := sq.project_to_shell(start)
			worst_two = maxf(worst_two, absf(sq.signed_distance(shipped)))
	# SD-OPEN-23: report measured pair, not just pass/fail (Director requirement).
	print("[SG-2d] two-step Newton residual on square_sim — 1-step worst |Φ|: %.4f m, 2-step worst |Φ|: %.4f m (tol %.3f m)" % [worst_one, worst_two, PROJECT_PHI_TOL])
	assert_lte(worst_one, PROJECT_PHI_TOL,
		"one Newton step worst |Φ| = %.4f m must be ≤ %.3f m" % [worst_one, PROJECT_PHI_TOL])
	assert_lte(worst_two, PROJECT_PHI_TOL,
		"two Newton steps worst |Φ| = %.4f m must be ≤ %.3f m" % [worst_two, PROJECT_PHI_TOL])


func test_sg2_shell_bounds_encloses_mesh_plus_halfwidth() -> void:
	# SG-2(e): shell_bounds encloses mesh AABB + field_shell_halfwidth (0.09 m).
	var params := IvyParams.new()
	var sdf := _load_square_sdf()
	var sq := SurfaceQuery.new()
	sq.setup(null, null, sdf, PackedByteArray(), params)
	var margin: float = params.field_shell_halfwidth
	assert_almost_eq(margin, 0.09, 1e-6, "expected default field_shell_halfwidth")
	var shell: AABB = sq.shell_bounds(margin)
	var expected: AABB = sdf.mesh_aabb.grow(margin)
	assert_eq(shell, expected, "shell_bounds must be mesh AABB grown by margin")
	assert_true(shell.encloses(sdf.mesh_aabb),
		"shell must enclose the mesh AABB")
	var corner_outside: Vector3 = sdf.mesh_aabb.position - Vector3(margin * 0.5, margin * 0.5, margin * 0.5)
	assert_true(shell.has_point(corner_outside),
		"shell must extend at least halfwidth beyond mesh corners")


func test_south_wall_raycast_near_design_probe() -> void:
	# Smoke: south face (z = mesh_aabb.position.z) is reachable by exterior raycast.
	var fixture: Dictionary = await _make_square_surface_query()
	var sq: SurfaceQuery = fixture.sq
	var sdf: MeshSdf = fixture.sdf
	var south_z: float = sdf.mesh_aabb.position.z
	var hits := 0
	for x_step in range(0, 11):
		for y_step in range(0, 11):
			var x: float = sdf.mesh_aabb.position.x + sdf.mesh_aabb.size.x * float(x_step) / 10.0
			var y: float = sdf.mesh_aabb.position.y + sdf.mesh_aabb.size.y * float(y_step) / 10.0
			var from := Vector3(x, y, south_z - 2.0)
			var to := Vector3(x, y, south_z + 1.0)
			var hit := sq.raycast(from, to)
			if hit.hit and absf(hit.position.z - south_z) <= 0.15:
				hits += 1
	assert_gt(hits, 0, "south face must yield ≥1 exterior raycast hit")


func test_mesh_normal_differs_from_tower_at_flat_wall() -> void:
	# SD-MESH-15 behavioural discrimination: flat wall normal ≠ TowerSdf radial normal.
	var fixture: Dictionary = await _make_square_surface_query()
	var sq: SurfaceQuery = fixture.sq
	var sdf: MeshSdf = fixture.sdf
	var hit = _find_flat_wall_discrimination_hit(sq, sdf)
	assert_not_null(hit, "need band-valid flat-wall hit for tower discrimination")
	var mesh_n: Vector3 = sdf.gradient_normalized(hit.position)
	var spec := load("res://src/world/tower_spec_default.tres") as TowerSpec
	var tower_n: Vector3 = TowerSdf.new(spec).gradient_normalized(hit.position)
	assert_gt(absf(mesh_n.dot(hit.normal.normalized())), 0.65,
		"mesh normal should align with flat-wall raycast normal")
	assert_lt(absf(mesh_n.dot(tower_n)), 0.75,
		"mesh flat-wall normal must not match TowerSdf cylindrical radial normal")


func test_mesh_sdf_source_does_not_reference_tower_sdf() -> void:
	# SD-MESH-15 source scan: MeshSdf module must not reference TowerSdf.
	var text := FileAccess.get_file_as_string(MESH_SDF_PATH)
	assert_false(text.contains("TowerSdf"), "MeshSdf must not reference TowerSdf (SD-MESH-1/15)")


func test_world_mesh_branch_does_not_construct_tower_sdf() -> void:
	# SD-MESH-15 source scan: mesh scenario path must not construct TowerSdf.
	var text := FileAccess.get_file_as_string(WORLD_PATH)
	var mesh_start := text.find("if mesh_scenario != null:")
	assert_gt(mesh_start, 0, "world.gd must have mesh_scenario branch")
	var else_start := text.find("else:", mesh_start)
	assert_gt(else_start, mesh_start, "world.gd must have tower else branch")
	var mesh_block := text.substr(mesh_start, else_start - mesh_start)
	assert_true(mesh_block.contains("MeshSdfScript.new"), "mesh branch must construct MeshSdf")
	assert_false(mesh_block.contains("TowerSdfScript.new"),
		"mesh branch must not construct TowerSdf (SD-MESH-15)")


func test_main_mesh_scenario_active_before_surface_query() -> void:
	var scenario: StructureScenario = load(
		"res://assets/structures/scenarios/square.tres"
	) as StructureScenario
	var main := MainScene.instantiate()
	main.set("mesh_scenario", scenario)
	add_child_autofree(main)
	await get_tree().process_frame
	var world: Node = main.get_node("World")
	assert_not_null(world.get_node_or_null("Structure"), "StructureBody must exist before _ready surface query")
	var surface: SurfaceQuery = world.call("get_surface_query", IvyParams.new())
	assert_not_null(surface, "surface query should build when provenance matches")
	assert_eq(surface.backend_tag(), "MeshSdf", "square scenario must use MeshSdf backend")


func test_sg3_nearest_refined_when_phi_exceeds_fixed_reach() -> void:
	# SG-3 regression: when |Φ| > reach - 2h (i.e. |Φ| > 0.10 m at h=0.05),
	# the old fixed-reach axis sweep falls short and nearest() falls back to
	# absf(Φ) > contact_distance, misclassifying a floating tip as FLOATING.
	# SD-MESH-6 compliant nearest() fires a ray of length |Φ| + 2h so it always
	# crosses the surface — this test pins that contract.
	var fixture: Dictionary = await _make_square_surface_query()
	var sq: SurfaceQuery = fixture.sq
	var sdf: MeshSdf = fixture.sdf
	# Probe at 0.12 m outside a set of band-valid surface points so that
	# |Φ| ≈ 0.12 m > reach-threshold (0.10 m). The SD-MESH-6 ray is 0.22 m;
	# the old reach was 0.20 m — 2 cm short.
	const PROBE_OFFSET := 0.12
	var hits: Array = _collect_band_valid_surface_hits(sq, sdf, STRATIFIED_SAMPLE_TARGET)
	assert_gte(hits.size(), BAND_VALID_SURFACE_MIN,
		"need ≥%d band-valid samples; got %d" % [BAND_VALID_SURFACE_MIN, hits.size()])
	var ok := 0
	var worst_err := 0.0
	for hit in hits:
		var n: Vector3 = hit.normal.normalized()
		var query: Vector3 = hit.position + n * PROBE_OFFSET
		var truth := sq.raycast(query, query - n * (PROBE_OFFSET + 0.3))
		if not truth.hit:
			continue
		var near := sq.nearest(query)
		assert_true(near.hit, "nearest() must return a hit at %.2f m offset" % PROBE_OFFSET)
		var err: float = near.position.distance_to(truth.position)
		worst_err = maxf(worst_err, err)
		if err <= NEAREST_DIST_TOL:
			ok += 1
	assert_gte(ok, BAND_VALID_SURFACE_MIN,
		"≥%d nearest() results within 5 mm at %.2f m probe offset (SD-MESH-6); worst=%.4f m"
		% [BAND_VALID_SURFACE_MIN, PROBE_OFFSET, worst_err])


func test_scenario_seed1_resources_use_second_seed() -> void:
	var square: StructureScenario = load(
		"res://assets/structures/scenarios/square_seed1.tres"
	) as StructureScenario
	var tower: StructureScenario = load(
		"res://assets/structures/scenarios/tower_seed1.tres"
	) as StructureScenario
	assert_eq(square.seed_index, 1)
	assert_eq(tower.seed_index, 1)
	assert_eq(square.scenario_id, "square")
	assert_eq(tower.scenario_id, "tower")


func test_phase_a_load_and_build_timing() -> void:
	# SD-OPEN-24: measure (a) phase-A mesh scenario load time (SDF file load +
	# SurfaceQuery setup with mesh backend) and (b) first IvyEnvironment.build()
	# wall-clock time (light bake + field allocation + warm_up). These numbers
	# gate W-097's scope trigger (light-bake disk cache, ivy-6b9).
	# No pass/fail threshold — this is a measurement, not a correctness gate.
	var t0_load: int = Time.get_ticks_msec()
	var fixture: Dictionary = await _make_square_surface_query()
	var load_ms: int = Time.get_ticks_msec() - t0_load

	print("[W-094 timing] Phase-A load (SDF + physics + SurfaceQuery): %d ms" % load_ms)

	var sq: SurfaceQuery = fixture.sq
	var t0_build: int = Time.get_ticks_msec()
	var env := IvyEnvironment.new()
	env.build(IvyParams.new(), sq)
	var build_ms: int = Time.get_ticks_msec() - t0_build

	print("[W-094 timing] Phase-A first IvyEnvironment.build() (light bake + field + warm_up): %d ms" % build_ms)
	print("[W-094 timing] Total load+build: %d ms" % (load_ms + build_ms))

	assert_not_null(env, "IvyEnvironment.build() must complete without error")


func test_phase_a_cached_build_skips_ray_bake() -> void:
	# W-097: second build on unchanged square_sim mesh loads coarse grid from disk.
	var fixture: Dictionary = await _make_square_surface_query()
	var sq: SurfaceQuery = fixture.sq
	var params := IvyParams.new()
	var prov := sq.mesh_provenance()
	var ph := LightBakeCache.params_hash(params)
	var cache_path := LightBakeCache.cache_path(prov, ph)
	if FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))

	var env1 := IvyEnvironment.new()
	var t0: int = Time.get_ticks_msec()
	env1.build(params, sq)
	var first_ms: int = Time.get_ticks_msec() - t0
	assert_true(FileAccess.file_exists(cache_path), "first build must write cache file")

	var env2 := IvyEnvironment.new()
	t0 = Time.get_ticks_msec()
	env2.build(params, sq)
	var second_ms: int = Time.get_ticks_msec() - t0

	print("[W-097 timing] first build (ray bake): %d ms; cached build: %d ms" % [first_ms, second_ms])
	assert_lt(second_ms, first_ms, "cached build must be faster than full ray bake")
