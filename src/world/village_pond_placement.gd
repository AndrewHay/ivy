class_name VillagePondPlacement
extends RefCounted

## Resolve and validate village pond centre XZ for classic and generated layouts.

const _COARSE_STEP_M := 2.0
const _REFINE_STEP_M := 0.75
const _COARSE_EVAL_CAP := 64
const _REFINE_EVAL_CAP := 24
const _REFINE_ANCHORS := 3


static func resolve_center(layout: VillageLayout) -> Vector2:
	if layout.pond_placed:
		return layout.pond_center
	if _is_authored_layout(layout):
		return VillagePondSite.CLASSIC_CENTER
	return _resolve_generated_center(layout, false)


## Re-scan after paths exist (B2); keeps layout.pond_placed true.
static func resolve_after_paths(layout: VillageLayout) -> Vector2:
	if _is_authored_layout(layout):
		return VillagePondSite.CLASSIC_CENTER
	return _resolve_generated_center(layout, true)


static func _resolve_generated_center(layout: VillageLayout, require_paths: bool) -> Vector2:
	var cache := _make_scan_cache(layout)
	var coarse := _coarse_centers(layout)
	_shuffle_centers(coarse, layout.stone_seed)

	var best_center := Vector2.ZERO
	var best_margin := -INF
	var refine_anchors: Array[Vector2] = []
	var evaluated := 0

	for center: Vector2 in coarse:
		if evaluated >= _COARSE_EVAL_CAP:
			break
		evaluated += 1
		if not _cheap_slot_ok(center, layout, require_paths, cache):
			continue
		if _validate_with_single_shape(center, layout, require_paths):
			return center
		var margin := _center_to_cottages_margin(center, layout.cottages)
		if margin > best_margin:
			best_margin = margin
			best_center = center
			refine_anchors.append(center)
			if refine_anchors.size() > _REFINE_ANCHORS:
				refine_anchors.pop_front()

	if not refine_anchors.is_empty():
		var refine := _refine_offsets()
		var r_eval := 0
		for anchor: Vector2 in refine_anchors:
			for off: Vector2 in refine:
				if r_eval >= _REFINE_EVAL_CAP:
					break
				r_eval += 1
				var center := anchor + off
				if not _cheap_slot_ok(center, layout, require_paths, cache):
					continue
				if _validate_with_single_shape(center, layout, require_paths):
					return center
				var margin := _center_to_cottages_margin(center, layout.cottages)
				if margin > best_margin:
					best_margin = margin
					best_center = center

	if best_center != Vector2.ZERO \
			and _validate_with_single_shape(best_center, layout, require_paths) \
			and not pond_overlaps_plaza_exclusion(best_center, layout):
		push_warning("VillagePondPlacement: using best-effort generated pond slot")
		return best_center
	if best_center != Vector2.ZERO:
		push_warning("VillagePondPlacement: no valid generated pond centre in scan disk")
	return best_center


static func plaza_exclusion_rect(layout: VillageLayout) -> Rect2:
	return layout.plaza_rect.grow(-1.0)


## Circle bound on bank (no spline build) — conservative for exclusion tests.
static func pond_overlaps_plaza_exclusion(center: Vector2, layout: VillageLayout) -> bool:
	if not layout.is_generated or layout.plaza_rect.size.x < 1e-3:
		return false
	return _circle_overlaps_rect(
		center,
		VillagePondSite.BANK_OUTER_M + layout.pond_path_clearance_m,
		plaza_exclusion_rect(layout))


static func has_phase1_slot(layout: VillageLayout) -> bool:
	var cache := _make_scan_cache(layout)
	var coarse := _coarse_centers(layout)
	_shuffle_centers(coarse, layout.stone_seed)
	var evaluated := 0
	for center: Vector2 in coarse:
		if evaluated >= _COARSE_EVAL_CAP:
			break
		evaluated += 1
		if not _cheap_slot_ok(center, layout, false, cache):
			continue
		if _validate_with_single_shape(center, layout, false):
			return true
	return false


