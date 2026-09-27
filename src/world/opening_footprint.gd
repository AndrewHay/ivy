class_name OpeningFootprint
extends RefCounted

## SD-METRIC-2 / SD-ENV-11 — shared opening azimuth + height bands on the tower
## exterior cylinder. Dedupes coverage.gd's half-width math; snap targets land on
## adjacent brick, not in door/window voids.


static func half_azimuth_deg(width_m: float, radius_m: float) -> float:
	return rad_to_deg(atan(width_m * 0.5 / maxf(radius_m, 1e-3)))


static func azimuth_deg_of(p: Vector3) -> float:
	var az := rad_to_deg(atan2(p.x, -p.z))
	if az < 0.0:
		az += 360.0
	return az


static func angular_delta_deg(a_deg: float, b_deg: float) -> float:
	var diff := fposmod(a_deg - b_deg, 360.0)
	if diff > 180.0:
		diff = 360.0 - diff
	return diff


static func in_opening_band(
	p: Vector3,
	center_az_deg: float,
	width_m: float,
	y_lo: float,
	y_hi: float,
	radius_m: float
) -> bool:
	if p.y <= y_lo or p.y >= y_hi:
		return false
	var half_deg := half_azimuth_deg(width_m, radius_m)
	return angular_delta_deg(azimuth_deg_of(p), center_az_deg) < half_deg


static func in_any_opening(p: Vector3, spec: TowerSpec) -> bool:
	var r := spec.radius_outer
	if in_opening_band(p, spec.door_azimuth, spec.door_width, 0.0, spec.door_height, r):
		return true
	if in_opening_band(
		p,
		spec.window_azimuth,
		spec.window_size,
		spec.window_sill,
		spec.window_sill + spec.window_size,
		r
	):
		return true
	return false


static func snap_to_exterior_shell(p: Vector3, spec: TowerSpec) -> Vector3:
	var r := spec.radius_outer
	var az_p := azimuth_deg_of(p)
	var y_p := p.y
	if not in_any_opening(p, spec):
		return _cylinder_point(az_p, y_p, r)
	var best: Vector3 = Vector3.ZERO
	var have_best := false
	for band in _opening_bands(spec):
		var center_az: float = band["center_az_deg"]
		var width_m: float = band["width_m"]
		var y_lo: float = band["y_lo"]
		var y_hi: float = band["y_hi"]
		if not in_opening_band(p, center_az, width_m, y_lo, y_hi, r):
			continue
		var half_deg := half_azimuth_deg(width_m, r)
		var az_lo: float = center_az - half_deg
		var az_hi: float = center_az + half_deg
		var az_values := [az_lo, az_hi, az_p]
		var y_values := [y_lo, y_hi, y_p]
		for az_deg in az_values:
			for y in y_values:
				var candidate := _cylinder_point(az_deg, y, r)
				if candidate.y < 0.0 or candidate.y > spec.height:
					continue
				if in_any_opening(candidate, spec):
					continue
				if not have_best or _prefer_candidate(candidate, best, p, az_p, y_p):
					best = candidate
					have_best = true
	if not have_best:
		return _cylinder_point(az_p, y_p, r)
	return best


static func _opening_bands(spec: TowerSpec) -> Array:
	return [
		{
			"center_az_deg": spec.door_azimuth,
			"width_m": spec.door_width,
			"y_lo": 0.0,
			"y_hi": spec.door_height,
		},
		{
			"center_az_deg": spec.window_azimuth,
			"width_m": spec.window_size,
			"y_lo": spec.window_sill,
			"y_hi": spec.window_sill + spec.window_size,
		},
	]


static func _cylinder_point(az_deg: float, y: float, radius_m: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	return Vector3(radius_m * sin(az), y, -radius_m * cos(az))


static func _prefer_candidate(
	candidate: Vector3,
	current: Vector3,
	p: Vector3,
	az_p: float,
	y_p: float
) -> bool:
	var d_cand := candidate.distance_squared_to(p)
	var d_curr := current.distance_squared_to(p)
	if not is_equal_approx(d_cand, d_curr):
		return d_cand < d_curr
	var cand_moved_y := not is_equal_approx(candidate.y, y_p)
	var curr_moved_y := not is_equal_approx(current.y, y_p)
	if cand_moved_y != curr_moved_y:
		return cand_moved_y
	if cand_moved_y and curr_moved_y:
		return candidate.y > current.y
	return false
