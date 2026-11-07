## Momentum path growth + pursuit along a guide polyline (v3 path-first).
class_name VillagePathGrower
extends RefCounted

const STEER_CLEAR_M := 3.0
const K_FALLBACK_MAX := 0.55
const K_BLOCKED_MULT := 1.35
const MAX_BLOCKED_RETRIES := 12


class GrowParams:
	var ds: float = 0.75
	var k: float = 0.09
	var amp_rad: float = 0.17
	var wavelength_m: float = 5.5
	var max_turn_deg: float = 12.0
	var seed: int = 1
	var lookahead_m: float = 3.0
	var steer_gain: float = 0.25
	var pursuit_lookahead_m: float = 4.0


static func params_from_variant(v: Variant) -> GrowParams:
	if v is GrowParams:
		return v as GrowParams
	var d: Dictionary = v as Dictionary
	var p := GrowParams.new()
	if d.has("ds"):
		p.ds = float(d["ds"])
	if d.has("k"):
		p.k = float(d["k"])
	if d.has("amp_rad"):
		p.amp_rad = float(d["amp_rad"])
	if d.has("wavelength_m"):
		p.wavelength_m = float(d["wavelength_m"])
	if d.has("max_turn_deg"):
		p.max_turn_deg = float(d["max_turn_deg"])
	if d.has("seed"):
		p.seed = int(d["seed"])
	if d.has("lookahead_m"):
		p.lookahead_m = float(d["lookahead_m"])
	if d.has("steer_gain"):
		p.steer_gain = float(d["steer_gain"])
	if d.has("pursuit_lookahead_m"):
		p.pursuit_lookahead_m = float(d["pursuit_lookahead_m"])
	return p


