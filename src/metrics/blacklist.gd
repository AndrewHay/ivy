class_name BlacklistAssertions
extends RefCounted

## D-5 automatable artifact-blacklist checks (W-022).
##
## Items 1, 2, 5, 6 are hard gates. Items 3 and 4 are numeric auto-screens
## (reported; human confirms). Item 7 is human review — preventative adjacency
## guard only; reports INCONCLUSIVE when leaf mass is too sparse to judge.

const THROUGH_WALL_PHI_SLACK_FACTOR := 2.5
const PETIOLE_STEM_SLACK := 0.002
const WIDTH_MIN_FRAC := 0.4
const WIDTH_MAX_FRAC := 1.6
const WIDTH_CV_MAX := 0.35
const SEED_GROUND_EXEMPT_RADIUS := 0.10
const COPLANAR_DIST := 0.03
const COPLANAR_NORMAL_DOT := 0.98
const COPLANAR_OFFSET_MAX := 0.002
const DIRECTION_BINS := 36
const FOURFOLD_FAIL_RATIO := 0.15
const ITEM7_MIN_LEAVES := 500
const ITEM7_ROT_ROUND_DEG := 15.0

const _LeafAtlas = preload("res://src/render/leaf_atlas.gd")
const MaterialRegistry = preload("res://src/world/material_registry.gd")


static func measure(
	plant: PlantData,
	tips: TipManager,
	surface: SurfaceQuery,
	params: IvyParams,
	seed_pos: Vector3,
	spec: TowerSpec = null
) -> Dictionary:
	var hard_failures: PackedStringArray = []
	_check_through_wall(plant, surface, params, spec, hard_failures)
	_check_float_off(plant, tips, surface, params, hard_failures)
	_check_leaf_attachment_and_scale(plant, params, hard_failures)
	_check_ground_and_air(plant, surface, params, seed_pos, hard_failures)

	var dir_ratio := _direction_fourfold_ratio(plant)
	var fft_ratio := _leaf_density_grid_peak_ratio(plant, params)
	var coplanar := _coplanar_leaf_pair_count(plant)

	var item7 := _item7_adjacency_status(plant)

	return {
		"hard_pass": hard_failures.is_empty(),
		"hard_failures": hard_failures,
		"direction_fourfold_ratio": dir_ratio,
		"direction_fourfold_fail": dir_ratio > FOURFOLD_FAIL_RATIO,
		"density_fft_peak_ratio": fft_ratio,
		"coplanar_pair_count": coplanar,
		"item7_status": item7.status,
		"item7_detail": item7.detail,
	}


static func hard_pass(result: Dictionary) -> bool:
	return bool(result.get("hard_pass", false))


static func _check_through_wall(
	plant: PlantData,
	surface: SurfaceQuery,
	params: IvyParams,
	spec: TowerSpec,
	failures: PackedStringArray
) -> void:
	var phi_min := -params.contact_distance * THROUGH_WALL_PHI_SLACK_FACTOR
	for i in plant.segment_count():
		for pt in [plant.seg_a[i], plant.seg_b[i]]:
			var near := surface.nearest(pt)
			if near.material_id == MaterialRegistry.OPENING_REVEAL \
					or near.material_id == MaterialRegistry.INTERIOR:
				continue
			if spec != null:
				var r := Vector2(pt.x, pt.z).length()
				if r < spec.radius_inner() - 0.05:
					continue
			var phi := surface.signed_distance(pt)
			if phi < phi_min:
				failures.append(
					"item1 through-wall: segment %d phi=%.5f at %s" % [i, phi, pt]
				)


static func _check_float_off(
	plant: PlantData,
	tips: TipManager,
	surface: SurfaceQuery,
	params: IvyParams,
	failures: PackedStringArray
) -> void:
	for t in tips.tips:
		if not t.is_live():
			continue
		if t.state == Tip.State.GROWING and t.floating_length > 0.001:
			failures.append(
				"item2 float counter: tip %d GROWING with F=%.4f"
				% [t.id, t.floating_length]
			)
		if t.state == Tip.State.FLOATING and t.floating_length > params.max_float + 0.05:
			failures.append(
				"item2 float counter: tip %d F=%.4f > max_float=%.4f"
				% [t.id, t.floating_length, params.max_float]
			)
	var max_phi := params.max_float + params.adhesion_range
	for i in plant.segment_count():
		for pt in [plant.seg_a[i], plant.seg_b[i]]:
			var phi := surface.signed_distance(pt)
			if phi > max_phi + 1e-5:
				failures.append(
					"item2 float-off SDF: segment %d phi=%.4f > %.4f at %s"
					% [i, phi, max_phi, pt]
				)


