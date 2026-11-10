class_name WandererRevealCamera
extends RefCounted

const WandererParams = preload("res://src/presentation/wanderer/wanderer_params.gd")
const WandererImagePlacement = preload("res://src/presentation/wanderer/wanderer_image_placement.gd")

const COTTAGE_GROW_M := 1.0
const EYE_Y_DEFAULT := 5.0
const YAW_STEP_DEG := 15.0
const YAW_TRIES := 24
const FRUSTUM_MARGIN := 1.35
const HERO_RECT := Rect2(-5.5, -5.0, 11.0, 8.5)
const HERO_GROW_M := 0.5


static func obstruction_rects(layout: VillageLayout, grow_m: float = COTTAGE_GROW_M) -> Array:
	var rects := cottage_rects_grown(layout, grow_m)
	rects.append(HERO_RECT.grow(HERO_GROW_M))
	return rects


static func cottage_rects_grown(layout: VillageLayout, grow_m: float = COTTAGE_GROW_M) -> Array:
	var rects: Array = []
	for spec in layout.cottages:
		rects.append(VillageBackdrop.cottage_exterior_rect(spec as Dictionary).grow(grow_m))
	return rects


static func los_clear(eye_xz: Vector2, target_xz: Vector2, rects: Array) -> bool:
	if not eye_outside_cottages(eye_xz, rects):
		return false
	var steps := 20
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var p := eye_xz.lerp(target_xz, t)
		if not eye_outside_cottages(p, rects):
			return false
	return true


static func eye_outside_cottages(eye_xz: Vector2, rects: Array) -> bool:
	for r_v in rects:
		var r: Rect2 = r_v as Rect2
		if r.has_point(eye_xz):
			return false
	return true


static func subject_in_vertical_fov(
		eye: Vector3, look: Vector3, fov_y_rad: float, points: Array) -> bool:
	var fwd := (look - eye)
	if fwd.length_squared() < 1e-9:
		return false
	fwd = fwd.normalized()
	var half := fov_y_rad * 0.5
	for p_v in points:
		var p: Vector3 = p_v as Vector3
		var dir := (p - eye)
		if dir.length_squared() < 1e-9:
			continue
		dir = dir.normalized()
		if acos(clampf(fwd.dot(dir), -1.0, 1.0)) > half:
			return false
	return true


static func subject_in_frustum(
		eye: Vector3, look: Vector3, fov_y_rad: float, aspect: float, points: Array) -> bool:
	var fwd := (look - eye)
	if fwd.length_squared() < 1e-9:
		return false
	fwd = fwd.normalized()
	var half_y := fov_y_rad * 0.5
	var half_x := atan(tan(half_y) * aspect)
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	for p_v in points:
		var p: Vector3 = p_v as Vector3
		var dir := (p - eye)
		if dir.length_squared() < 1e-9:
			continue
		dir = dir.normalized()
		var z := dir.dot(fwd)
		if z <= 1e-6:
			return false
		var x := dir.dot(right)
		var y := dir.dot(up)
		if absf(x) > z * tan(half_x) + 1e-4:
			return false
		if absf(y) > z * tan(half_y) + 1e-4:
			return false
	return true


static func _fit_distance(fov_y_rad: float, height_m: float) -> float:
	return (height_m * FRUSTUM_MARGIN * 0.5) / tan(fov_y_rad * 0.5)


