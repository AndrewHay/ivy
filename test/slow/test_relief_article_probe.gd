## ivy-b1e.6 — SG-9(d) growth probe on the relief test article (IMPLEMENTATION.md SD-MESH-19.5).
##
## Default IvyParams (no overrides), 30 game-days at SimClock NORMAL, the four seed anchors A1-A4 of
## the scenario. RNG: SimRoot plants scenario seed i with stream seed 12345 + i (the recorded seed;
## nothing else is random). Every distance is to the analytic, sharp-edged article
## (tools/relief_article_probe.gd), never to the proxy under test.
##
##   sharp variant (tools/build_growth_surface.py output): D0-D4 pass, fingerprint equals the one
##   recorded from two separate processes (D5)
##   bounding-box variant: fails D1 or D2 (D6, falsifiability)
##   0.025 m / 0.05 m fillet variants: reported only (the owner's feel read, G7)
##
## D1 and D2 as ratified in ivy-b1e.21 (SD-MESH-19.5): D1 = >= 95 % of floor-zone nodes within
## 0.045 m and median <= 0.02 m; D2 = no far footprint node attached to the growth surface.
## Reported per variant: turn angles at inside corners, the share of nearest() calls returned
## unrefined, the share of floor-zone nodes 0.02-0.045 m off the floor, the flat-wall control,
## floating far nodes, a distance histogram per feature. Run alone: -gtest=res://test/slow/test_relief_article_probe.gd
extends GutTest

const Probe = preload("res://tools/relief_article_probe.gd")
const ProbeQuery = preload("res://tools/relief_article_probe_query.gd")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")
const StructureBody = preload("res://src/world/structure_body.gd")
const MeshSdf = preload("res://src/world/mesh_sdf.gd")
const SimRoot = preload("res://src/sim/sim_root.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const SimClock = preload("res://src/core/sim_clock.gd")

const GAME_DAYS := 30.0
const SEED_STREAM_BASE := 12345  # SimRoot._plant_scenario_seed: 12345 + anchor index
## D5: the sharp variant's fingerprint from a separate-process run (2026-11-14).
## Re-recorded for ivy-9bt7 (mesh snap skin and extended mesh rays); before that fix it was
## 600f8904 / a81ca9df...c4d.
const SHARP_RUN_HASH := "52875f3f"
const SHARP_SHA256 := "45fc70a6f2add3fe6061b275594c9f4045d0b4effb8db335ec3de4ca35fad6bb"


## Grows one variant and returns the probe report (plus fingerprints and query counts).
func _grow(id: String) -> Dictionary:
	var scenario = BuildingCatalog.scenario_for(id)
	assert_not_null(scenario, "scenario %s" % id)
	var body := StructureBody.new()
	add_child(body)
	body.build(scenario.collision_glb, "")
	await get_tree().physics_frame
	var sdf := MeshSdf.new()
	sdf.load_from_file(scenario.sdf_path)
	assert_true(sdf.verify_provenance(scenario.collision_glb), "%s SDF baked from its collision GLB" % id)
	var params := IvyParams.new()
	var sq := ProbeQuery.new()
	sq.setup(body.get_world_3d().direct_space_state, body, sdf, body.face_material, params)
	var sim := SimRoot.new()
	sim.setup(params, sq, scenario, 0)
	assert_eq(sim.tips.tips.size(), 4, "%s: A1-A4 all planted" % id)
	sq.reset_counts()
	var started := Time.get_ticks_msec()
	sim.advance_ticks(SimClock.ticks_for_game_days(GAME_DAYS, SimClock.Speed.NORMAL))
	var ends: Array = []
	for tip in sim.tips.tips:
		ends.append(tip.position)
	var r: Dictionary = Probe.analyse(sim.plant, ends, sdf.signed_distance)
	r["nearest_calls"] = sq.nearest_total
	r["unrefined_share"] = float(sq.nearest_unrefined) / maxi(1, sq.nearest_total)
	r["run_hash"] = RunHash.of(sim.plant, sim.tips)
	r["sha"] = _sha(sim.plant)
	var text := "%s\n  fingerprint RunHash %s sha256 %s; grown in %.1f s" % [
		Probe.format_report(id, r), r["run_hash"], String(r["sha"]).substr(0, 16),
		(Time.get_ticks_msec() - started) / 1000.0]
	gut.p(text)
	print(text)
	sim.free()
	remove_child(body)
	body.free()
	await get_tree().physics_frame
	return r


static func _sha(plant: PlantData) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(plant.seg_a.to_byte_array())
	ctx.update(plant.seg_b.to_byte_array())
	ctx.update(plant.seg_normal.to_byte_array())
	ctx.update(plant.seg_tip.to_byte_array())
	ctx.update(plant.leaf_xform.to_byte_array())
	ctx.update(PackedFloat64Array([plant.total_length]).to_byte_array())
	return ctx.finish().hex_encode()


func test_sharp_variant_meets_d0_to_d5() -> void:
	var r: Dictionary = await _grow("relief_article")
	assert_true(r["d0_pass"], "D0 evidence: %d crossings, %d stems in N1's floor zone, %d in M1's" % [
		r["crossings"], r["n1_stems"], r["m1_stems"]])
	assert_true(r["d1_pass"], "D1: %.1f %% of %d floor-zone nodes within 0.045 m, median %.4f m" % [
		100.0 * float(r["d1_share_effective"]), r["floor_nodes"], r["d1_median"]])
	assert_true(r["d2_pass"], "D2: %d attached footprint nodes farther than 0.05 m (max %.4f); %d floating" % [
		r["d2_far_nodes"], r["d2_max"], r["d2_floating_far_nodes"]])
	assert_true(r["d3_pass"], "D3: %d tip ends inside, %d nodes deeper than 0.01 m" % [
		r["d3_tips_inside"], r["d3_nodes_deep"]])
	assert_true(r["d4_pass"], "D4: %d nodes threaded into S1" % r["d4_slot_nodes"])
	# D5 (SG-6 discipline): two runs in separate processes give the same fingerprint. Recorded
	# from two such runs on 2026-11-14 (ivy-b1e.6); every run of this test is a further one.
	# Re-record, with the old and new values in the bead notes, when the article or growth changes.
	# (A second run inside the SAME process differs, 6f73a0bb: not the SG-6 contract, reported.)
	assert_eq(r["run_hash"], SHARP_RUN_HASH, "D5: RunHash equals the recorded separate-process run")
	assert_eq(r["sha"], SHARP_SHA256, "D5: segment and leaf bytes equal the recorded run")


func test_bounding_box_variant_fails_d1_or_d2() -> void:
	var r: Dictionary = await _grow("relief_article_bbox")
	assert_gt(int(r["floor_nodes"]), 0, "D6 needs floor-zone evidence on the box too")
	assert_false(bool(r["d1_pass"]) and bool(r["d2_pass"]),
		"D6: the probe must fail a bounding-box proxy (D1 %.1f %% within 0.045 m, median %.4f m; D2 %d attached far nodes, %d floating)" % [
			100.0 * float(r["d1_share_effective"]), r["d1_median"], r["d2_far_nodes"],
			r["d2_floating_far_nodes"]])


func test_fillet_variants_are_reported() -> void:
	for id in ["relief_article_r025", "relief_article_r050"]:
		var r: Dictionary = await _grow(id)
		assert_gt(int(r["segments"]), 0, "%s grew" % id)
