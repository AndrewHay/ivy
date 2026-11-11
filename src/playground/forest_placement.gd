class_name ForestPlacement
extends RefCounted

const ForestParams = preload("res://src/playground/forest_params.gd")
const ForestCamRef = preload("res://src/world/forest_cam_ref.gd")
const _SCATTER_SCRIPT := "res://src/world/village_scatter_positions.gd"


static func _scatter():
	return load(_SCATTER_SCRIPT) as GDScript


static func _lcg_step(state: int) -> int:
	return (state * 1664525 + 1013904223) & 0x7FFFFFFF


static func _lcg_f01(state: int) -> float:
	return float(state & 0x7FFFFFFF) / float(0x7FFFFFFF)


static func forest_tree_positions(
		layout: VillageLayout,
		params: ForestParams = null) -> Array[Transform3D]:
	var p := params if params != null else ForestParams.production()
	if not layout.is_generated:
		return _classic_pine_ring_positions(layout, p)
	match p.variant:
		2:
			return _forest_arc_ring(layout, p)
		0, 4:
			return _forest_tree_backdrop(layout, p)
		5:
			return _forest_wedge_collar(layout, p)
		_:
			return _forest_wedge_collar(layout, p)


static func forest_tree_xz(layout: VillageLayout, params: ForestParams = null) -> Array[Vector2]:
	var xf := forest_tree_positions(layout, params)
	var out: Array[Vector2] = []
	for t in xf:
		out.append(Vector2(t.origin.x, t.origin.z))
	return out


static func forest_blocks_camsun_view(p: Vector2, params: ForestParams = null) -> bool:
	var prm := params if params != null else ForestParams.production()
	return _camsun_corridor(p, prm)


static func _classic_pine_ring_positions(layout: VillageLayout, params: ForestParams) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var n := layout.pine_count
	var st := params.lcg_seed
	for i in range(n):
		st = _lcg_step(st)
		var angle_jitter: float = (_lcg_f01(st) - 0.5) * 0.5
		var angle: float = (float(i) / n) * TAU + angle_jitter
		st = _lcg_step(st)
		var r: float = lerpf(layout.pine_inner, layout.pine_outer, _lcg_f01(st))
		st = _lcg_step(st)
		var s: float = lerpf(params.scale_min, params.scale_max, _lcg_f01(st))
		st = _lcg_step(st)
		var rot: float = _lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(cos(angle) * r, 0.0, sin(angle) * r)))
	return out


static func _forest_wedge_collar(layout: VillageLayout, params: ForestParams) -> Array[Transform3D]:
	var g := layout.hamlet_centre_xz
	var r_lawn := layout.lawn_radius
	var target := params.effective_tree_count(layout)
	var path_segments: Array = layout.path_polylines()
	var accepted: Array[Vector2] = []
	var st := params.lcg_seed
	var attempts := 0
	var max_attempts := target * 80
	var wedge_quota := mini(target, int(ceil(float(target) * params.wedge_quota_frac)))
	while accepted.size() < target and attempts < max_attempts:
		attempts += 1
		st = _lcg_step(st)
		var wedge_only := accepted.size() < wedge_quota \
				or accepted.size() < params.wedge_min_before_collar
		var pt: Vector2
		if wedge_only or _lcg_f01(st) < params.wedge_sample_frac:
			st = _lcg_step(st)
			var r_s := lerpf(
				r_lawn - params.wedge_r_inset_m, r_lawn + params.wedge_r_outset_m,
				_lcg_f01(st))
			st = _lcg_step(st)
			var phi := lerpf(-params.wedge_phi_half_rad, params.wedge_phi_half_rad,
				_lcg_f01(st))
			pt = g + Vector2(sin(phi) * r_s, cos(phi) * r_s)
		else:
			st = _lcg_step(st)
			var px2 := lerpf(
				g.x - params.scatter_box_x_half, g.x + params.scatter_box_x_half,
				_lcg_f01(st))
			st = _lcg_step(st)
			var pz2 := lerpf(
				g.y - params.scatter_box_z_back, g.y + params.scatter_box_z_front,
				_lcg_f01(st))
			pt = Vector2(px2, pz2)
		var w := _accept_weight(pt, g, r_lawn, layout, params)
		if w <= 0.0:
			continue
		st = _lcg_step(st)
		if _lcg_f01(st) > w / params.w_max:
			continue
		if not _site_ok(pt, layout, path_segments, params):
			continue
		var ok_sep := true
		for other: Vector2 in accepted:
			if pt.distance_to(other) < params.min_sep_m:
				ok_sep = false
				break
		if not ok_sep:
			continue
		accepted.append(pt)
	if params.variant == 3:
		_add_corridor_flanks(accepted, target, g, r_lawn, layout, path_segments, params)
	if accepted.size() < params.wedge_min_before_collar:
		_top_up_positions(accepted, params.wedge_min_before_collar, g, r_lawn, layout, path_segments, params)
	if accepted.size() < target:
		_top_up_positions(accepted, target, g, r_lawn, layout, path_segments, params, false)
	return _transforms_from_xz(accepted, params, st)