static func compute_reveal_front(
		placement: Dictionary,
		rects: Array,
		fov_y_rad: float,
		aspect: float,
		door_exterior: Vector2 = Vector2.ZERO,
) -> Dictionary:
	var P: Vector2 = placement.get("figure_xz", Vector2.ZERO)
	var n: Vector2 = placement.get("normal", Vector2(0, 1))
	var left: Vector2 = placement.get("left", Vector2(1, 0))
	var sz: Vector2 = placement.get("size", Vector2(7, 7))
	var H := sz.y
	var W := sz.x
	var centre: Vector3 = placement.get("centre", Vector3.ZERO)
	var head := Vector3(P.x, 2.0, P.y)
	var feet := Vector3(P.x, 0.0, P.y)
	var subjects: Array = [feet, head]
	for bc in WandererImagePlacement.bottom_corners_world(placement):
		subjects.append(bc)
		subjects.append(bc + Vector3(0.0, H, 0.0))
	var look := Vector3(centre.x, lerpf(2.0, centre.y, 0.5), centre.z)
	var span_h := H + 2.5
	var span_w := W + 2.0
	var fov_x := 2.0 * atan(tan(fov_y_rad * 0.5) * aspect)
	var d0 := maxf(
		(span_h * FRUSTUM_MARGIN * 0.5) / tan(fov_y_rad * 0.5),
		(span_w * FRUSTUM_MARGIN * 0.5) / tan(fov_x * 0.5))
	var base_view := -n
	var try_idx := 0
	for attempt in range(YAW_TRIES):
		var yaw_off := deg_to_rad(YAW_STEP_DEG * float(attempt))
		for sign in [1.0, -1.0]:
			if attempt == 0 and sign < 0:
				continue
			var view_dir: Vector2 = base_view if attempt == 0 else base_view.rotated(sign * yaw_off)
			for dist in [6.0, 8.0, 10.0, 12.0, 15.0, 20.0, 26.0]:
				var eye_xz: Vector2 = P - view_dir * float(dist)
				if not eye_outside_cottages(eye_xz, rects):
					continue
				if not los_clear(eye_xz, P, rects):
					continue
				var look_pt := Vector3(P.x, lerpf(2.0, centre.y, 0.4), P.y)
				for eye_y in [5.0, 7.0, 9.0, 12.0]:
					var eye := Vector3(eye_xz.x, eye_y, eye_xz.y)
					if subject_in_frustum(eye, look_pt, fov_y_rad, aspect, subjects) \
							or subject_in_vertical_fov(eye, look_pt, fov_y_rad, subjects):
						return {"eye": eye, "look": look_pt, "distance_m": dist, "try": try_idx}
				try_idx += 1
	for shift_i in range(16):
		var shift_m := float(shift_i) * 1.5
		for side_sign in [-1.0, 1.0]:
			if shift_i == 0 and side_sign < 0:
				continue
			var lateral: Vector2 = left * shift_m * side_sign
			var look_xz: Vector2 = Vector2(look.x, look.z) + lateral
			var look_shift := Vector3(look_xz.x, look.y, look_xz.y)
			var dist := d0
			for _dist_step in 12:
				for eye_y in [look.y, 6.5, 9.0, 12.0, 16.0]:
					var eye_xz: Vector2 = look_xz + n * dist
					if not eye_outside_cottages(eye_xz, rects):
						continue
					if not los_clear(eye_xz, P, rects):
						continue
					var eye := Vector3(eye_xz.x, eye_y, eye_xz.y)
					var in_view: bool = subject_in_frustum(eye, look_shift, fov_y_rad, aspect, subjects)
					if not in_view:
						in_view = subject_in_vertical_fov(eye, look_shift, fov_y_rad, subjects)
					if in_view:
						return {"eye": eye, "look": look_shift, "distance_m": dist, "try": try_idx}
					try_idx += 1
				dist *= 1.15
	for shift_i in range(8):
		var shift_m := float(shift_i + 1) * 2.5
		for side_sign in [-1.0, 1.0]:
			var lateral: Vector2 = left * shift_m * side_sign
			for dist in [8.0, 12.0, 18.0, 24.0]:
				var eye_xz: Vector2 = P + n * dist + lateral
				if not eye_outside_cottages(eye_xz, rects):
					continue
				var look_pt := Vector3(P.x, 3.0, P.y)
				var eye := Vector3(eye_xz.x, 6.0, eye_xz.y)
				if los_clear(eye_xz, P, rects) and subject_in_vertical_fov(eye, look_pt, fov_y_rad, subjects):
					return {"eye": eye, "look": look_pt, "distance_m": dist, "try": 100 + shift_i}
	var fb_xz := Vector2(look.x, look.z) + n * (d0 + 4.0)
	return {
		"eye": Vector3(fb_xz.x, 10.0, fb_xz.y),
		"look": look,
		"distance_m": d0 + 4.0,
		"try": -1,
	}


