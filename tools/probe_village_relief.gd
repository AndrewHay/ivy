## Headless relief probe (ivy-82zn.14.1; landscape-first rewrite ivy-82zn.14.14). Per seed, on
## production VillageTerrainParams (optional overrides), heights relative to y_hero:
## village span (r ≤ 46 m about G, pond basin out), open-land slope max / p95 (outside hero / pad
## rings and the pond basin), path max slope (SD-20 metric), CamSun / CamShade in-view relief,
## and the anchors (pads / plaza / pond water) relative to the hero pad.
##
##   Godot --headless --script res://tools/probe_village_relief.gd -- \
##       [--seeds=1-30] [--set=landform_height_m:12,base_amplitude_m:0.3] [--no-view-slope]
extends SceneTree

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillagePondSite = preload("res://src/world/village_pond_site.gd")
const VillageViewRelief = preload("res://tools/village_view_relief.gd")

const VILLAGE_R_M := 46.0


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
	if seeds.is_empty():
		seeds = [7]
	var with_view_slope := not OS.get_cmdline_user_args().has("--no-view-slope")
	for seed in seeds:
		var params := VillageTerrainParams.production()
		for k in overrides.keys():
			var cur: Variant = params.get(k)
			params.set(k, int(overrides[k]) if typeof(cur) == TYPE_INT else overrides[k])
		var layout := VillageLayout.generate(seed, params)
		if layout.fallback:
			print("[relief] seed=%d fallback" % seed)
			continue
		var f = VillageTerrain.field(layout, params)
		var y0: float = f.y_hero
		var vs := VillageViewRelief.camsun(VillageTerrain, layout, params, 0, with_view_slope)
		var vh := VillageViewRelief.camshade(VillageTerrain, layout, params, 0, with_view_slope)
		var st := _stats(f)
		var pads: Array[String] = []
		for s: Dictionary in f.sites:
			if s["kind"] == "cottage":
				pads.append("%+.2f" % (float(s["target"]) - y0))
		var path: Dictionary = f.max_path_slope(layout)
		print("[relief] seed=%d y_hero=%.2f span=%.2f open_slope max=%.1f p95=%.1f path=%.1f (door %.1f) storey=%.2f" % [
			seed, y0, st["span"], st["max"], st["p95"], path["deg"], path["door_exempt_deg"], st["storey"]])
		print("[relief]   pads Δ=[%s] pond_water Δ=%+.2f offset=%s cand=%d" % [", ".join(pads),
			VillageTerrain.pond_water_y(layout, params) - y0, str(layout.landform["offset"]),
			int(layout.landform["index"])])
		print("[relief]   camsun span=%.2f mean|Δh|=%.2f max_slope=%.1f | camshade span=%.2f mean|Δh|=%.2f" % [
			vs.span, vs.mean_abs, vs.max_slope, vh.span, vh.mean_abs])
	quit(0)


func _stats(f) -> Dictionary:
	var layout: VillageLayout = f.layout
	var p: VillageTerrainParams = f.params
	var g := layout.hamlet_centre_xz
	var pond_r := VillagePondSite.BANK_OUTER_M + p.pond_rim_extra_m + p.pond_skirt_m
	var lo := INF
	var hi := -INF
	var slopes: Array[float] = []
	var x := -VILLAGE_R_M
	while x <= VILLAGE_R_M:
		var z := -VILLAGE_R_M
		while z <= VILLAGE_R_M:
			var xz := g + Vector2(x, z)
			if Vector2(x, z).length() <= VILLAGE_R_M and xz.distance_to(layout.pond_center) > pond_r:
				var y: float = f.sample_y(xz)
				lo = minf(lo, y)
				hi = maxf(hi, y)
				var in_ring := false
				for s: Dictionary in f.sites:
					if (s["kind"] == "hero" or s["kind"] == "cottage") and f.site_sdf(s, xz) <= float(s["w"]):
						in_ring = true
						break
				if not in_ring:
					slopes.append(f.sample_slope_deg(xz))
			z += 2.0
		x += 2.0
	slopes.sort()
	var storey := 0.0
	for s: Dictionary in f.sites:
		if s["kind"] == "cottage":
			storey = maxf(storey, absf(float(s["target"]) - float(f.y_hero)))
	return {
		"span": hi - lo,
		"max": slopes[slopes.size() - 1] if not slopes.is_empty() else 0.0,
		"p95": slopes[int(slopes.size() * 0.95)] if not slopes.is_empty() else 0.0,
		"storey": storey,
	}
