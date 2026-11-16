## Headless probe for the village-on-a-hill plan (ivy-82zn.14.9, architect). Throwaway-grade but
## kept so the programmer (ivy-82zn.14.10) can re-run the same numbers.
##
##   Godot --headless --script res://tools/probe_village_hill.gd -- --geom [--seeds=1-30]
##       [--rise=7.0] [--crest=10.0] [--pow=1.0] [--shift=0.0]
##     Candidate hill profile P (per-ray normalised to the rim band, see _hill) on each layout:
##     stoop-to-rim distances, cottage / pond / plaza distances, fall from the hero to the
##     outermost cottage, max hill grade on open lawn / along paths / at cottages, terrace
##     cut+fill across each grown pad rect, pond and plaza P range.
##
##   Godot --headless --script res://tools/probe_village_hill.gd -- --diag [--seeds=7]
##       [--set=base_amplitude_m:6,max_rise_m:8,max_depression_m:6]
##     Production sampler: 1 m LUT, cells steeper than 25 deg classified by the nearest
##     feature (path-corridor edge, hero edge, pad skirt, pond, plaza, rim, other); the
##     corridor-edge step at 5 m beside every path; pond bank ring chord vs the lawn mesh.
extends SceneTree

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillagePondSite = preload("res://src/world/village_pond_site.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

const RIDGE_M := 3.125 + 3.7178683280944824  # WALL_TOP + Roof_RoundTiles_4x6/4x8 max y

var _rise := 7.0
var _crest := 10.0
var _pow := 1.0
var _shift := 0.0


func _init() -> void:
	var seeds: Array[int] = []
	var overrides := {}
	var mode := "geom"
	for arg in OS.get_cmdline_user_args():
		if arg == "--geom":
			mode = "geom"
		elif arg == "--diag":
			mode = "diag"
		elif arg == "--fall":
			mode = "fall"
		elif arg == "--steep":
			mode = "steep"
		elif arg == "--limits":
			mode = "limits"
		elif arg == "--luterr":
			mode = "luterr"
		elif arg.begins_with("--at="):
			mode = "at"
			var xy := arg.substr(5).split(",")
			_at = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("--seeds="):
			var spec := arg.substr(8)
			if spec.contains("-"):
				var ab := spec.split("-")
				for s in range(int(ab[0]), int(ab[1]) + 1):
					seeds.append(s)
			else:
				for s in spec.split(","):
					seeds.append(int(s))
		elif arg.begins_with("--set="):
			for kv in arg.substr(6).split(","):
				var parts := kv.split(":")
				overrides[parts[0]] = float(parts[1])
		elif arg.begins_with("--rise="):
			_rise = float(arg.substr(7))
		elif arg.begins_with("--crest="):
			_crest = float(arg.substr(8))
		elif arg.begins_with("--pow="):
			_pow = float(arg.substr(6))
		elif arg.begins_with("--shift="):
			_shift = float(arg.substr(8))
		elif arg == "--end=village":
			_end_village = true
		elif arg.begins_with("--shoulder="):
			_shoulder = float(arg.substr(11))
	if seeds.is_empty():
		seeds = [7]
	print("[hill] ridge_m=%.3f" % RIDGE_M)
	if mode == "geom":
		_geom(seeds)
	elif mode == "fall":
		_fall(seeds, overrides)
	elif mode == "steep":
		_steep(seeds, overrides)
	elif mode == "at":
		_probe_at(seeds, overrides)
	elif mode == "limits":
		_limits(seeds, overrides)
	elif mode == "luterr":
		_luterr(seeds, overrides)
	else:
		_diag(seeds, overrides)
	quit(0)


# ── Production sampler (ivy-82zn.14.10) ──────────────────────────────────────

var _at := Vector2.ZERO


func _luterr(seeds: Array[int], overrides: Dictionary) -> void:
	## --luterr: 1 m LUT bilinear vs exact sample_y on a 0.37 m grid; the 6 worst points, tagged.
	for seed in seeds:
		var layout := VillageLayout.generate(seed)
		var params := _params_with(overrides)
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var lut := VillageTerrain.build_sample_lut(layout, params, t_seed, 1.0)
		var g := layout.hamlet_centre_xz
		var worst: Array = []
		var x := -layout.lawn_radius
		while x <= layout.lawn_radius:
			var z := -layout.lawn_radius
			while z <= layout.lawn_radius:
				var p := g + Vector2(x, z)
				z += 0.37
				if p.distance_to(g) >= layout.lawn_radius - 0.5:
					continue
				var e := absf(VillageTerrain.sample_y(p, layout, params, t_seed) - VillageTerrain.lut_sample(lut, p))
				if e > 0.05:
					worst.append([e, p])
			x += 0.37
		worst.sort_custom(func(a, b): return a[0] > b[0])
		print("[luterr] seed=%d points>5cm=%d" % [seed, worst.size()])
		for k in range(mini(6, worst.size())):
			var p: Vector2 = worst[k][1]
			print("[luterr]   err=%.3f at %s tag=%s" % [worst[k][0], str(p), _feature_tag(p, layout, params)])


func _limits(seeds: Array[int], overrides: Dictionary) -> void:
	## --limits: the AC 2 / AC 4 numbers per seed, same measures as test_village_terrain_hill.gd:
	## fall to the outermost cottage, hero ring max slope, total pad bank (0.5 m walks out of every
	## pad, 1.5 m off paths), lane grade outside pad banks, steepest rendered lawn cell.
	var w := {"fall": INF, "hero": 0.0, "bank": 0.0, "lane": 0.0, "cell": 0.0}
	for seed in seeds:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		var params := _params_with(overrides)
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var far_c := Vector2.ZERO
		var far_d := -1.0
		for spec: Dictionary in layout.cottages:
			var c := spec["centre"] as Vector2
			if c.distance_to(VillageLayout.HERO_DOOR_STOOP) > far_d:
				far_d = c.distance_to(VillageLayout.HERO_DOOR_STOOP)
				far_c = c
		var fall := VillageTerrain.sample_y(VillageLayout.HERO_DOOR_STOOP, layout, params, t_seed) \
			- VillageTerrain.sample_y(far_c, layout, params, t_seed)
		var stoop := VillageLayout.HERO_DOOR_STOOP
		var hero := 0.0
		var hero_xz := Vector2.ZERO
		for i in range(64):
			var a := TAU * float(i) / 64.0
			var r := params.hero_flat_r_m + 0.3
			while r <= params.hero_flat_r_m + params.hero_skirt_m:
				var xz := stoop + Vector2(sin(a), cos(a)) * r
				r += 0.5
				if not VillageTerrain.in_any_pad_terrace(xz, layout, params, t_seed):
					var hs := VillageTerrain.sample_slope_deg(xz, layout, params, t_seed)
					if hs > hero:
						hero = hs
						hero_xz = xz
		var bank := 0.0
		var bank_xz := Vector2.ZERO
		var reach := VillageTerrain.pad_terrace_reach_m(layout, params, t_seed)
		for spec: Dictionary in layout.cottages:
			var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
			for i in range(16):
				var dir := Vector2(sin(TAU * i / 16.0), cos(TAU * i / 16.0))
				var q := rect.get_center()
				while VillageTerrain._rect_sdf(q, rect) < 0.0:
					q += dir * 0.25
				var prev := VillageTerrain.sample_y(q, layout, params, t_seed)
				var walked := 0.0
				while walked < reach:
					var nq := q + dir * 0.5
					var hn := VillageTerrain.sample_y(nq, layout, params, t_seed)
					if absf(hn - prev) / 0.5 > bank and VillageTerrain._min_dist_to_paths(nq, layout) > 1.5:
						bank = absf(hn - prev) / 0.5
						bank_xz = nq
					prev = hn
					q = nq
					walked += 0.5
		var lane := 0.0
		var lane_xz := Vector2.ZERO
		for polyline: Variant in layout.path_polylines():
			var pts: Array = polyline as Array
			for i in range(pts.size() - 1):
				var a2: Vector2 = pts[i]
				var b2: Vector2 = pts[i + 1]
				var nseg := maxi(int(a2.distance_to(b2) / 0.5), 1)
				for k in range(nseg):
					var p0 := a2.lerp(b2, float(k) / nseg)
					var p1 := a2.lerp(b2, float(k + 1) / nseg)
					if p0.distance_to(p1) < 0.05 \
							or VillageTerrain.in_any_pad_terrace(p0, layout, params, t_seed) \
							or VillageTerrain.in_any_pad_terrace(p1, layout, params, t_seed):
						continue
					var gr := absf(VillageTerrain.sample_y(p1, layout, params, t_seed)
						- VillageTerrain.sample_y(p0, layout, params, t_seed)) / p0.distance_to(p1)
					if gr > lane:
						lane = gr
						lane_xz = p0
		var cell := VillageTerrain.max_mesh_cell_slope_deg(layout, params)
		print("[limits] seed=%d fall=%.2f hero_ring=%.1fdeg at %s pad_bank=%.1fdeg at %s lane=%.1fdeg at %s cell=%.1fdeg" % [
			seed, fall, hero, str(hero_xz), _deg(bank), str(bank_xz), _deg(lane), str(lane_xz), cell])
		w.fall = minf(w.fall, fall)
		w.hero = maxf(w.hero, hero)
		w.bank = maxf(w.bank, _deg(bank))
		w.lane = maxf(w.lane, _deg(lane))
		w.cell = maxf(w.cell, cell)
	print("[limits] WORST fall=%.2f hero_ring=%.1fdeg pad_bank=%.1fdeg lane=%.1fdeg cell=%.1fdeg" % [
		w.fall, w.hero, w.bank, w.lane, w.cell])


func _probe_at(seeds: Array[int], overrides: Dictionary) -> void:
	## --at=x,z: layer breakdown and the terraces acting at one point, plus a 1 m cross of heights.
	for seed in seeds:
		var layout := VillageLayout.generate(seed)
		var params := _params_with(overrides)
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var kc := VillageTerrain.knoll_centres(layout, params, t_seed)
		var p := _at
		print("[at] seed=%d p=%s y=%.3f slope=%.1f L=%.3f Lt=%.3f R=%.3f path=%.3f" % [seed, str(p),
			VillageTerrain.sample_y(p, layout, params, t_seed),
			VillageTerrain.sample_slope_deg(p, layout, params, t_seed),
			VillageTerrain._large_raw(p, layout, params, t_seed),
			VillageTerrain._large_terraced(p, layout, params, t_seed),
			VillageTerrain.detail_y(p, layout, params, t_seed),
			VillageTerrain._path_correction(p, layout, params, t_seed, kc)])
		var hit := VillageTerrain._closest_on_paths(p, layout)
		print("[at]   nearest path dist=%.2f foot=%s key=%s" % [hit["dist"], str(hit["point"]), hit["cache_key"]])
		VillageTerrain._ensure_path_spine(layout, params, t_seed, kc)
		for ci in range(VillageTerrain._path_spine_chains.size()):
			var ch: Dictionary = VillageTerrain._path_spine_chains[ci]
			var pts: PackedVector2Array = ch["pts"]
			for i in range(pts.size()):
				if pts[i].distance_to(p) < 1.6:
					print("[at]   chain %d #%d %s raw=%.3f hs=%.3f grad=%.2f" % [ci, i, str(pts[i]),
						(ch["raw"] as PackedFloat32Array)[i], (ch["hs"] as PackedFloat32Array)[i],
						(ch["grads"] as PackedFloat32Array)[i]])
		for o: Vector2 in [Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0, -0.5), Vector2(0, 0.5)]:
			var q := p + o
			print("[at]   %s y=%.3f Lt=%.3f" % [str(q), VillageTerrain.sample_y(q, layout, params, t_seed),
				VillageTerrain._large_terraced(q, layout, params, t_seed)])
		var cs := VillageTerrain._terrace_cone_slope(params)
		var lt := VillageTerrain._large_terraced(p, layout, params, t_seed)
		for it: Dictionary in VillageTerrain._terraces(layout, params, t_seed):
			var sdf := VillageTerrain._terrace_sdf(p, it)
			var a: float = it["anchor"]
			var dd := maxf(sdf, 0.0)
			if absf(a + cs * dd - lt) < 0.3 or absf(a - cs * dd - lt) < 0.3 or sdf < float(it["skirt"]):
				print("[at]   terrace %s c=%s sdf=%.2f skirt=%.1f anchor=%.2f raw=%.2f" % [
					"pond" if it["circle"] else ("pad" if it["pad"] else "plaza"), str(it["centre"]), sdf,
					float(it["skirt"]), float(it["anchor"]),
					VillageTerrain._large_raw(it["centre"], layout, params, t_seed)])