static func compute_reveal_oblique(
		placement: Dictionary,
		rects: Array,
		fov_y_rad: float,
		aspect: float,
		door_exterior: Vector2 = Vector2.ZERO,
		side: int = -1,
) -> Dictionary:
	var P: Vector2 = placement.get("figure_xz", Vector2.ZERO)
	var n: Vector2 = placement.get("normal", Vector2(0, 1))
	var left: Vector2 = placement.get("left", Vector2(1, 0))
	var sz: Vector2 = placement.get("size", Vector2(7, 7))
	var H := sz.y
	var centre: Vector3 = placement.get("centre", Vector3.ZERO)
	var head := Vector3(P.x, 2.0, P.y)
	var wall_near := Vector3(door_exterior.x, 0.0, door_exterior.y)
	var wall_hi := Vector3(door_exterior.x, 2.2, door_exterior.y)
	var corners := WandererImagePlacement.bottom_corners_world(placement)
	var subjects: Array = [head, wall_near, wall_hi, corners[0], corners[1]]
	subjects.append(corners[0] + Vector3(0.0, H, 0.0))
	var c45 := cos(PI * 0.25)
	var s45 := sin(PI * 0.25)
	var look := Vector3(P.x, 3.5, P.y)
	for try_side in [side, -side]:
		var view_xz: Vector2 = -(n * c45 + left * float(try_side) * s45).normalized()
		for dist in [7.0, 9.0, 11.0, 14.0, 18.0, 22.0, 28.0]:
			var eye_xz: Vector2 = Vector2(P.x, P.y) - view_xz * dist
			if not eye_outside_cottages(eye_xz, rects):
				continue
			if not los_clear(eye_xz, P, rects):
				continue
			for eye_y in [5.0, 7.0, 9.0, 12.0]:
				var eye := Vector3(eye_xz.x, eye_y, eye_xz.y)
				if subject_in_frustum(eye, look, fov_y_rad, aspect, subjects) \
						or subject_in_vertical_fov(eye, look, fov_y_rad, subjects):
					return {"eye": eye, "look": look, "distance_m": dist, "try": try_side}
	for attempt in range(YAW_TRIES):
		var yaw_off := deg_to_rad(YAW_STEP_DEG * float(attempt))
		for sign in [1.0, -1.0]:
			if attempt == 0 and sign < 0:
				continue
			var view_dir: Vector2 = (-n).rotated(sign * yaw_off) if attempt > 0 else -left
			for dist in [10.0, 16.0, 24.0]:
				var eye_xz: Vector2 = P - view_dir * dist
				if eye_outside_cottages(eye_xz, rects) and los_clear(eye_xz, P, rects):
					return {
						"eye": Vector3(eye_xz.x, 6.0, eye_xz.y),
						"look": look,
						"distance_m": dist,
						"try": attempt,
					}
	return {
		"eye": Vector3(P.x + 12.0, 8.0, P.y + 12.0),
		"look": look,
		"distance_m": 12.0,
		"try": -1,
	}


static func compute_bubble_phrase(
		figure_xz: Vector2,
		door_outward: Vector2,
		obstacle_rects: Array,
		standoff: float = 7.0,
		eye_h: float = 3.0,
		head_y: float = 2.0,
) -> Dictionary:
	var out := door_outward
	if out.length_squared() < 1e-6:
		out = Vector2(0.0, 1.0)
	else:
		out = out.normalized()
	var dists := [6.0, 7.0, 8.0, 9.0, 10.0]
	var look := Vector3(figure_xz.x, head_y + 0.6, figure_xz.y)
	for attempt in range(YAW_TRIES):
		var yaw_off := deg_to_rad(YAW_STEP_DEG * float(attempt))
		for sign in [1.0, -1.0]:
			if attempt == 0 and sign < 0:
				continue
			var dir := out if attempt == 0 else out.rotated(sign * yaw_off)
			for dist in dists:
				var eye_xz := figure_xz + dir * float(dist)
				if not eye_outside_cottages(eye_xz, obstacle_rects):
					continue
				if not los_clear(eye_xz, figure_xz, obstacle_rects):
					continue
				var eye := Vector3(eye_xz.x, eye_h, eye_xz.y)
				return {"eye": eye, "look": look}
	var fb := figure_xz + out * 9.0
	return {"eye": Vector3(fb.x, eye_h + 1.0, fb.y), "look": look}


static func compute_bubble_walk(
		figure_xz: Vector2,
		hero_xz: Vector2,
		cottage_rects: Array,
		standoff: float = 9.0,
		eye_h: float = 4.0,
		look_y: float = 2.2,
) -> Dictionary:
	var to_hero := hero_xz - figure_xz
	if to_hero.length_squared() < 1e-6:
		to_hero = Vector2(0.0, 1.0)
	to_hero = to_hero.normalized()
	for attempt in range(YAW_TRIES):
		var yaw_off := deg_to_rad(YAW_STEP_DEG * float(attempt))
		for sign in [1.0, -1.0]:
			if attempt == 0 and sign < 0:
				continue
			var dir := -to_hero if attempt == 0 else (-to_hero).rotated(sign * yaw_off)
			var eye_xz := figure_xz + dir * standoff
			if not eye_outside_cottages(eye_xz, cottage_rects):
				continue
			if not los_clear(eye_xz, figure_xz, cottage_rects):
				continue
			var eye := Vector3(eye_xz.x, eye_h, eye_xz.y)
			var look := Vector3(figure_xz.x, look_y, figure_xz.y)
			return {"eye": eye, "look": look}
	var eye_xz := figure_xz + Vector2(standoff, 0.0)
	return {"eye": Vector3(eye_xz.x, eye_h, eye_xz.y), "look": Vector3(figure_xz.x, look_y, figure_xz.y)}