static func _make_noise(seed: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 1.0
	return n


static func _wrap_pi(a: float) -> float:
	while a > PI:
		a -= TAU
	while a < -PI:
		a += TAU
	return a


static func grow_free(
	start: Vector2,
	bearing_rad: float,
	length_m: float,
	params: Variant,
	grid = null,
	destination = null,
) -> PackedVector2Array:
	var p: GrowParams = params_from_variant(params)
	var noise := _make_noise(p.seed)
	var out := PackedVector2Array()
	out.append(start)
	var theta := bearing_rad
	var s_accum := 0.0
	var dest: Vector2 = destination if destination is Vector2 else Vector2(INF, INF)
	var has_dest := destination is Vector2
	var max_turn := deg_to_rad(p.max_turn_deg)
	var travelled := 0.0
	while travelled + 1e-6 < length_m:
		var p_cur: Vector2 = out[out.size() - 1]
		if has_dest and p_cur.distance_to(dest) <= p.ds + 1e-6:
			break
		var theta_tgt := bearing_rad
		if has_dest:
			theta_tgt = (dest - p_cur).angle()
		var k_eff: float = p.k if has_dest else 0.0
		var delta := k_eff * _wrap_pi(theta_tgt - theta)
		var ns := s_accum / maxf(p.wavelength_m, 1e-6)
		## 2D sample breaks long-run cancellation vs pure arc-length 1D noise (smoother meander).
		delta += p.amp_rad * noise.get_noise_2d(ns, float(p.seed) * 0.019)
		## Slow bias: integrated smooth noise often tracks ~straight; bias guarantees len/chord > 1.
		if not has_dest:
			var ph := float(p.seed) * 0.0193
			delta += 0.11 * sin(TAU * s_accum / 21.0 + ph)
			delta += 0.065 * sin(TAU * s_accum / 8.2 + ph * 1.7 + 0.4)
		if grid != null:
			var ahead := p_cur + Vector2(cos(theta), sin(theta)) * p.lookahead_m
			var clr: float = grid.clearance(ahead)
			if clr < STEER_CLEAR_M:
				var gr: Vector2 = grid.clearance_gradient(ahead)
				var theta_g := atan2(gr.y, gr.x)
				delta += p.steer_gain * _wrap_pi(theta_g - theta)
		delta = clampf(delta, -max_turn, max_turn)
		theta = theta + delta
		var step := minf(p.ds, length_m - travelled)
		if has_dest:
			step = minf(step, maxf(0.0, p_cur.distance_to(dest) - 1e-6))
		var p_next := p_cur + Vector2(cos(theta), sin(theta)) * step
		if grid != null and not grid.is_free(p_next):
			break
		out.append(p_next)
		s_accum += step
		travelled += step
	return out


static func _poly_cumulative_lengths(poly: PackedVector2Array) -> PackedFloat32Array:
	var lens := PackedFloat32Array()
	if poly.size() < 2:
		lens.append(0.0)
		return lens
	var acc := 0.0
	lens.append(0.0)
	for i in range(1, poly.size()):
		acc += poly[i - 1].distance_to(poly[i])
		lens.append(acc)
	return lens


static func _poly_point_at_s(poly: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	if poly.size() == 1:
		return poly[0]
	var total: float = cum[cum.size() - 1]
	var ss := clampf(s, 0.0, total)
	for i in range(cum.size() - 1):
		var s0: float = cum[i]
		var s1: float = cum[i + 1]
		if ss <= s1 + 1e-6:
			var t := 0.0 if absf(s1 - s0) < 1e-8 else (ss - s0) / (s1 - s0)
			return poly[i].lerp(poly[i + 1], t)
	return poly[poly.size() - 1]


static func _closest_on_poly(
	poly: PackedVector2Array, cum: PackedFloat32Array, p: Vector2
) -> Dictionary:
	var best_d := INF
	var best_seg := 0
	var best_t := 0.0
	var best_pt := poly[0]
	if poly.size() == 1:
		return {"seg": 0, "t": 0.0, "point": poly[0], "s": 0.0, "dist": p.distance_to(poly[0])}
	for i in range(poly.size() - 1):
		var a := poly[i]
		var b := poly[i + 1]
		var ab := b - a
		var ab2 := ab.length_squared()
		var t := 0.5
		if ab2 > 1e-12:
			t = clampf((p - a).dot(ab) / ab2, 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best_seg = i
			best_t = t
			best_pt = q
	var s_at := float(cum[best_seg]) + poly[best_seg].distance_to(best_pt)
	return {"seg": best_seg, "t": best_t, "point": best_pt, "s": s_at, "dist": sqrt(best_d)}


static func _lookahead_point(
	guide: PackedVector2Array, cum: PackedFloat32Array, s0: float, ahead: float
) -> Vector2:
	var total: float = cum[cum.size() - 1]
	return _poly_point_at_s(guide, cum, s0 + ahead)


static func grow_pursuit(
	start: Vector2,
	guide: PackedVector2Array,
	params: Variant,
	grid = null,
) -> PackedVector2Array:
	var p: GrowParams = params_from_variant(params)
	if guide.size() < 2:
		return PackedVector2Array([start])
	var noise := _make_noise(p.seed + 917)
	var cum := _poly_cumulative_lengths(guide)
	var g_end: Vector2 = guide[guide.size() - 1]
	var out := PackedVector2Array()
	out.append(start)
	var theta := (guide[1] - guide[0]).angle()
	var s_noise := 0.0
	var k_boost := 1.0
	var max_turn := deg_to_rad(p.max_turn_deg)
	var safety := 0
	var max_steps := int(ceil((cum[cum.size() - 1] + 80.0) / maxf(p.ds * 0.5, 1e-6)))
	while safety < max_steps:
		safety += 1
		var p_cur: Vector2 = out[out.size() - 1]
		if p_cur.distance_to(g_end) <= p.ds + 1e-5:
			out[out.size() - 1] = g_end
			break
		var clo := _closest_on_poly(guide, cum, p_cur)
		var s0: float = clo["s"]
		var tgt := _lookahead_point(guide, cum, s0, p.pursuit_lookahead_m)
		var theta_tgt := (tgt - p_cur).angle()
		var k_use := minf(K_FALLBACK_MAX, p.k * k_boost)
		var delta := k_use * _wrap_pi(theta_tgt - theta)
		var ns2 := s_noise / maxf(p.wavelength_m, 1e-6)
		delta += p.amp_rad * noise.get_noise_2d(ns2, float(p.seed + 31) * 0.019)
		if grid != null:
			var ahead := p_cur + Vector2(cos(theta), sin(theta)) * p.lookahead_m
			var clr: float = grid.clearance(ahead)
			if clr < STEER_CLEAR_M:
				var g2: Vector2 = grid.clearance_gradient(ahead)
				delta += p.steer_gain * _wrap_pi(atan2(g2.y, g2.x) - theta)
		delta = clampf(delta, -max_turn, max_turn)
		theta = theta + delta
		var step := p.ds
		var p_next := p_cur + Vector2(cos(theta), sin(theta)) * step
		var blocked: bool = grid != null and not grid.is_free(p_next)
		var retries := 0
		while blocked and retries < MAX_BLOCKED_RETRIES:
			retries += 1
			k_boost = minf(k_boost * K_BLOCKED_MULT, 8.0)
			k_use = minf(K_FALLBACK_MAX, p.k * k_boost)
			delta = k_use * _wrap_pi(theta_tgt - theta)
			var ns3 := s_noise / maxf(p.wavelength_m, 1e-6)
			delta += p.amp_rad * noise.get_noise_2d(ns3, float(p.seed + 31) * 0.019)
			delta = clampf(delta, -max_turn, max_turn)
			theta = theta + delta
			p_next = p_cur + Vector2(cos(theta), sin(theta)) * step
			blocked = not grid.is_free(p_next)
		if blocked:
			# Slide along guide toward end
			var s_slide := minf(s0 + step, cum[cum.size() - 1])
			p_next = _poly_point_at_s(guide, cum, s_slide)
			if grid != null and not grid.is_free(p_next):
				# Last resort: step from current straight to end
				var toward := (g_end - p_cur).normalized()
				p_next = p_cur + toward * minf(step, p_cur.distance_to(g_end))
			theta = (p_next - p_cur).angle()
		out.append(p_next)
		s_noise += step
		k_boost = lerpf(k_boost, 1.0, 0.12)
	if out[out.size() - 1].distance_to(g_end) > 1e-4:
		out[out.size() - 1] = g_end
	return out


static func resample(poly: PackedVector2Array, step: float = 0.3) -> PackedVector2Array:
	if poly.size() < 2 or step <= 1e-8:
		return poly.duplicate()
	var raw := PackedVector2Array()
	raw.append(poly[0])
	var rem := 0.0
	for i in range(1, poly.size()):
		var a: Vector2 = poly[i - 1]
		var b: Vector2 = poly[i]
		var seg_len := a.distance_to(b)
		if seg_len < 1e-8:
			continue
		var dir := (b - a) / seg_len
		var t := rem
		while t < seg_len:
			raw.append(a + dir * t)
			t += step
		rem = t - seg_len
	var min_d2: float = (step * 1e-4) * (step * 1e-4)
	var out := PackedVector2Array()
	out.append(raw[0])
	for k: int in range(1, raw.size()):
		if (raw[k] - out[out.size() - 1]).length_squared() > min_d2:
			out.append(raw[k])
	var last_v: Vector2 = poly[poly.size() - 1]
	if out.is_empty() or (last_v - out[out.size() - 1]).length_squared() > min_d2:
		out.append(last_v)
	return out


## Resample then snap any vertex within ~1 step of a pinned junction onto the exact pin (stage 7 V3).
static func resample_pinned(poly: PackedVector2Array, step: float, pins: Array[Vector2]) -> PackedVector2Array:
	var out := resample(poly, step)
	if out.is_empty() or pins.is_empty():
		return out
	var pin_d2 := (step * 1.55) * (step * 1.55)
	for pin: Vector2 in pins:
		var best_i := -1
		var best_d2 := pin_d2
		for i: int in range(out.size()):
			var d2: float = out[i].distance_squared_to(pin)
			if d2 < best_d2:
				best_d2 = d2
				best_i = i
		if best_i >= 0:
			out[best_i] = pin
	return out


static func len_over_chord(poly: PackedVector2Array) -> float:
	if poly.size() < 2:
		return 1.0
	var chord := poly[0].distance_to(poly[poly.size() - 1])
	if chord < 1e-6:
		return 1.0
	var lens := _poly_cumulative_lengths(poly)
	return float(lens[lens.size() - 1]) / chord


static func max_lateral_deviation(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var a := poly[0]
	var b := poly[poly.size() - 1]
	var ab := b - a
	var ab_len2 := ab.length_squared()
	if ab_len2 < 1e-12:
		return 0.0
	var max_d := 0.0
	for i in range(1, poly.size() - 1):
		var p: Vector2 = poly[i]
		var t := clampf((p - a).dot(ab) / ab_len2, 0.0, 1.0)
		var proj := a + ab * t
		max_d = maxf(max_d, p.distance_to(proj))
	return max_d


static func max_heading_change_per_m(poly: PackedVector2Array) -> float:
	var dbg: Dictionary = v5_worst_heading_window(poly)
	return float(dbg.get("rate_deg_per_m", 0.0))


## Where V5 max heading-change window sits (for probes / regression).
static func v5_worst_heading_window(poly: PackedVector2Array) -> Dictionary:
	var empty := {
		"rate_deg_per_m": 0.0,
		"i": -1,
		"j": -1,
		"arc_m": 0.0,
	}
	if poly.size() < 3:
		return empty
	var max_r := 0.0
	var best_i := -1
	var best_j := -1
	var best_arc := 0.0
	var win := 1.0
	var i := 0
	var j := 0
	var acc := 0.0
	while i < poly.size() - 1:
		while j < poly.size() - 1 and acc < win - 1e-6:
			acc += poly[j].distance_to(poly[j + 1])
			j += 1
		if j <= i + 1:
			i += 1
			continue
		var h0 := (poly[i + 1] - poly[i]).angle()
		var h1 := (poly[j] - poly[j - 1]).angle()
		var dth := absf(rad_to_deg(_wrap_pi(h1 - h0)))
		var r := dth / maxf(acc, 1e-6)
		if r > max_r:
			max_r = r
			best_i = i
			best_j = j
			best_arc = acc
		acc -= poly[i].distance_to(poly[i + 1])
		i += 1
	return {
		"rate_deg_per_m": max_r,
		"i": best_i,
		"j": best_j,
		"arc_m": best_arc,
	}


static func curvature_cost(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var cost := 0.0
	for i in range(1, poly.size() - 1):
		var v0: Vector2 = poly[i] - poly[i - 1]
		var v1: Vector2 = poly[i + 1] - poly[i]
		var a0 := v0.angle()
		var a1 := v1.angle()
		var d := _wrap_pi(a1 - a0)
		cost += d * d
	return cost


static func shape_cost(
	poly: PackedVector2Array, grid, others: Array, weights: Dictionary = {}
) -> float:
	var w1: float = float(weights.get("w1", 1.0))
	var w2: float = float(weights.get("w2", 1.0))
	var w3: float = float(weights.get("w3", 1.0))
	var w4: float = float(weights.get("w4", 1.0))
	var w5: float = float(weights.get("w5", 1.0))
	var lens := _poly_cumulative_lengths(poly)
	var L: float = lens[lens.size() - 1] if lens.size() > 0 else 0.0
	var K := curvature_cost(poly)
	var O := 0.0
	if grid != null and poly.size() > 0:
		var req := float(weights.get("clear_req", 1.0))
		for pt in poly:
			var c: Vector2 = pt as Vector2
			var cl: float = grid.clearance(c)
			O += maxf(0.0, req - cl)
	var X := 0.0
	var near_d := float(weights.get("near_miss_m", 2.0))
	var trim := float(weights.get("end_trim_m", 1.0))
	for other_raw in others:
		var other: PackedVector2Array = other_raw as PackedVector2Array
		if other.size() < 2 or poly.size() < 2:
			continue
		var ocum := _poly_cumulative_lengths(other)
		var o_total: float = ocum[ocum.size() - 1]
		for i in range(1, poly.size() - 1):
			var pti: Vector2 = poly[i]
			var s_i: float = lens[i]
			if s_i < trim or s_i > L - trim:
				continue
			var cl_o := _closest_on_poly(other, ocum, pti)
			var s_o: float = cl_o["s"]
			if s_o < trim or s_o > o_total - trim:
				continue
			var d: float = cl_o["dist"]
			if d < near_d and d > 1e-4:
				X += (near_d - d) * (near_d - d)
	var M := 0.0
	var ratio := len_over_chord(poly)
	if ratio < 1.03 or ratio > 1.3:
		M += 10.0 * absf(ratio - clampf(ratio, 1.03, 1.3))
	# Long almost-straight segment: arc length ≥ 15 m but stays near chord.
	var run_need := 15.0
	for i0 in range(poly.size()):
		for i1 in range(i0 + 1, poly.size()):
			var seg_len_arc := lens[i1] - lens[i0]
			if seg_len_arc < run_need - 1e-6:
				continue
			var aa := poly[i0]
			var bb := poly[i1]
			var ab := bb - aa
			var ab2 := ab.length_squared()
			if ab2 < 1e-12:
				continue
			var max_loc := 0.0
			for k in range(i0 + 1, i1):
				var ptk: Vector2 = poly[k]
				var t := clampf((ptk - aa).dot(ab) / ab2, 0.0, 1.0)
				var proj := aa + ab * t
				max_loc = maxf(max_loc, ptk.distance_to(proj))
			if max_loc < 0.15:
				M += (seg_len_arc - run_need) * 2.0
	# S-curve symmetry: lateral deviation sign flip balance
	var signs: Array = []
	var n := poly.size()
	for k in range(1, n - 1):
		var cr := (poly[k] - poly[0]).cross(poly[n - 1] - poly[0])
		if absf(cr) > 1e-3:
			signs.append(1 if cr > 0 else -1)
	var flips := 0
	for fi in range(signs.size() - 1):
		if signs[fi] != signs[fi + 1]:
			flips += 1
	if signs.size() >= 6 and flips >= signs.size() - 2:
		M += 5.0
	return w1 * L + w2 * K + w3 * O + w4 * X + w5 * M


static func best_of(
		candidates: Array, grid, others: Array, weights: Dictionary = {}
) -> PackedVector2Array:
	var best: PackedVector2Array = PackedVector2Array()
	var best_c := INF
	for cand in candidates:
		var poly: PackedVector2Array = cand as PackedVector2Array
		if poly.size() < 2:
			continue
		var c := shape_cost(poly, grid, others, weights)
		if c < best_c:
			best_c = c
			best = poly
	return best


## Cheaper candidate pick for long polylines: curvature + clearance only (no near-path crossing term).
static func best_of_light(
		candidates: Array, grid, others: Array, weights: Dictionary = {}
) -> PackedVector2Array:
	var w := {
		"w1": float(weights.get("w1", 1.0)),
		"w2": float(weights.get("w2", 1.0)),
		"w3": float(weights.get("w3", 0.35)),
		"w4": 0.0,
		"w5": float(weights.get("w5", 0.0)),
		"clear_req": float(weights.get("clear_req", 0.85)),
	}
	return best_of(candidates, grid, others, w)