static func validate(center: Vector2, layout: VillageLayout, require_path_clearance: bool = true) -> bool:
	return _validate_with_single_shape(center, layout, require_path_clearance)


static func _validate_with_single_shape(
		center: Vector2, layout: VillageLayout, require_paths: bool) -> bool:
	if not _cheap_slot_ok(center, layout, require_paths, _make_scan_cache(layout)):
		return false
	var shape := VillagePondShape.at(center)
	var bank := shape.bank_outer_outline_world_xz()
	if bank.size() < 3:
		return false
	if not _hero_distance_ok(bank):
		return false
	if not _lawn_distance_ok(bank, layout.lawn_radius):
		return false
	if not _cottage_clearance_ok(bank, layout.cottages, layout.pond_cottage_clearance_m):
		return false
	if require_paths and not layout.is_generated \
			and not _path_clearance_ok(bank, layout.paths, layout.pond_path_clearance_m):
		return false
	return true


static func _make_scan_cache(layout: VillageLayout) -> Dictionary:
	var cottages_grown: Array[Rect2] = []
	for spec in layout.cottages:
		cottages_grown.append(
			VillageBackdrop.cottage_exterior_rect(spec).grow(VillagePondSite.COTTAGE_ROOF_GROW_M))
	return {
		"cottages_grown": cottages_grown,
		"g": layout.hamlet_centre_xz,
		"paths": layout.paths,
	}


static func _cheap_slot_ok(
		center: Vector2,
		layout: VillageLayout,
		require_paths: bool,
		cache: Dictionary) -> bool:
	if layout.is_generated and pond_overlaps_plaza_exclusion(center, layout):
		return false
	var bank_r := VillagePondSite.BANK_OUTER_M
	if center.length() - bank_r < VillagePondSite.HERO_MIN_BANK_DIST_M:
		return false
	var g: Vector2 = cache["g"]
	var r_lawn := (center - g).length()
	if r_lawn + bank_r > layout.lawn_radius - VillagePondSite.LAWN_BANK_INSET_M:
		return false
	for rect: Rect2 in cache["cottages_grown"]:
		if _dist_point_to_rect(center, rect) \
				< layout.pond_cottage_clearance_m + bank_r:
			return false
	if require_paths:
		var paths: Array = cache["paths"]
		if not paths.is_empty():
			if VillageScatterPositions.min_xz_dist_to_path_segments(center, paths) \
					< layout.pond_path_clearance_m + bank_r:
				return false
	return true


static func _coarse_centers(layout: VillageLayout) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not layout.is_generated:
		return _classic_scan_grid(layout)
	var g := layout.hamlet_centre_xz
	var band_lo := VillagePondSite.HERO_MIN_BANK_DIST_M + VillagePondSite.BANK_OUTER_M
	var band_hi := layout.lawn_radius - VillagePondSite.LAWN_BANK_INSET_M - VillagePondSite.BANK_OUTER_M
	if band_hi <= band_lo:
		return out
	var extent := band_hi + 1.0
	var x := -extent
	while x <= extent:
		var z := -extent
		while z <= extent:
			var c := g + Vector2(x, z)
			var r := (c - g).length()
			if r >= band_lo and r <= band_hi:
				out.append(c)
			z += _COARSE_STEP_M
		x += _COARSE_STEP_M
	var pr := layout.plaza_rect
	if pr.size.x > 1e-3:
		var pad := VillagePondSite.BANK_OUTER_M + layout.pond_path_clearance_m + 1.0
		for dx: float in [-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0]:
			out.append(Vector2(g.x + dx, pr.position.y - pad))
			out.append(Vector2(g.x + dx, pr.end.y + pad))
		for dz: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			out.append(Vector2(pr.position.x - pad, g.y + dz))
			out.append(Vector2(pr.end.x + pad, g.y + dz))
	return out


