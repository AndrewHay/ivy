extends GutTest

## ivy-b1e.6 — the SG-9(d) growth probe's measurements (tools/relief_article_probe.gd), checked
## on synthetic stems against the analytic relief article (SD-MESH-19.5). The 30-day growth run
## itself is test/slow/test_relief_article_probe.gd.

const Probe = preload("res://tools/relief_article_probe.gd")


func test_phi_is_the_exact_distance_to_the_sharp_article() -> void:
	# In front of the flat zone and of a panel floor.
	assert_almost_eq(Probe.phi(Vector3(0.0, 1.0, 0.05)), 0.05, 1e-6)
	assert_almost_eq(Probe.phi(Vector3(-0.90, 1.0, 0.05)), 0.05, 1e-6)
	# Hovering over N1's opening: the nearest surface is the niche floor 0.21 m behind, not the
	# plane of the wall face (a CSG estimate would say 0.01).
	assert_almost_eq(Probe.phi(Vector3(0.60, 1.05, 0.01)), 0.21, 1e-6)
	# Inside the niche, the slot and M1.
	assert_almost_eq(Probe.phi(Vector3(0.60, 1.05, -0.10)), 0.10, 1e-6)
	assert_almost_eq(Probe.phi(Vector3(1.52, 2.0, -0.05)), 0.02, 1e-6)
	assert_almost_eq(Probe.phi(Vector3(1.28, 0.75, -0.03)), 0.03, 1e-6)
	# In front of a rib, of the rail, of the plaque.
	assert_almost_eq(Probe.phi(Vector3(-1.575, 1.0, 0.13)), 0.03, 1e-6)
	assert_almost_eq(Probe.phi(Vector3(-0.90, 1.50, 0.12)), 0.02, 1e-6)
	assert_almost_eq(Probe.phi(Vector3(0.60, 2.30, 0.03)), 0.01, 1e-6)
	# Inside solid: the depth to the nearest air, through internal seams of the decomposition.
	assert_almost_eq(Probe.phi(Vector3(0.0, 1.0, -0.05)), -0.05, 1e-6)
	assert_almost_eq(Probe.phi(Vector3(0.299, 1.0, -0.15)), -0.001, 1e-6, "beside N1's wall")
	assert_almost_eq(Probe.phi(Vector3(-1.575, 1.0, 0.05)), -0.05, 1e-6, "inside rib R1")
	assert_almost_eq(Probe.phi(Vector3(0.60, 1.0, -0.21)), -0.01, 1e-6, "behind N1's floor")
	assert_lt(Probe.phi(Vector3(0.0, 1.0, -0.44)), 0.0)
	assert_gt(Probe.phi(Vector3(1.81, 1.0, -0.2)), 0.0)


func test_footprints_and_floor_zones() -> void:
	var fps: Array = Probe.footprints()
	assert_eq(fps.size(), 8, "six panels, N1, M1")
	var n1: Dictionary = Probe.footprint("N1")
	assert_almost_eq(float(n1["floor_z"]), -0.20, 1e-9)
	assert_true(Probe.in_floor_zone(n1, Vector3(0.60, 1.05, -0.19)))
	assert_false(Probe.in_floor_zone(n1, Vector3(0.36, 1.05, -0.19)), "within 0.075 m of a side wall")
	assert_true(Probe.in_footprint(n1, Vector3(0.36, 1.05, 0.5)), "projection on the wall plane")
	var m1: Dictionary = Probe.footprint("M1")
	assert_true(Probe.in_floor_zone(m1, Vector3(1.28, 0.75, -0.05)), "M1's zone is 0.01 m wide")
	assert_false(Probe.in_floor_zone(m1, Vector3(1.29, 0.75, -0.05)))
	var low: Dictionary = Probe.footprint("panel_2_low")
	assert_true(Probe.in_floor_zone(low, Vector3(-0.90, 0.10, 0.01)), "A1 starts in the middle bay's zone")
	assert_false(Probe.in_floor_zone(low, Vector3(-0.90, 1.36, 0.01)), "within 0.075 m of the rail")
	assert_false(Probe.in_floor_zone(low, Vector3(-1.04, 0.5, 0.01)), "within 0.075 m of rib R2")
	var high: Dictionary = Probe.footprint("panel_2_high")
	assert_true(Probe.in_floor_zone(high, Vector3(-0.90, 2.9, 0.01)))


