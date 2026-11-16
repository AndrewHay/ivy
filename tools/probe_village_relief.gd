## Headless relief probe (ivy-82zn.14.1): per-seed open-lawn span, full span, open-lawn max
## slope, path max slope, and pad-skirt max slope for production VillageTerrainParams, with
## optional overrides. Same open-lawn mask as test_production_open_lawn_relief_floor_seed7.
##
## ivy-82zn.14.5: also reports rim_slope, the open-lawn max slope with the rim taper band
## INCLUDED (disc out to lawn_radius - RIM_INNER_M; pads, paths 5 m and pond still excluded).
## open_slope keeps the legacy interior mask (lawn_radius - rim_blend_m - 1 m) for comparison.
## Same mask as test_open_lawn_slope_with_rim_band.
##
## ivy-82zn.14.1 swell: camsun_view and camshade_view (tools/village_view_relief.gd) with span,
## mean |h| and fraction of in-view ground above 0.15 m; pad / plaza / pond anchor heights.
##
##   Godot --headless --script res://tools/probe_village_relief.gd -- \
##       [--seeds=1-30] [--set=base_amplitude_m:1.2,max_rise_m:1.6] [--terrain=res://<copy>.gd]
##       [--no-view-slope] [--view-only]
##
## --terrain= runs the same measures against another sampler script with the VillageTerrain
## static API (e.g. a scratch copy of HEAD for a before/after baseline). Diagnostics that need
## helpers newer than that copy are skipped.
extends SceneTree

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillagePondSite = preload("res://src/world/village_pond_site.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")
## CamSun / CamShade in-view measure, shared with test_camsun_view_relief_floor_seed7 (ivy-82zn.14.1).
const VillageViewRelief = preload("res://tools/village_view_relief.gd")

## Rim-inclusive slope mask stops this far inside lawn_radius (the FD stencil must stay inside
## the lawn disc; outside it the outer-hill field takes over).
const RIM_INNER_M := 0.6

static var T: GDScript = VillageTerrain