static func _classic_scan_grid(layout: VillageLayout) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var step := 1.25
	var centre_r_max := layout.lawn_radius - VillagePondSite.LAWN_BANK_INSET_M - VillagePondSite.BANK_OUTER_M
	var centre_r_min := VillagePondSite.HERO_MIN_BANK_DIST_M - VillagePondSite.BANK_OUTER_M * 0.35
	if centre_r_max <= centre_r_min:
		return out
	var extent := layout.lawn_radius - VillagePondSite.BANK_OUTER_M
	var x0 := -extent
	while x0 <= extent:
		var z0 := -extent
		while z0 <= extent:
			var c0 := Vector2(x0, z0)
			var r0 := c0.length()
			if r0 >= centre_r_min and r0 <= centre_r_max:
				out.append(c0)
			z0 += step
		x0 += step
	return out


static func _refine_offsets() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for ix: int in range(-1, 2):
		for iz: int in range(-1, 2):
			out.append(Vector2(float(ix) * _REFINE_STEP_M, float(iz) * _REFINE_STEP_M))
	return out


static func _shuffle_centers(centers: Array[Vector2], seed_st: int) -> void:
	var st := seed_st
	for i: int in range(centers.size() - 1, 0, -1):
		st = VillageScatterPositions.lcg_step(st)
		var j := int(VillageScatterPositions.lcg_f01(st) * float(i + 1)) % (i + 1)
		var tmp := centers[i]
		centers[i] = centers[j]
		centers[j] = tmp


static func _circle_overlaps_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	if rect.has_point(center):
		return true
	return _dist_point_to_rect(center, rect) < radius


static func _is_authored_layout(layout: VillageLayout) -> bool:
	return not layout.is_generated


static func _center_to_cottages_margin(center: Vector2, cottages: Array) -> float:
	var best := INF
	for spec in cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(VillagePondSite.COTTAGE_ROOF_GROW_M)
		best = minf(best, _dist_point_to_rect(center, rect))
	return best


static func _hero_distance_ok(bank: PackedVector2Array) -> bool:
	var min_r := INF
	for v in bank:
		min_r = minf(min_r, v.length())
	return min_r >= VillagePondSite.HERO_MIN_BANK_DIST_M


static func _lawn_distance_ok(bank: PackedVector2Array, lawn_radius: float) -> bool:
	var max_r := 0.0
	for v in bank:
		max_r = maxf(max_r, v.length())
	return max_r <= lawn_radius - VillagePondSite.LAWN_BANK_INSET_M


static func _cottage_clearance_ok(
		bank: PackedVector2Array, cottages: Array, cottage_clearance_m: float) -> bool:
	var stride := maxi(1, bank.size() / 8)
	for spec in cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(VillagePondSite.COTTAGE_ROOF_GROW_M)
		for i: int in range(0, bank.size(), stride):
			if _dist_point_to_rect(bank[i], rect) < cottage_clearance_m:
				return false
	return true


static func _path_clearance_ok(
		bank: PackedVector2Array, paths: Array, path_clearance_m: float) -> bool:
	if paths.is_empty():
		return true
	var stride := maxi(1, bank.size() / 6)
	for i: int in range(0, bank.size(), stride):
		if VillageScatterPositions.min_xz_dist_to_path_segments(bank[i], paths) \
				< path_clearance_m:
			return false
	return true


static func _dist_point_to_rect(p: Vector2, rect: Rect2) -> float:
	var cx := clampf(p.x, rect.position.x, rect.end.x)
	var cz := clampf(p.y, rect.position.y, rect.end.y)
	return p.distance_to(Vector2(cx, cz))


static func segment_point_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return _dist_point_to_segment(p, a, b)


static func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	var t := 0.0
	if ab_len_sq > 0.0:
		t = clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	return p.distance_to(a.lerp(b, t))