## Production + variant 4: dense lawn band 40–55 m from CamSun, behind cottages.
static func _forest_tree_backdrop(layout: VillageLayout, params: ForestParams) -> Array[Transform3D]:
	var g := layout.hamlet_centre_xz
	var target := params.effective_tree_count(layout)
	var path_segments: Array = layout.path_polylines()
	var accepted: Array[Vector2] = []
	var st := params.lcg_seed
	var attempts := 0
	var max_attempts := target * 120
	var sep := params.backdrop_min_sep_m
	while accepted.size() < target and attempts < max_attempts:
		attempts += 1
		st = _lcg_step(st)
		var cd := lerpf(params.backdrop_cam_dist_lo_m, params.backdrop_cam_dist_hi_m, _lcg_f01(st))
		st = _lcg_step(st)
		var bearing := lerpf(
			-params.backdrop_phi_half_rad, params.backdrop_phi_half_rad, _lcg_f01(st))
		var pt := _layout_from_camsun_polar(cd, bearing, params)
		var w := _backdrop_weight(pt, g, params)
		if w <= 0.0:
			continue
		st = _lcg_step(st)
		if _lcg_f01(st) > w / params.w_max:
			continue
		if not _site_ok_backdrop(pt, layout, path_segments, params):
			continue
		var ok_sep := true
		for other: Vector2 in accepted:
			if pt.distance_to(other) < sep:
				ok_sep = false
				break
		if not ok_sep:
			continue
		accepted.append(pt)
	_top_up_tree_backdrop(accepted, target, g, layout, path_segments, params)
	return _transforms_from_xz(accepted, params, st, params.backdrop_tree_scale_mul)


static func debug_cam_horiz_dist(layout_pt: Vector2, params: ForestParams = null) -> float:
	var prm := params if params != null else ForestParams.production()
	return _camsun_cam_horizontal_dist(layout_pt, prm)


static func _layout_from_camsun_polar(
		cam_dist: float, bearing: float, params: ForestParams) -> Vector2:
	var pivot := ForestCamRef.resolve_orbit_pivot(params)
	var cam := ForestCamRef.camsun_eye(pivot, ForestCamRef.resolve_rig_scale(params))
	var off := ForestCamRef.backdrop_origin(pivot)
	var fwd := ForestCamRef.camsun_forward()
	var right := Vector3(1.0, 0.0, 0.0)
	var rel := fwd * cam_dist * cos(bearing) + right * cam_dist * sin(bearing)
	var wp_x := cam.x + rel.x
	var wp_z := cam.z + rel.z
	return Vector2(wp_x - off.x, wp_z - off.z)


static func _backdrop_weight(p: Vector2, g: Vector2, params: ForestParams) -> float:
	var d := _camsun_cam_horizontal_dist(p, params)
	if d < params.backdrop_cam_dist_lo_m - 0.5 or d > params.backdrop_cam_dist_hi_m + 0.5:
		return 0.0
	var pivot := ForestCamRef.resolve_orbit_pivot(params)
	var off := ForestCamRef.backdrop_origin(pivot)
	var cam := ForestCamRef.camsun_eye(pivot, ForestCamRef.resolve_rig_scale(params))
	var wp := Vector2(p.x + off.x, p.y + off.z)
	var fwd := ForestCamRef.camsun_forward()
	var rel := Vector3(wp.x - cam.x, 0.0, wp.y - cam.z)
	if rel.length() < 0.5:
		return 0.0
	if fwd.dot(rel / rel.length()) < 0.08:
		return 0.0
	var dg := p - g
	var phi := atan2(dg.x, -dg.y)
	if absf(phi) > params.backdrop_phi_half_rad:
		return 0.0
	return params.wedge_weight