func _params_with(overrides: Dictionary) -> VillageTerrainParams:
	var params := VillageTerrainParams.production()
	for k in overrides.keys():
		var cur: Variant = params.get(k)
		params.set(k, int(overrides[k]) if typeof(cur) == TYPE_INT else overrides[k])
	return params


func _fall(seeds: Array[int], overrides: Dictionary) -> void:
	## --fall: hero datum minus sample_y at the outermost cottage centre (farthest from the stoop),
	## broken down into hill P, swell, raw / relaxed terrace anchor and detail R at that centre.
	var worst := INF
	for seed in seeds:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			print("[fall] seed=%d fallback" % seed)
			continue
		var params := _params_with(overrides)
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var idx := -1
		var best := -1.0
		for i in layout.cottages.size():
			var d := (layout.cottages[i]["centre"] as Vector2).distance_to(VillageLayout.HERO_DOOR_STOOP)
			if d > best:
				best = d
				idx = i
		var c := layout.cottages[idx]["centre"] as Vector2
		var datum := VillageTerrain.hero_datum_y(layout, params)
		var y := VillageTerrain.sample_y(c, layout, params, t_seed)
		var items: Array = VillageTerrain._terraces(layout, params, t_seed)
		var raw := VillageTerrain._large_raw(c, layout, params, t_seed)
		var fall := datum - y
		worst = minf(worst, fall)
		print("[fall] seed=%d fall=%.2f datum=%.2f y=%.2f d_stoop=%.1f edge_r=%.1f P=%.2f swell=%.2f anchor_raw=%.2f anchor=%.2f skirt=%.1f R=%.2f" % [
			seed, fall, datum, y, best, VillageTerrain.village_edge_r(layout, params),
			VillageTerrain.hill_y(c, layout, params), raw - VillageTerrain.hill_y(c, layout, params),
			raw, float(items[idx]["anchor"]), float(items[idx]["skirt"]),
			VillageTerrain.detail_y(c, layout, params, t_seed)])
	print("[fall] WORST %.2f m (ridge %.2f)" % [worst, RIDGE_M])