func _init() -> void:
	var seeds: Array[int] = []
	var overrides := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
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
		elif arg.begins_with("--terrain="):
			T = load(arg.substr(10)) as GDScript
			print("[relief] sampler=%s" % arg.substr(10))
	if seeds.is_empty():
		seeds = [7]
	var worst := {"open_slope": 0.0, "rim_slope": 0.0, "path_slope": 0.0, "min_open_span": INF,
		"min_sun_mean": INF, "min_shade_mean": INF, "sun_spans": []}
	for seed in seeds:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			print("[relief] seed=%d fallback" % seed)
			continue
		var params := VillageTerrainParams.production()
		for k in overrides.keys():
			var cur: Variant = params.get(k)
			if typeof(cur) == TYPE_INT:
				params.set(k, int(overrides[k]))
			else:
				params.set(k, overrides[k])
		T.clear_knoll_centres_cache()
		var t_seed: int = T.terrain_seed(layout, params)
		var with_view_slope := not OS.get_cmdline_user_args().has("--no-view-slope")
		var vs := VillageViewRelief.camsun(T, layout, params, t_seed, with_view_slope)
		var vh := VillageViewRelief.camshade(T, layout, params, t_seed, with_view_slope)
		print("[relief]   camsun_view seed=%d span=%.3f mean_abs_h=%.3f frac_gt15=%.2f max_slope=%.2f n=%d" % [
			seed, vs.span, vs.mean_abs, vs.frac_visible, vs.max_slope, vs.n])
		print("[relief]   camshade_view seed=%d span=%.3f mean_abs_h=%.3f frac_gt15=%.2f max_slope=%.2f n=%d" % [
			seed, vh.span, vh.mean_abs, vh.frac_visible, vh.max_slope, vh.n])
		var pad_hs: Array[String] = []
		for spec: Dictionary in layout.cottages:
			pad_hs.append("%.2f" % T.sample_y(spec["centre"] as Vector2, layout, params, t_seed))
		var plaza_h: float = T.sample_y(layout.plaza_rect.get_center(), layout, params, t_seed) \
			if layout.plaza_rect.has_area() else 0.0
		print("[relief]   anchors seed=%d pads=[%s] plaza=%.3f pond_c=%.3f" % [seed, ", ".join(pad_hs),
			plaza_h, T._compose_base(layout.pond_center, layout, params, t_seed)])
		worst.min_sun_mean = minf(worst.min_sun_mean, vs.mean_abs)
		worst.min_shade_mean = minf(worst.min_shade_mean, vh.mean_abs)
		worst.sun_spans.append(vs.span)
		if OS.get_cmdline_user_args().has("--view-only"):
			print("[relief]   knolls=%s" % str(T.knoll_centres(layout, params, t_seed)))
			if T == VillageTerrain:
				var kc := VillageTerrain.knoll_centres(layout, params, t_seed)
				for p: Vector2 in [Vector2(-14, -2), Vector2(14, -2), Vector2(-10, -12), Vector2(10, -12), Vector2(0, -24)]:
					var pd := VillageTerrain._min_dist_to_paths(p, layout)
					print("[relief]   pt %s h=%.3f base=%.3f pad=%.2f feat=%.2f path_d=%.1f" % [str(p),
						VillageTerrain.sample_y(p, layout, params, t_seed),
						VillageTerrain._compose_base_with_knolls(p, layout, params, t_seed, kc),
						VillageTerrain._pad_relief_scale(p, layout, params),
						VillageTerrain._feature_relief_scale(p, layout, params), pd])
			continue
		var st := _stats(layout, params, t_seed)
		var ps := _path_slope(layout, params, t_seed)
		print("[relief] seed=%d open_span=%.3f full_span=%.3f open_slope=%.2f rim_slope=%.2f path_slope=%.2f min=%.3f max=%.3f knolls=%d" % [
			seed, st.open_span, st.full_span, st.open_slope, st.rim_slope, ps, st.min_h, st.max_h,
			st.knoll_n])
		worst.open_slope = maxf(worst.open_slope, st.open_slope)
		worst.rim_slope = maxf(worst.rim_slope, st.rim_slope)
		worst.path_slope = maxf(worst.path_slope, ps)
		worst.min_open_span = minf(worst.min_open_span, st.open_span)
	print("[relief] WORST open_slope=%.2f rim_slope=%.2f path_slope=%.2f min_open_span=%.3f" % [
		worst.open_slope, worst.rim_slope, worst.path_slope, worst.min_open_span])
	var spans: Array = worst.sun_spans
	spans.sort()
	var median_span: float = spans[spans.size() / 2] if not spans.is_empty() else 0.0
	print("[relief] VIEWS camsun_median_span=%.3f camsun_min_mean_abs=%.3f camshade_min_mean_abs=%.3f" % [
		median_span, worst.min_sun_mean, worst.min_shade_mean])
	quit(0)