static func _top_up_tree_backdrop(
		accepted: Array[Vector2],
		target: int,
		g: Vector2,
		layout: VillageLayout,
		path_segments: Array,
		params: ForestParams) -> void:
	var sep := params.backdrop_min_sep_m
	var cd := params.backdrop_cam_dist_lo_m
	while cd <= params.backdrop_cam_dist_hi_m and accepted.size() < target:
		var bearing := -params.backdrop_phi_half_rad
		while bearing <= params.backdrop_phi_half_rad and accepted.size() < target:
			var p := _layout_from_camsun_polar(cd, bearing, params)
			if _backdrop_weight(p, g, params) > 0.0:
				_try_accept_backdrop(p, accepted, g, layout, path_segments, params, sep)
			bearing += 0.07
		cd += sep * 0.85


static func _try_accept_backdrop(
		p: Vector2,
		accepted: Array[Vector2],
		g: Vector2,
		layout: VillageLayout,
		path_segments: Array,
		params: ForestParams,
		sep: float) -> bool:
	if _backdrop_weight(p, g, params) <= 0.0:
		return false
	if not _site_ok_backdrop(p, layout, path_segments, params):
		return false
	for other: Vector2 in accepted:
		if p.distance_to(other) < sep:
			return false
	accepted.append(p)
	return true


static func _site_ok_backdrop(
		p: Vector2, layout: VillageLayout, path_segments: Array, params: ForestParams) -> bool:
	if VillageLayout.inside_cottages(layout.cottages, p, 0.45):
		return false
	var scatter: Script = load(_SCATTER_SCRIPT)
	if scatter.call("blocks_scatter_at", p):
		return false
	if float(scatter.call("min_xz_dist_to_path_segments", p, path_segments)) < 0.55:
		return false
	if params.camsun_corridor_on and _camsun_corridor(p, params):
		return false
	var g := layout.hamlet_centre_xz
	var rg := p.distance_to(g)
	if rg < params.backdrop_min_g_dist_m or rg > params.backdrop_lawn_max_g_dist_m:
		return false
	if p.distance_to(VillageLayout.HERO_DOOR_STOOP) < params.backdrop_min_hero_dist_m:
		return false
	return true


static func _forest_arc_ring(layout: VillageLayout, params: ForestParams) -> Array[Transform3D]:
	var g := layout.hamlet_centre_xz
	var r_lawn := layout.lawn_radius
	var target := params.effective_tree_count(layout)
	var path_segments: Array = layout.path_polylines()
	var accepted: Array[Vector2] = []
	var st := params.lcg_seed
	var attempts := 0
	var max_attempts := target * 120
	var r_in := r_lawn + params.arc_r_inner_offset_m
	var r_out := r_lawn + params.arc_r_outer_offset_m
	while accepted.size() < target and attempts < max_attempts:
		attempts += 1
		st = _lcg_step(st)
		var r_s := lerpf(r_in, r_out, _lcg_f01(st))
		st = _lcg_step(st)
		var phi := lerpf(-params.arc_phi_half_rad, params.arc_phi_half_rad,
			_lcg_f01(st))
		var pt := g + Vector2(sin(phi) * r_s, cos(phi) * r_s)
		var w := _arc_accept_weight(pt, g, r_lawn, r_s, r_in, r_out, params)
		if w <= 0.0:
			continue
		st = _lcg_step(st)
		if _lcg_f01(st) > w / params.w_max:
			continue
		if not _site_ok(pt, layout, path_segments, params):
			continue
		var ok_sep := true
		for other: Vector2 in accepted:
			if pt.distance_to(other) < params.min_sep_m:
				ok_sep = false
				break
		if not ok_sep:
			continue
		accepted.append(pt)
	if accepted.size() < target:
		_top_up_arc(accepted, target, g, r_lawn, layout, path_segments, params)
	return _transforms_from_xz(accepted, params, st)