func _steep(seeds: Array[int], overrides: Dictionary) -> void:
	## --steep: mesh-step LUT cells steeper than 30°, tagged by feature, with the large / detail /
	## path-correction parts at the worst cell; plus the max rendered-cell slope.
	for seed in seeds:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var params := _params_with(overrides)
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var g := layout.hamlet_centre_xz
		var counts := {}
		var worst := {}
		var worst_xz := {}
		var x := -layout.lawn_radius
		while x <= layout.lawn_radius:
			var z := -layout.lawn_radius
			while z <= layout.lawn_radius:
				var p := g + Vector2(x, z)
				z += 1.0
				if p.distance_to(g) >= layout.lawn_radius - 0.6:
					continue
				var s := VillageTerrain.sample_slope_deg(p, layout, params, t_seed)
				if s <= 30.0:
					continue
				var tag := _feature_tag(p, layout, params)
				counts[tag] = int(counts.get(tag, 0)) + 1
				if s > float(worst.get(tag, 0.0)):
					worst[tag] = s
					worst_xz[tag] = p
			x += 1.0
		var parts: Array[String] = []
		for k in counts.keys():
			var p: Vector2 = worst_xz[k]
			var kc := VillageTerrain.knoll_centres(layout, params, t_seed)
			parts.append("%s=%d(max %.0fdeg at %s Lt=%.2f R=%.2f path=%.2f)" % [k, counts[k], worst[k], str(p),
				VillageTerrain._large_terraced(p, layout, params, t_seed),
				VillageTerrain.detail_y(p, layout, params, t_seed),
				VillageTerrain._path_correction(p, layout, params, t_seed, kc)])
		print("[steep] seed=%d cell_max=%.1fdeg >30deg: %s" % [
			seed, VillageTerrain.max_mesh_cell_slope_deg(layout, params), ", ".join(parts)])
		for it: Dictionary in VillageTerrain._terraces(layout, params, t_seed):
			var c: Vector2 = it["centre"]
			print("[steep]   terrace %s c=%s d_hero=%.1f r_g=%.1f raw=%.2f anchor=%.2f skirt=%.1f" % [
				"pond" if it["circle"] else ("pad" if it["pad"] else "plaza"), str(c),
				c.distance_to(VillageLayout.HERO_DOOR_STOOP), c.distance_to(layout.hamlet_centre_xz),
				VillageTerrain._large_raw(c, layout, params, t_seed), float(it["anchor"]), float(it["skirt"])])