static func _check_leaf_attachment_and_scale(
	plant: PlantData, params: IvyParams, failures: PackedStringArray
) -> void:
	if plant.leaf_count() == 0:
		return
	var w0 := params.leaf_width_base
	var widths: PackedFloat32Array = PackedFloat32Array()
	widths.resize(plant.leaf_count())
	for i in plant.leaf_count():
		var origin := _leaf_origin(plant, i)
		var petiole_tol := params.leaf_offset_base \
			+ params.leaf_offset_step * float(maxi(params.leaf_offset_ladder - 1, 0)) \
			+ PETIOLE_STEM_SLACK
		var stem_d := _distance_to_stem_polyline(plant, origin)
		if stem_d > petiole_tol:
			failures.append(
				"item5 detached petiole: leaf %d stem_dist=%.5f > %.5f at %s"
				% [i, stem_d, petiole_tol, origin]
			)
		var w := Vector3(
			plant.leaf_xform[i * 12],
			plant.leaf_xform[i * 12 + 1],
			plant.leaf_xform[i * 12 + 2]
		).length()
		widths[i] = w
		if w < WIDTH_MIN_FRAC * w0 - 1e-5 or w > WIDTH_MAX_FRAC * w0 + 1e-5:
			failures.append(
				"item5 leaf width: leaf %d w=%.5f outside [%.4f, %.4f]"
				% [i, w, WIDTH_MIN_FRAC * w0, WIDTH_MAX_FRAC * w0]
			)
	var cv := _coefficient_of_variation(widths)
	if cv > WIDTH_CV_MAX + 1e-5:
		failures.append("item5 width CV=%.4f exceeds %.2f" % [cv, WIDTH_CV_MAX])


static func _check_ground_and_air(
	plant: PlantData,
	surface: SurfaceQuery,
	params: IvyParams,
	seed_pos: Vector3,
	failures: PackedStringArray
) -> void:
	for i in plant.segment_count():
		for pt in [plant.seg_a[i], plant.seg_b[i]]:
			if pt.y < params.ground_y_min - 1e-5:
				var horiz := Vector2(pt.x - seed_pos.x, pt.z - seed_pos.z).length()
				if horiz > SEED_GROUND_EXEMPT_RADIUS:
					failures.append(
						"item6 ground growth: segment %d y=%.4f >%.1fm from seed at %s"
						% [i, pt.y, SEED_GROUND_EXEMPT_RADIUS, pt]
					)


static func _direction_fourfold_ratio(plant: PlantData) -> float:
	var bins := PackedFloat32Array()
	bins.resize(DIRECTION_BINS)
	for i in plant.segment_count():
		var d := plant.seg_b[i] - plant.seg_a[i]
		var horiz := Vector2(d.x, d.z)
		if horiz.length_squared() < 1e-8:
			continue
		var ang := fposmod(atan2(horiz.x, -horiz.y), TAU)
		var idx := int(floor(ang / TAU * float(DIRECTION_BINS))) % DIRECTION_BINS
		bins[idx] += d.length()
	var dc := 0.0
	for b in bins:
		dc += b
	dc /= float(DIRECTION_BINS)
	if dc < 1e-8:
		return 0.0
	var c4_re := 0.0
	var c4_im := 0.0
	for k in DIRECTION_BINS:
		var ang := TAU * float(k) / float(DIRECTION_BINS)
		c4_re += bins[k] * cos(4.0 * ang)
		c4_im += bins[k] * sin(4.0 * ang)
	var four := sqrt(c4_re * c4_re + c4_im * c4_im) / float(DIRECTION_BINS)
	return four / dc


static func _leaf_density_grid_peak_ratio(plant: PlantData, params: IvyParams) -> float:
	const AZ_BINS := 72
	const Z_BINS := 35
	var grid := PackedFloat32Array()
	grid.resize(AZ_BINS * Z_BINS)
	for i in plant.leaf_count():
		var p := _leaf_origin(plant, i)
		var az := fposmod(atan2(p.x, -p.z), TAU)
		var az_i := clampi(int(floor(az / TAU * float(AZ_BINS))), 0, AZ_BINS - 1)
		var z_i := clampi(int(floor(p.y / 0.10)), 0, Z_BINS - 1)
		grid[az_i * Z_BINS + z_i] += 1.0
	var mean := 0.0
	for c in grid:
		mean += c
	mean /= float(grid.size())
	if mean < 1e-6:
		return 0.0
	var peak := 0.0
	for c in grid:
		peak = maxf(peak, c)
	return peak / mean