static func _transforms_from_xz(
		accepted: Array[Vector2], params: ForestParams, st: int, extra_scale_mul: float = 1.0) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var scale_mul := extra_scale_mul
	for p in accepted:
		st = _lcg_step(st)
		var s: float = lerpf(params.scale_min, params.scale_max, _lcg_f01(st)) * scale_mul
		st = _lcg_step(st)
		var rot: float = _lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))
	return out


static func _camsun_cam_horizontal_dist(layout_pt: Vector2, params: ForestParams) -> float:
	var pivot := ForestCamRef.resolve_orbit_pivot(params)
	var off := ForestCamRef.backdrop_origin(pivot)
	var wp := Vector2(layout_pt.x + off.x, layout_pt.y + off.z)
	var cam := ForestCamRef.camsun_eye(pivot, ForestCamRef.resolve_rig_scale(params))
	return Vector2(wp.x - cam.x, wp.y - cam.z).length()


static func _in_wedge(p: Vector2, g: Vector2, r_lawn: float, params: ForestParams) -> bool:
	if p.y <= VillageLayout.HERO_DOOR_STOOP.y + 1.0:
		return false
	var dg := p - g
	var r_g := dg.length()
	if r_g < r_lawn - params.wedge_r_inset_m or r_g > r_lawn + params.wedge_r_outset_m:
		return false
	var phi := atan2(dg.x, dg.y)
	return absf(phi) <= params.wedge_phi_half_rad


static func _accept_weight(
		p: Vector2, g: Vector2, r_lawn: float, _layout: VillageLayout, params: ForestParams) -> float:
	var dg := p - g
	var r_g := dg.length()
	if p.y <= params.back_yard_z_max and r_g < r_lawn:
		return 0.0
	if _in_flank_strip(p, params):
		return params.flank_weight
	if _in_wedge(p, g, r_lawn, params):
		var w := params.wedge_weight
		if params.variant == 1 and params.deep_outer_bias > 0.0:
			var t := (r_g - (r_lawn - params.wedge_r_inset_m)) \
				/ maxf(params.wedge_r_outset_m + params.wedge_r_inset_m, 0.01)
			w *= lerpf(1.0, 1.0 + params.deep_outer_bias, clampf(t, 0.0, 1.0))
		return w
	if r_g >= r_lawn - params.collar_inset_m and r_g <= r_lawn + params.collar_outer_m \
			and p.y <= g.y + 6.0:
		var w := params.collar_weight_lo
		var phi := rad_to_deg(atan2(dg.x, -(dg.y)))
		if absf(phi) <= 75.0 and r_g >= r_lawn - params.collar_inset_m \
				and r_g <= r_lawn + 10.0:
			w = params.collar_weight_hi
		return w
	if p.y > 0.0 and p.y <= params.back_yard_z_max:
		return 0.0
	return params.scatter_weight


static func _arc_accept_weight(
		p: Vector2, g: Vector2, r_lawn: float, r_s: float, r_in: float, r_out: float,
		params: ForestParams) -> float:
	if p.y <= VillageLayout.HERO_DOOR_STOOP.y + 1.0:
		return 0.0
	var dg := p - g
	var r_g := dg.length()
	if r_g < r_in - 0.5 or r_g > r_out + 0.5:
		return 0.0
	var phi := absf(atan2(dg.x, dg.y))
	if phi > params.arc_phi_half_rad:
		return 0.0
	var t := (r_s - r_in) / maxf(r_out - r_in, 0.01)
	return lerpf(params.wedge_weight * 0.85, params.wedge_weight * 1.35, clampf(t, 0.0, 1.0))


static func _in_flank_strip(p: Vector2, params: ForestParams) -> bool:
	if params.variant != 3:
		return false
	var h := VillageLayout.HERO_DOOR_STOOP
	if p.y < params.camsun_z_min or p.y > params.camsun_z_max + 12.0:
		return false
	var dx := absf(p.x - h.x)
	return dx >= params.flank_x_offset_m and dx <= params.flank_x_offset_m + 8.0