# ── Candidate profile ─────────────────────────────────────────────────────────

func _centre(layout: VillageLayout) -> Vector2:
	return VillageLayout.HERO_DOOR_STOOP.lerp(layout.hamlet_centre_xz, _shift)


func _ray_end(c: Vector2, dir: Vector2, g: Vector2, r_end: float) -> float:
	## Distance from c along unit dir to the circle (g, r_end); c is inside the circle.
	var oc := c - g
	var b := dir.dot(oc)
	var cc := oc.dot(oc) - r_end * r_end
	return -b + sqrt(maxf(b * b - cc, 0.0))


var _end_village := false
var _shoulder := 1.0
var _village_r_cache := {}


func _village_r(layout: VillageLayout) -> float:
	## Village edge radius from the hill centre: farthest grown cottage-rect corner + 2 m.
	var key := layout.generation_seed
	if _village_r_cache.has(key):
		return _village_r_cache[key]
	var c := _centre(layout)
	var r := 0.0
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(0.6)
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
				Vector2(rect.position.x, rect.end.y)]:
			r = maxf(r, corner.distance_to(c))
	_village_r_cache[key] = r + 2.0
	return r + 2.0


func _hill(xz: Vector2, layout: VillageLayout, rim_blend: float) -> float:
	## P = rise × (1 − S(u^pow)), u = (d − crest) / (D_end(ray) − crest); local frame,
	## crest = +rise, end = 0. D_end = rim band inner edge (lawn_radius − rim_blend) on that ray,
	## or with --end=village min(that, village edge radius). S = lerp(u, smoothstep(u), shoulder).
	var c := _centre(layout)
	var d := xz.distance_to(c)
	if d <= _crest:
		return _rise
	var dir := (xz - c) / d
	var d_end := _ray_end(c, dir, layout.hamlet_centre_xz, layout.lawn_radius - rim_blend)
	if _end_village:
		d_end = minf(d_end, _village_r(layout))
	var u := clampf((d - _crest) / maxf(d_end - _crest, 1.0), 0.0, 1.0)
	var t := pow(u, _pow)
	var s := lerpf(t, t * t * (3.0 - 2.0 * t), _shoulder)
	return _rise * (1.0 - s)


