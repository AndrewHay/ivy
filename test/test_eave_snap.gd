## Face-aware WallSdf post-placement snap (ivy-a4n) — unit + step_tip coverage.
extends GutTest

const SurfaceQuery = preload("res://src/world/surface_query.gd")
const OverhangSpec = preload("res://src/world/overhang_spec.gd")
const OverhangSdf = preload("res://src/world/overhang_sdf.gd")
const OverhangWall = preload("res://src/world/overhang_wall.gd")
const WallSdf = preload("res://src/world/wall_sdf.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const GrowthStep = preload("res://src/sim/growth_step.gd")
const SimContext = preload("res://src/sim/sim_context.gd")
const TipManager = preload("res://src/sim/tip_manager.gd")
const PlantData = preload("res://src/sim/plant_data.gd")
const SimClock = preload("res://src/core/sim_clock.gd")
const Solar = preload("res://src/env/solar.gd")
const IvyEnvironment = preload("res://src/env/environment.gd")
const Conv = preload("res://src/core/conv.gd")

const SKIN := 1e-3
const SOFFIT_EPS := 0.02


func _sq_overhang(space = null, body = null) -> SurfaceQuery:
	var params := IvyParams.new()
	var sq := SurfaceQuery.new()
	sq.setup(space, body, OverhangSdf.new(OverhangSpec.new()), PackedByteArray(), params)
	return sq


func _hit(pos: Vector3, normal: Vector3, dist: float) -> SurfaceQuery.Hit:
	var h := SurfaceQuery.Hit.new()
	h.hit = true
	h.position = pos
	h.normal = normal
	h.distance = dist
	return h


func _snap(
	sq: SurfaceQuery,
	tip_start: Vector3,
	candidate: SurfaceQuery.Hit,
	start_normal: Vector3,
	contact: float,
	adhesion: float,
	face_cos: float,
	soffit_y: float,
	allow_soffit: bool = false
) -> SurfaceQuery.WallSnap:
	return sq.supported_wall_snap(
		tip_start, candidate, start_normal,
		contact, adhesion, face_cos, soffit_y, SOFFIT_EPS, allow_soffit
	)


func test_overhang_soffit_y() -> void:
	var sdf := OverhangSdf.new(OverhangSpec.new())
	assert_eq(sdf.soffit_y(), 5.0)


func test_eave_soffit_y_from_backend() -> void:
	var sq := _sq_overhang()
	assert_eq(sq.eave_soffit_y(), 5.0)


func test_eave_soffit_y_inf_for_plain_wall() -> void:
	var sq := SurfaceQuery.new()
	sq.setup(null, null, WallSdf.new(WallSpec.new()), PackedByteArray(), IvyParams.new())
	assert_eq(sq.eave_soffit_y(), INF)


func test_rejects_when_within_contact_threshold() -> void:
	var sq := _sq_overhang()
	var cand := _hit(Vector3.ZERO, Conv.SOUTH, 0.01)
	var ws := _snap(sq, Vector3(0, 1, 0.2), cand, Conv.SOUTH, 0.02, 0.15, 0.5, 5.0)
	assert_false(ws.apply)


func test_rejects_when_beyond_adhesion_range() -> void:
	var sq := _sq_overhang()
	var cand := _hit(Vector3.ZERO, Conv.SOUTH, 0.20)
	var ws := _snap(sq, Vector3(0, 1, 0.2), cand, Conv.SOUTH, 0.02, 0.15, 0.5, 5.0)
	assert_false(ws.apply)


func test_rejects_roof_upward_normal() -> void:
	var sq := _sq_overhang()
	var cand := _hit(Vector3(0, 5.2, 0.3), Conv.UP, 0.08)
	var ws := _snap(sq, Vector3(0, 5.1, 0.3), cand, Conv.SOUTH, 0.02, 0.15, 0.5, 5.0)
	assert_false(ws.apply)


func test_rejects_candidate_above_soffit_band() -> void:
	var sq := _sq_overhang()
	## Horizontal wall-ish normal but point above soffit + eps (roof zone).
	var cand := _hit(Vector3(0, 5.05, 0.3), Vector3(0.0, 0.0, 1.0), 0.08)
	var ws := _snap(sq, Vector3(0, 4.5, 0.2), cand, Conv.SOUTH, 0.02, 0.15, 0.5, 5.0)
	assert_false(ws.apply)


func test_accepts_matching_wall_face_and_offsets_skin() -> void:
	var sq := _sq_overhang()
	var on_face := Vector3(0.0, 2.5, 0.0)
	var cand := _hit(on_face, Conv.SOUTH, 0.06)
	var ws := _snap(sq, Vector3(0, 2.5, 0.08), cand, Conv.SOUTH, 0.02, 0.15, 0.5, 5.0)
	assert_true(ws.apply, "same-face snap must apply")
	var outward := (ws.position - on_face).dot(Conv.SOUTH)
	assert_gt(outward, SKIN * 0.5, "snap must push outward by COLLISION_SKIN")


func test_rejects_mismatched_face_without_concave_path() -> void:
	var sq := _sq_overhang()
	var cand := _hit(Vector3(0, 2.5, -0.2), Conv.NORTH, 0.06)
	var ws := _snap(sq, Vector3(0, 2.5, 0.08), cand, Conv.SOUTH, 0.02, 0.15, 0.5, 5.0)
	assert_false(ws.apply)


func test_accepts_concave_soffit_when_ray_clear() -> void:
	var spec := OverhangSpec.new()
	var ow := OverhangWall.new()
	add_child_autofree(ow)
	ow.build_from_spec(spec, true)
	await get_tree().physics_frame
	var sq := _sq_overhang(ow.get_world_3d().direct_space_state, ow)
	## South-wall tip just below the soffit; snap candidate is the underside face in open air.
	var tip_start := Vector3(0.0, 4.92, 0.06)
	var soffit_pt := Vector3(0.0, spec.wall_height, 0.45)
	var cand := _hit(soffit_pt, -Conv.UP, 0.07)
	var ws := _snap(sq, tip_start, cand, Conv.SOUTH, 0.02, 0.15, 0.5, spec.wall_height, true)
	assert_true(ws.apply, "concave corner should snap to soffit when line-of-sight is clear")
	assert_lt(ws.position.y, spec.wall_height + SOFFIT_EPS)


func test_rejects_concave_soffit_when_traverse_off() -> void:
	var spec := OverhangSpec.new()
	var ow := OverhangWall.new()
	add_child_autofree(ow)
	ow.build_from_spec(spec, true)
	await get_tree().physics_frame
	var sq := _sq_overhang(ow.get_world_3d().direct_space_state, ow)
	var tip_start := Vector3(0.0, 4.92, 0.06)
	var soffit_pt := Vector3(0.0, spec.wall_height, 0.45)
	var cand := _hit(soffit_pt, -Conv.UP, 0.07)
	var ws := _snap(sq, tip_start, cand, Conv.SOUTH, 0.02, 0.15, 0.5, spec.wall_height, false)
	assert_false(ws.apply, "traverse-off must not snap to soffit underside (M6 guard)")


func _make_overhang_step_ctx() -> Dictionary:
	var params := IvyParams.new()
	var surface := SurfaceQuery.new()
	surface.setup(null, null, OverhangSdf.new(OverhangSpec.new()), PackedByteArray(), params)
	var env := IvyEnvironment.new()
	env.build(params, surface, Solar.new(params))
	var ctx := SimContext.new(params, env, surface, PlantData.new(), TipManager.new(), SimClock.new(params))
	var anchor := surface.nearest(Vector3(0.0, 2.5, 0.08))
	var tip := ctx.tips.add_seed(anchor.position + anchor.normal * 0.015, anchor.normal, 4242, params)
	tip.direction = anchor.normal
	tip.random_dir = anchor.normal
	return {"ctx": ctx, "tip": tip, "surface": surface}


func test_wall_sdf_attached_tip_stays_on_wall_not_soffit() -> void:
	var d := _make_overhang_step_ctx()
	var tip: Tip = d.tip
	var ctx: SimContext = d.ctx
	var surface: SurfaceQuery = d.surface
	GrowthStep.step_tip(tip, ctx)
	assert_eq(tip.state, Tip.State.GROWING)
	assert_lte(surface.nearest(tip.position).distance, ctx.params.contact_distance)
	assert_lt(tip.position.y, surface.eave_soffit_y() + SOFFIT_EPS,
		"wall-hugging snap must not park the tip above the soffit band")


func test_floating_tip_not_snapped_on_overhang() -> void:
	var d := _make_overhang_step_ctx()
	var tip: Tip = d.tip
	var ctx: SimContext = d.ctx
	var gap := ctx.params.adhesion_range + 0.1
	var anchor := ctx.surface.nearest(Vector3(0.0, 2.5, 0.08))
	tip.position = anchor.position + anchor.normal * gap
	tip.direction = anchor.normal
	GrowthStep.step_tip(tip, ctx)
	assert_eq(tip.state, Tip.State.FLOATING)
