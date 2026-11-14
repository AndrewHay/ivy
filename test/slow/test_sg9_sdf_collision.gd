## SG-9(c) — baked MeshSdf agrees with the collision mesh it was baked from (SD-OPEN-28).
extends GutTest

const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const StructureBody = preload("res://src/world/structure_body.gd")
const StructureScenario = preload("res://src/world/structure_scenario.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")

const Audit = preload("res://tools/growth_surface_audit.gd")

## Gate (c) as ratified in IMPLEMENTATION.md SD-MESH-19.4 (ivy-b1e.12): raw |Φ| read at the
## collision face with no search along the normal, p95 and half-cell cap; Φ negative 0.10 m
## inside solid. The statistic and thresholds are the audit tool's own (Audit.audit_sdf), so
## this test and tools/audit_growth_surface.tscn cannot disagree.

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


func test_sg9c_sdf_agrees_with_collision_mesh_on_all_playable_structures() -> void:
	for scenario_path in _PLAYABLE_SCENARIOS:
		var fixture: Dictionary = await _make_scenario_fixture(scenario_path)
		if fixture.get("skip", false):
			pending("%s assets missing" % fixture.get("id", scenario_path))
			continue
		var body: Node3D = fixture.body
		var audit = Audit.new()
		audit.setup(body.get_world_3d().direct_space_state, [], fixture.sdf)
		var report: Dictionary = audit.audit_sdf()
		var sid: String = fixture.id
		await _free_fixture(fixture)
		print(
			"[SG-9c] %s — face samples: %d, raw |Φ| p95 %.4f p99 %.4f max %.4f m; inside probes: %d, worst Φ@%.2f m: %.4f, not negative: %d"
			% [
				sid, report.face_n, report.face_p95, report.face_p99, report.face_max,
				report.inside_n, Audit.SDF_INSIDE_DEPTH, report.inside_worst, report.inside_not_negative,
			]
		)
		assert_gte(report.face_n, Audit.SDF_FACE_MIN_SAMPLES, "%s: collision-face samples" % sid)
		assert_lte(
			report.face_p95, Audit.SDF_FACE_P95_MAX,
			"%s: raw |Φ| p95 on collision faces must be ≤ %.3f m" % [sid, Audit.SDF_FACE_P95_MAX]
		)
		assert_lte(
			report.face_max, Audit.SDF_FACE_ABS_MAX,
			"%s: raw |Φ| max on collision faces must be ≤ %.3f m" % [sid, Audit.SDF_FACE_ABS_MAX]
		)
		assert_gte(report.inside_n, Audit.SDF_INSIDE_MIN_SAMPLES, "%s: inward probes" % sid)
		assert_eq(
			report.inside_not_negative, 0,
			"%s: Φ must be negative %.2f m inside solid (worst %.4f m)"
			% [sid, Audit.SDF_INSIDE_DEPTH, report.inside_worst]
		)