func _hill_grad(xz: Vector2, layout: VillageLayout, rim_blend: float) -> float:
	var e := 0.25
	var dx := (_hill(xz + Vector2(e, 0), layout, rim_blend) - _hill(xz - Vector2(e, 0), layout, rim_blend)) / (2.0 * e)
	var dz := (_hill(xz + Vector2(0, e), layout, rim_blend) - _hill(xz - Vector2(0, e), layout, rim_blend)) / (2.0 * e)
	return sqrt(dx * dx + dz * dz)


static func _deg(grade: float) -> float:
	return rad_to_deg(atan(grade))


func _geom(seeds: Array[int]) -> void:
	print("[hill] profile rise=%.2f crest=%.1f pow=%.2f shift=%.2f end_village=%s shoulder=%.2f" % [
		_rise, _crest, _pow, _shift, str(_end_village), _shoulder])
	var worst := {"open": 0.0, "path": 0.0, "cot": 0.0, "terrace": 0.0, "min_fall": INF,
		"pond_range": 0.0, "plaza_range": 0.0, "min_rim_d": INF, "max_rim_d": 0.0, "rim2": 0.0}
	var params := VillageTerrainParams.production()
	var rb := params.rim_blend_m
	for seed in seeds:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			print("[hill] seed=%d fallback" % seed)
			continue
		var g := layout.hamlet_centre_xz
		var c := _centre(layout)
		var r_end := layout.lawn_radius - rb
		var rim_min := INF
		var rim_max := 0.0
		for i in range(72):
			var a := TAU * float(i) / 72.0
			var dd := _ray_end(c, Vector2(sin(a), cos(a)), g, layout.lawn_radius)
			rim_min = minf(rim_min, dd)
			rim_max = maxf(rim_max, dd)
		# Cottages
		var cot_dmin := INF
		var cot_dmax := 0.0
		var cot_grade := 0.0
		var terrace := 0.0
		var min_p_cot := INF
		for spec: Dictionary in layout.cottages:
			var cc := spec["centre"] as Vector2
			var dcot := cc.distance_to(c)
			cot_dmin = minf(cot_dmin, dcot)
			cot_dmax = maxf(cot_dmax, dcot)
			cot_grade = maxf(cot_grade, _hill_grad(cc, layout, rb))
			min_p_cot = minf(min_p_cot, _hill(cc, layout, rb))
			var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
			var lo := INF
			var hi := -INF
			for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
					Vector2(rect.position.x, rect.end.y)]:
				var pv := _hill(corner, layout, rb)
				lo = minf(lo, pv)
				hi = maxf(hi, pv)
			terrace = maxf(terrace, hi - lo)
		var fall := _rise - min_p_cot
		# Neighbour pad terraces: anchor difference over the gap between grown rects (gap < 8 m).
		var pair_grade := 0.0
		var pair_dp := 0.0
		var nc := layout.cottages.size()
		for i in range(nc):
			var ri := VillageBackdrop.cottage_exterior_rect(layout.cottages[i]).grow(params.pad_margin_m)
			var pi_ := _hill(layout.cottages[i]["centre"] as Vector2, layout, rb)
			for j in range(i + 1, nc):
				var rj := VillageBackdrop.cottage_exterior_rect(layout.cottages[j]).grow(params.pad_margin_m)
				var gap := VillageTerrain._rect_gap(ri, rj)
				if gap > 8.0:
					continue
				var dp := absf(pi_ - _hill(layout.cottages[j]["centre"] as Vector2, layout, rb))
				pair_grade = maxf(pair_grade, dp / maxf(gap, 0.5))
				pair_dp = maxf(pair_dp, dp)
		print("[hill] seed=%d neighbour_pads(gap<8m) max_dP=%.2f max_dP_over_gap=%.1fdeg" % [
			seed, pair_dp, _deg(pair_grade)])
		# Paths: along-path grade of P alone (0.5 m chords), farthest path point.
		var path_grade := 0.0
		var path_dmax := 0.0
		for polyline: Variant in layout.path_polylines():
			var pts: Array = polyline as Array
			for i in range(pts.size() - 1):
				var a: Vector2 = pts[i] as Vector2
				var b: Vector2 = pts[i + 1] as Vector2
				var seg := a.distance_to(b)
				var n := maxi(int(seg / 0.5), 1)
				for k in range(n):
					var p0 := a.lerp(b, float(k) / n)
					var p1 := a.lerp(b, float(k + 1) / n)
					var l := p0.distance_to(p1)
					if l < 1e-4:
						continue
					path_grade = maxf(path_grade, absf(_hill(p1, layout, rb) - _hill(p0, layout, rb)) / l)
					path_dmax = maxf(path_dmax, p1.distance_to(c))
		# Open lawn: max hill grade on a 1 m grid inside the rim band.
		var open_grade := 0.0
		var rim2 := 0.0
		var x := -layout.lawn_radius
		while x <= layout.lawn_radius:
			var z := -layout.lawn_radius
			while z <= layout.lawn_radius:
				var p := g + Vector2(x, z)
				var r := p.distance_to(g)
				if r < r_end:
					open_grade = maxf(open_grade, _hill_grad(p, layout, rb))
				z += 1.0
			x += 1.0
		# Pond and plaza P range.
		var pond_range := 0.0
		var r_pond := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m
		var plo := INF
		var phi_ := -INF
		for i in range(36):
			var a := TAU * float(i) / 36.0
			var pv := _hill(layout.pond_center + Vector2(sin(a), cos(a)) * r_pond, layout, rb)
			plo = minf(plo, pv)
			phi_ = maxf(phi_, pv)
		pond_range = phi_ - plo
		var plaza_range := 0.0
		if layout.plaza_rect.has_area():
			var pr := layout.plaza_rect
			var qlo := INF
			var qhi := -INF
			for corner: Vector2 in [pr.position, Vector2(pr.end.x, pr.position.y), pr.end,
					Vector2(pr.position.x, pr.end.y)]:
				var pv := _hill(corner, layout, rb)
				qlo = minf(qlo, pv)
				qhi = maxf(qhi, pv)
			plaza_range = qhi - qlo
		print("[hill] seed=%d village_r=%.1f" % [seed, _village_r(layout)])
		print("[hill] seed=%d rim_d=%.1f..%.1f cot_d=%.1f..%.1f path_dmax=%.1f pond_d=%.1f plaza_d=%.1f fall_to_outer_cottage=%.2f open=%.1fdeg path=%.1fdeg cot=%.1fdeg terrace=%.2f pond_P=%.2f plaza_P=%.2f" % [
			seed, rim_min, rim_max, cot_dmin, cot_dmax, path_dmax,
			layout.pond_center.distance_to(c), layout.plaza_rect.get_center().distance_to(c),
			fall, _deg(open_grade), _deg(path_grade), _deg(cot_grade), terrace, pond_range, plaza_range])
		worst.open = maxf(worst.open, open_grade)
		worst.path = maxf(worst.path, path_grade)
		worst.cot = maxf(worst.cot, cot_grade)
		worst.terrace = maxf(worst.terrace, terrace)
		worst.min_fall = minf(worst.min_fall, fall)
		worst.pond_range = maxf(worst.pond_range, pond_range)
		worst.plaza_range = maxf(worst.plaza_range, plaza_range)
		worst.min_rim_d = minf(worst.min_rim_d, rim_min)
		worst.max_rim_d = maxf(worst.max_rim_d, rim_max)
	print("[hill] WORST open=%.1fdeg path=%.1fdeg cottage=%.1fdeg terrace=%.2fm min_fall_to_outer_cottage=%.2fm pond_P=%.2f plaza_P=%.2f rim_d=%.1f..%.1f" % [
		_deg(worst.open), _deg(worst.path), _deg(worst.cot), worst.terrace, worst.min_fall,
		worst.pond_range, worst.plaza_range, worst.min_rim_d, worst.max_rim_d])