## A PlantData with one polyline per entry of `stems` (each an Array of Vector3 nodes).
func _plant(stems: Array) -> PlantData:
	var plant := PlantData.new()
	for tip_id in stems.size():
		var nodes: Array = stems[tip_id]
		for k in nodes.size() - 1:
			plant.append_segment(nodes[k], nodes[k + 1], Vector3.BACK, tip_id, 0, 0.03 * k)
	return plant


static func _line(a: Vector3, b: Vector3, n: int) -> Array:
	var out: Array = []
	for k in n + 1:
		out.append(a.lerp(b, float(k) / n))
	return out


func test_floor_contact_and_spanning_are_judged_per_node() -> void:
	# Stem 0 lies on N1's floor; stem 1 bridges N1's opening at the wall plane.
	var on_floor := _line(Vector3(0.45, 0.70, -0.195), Vector3(0.75, 1.40, -0.195), 20)
	var bridge := _line(Vector3(0.40, 0.55, 0.005), Vector3(0.80, 1.55, 0.005), 20)
	var r: Dictionary = Probe.analyse(_plant([on_floor]), [])
	assert_eq(int(r["nodes"]), 21, "a stem's nodes are its origin and every segment end")
	assert_eq(int(r["floor_nodes"]), 21)
	assert_almost_eq(float(r["d1_share"]), 1.0, 1e-9)
	assert_eq(int(r["d2_far_nodes"]), 0)
	assert_true(bool(r["d1_pass"]))
	assert_true(bool(r["d2_pass"]))
	var r2: Dictionary = Probe.analyse(_plant([on_floor, bridge]), [])
	assert_lt(float(r2["d1_share"]), 0.95, "the bridge is 0.205 m off N1's floor")
	assert_false(bool(r2["d1_pass"]))
	assert_gt(int(r2["d2_far_nodes"]), 0)
	assert_false(bool(r2["d2_pass"]))
	assert_almost_eq(float(r2["d2_max"]), 0.205, 1e-3)
	assert_eq(int(r2["n1_stems"]), 2)


func test_floor_band_share_counts_nodes_between_contact_and_effective_contact() -> void:
	var mid := _line(Vector3(-0.95, 0.2, 0.03), Vector3(-0.85, 1.2, 0.03), 10)
	var r: Dictionary = Probe.analyse(_plant([mid]), [])
	assert_almost_eq(float(r["floor_band_share"]), 1.0, 1e-9, "every node 0.03 m off the floor")
	assert_almost_eq(float(r["d1_share"]), 0.0, 1e-9)


## ivy-b1e.21 (SD-MESH-19.5 D1, ratified): >= 95 % of floor-zone nodes within EFFECTIVE_CONTACT
## (0.045 m) of the floor AND median distance to the floor <= D_CONTACT (0.02 m).
func test_d1_passes_a_panel_stem_one_centimetre_off_the_floor() -> void:
	var near := _line(Vector3(-0.90, 0.2, 0.01), Vector3(-0.90, 1.2, 0.01), 10)
	var r: Dictionary = Probe.analyse(_plant([near]), [])
	assert_eq(int(r["floor_nodes"]), 11)
	assert_almost_eq(float(r["d1_share_effective"]), 1.0, 1e-9)
	assert_almost_eq(float(r["d1_median"]), 0.01, 1e-6)
	assert_true(bool(r["d1_pass"]))


func test_d1_fails_on_the_median_when_every_node_is_three_centimetres_off() -> void:
	var mid := _line(Vector3(-0.90, 0.2, 0.03), Vector3(-0.90, 1.2, 0.03), 10)
	var r: Dictionary = Probe.analyse(_plant([mid]), [])
	assert_almost_eq(float(r["d1_share_effective"]), 1.0, 1e-9, "all within 0.045 m")
	assert_almost_eq(float(r["d1_median"]), 0.03, 1e-6)
	assert_almost_eq(float(r["floor_p95"]), 0.03, 1e-6)
	assert_false(bool(r["d1_pass"]), "median 0.03 m > 0.02 m")