static func _coplanar_leaf_pair_count(plant: PlantData) -> int:
	var n := plant.leaf_count()
	if n < 2:
		return 0
	var cell := COPLANAR_DIST
	var buckets: Dictionary = {}
	for i in n:
		var p := _leaf_origin(plant, i)
		var key := Vector3i(
			int(floor(p.x / cell)),
			int(floor(p.y / cell)),
			int(floor(p.z / cell))
		)
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(i)
	var count := 0
	for _key in buckets:
		var ids: Array = buckets[_key]
		for a in range(ids.size()):
			for b in range(a + 1, ids.size()):
				if _leaves_coplanar(plant, ids[a], ids[b]):
					count += 1
	return count


static func _item7_adjacency_status(plant: PlantData) -> Dictionary:
	if plant.leaf_count() < ITEM7_MIN_LEAVES:
		return {
			"status": "inconclusive",
			"detail": "leaf_count=%d < %d — item7 requires human review at higher density"
			% [plant.leaf_count(), ITEM7_MIN_LEAVES],
		}
	var atlas := _LeafAtlas.new()
	var violations := 0
	var by_tip := _leaves_grouped_by_tip(plant)
	for tip_id in by_tip:
		var indices: Array = by_tip[tip_id]
		indices.sort_custom(func(a, b): return plant.leaf_s_at_node[a] < plant.leaf_s_at_node[b])
		for j in range(1, indices.size()):
			var prev_i: int = indices[j - 1]
			var cur_i: int = indices[j]
			if plant.leaf_s_at_node[cur_i] - plant.leaf_s_at_node[prev_i] > 0.15:
				continue
			var id_a := atlas.id_for_rect(_leaf_rect(plant, prev_i))
			var id_b := atlas.id_for_rect(_leaf_rect(plant, cur_i))
			if id_a.is_empty() or id_b.is_empty():
				continue
			if id_a != id_b:
				continue
			var rot_a := _leaf_yaw_deg(plant, prev_i)
			var rot_b := _leaf_yaw_deg(plant, cur_i)
			if int(round(rot_a / ITEM7_ROT_ROUND_DEG)) == int(round(rot_b / ITEM7_ROT_ROUND_DEG)):
				violations += 1
	if violations > 0:
		return {
			"status": "fail",
			"detail": "%d adjacent leaf pairs share atlas id and 15° rotation bucket" % violations,
		}
	return {"status": "pass", "detail": "adjacency guard clean at current density"}


static func _leaf_origin(plant: PlantData, i: int) -> Vector3:
	var base := i * 12
	return Vector3(
		plant.leaf_xform[base + 3],
		plant.leaf_xform[base + 7],
		plant.leaf_xform[base + 11]
	)


static func _leaf_rect(plant: PlantData, i: int) -> Vector4:
	var base := i * 4
	return Vector4(
		plant.leaf_custom[base],
		plant.leaf_custom[base + 1],
		plant.leaf_custom[base + 2],
		plant.leaf_custom[base + 3]
	)


static func _leaf_normal(plant: PlantData, i: int) -> Vector3:
	var base := i * 12
	return Vector3(
		plant.leaf_xform[base + 8],
		plant.leaf_xform[base + 9],
		plant.leaf_xform[base + 10]
	).normalized()


static func _leaf_yaw_deg(plant: PlantData, i: int) -> float:
	var n := _leaf_normal(plant, i)
	return rad_to_deg(atan2(n.x, n.z))


static func _leaves_coplanar(plant: PlantData, i: int, j: int) -> bool:
	var p1 := _leaf_origin(plant, i)
	var p2 := _leaf_origin(plant, j)
	if p1.distance_to(p2) > COPLANAR_DIST:
		return false
	var n1 := _leaf_normal(plant, i)
	var n2 := _leaf_normal(plant, j)
	if absf(n1.dot(n2)) < COPLANAR_NORMAL_DOT:
		return false
	var offset := absf((p2 - p1).dot(n1))
	return offset < COPLANAR_OFFSET_MAX


static func _distance_to_stem_polyline(plant: PlantData, p: Vector3) -> float:
	var best := INF
	for i in plant.segment_count():
		best = minf(best, _point_segment_distance(p, plant.seg_a[i], plant.seg_b[i]))
	return best


static func _point_segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _coefficient_of_variation(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var mean := 0.0
	for v in values:
		mean += v
	mean /= float(values.size())
	if mean < 1e-8:
		return 0.0
	var var_sum := 0.0
	for v in values:
		var d := v - mean
		var_sum += d * d
	return sqrt(var_sum / float(values.size())) / mean


static func _leaves_grouped_by_tip(plant: PlantData) -> Dictionary:
	var out: Dictionary = {}
	for i in plant.leaf_count():
		var tip_id: int = plant.leaf_tip[i]
		if not out.has(tip_id):
			out[tip_id] = []
		(out[tip_id] as Array).append(i)
	return out