# ── Diagnosis of the dark bands / pond shards ─────────────────────────────────

func _diag(seeds: Array[int], overrides: Dictionary) -> void:
	for seed in seeds:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			continue
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		var params := VillageTerrainParams.production()
		for k in overrides.keys():
			var cur: Variant = params.get(k)
			params.set(k, int(overrides[k]) if typeof(cur) == TYPE_INT else overrides[k])
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var t0 := Time.get_ticks_msec()
		var lut := VillageTerrain.build_sample_lut(layout, params, t_seed, 1.0)
		print("[diag] seed=%d lut 1m built in %d ms" % [seed, Time.get_ticks_msec() - t0])
		_classify_cliffs(layout, params, lut)
		_corridor_step(layout, params, t_seed)
		_bank_vs_mesh(layout, params, t_seed)


func _classify_cliffs(layout: VillageLayout, params: VillageTerrainParams, lut: Dictionary) -> void:
	var g := layout.hamlet_centre_xz
	var counts := {}
	var worst := {}
	var x := -layout.lawn_radius
	var n_total := 0
	while x <= layout.lawn_radius:
		var z := -layout.lawn_radius
		while z <= layout.lawn_radius:
			var p := g + Vector2(x, z)
			if p.distance_to(g) < layout.lawn_radius - 0.6:
				var nrm := VillageTerrain.lut_sample_normal(lut, p)
				var deg := rad_to_deg(acos(clampf(nrm.y, -1.0, 1.0)))
				if deg > 25.0:
					n_total += 1
					var tag := _feature_tag(p, layout, params)
					counts[tag] = int(counts.get(tag, 0)) + 1
					worst[tag] = maxf(float(worst.get(tag, 0.0)), deg)
			z += 1.0
		x += 1.0
	var parts: Array[String] = []
	for k in counts.keys():
		parts.append("%s=%d(max %.0fdeg)" % [k, counts[k], worst[k]])
	print("[diag]   cells>25deg total=%d %s" % [n_total, ", ".join(parts)])