static func _add_corridor_flanks(
		accepted: Array[Vector2],
		target: int,
		g: Vector2,
		r_lawn: float,
		layout: VillageLayout,
		path_segments: Array,
		params: ForestParams) -> void:
	var h := VillageLayout.HERO_DOOR_STOOP
	var z := params.camsun_z_min
	while z <= params.camsun_z_max + 10.0 and accepted.size() < target:
		for sign: float in [-1.0, 1.0]:
			var x: float = h.x + sign * params.flank_x_offset_m
			var pt := Vector2(x, z)
			if _accept_weight(pt, g, r_lawn, layout, params) <= 0.0:
				continue
			_try_accept(pt, accepted, g, r_lawn, layout, path_segments, params)
		z += params.min_sep_m


static func _top_up_positions(
		accepted: Array[Vector2],
		target: int,
		g: Vector2,
		r_lawn: float,
		layout: VillageLayout,
		path_segments: Array,
		params: ForestParams,
		wedge_only: bool = true) -> void:
	var r_step := params.min_sep_m
	var phi_step := 0.12
	var r := r_lawn - params.wedge_r_inset_m
	while r <= r_lawn + params.wedge_r_outset_m and accepted.size() < target:
		var phi := -params.wedge_phi_half_rad
		while phi <= params.wedge_phi_half_rad and accepted.size() < target:
			var p := g + Vector2(sin(phi) * r, cos(phi) * r)
			if wedge_only or _in_wedge(p, g, r_lawn, params):
				_try_accept(p, accepted, g, r_lawn, layout, path_segments, params)
			phi += phi_step
		r += r_step
	if wedge_only or accepted.size() >= target:
		return
	r = r_lawn - params.collar_inset_m
	while r <= r_lawn + params.collar_outer_m and accepted.size() < target:
		var phi := -1.2
		while phi <= 1.2 and accepted.size() < target:
			var p := g + Vector2(sin(phi) * r, cos(phi) * r)
			if not _in_wedge(p, g, r_lawn, params):
				_try_accept(p, accepted, g, r_lawn, layout, path_segments, params)
			phi += phi_step
		r += r_step


static func _top_up_arc(
		accepted: Array[Vector2],
		target: int,
		g: Vector2,
		r_lawn: float,
		layout: VillageLayout,
		path_segments: Array,
		params: ForestParams) -> void:
	var r_in := r_lawn + params.arc_r_inner_offset_m
	var r_out := r_lawn + params.arc_r_outer_offset_m
	var r_step := params.min_sep_m
	var r := r_in
	while r <= r_out and accepted.size() < target:
		var phi := -params.arc_phi_half_rad
		while phi <= params.arc_phi_half_rad and accepted.size() < target:
			var p := g + Vector2(sin(phi) * r, cos(phi) * r)
			_try_accept(p, accepted, g, r_lawn, layout, path_segments, params)
			phi += 0.12
		r += r_step


static func _try_accept(
		p: Vector2,
		accepted: Array[Vector2],
		g: Vector2,
		r_lawn: float,
		layout: VillageLayout,
		path_segments: Array,
		params: ForestParams,
		weight_fn: Callable = Callable()) -> bool:
	var w := 0.0
	if weight_fn.is_valid():
		w = float(weight_fn.call(p, g, r_lawn, layout, params))
	else:
		w = _accept_weight(p, g, r_lawn, layout, params)
	if w <= 0.0:
		return false
	if not _site_ok(p, layout, path_segments, params):
		return false
	for other: Vector2 in accepted:
		if p.distance_to(other) < params.min_sep_m:
			return false
	accepted.append(p)
	return true


static func _site_ok(
		p: Vector2, layout: VillageLayout, path_segments: Array, params: ForestParams) -> bool:
	if VillageLayout.inside_cottages(layout.cottages, p, 0.45):
		return false
	var scatter: Script = load(_SCATTER_SCRIPT)
	if scatter.call("blocks_scatter_at", p):
		return false
	if float(scatter.call("min_xz_dist_to_path_segments", p, path_segments)) < 0.55:
		return false
	if params.camsun_corridor_on and _camsun_corridor(p, params):
		return false
	var g := layout.hamlet_centre_xz
	if p.distance_to(g) < layout.lawn_radius - 4.0:
		return false
	return true


static func _camsun_corridor(p: Vector2, params: ForestParams) -> bool:
	var h := VillageLayout.HERO_DOOR_STOOP
	if p.y > h.y + params.camsun_corridor_y_slack:
		return false
	if p.y < params.camsun_z_min or p.y > params.camsun_z_max:
		return false
	return absf(p.x - h.x) <= params.camsun_x_half