func test_d1_fails_on_the_share_when_ten_percent_are_ten_centimetres_off() -> void:
	# 18 nodes at 0.005 m and 2 at 0.10 m: 90 % within 0.045 m, median 0.005 m.
	var close := _line(Vector3(-0.90, 0.1, 0.005), Vector3(-0.90, 1.3, 0.005), 17)
	var off := _line(Vector3(-0.85, 0.5, 0.10), Vector3(-0.85, 0.6, 0.10), 1)
	var r: Dictionary = Probe.analyse(_plant([close, off]), [])
	assert_eq(int(r["floor_nodes"]), 20)
	assert_almost_eq(float(r["d1_share_effective"]), 0.9, 1e-9)
	assert_lte(float(r["d1_median"]), 0.02, "the median line holds")
	assert_false(bool(r["d1_pass"]), "90 % < 95 %")


## ivy-b1e.21 (SD-MESH-19.5 D2, ratified): only far footprint nodes attached to the growth
## surface (|proxy phi| <= 0.045 m) fail D2; floating ones are reported.
func test_d2_counts_only_far_nodes_attached_to_the_growth_surface() -> void:
	var hanging := _line(Vector3(-0.90, 0.5, 0.10), Vector3(-0.90, 0.6, 0.10), 1)
	var floating_stub := func(_p: Vector3) -> float: return 0.10
	var r: Dictionary = Probe.analyse(_plant([hanging]), [], floating_stub)
	assert_eq(int(r["d2_far_nodes"]), 0, "floating far nodes are not gated")
	assert_eq(int(r["d2_floating_far_nodes"]), 2)
	assert_almost_eq(float(r["d2_floating_max"]), 0.10, 1e-6)
	assert_true(bool(r["d2_pass"]))
	var attached_stub := func(_p: Vector3) -> float: return 0.0
	var r2: Dictionary = Probe.analyse(_plant([hanging]), [], attached_stub)
	assert_eq(int(r2["d2_far_nodes"]), 2, "on the proxy surface yet 0.10 m off the article")
	assert_eq(int(r2["d2_floating_far_nodes"]), 0)
	assert_almost_eq(float(r2["d2_max"]), 0.10, 1e-6)
	assert_false(bool(r2["d2_pass"]))
	var r3: Dictionary = Probe.analyse(_plant([hanging]), [])
	assert_eq(int(r3["d2_far_nodes"]), 2, "without a proxy field every node counts as attached")
	assert_false(bool(r3["d2_pass"]))


## ivy-b1e.21 P2: the flat-wall control (front, z >= 0, flat, x in [-0.15, 0.30] or [0.90, 1.20]).
func test_flat_control_is_reported() -> void:
	var flat_a := _line(Vector3(0.0, 0.2, 0.01), Vector3(0.0, 1.0, 0.01), 8)
	var flat_b := _line(Vector3(1.0, 0.2, 0.03), Vector3(1.0, 0.4, 0.03), 2)
	var in_n1 := _line(Vector3(0.6, 1.0, 0.01), Vector3(0.6, 1.2, 0.01), 2)
	var r: Dictionary = Probe.analyse(_plant([flat_a, flat_b, in_n1]), [])
	assert_eq(int(r["flat_nodes"]), 12, "9 + 3 flat nodes; N1's are not flat")
	assert_almost_eq(float(r["flat_share"]), 9.0 / 12.0, 1e-9)
	assert_almost_eq(float(r["flat_median"]), 0.01, 1e-6)
	assert_almost_eq(float(r["flat_p95"]), 0.03, 1e-6)