func _feature_tag(p: Vector2, layout: VillageLayout, params: VillageTerrainParams) -> String:
	var path_d := VillageTerrain._min_dist_to_paths(p, layout)
	var d_hero := p.distance_to(VillageLayout.HERO_DOOR_STOOP)
	if absf(path_d - 5.0) <= 1.0:
		return "path_corridor_edge_5m"
	if d_hero <= params.hero_flat_r_m + params.hero_skirt_m + 0.5:
		return "hero_disc_or_skirt"
	var d_pond := p.distance_to(layout.pond_center)
	if d_pond <= VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m + params.pond_skirt_m + 1.0:
		return "pond"
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		if VillageTerrain._rect_sdf(p, rect) <= 4.0:
			return "pad_skirt"
	if layout.plaza_rect.has_area() and VillageTerrain._rect_sdf(p, layout.plaza_rect) <= params.plaza_skirt_m + 1.0:
		return "plaza"
	if path_d < 4.0:
		return "path_corridor_inside"
	if p.distance_to(layout.hamlet_centre_xz) > layout.lawn_radius - params.rim_blend_m - 1.0:
		return "rim_band"
	return "open_lawn"


func _corridor_step(layout: VillageLayout, params: VillageTerrainParams, t_seed: int) -> void:
	## |h(4.95 m) − h(5.05 m)| perpendicular to each path segment midpoint, both sides.
	var max_step := 0.0
	var sum := 0.0
	var n := 0
	var worst_pt := Vector2.ZERO
	for polyline: Variant in layout.path_polylines():
		var pts: Array = polyline as Array
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i] as Vector2
			var b: Vector2 = pts[i + 1] as Vector2
			if a.distance_to(b) < 0.2 or i % 2 == 1:
				continue
			var mid := a.lerp(b, 0.5)
			var nrm := (b - a).normalized().orthogonal()
			for s: float in [-1.0, 1.0]:
				var pin: Vector2 = mid + nrm * s * 4.95
				var pout: Vector2 = mid + nrm * s * 5.05
				# only where 5 m from THIS segment is also 5 m from the network (no other path closer)
				if VillageTerrain._min_dist_to_paths(pin, layout) >= 5.0:
					continue
				if VillageTerrain._min_dist_to_paths(pout, layout) < 5.0:
					continue
				if pin.distance_to(VillageLayout.HERO_DOOR_STOOP) < params.hero_flat_r_m + 1.0:
					continue
				if VillageTerrain._in_cottage_pad_skirt(pin, layout, params, t_seed):
					continue
				var dh := absf(VillageTerrain.sample_y(pin, layout, params, t_seed)
					- VillageTerrain.sample_y(pout, layout, params, t_seed))
				sum += dh
				n += 1
				if dh > max_step:
					max_step = dh
					worst_pt = pin
	print("[diag]   corridor_edge_step n=%d mean=%.3f max=%.3f at %s (0.10 m apart)" % [
		n, sum / maxf(float(n), 1.0), max_step, str(worst_pt)])