func _stats(layout: VillageLayout, params: VillageTerrainParams, t_seed: int) -> Dictionary:
	var g := layout.hamlet_centre_xz
	var r := layout.lawn_radius
	var interior_inner := params.rim_blend_m + 1.0
	var min_h := INF
	var max_h := -INF
	var min_open := INF
	var max_open := -INF
	var max_slope := 0.0
	var worst_xz := Vector2.ZERO
	var max_rim_slope := 0.0
	var worst_rim_xz := Vector2.ZERO
	var x := g.x - r
	while x <= g.x + r:
		var z := g.y - r
		while z <= g.y + r:
			var xz := Vector2(x, z)
			if xz.distance_to(g) < r:
				var h: float = T.sample_y(xz, layout, params, t_seed)
				min_h = minf(min_h, h)
				max_h = maxf(max_h, h)
				if _open(xz, layout, params, t_seed, false, interior_inner):
					min_open = minf(min_open, h)
					max_open = maxf(max_open, h)
				if _open(xz, layout, params, t_seed, true, RIM_INNER_M):
					var s: float = T.sample_slope_deg(xz, layout, params, t_seed)
					if s > max_rim_slope:
						max_rim_slope = s
						worst_rim_xz = xz
					if xz.distance_to(g) <= r - interior_inner and s > max_slope:
						max_slope = s
						worst_xz = xz
			z += 2.0
		x += 2.0
	var knolls: Array = T.knoll_centres(layout, params, t_seed)
	print("[relief]   worst open slope at %s r_g=%.1f d_pond=%.1f d_hero=%.1f pad_sdf=%.1f skirt_outer=%.1f knolls=%s" % [
		str(worst_xz), worst_xz.distance_to(g), worst_xz.distance_to(layout.pond_center),
		worst_xz.distance_to(VillageLayout.HERO_DOOR_STOOP), _pad_sdf(worst_xz, layout, params),
		T.pad_skirt_outer_m(params, layout, t_seed), str(knolls)])
	print("[relief]   worst rim-incl slope %.2f at %s r_g=%.1f (rim band starts r=%.1f)" % [
		max_rim_slope, str(worst_rim_xz), worst_rim_xz.distance_to(g), r - params.rim_blend_m])
	print("[relief]   g=%s lawn_r=%.1f hero=%s pond=%s" % [str(g), r, str(VillageLayout.HERO_DOOR_STOOP), str(layout.pond_center)])
	if T == VillageTerrain:
		for kc: Vector2 in knolls:
			var path_d := VillageTerrain._min_dist_to_paths(kc, layout)
			print("[relief]   knoll %s r_g=%.1f r+R=%.1f path_d=%.1f knoll_shield=%.2f pad_cover=%.2f feature_scale=%.2f h=%.3f" % [
				str(kc), kc.distance_to(g), kc.distance_to(g) + params.knoll_radius_m, path_d,
				VillageTerrain._knoll_shield(path_d, params),
				VillageTerrain._max_cottage_pad_weight(kc, layout, params, t_seed),
				VillageTerrain._feature_relief_scale(kc, layout, params),
				VillageTerrain.sample_y(kc, layout, params, t_seed)])
	return {
		"open_span": (max_open - min_open) if min_open < INF else 0.0,
		"full_span": max_h - min_h, "open_slope": max_slope, "rim_slope": max_rim_slope,
		"min_h": min_h, "max_h": max_h, "knoll_n": knolls.size(),
	}


static func _pad_sdf(xz: Vector2, layout: VillageLayout, params: VillageTerrainParams) -> float:
	var pad_sdf := INF
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var c := rect.get_center()
		var half := rect.size * 0.5
		pad_sdf = minf(pad_sdf, maxf(absf(xz.x - c.x) - half.x, absf(xz.y - c.y) - half.y))
	return pad_sdf


func _path_slope(layout: VillageLayout, params: VillageTerrainParams, t_seed: int) -> float:
	var m := 0.0
	for polyline: Variant in layout.path_polylines():
		var pts: Array = polyline
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 0.25))
			for k in range(n + 1):
				m = maxf(m, T.sample_slope_deg(a.lerp(b, float(k) / n), layout, params, t_seed))
	return m


## rim_inner_m: points beyond lawn_radius - rim_inner_m are dropped. RIM_INNER_M keeps the rim
## taper band; rim_blend_m + 1 is the legacy interior-only mask.
static func _open(xz: Vector2, layout: VillageLayout, params: VillageTerrainParams,
		t_seed: int, for_slope: bool, rim_inner_m: float) -> bool:
	var g := layout.hamlet_centre_xz
	if xz.distance_to(g) > layout.lawn_radius - rim_inner_m:
		return false
	if for_slope:
		var pond_r := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m + params.pond_skirt_m + 1.0
		if xz.distance_to(layout.pond_center) < pond_r:
			return false
		for polyline: Variant in layout.path_polylines():
			var pts: Array = polyline
			for i in range(pts.size() - 1):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var ab := b - a
				var t := clampf((xz - a).dot(ab) / maxf(ab.dot(ab), 1e-6), 0.0, 1.0)
				if xz.distance_to(a + ab * t) < 5.0:
					return false
	var skirt_outer: float = T.pad_skirt_outer_m(params, layout, t_seed) + 1.0
	for spec: Dictionary in layout.cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var c := rect.get_center()
		var half := rect.size * 0.5
		var sdf := maxf(absf(xz.x - c.x) - half.x, absf(xz.y - c.y) - half.y)
		if sdf <= skirt_outer:
			return false
	return true