func test_inside_solid_and_slot_threading_are_counted() -> void:
	var dive := _line(Vector3(0.0, 1.0, 0.01), Vector3(0.0, 1.2, -0.05), 4)
	var slot := _line(Vector3(1.52, 1.6, 0.01), Vector3(1.52, 2.0, -0.06), 4)
	var r: Dictionary = Probe.analyse(_plant([dive, slot]), [Vector3(0.0, 1.2, -0.05), Vector3(0.0, 0.5, 0.01)])
	assert_eq(int(r["d3_tips_inside"]), 1)
	assert_gt(int(r["d3_nodes_deep"]), 0)
	assert_false(bool(r["d3_pass"]))
	assert_gt(int(r["d4_slot_nodes"]), 0)
	assert_false(bool(r["d4_pass"]))
	# Diagnostics: where the deep nodes are, and what a second distance field says about them.
	assert_eq(int(r["d3_by_feature"]["flat"]), 3)
	assert_eq((r["d3_samples"] as Array).size(), int(r["d3_nodes_deep"]))
	var proxy_phi := func(p: Vector3) -> float: return p.z  # a flat wall at z = 0
	var r2: Dictionary = Probe.analyse(_plant([dive]), [], proxy_phi)
	assert_eq(int(r2["d3_nodes_deep_in_proxy"]), 3)


func test_stems_on_the_back_face_are_not_judged_against_the_front_relief() -> void:
	# ivy-9bt7: the footprints are projections on the front wall plane. A stem on the back face
	# (z = -0.45) behind N1 or behind S1 is neither a floor-zone node nor a slot node.
	var behind_n1 := _line(Vector3(0.45, 0.70, -0.455), Vector3(0.75, 1.40, -0.455), 20)
	var behind_s1 := _line(Vector3(1.52, 1.6, -0.455), Vector3(1.52, 2.4, -0.455), 20)
	var r: Dictionary = Probe.analyse(_plant([behind_n1, behind_s1]), [])
	assert_eq(int(r["floor_nodes"]), 0, "no floor-zone nodes on the back face")
	assert_eq(int(r["n1_stems"]), 0)
	assert_eq(int(r["d2_far_nodes"]), 0)
	assert_eq(int(r["d4_slot_nodes"]), 0, "no slot nodes on the back face")
	assert_eq(int(r["d3_nodes_deep"]), 0)


func test_crossings_need_attached_nodes_on_both_sides() -> void:
	# Over rib R3 (x -0.75 .. -0.60) from bay 2 to bay 3, hugging the surface.
	var over := [Vector3(-0.85, 1.0, 0.005), Vector3(-0.75, 1.0, 0.005), Vector3(-0.75, 1.0, 0.105),
		Vector3(-0.60, 1.0, 0.105), Vector3(-0.60, 1.0, 0.005), Vector3(-0.50, 1.0, 0.005)]
	# The same path 0.2 m out from the wall: no attached node anywhere.
	var floating: Array = []
	for p in over:
		floating.append(p + Vector3(0.0, 0.0, 0.2))
	# Up bay 1 across the rail.
	var climb := _line(Vector3(-1.35, 1.2, 0.005), Vector3(-1.35, 1.8, 0.005), 6)
	var r: Dictionary = Probe.analyse(_plant([over, floating, climb]), [])
	assert_eq(int(r["crossings"]), 2, "one rib crossing, one rail crossing")
	# The corner at the foot of R3: turn angles are reported at inside corners only.
	assert_gt(int(r["turn_n"]), 0)
	assert_almost_eq(float(r["turn_max"]), 90.0, 0.5)


func test_d0_needs_crossings_and_recess_evidence() -> void:
	var r: Dictionary = Probe.analyse(_plant([]), [])
	assert_false(bool(r["d0_pass"]), "no stems is inconclusive, which counts as a fail")
	assert_eq(int(r["crossings"]), 0)
	assert_eq(int(r["n1_stems"]), 0)
	assert_eq(int(r["m1_stems"]), 0)


func test_report_is_printable() -> void:
	var r: Dictionary = Probe.analyse(_plant([_line(Vector3(0.0, 0.1, 0.01), Vector3(0.0, 1.0, 0.01), 30)]), [])
	r["unrefined_share"] = 0.25
	var text: String = Probe.format_report("unit", r)
	assert_string_contains(text, "D0")
	assert_string_contains(text, "D4")
	assert_string_contains(text, "turn angle")
	assert_string_contains(text, "unrefined")
	assert_string_contains(text, "0.02-0.045")
	assert_string_contains(text, "median")
	assert_string_contains(text, "flat control")
	assert_string_contains(text, "floating")