func _bank_vs_mesh(layout: VillageLayout, params: VillageTerrainParams, t_seed: int) -> void:
	## Bank ring = quads between the water render outline and the bank outer outline, vertices at
	## sample_y (village_backdrop.gd _add_village_pond). Lawn = mesh_from_lut at
	## terrain_mesh_step_m (bilinear LUT). Report bank − lawn at quad edge midpoints / centres.
	var step := maxf(params.terrain_mesh_step_m, 0.1)
	var mesh_lut := VillageTerrain.build_sample_lut(layout, params, t_seed, step)
	var inner := VillagePondShape.water_render_outline_xz()
	var outer := VillagePondShape.bank_outer_outline_xz()
	var n := inner.size()
	var above := 0.0
	var below := 0.0
	var vert_diff := 0.0
	var edge_len := 0.0
	var n_above := 0
	var n_samp := 0
	for i in range(n):
		var i0 := inner[i]
		var i1 := inner[(i + 1) % n]
		var o0 := outer[i]
		var o1 := outer[(i + 1) % n]
		edge_len = maxf(edge_len, o0.distance_to(o1))
		var yi0 := VillageTerrain.sample_y(i0, layout, params, t_seed)
		var yi1 := VillageTerrain.sample_y(i1, layout, params, t_seed)
		var yo0 := VillageTerrain.sample_y(o0, layout, params, t_seed)
		var yo1 := VillageTerrain.sample_y(o1, layout, params, t_seed)
		vert_diff = maxf(vert_diff, absf(yo0 - VillageTerrain.lut_sample(mesh_lut, o0)))
		for uv: Vector2 in [Vector2(0.5, 0.0), Vector2(0.5, 1.0), Vector2(0.0, 0.5), Vector2(0.5, 0.5), Vector2(0.25, 0.5), Vector2(0.75, 0.5)]:
			# bilinear over the quad (u along ring, v inner→outer)
			var pi := i0.lerp(i1, uv.x)
			var po := o0.lerp(o1, uv.x)
			var p := pi.lerp(po, uv.y)
			var yb := lerpf(lerpf(yi0, yi1, uv.x), lerpf(yo0, yo1, uv.x), uv.y)
			var yl := VillageTerrain.lut_sample(mesh_lut, p)
			var d := yb - yl
			above = maxf(above, d)
			below = minf(below, d)
			n_samp += 1
			if d > 0.01:
				n_above += 1
	print("[diag]   pond_bank verts=%d max_outer_edge=%.2fm bank_minus_lawn max=%.3f min=%.3f frac_above_1cm=%.2f vertex_vs_mesh=%.3f mesh_step=%.2f" % [
		n, edge_len, above, below, float(n_above) / maxf(float(n_samp), 1.0), vert_diff, step])
