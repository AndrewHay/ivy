## Landscape-first probe (ivy-82zn.14.14, replaces tools/probe_village_hill.gd; AR-LF-KEEP).
## Per seed: chosen landform offset + candidate + SD-18 measures, fallback flag, fitted village
## span, max |T_i − y_hero| (storey), open-land slope p95 / max, hero ring max slope, path max
## slope (door zone separately), nearest cottage centre spacing, generate / search ms.
##
##   Godot --headless --script res://tools/probe_village_landscape.gd -- [--seeds=1-20] [--out=res://.tmp/x.txt]
extends SceneTree

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")


func _init() -> void:
	var seeds: Array[int] = [1, 7, 12]
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds.clear()
			var spec := arg.substr(8)
			if spec.contains("-"):
				var ab := spec.split("-")
				for s in range(int(ab[0]), int(ab[1]) + 1):
					seeds.append(s)
			else:
				for s in spec.split(","):
					seeds.append(int(s))
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
	var lines := PackedStringArray()
	var p := VillageTerrainParams.production()
	for seed in seeds:
		var t0 := Time.get_ticks_usec()
		var layout := VillageLayout.generate(seed)
		var gen_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if layout.fallback:
			lines.append("seed %2d generator fallback" % seed)
			continue
		var f = VillageTerrain.field(layout, p)
		var m: Dictionary = layout.landform["measures"]
		var span_storey := _span_storey(f)
		var slopes := _open_slopes(f)
		var path: Dictionary = f.max_path_slope(layout)
		lines.append(("seed %2d cand %2d off %s fb %s | s_hero %.1f up %.1f down %.1f span_raw %.2f p95_raw %.1f"
			+ " | span %.2f storey %.2f open p95 %.1f max %.1f hero_ring %.1f | path %.1f door %.1f"
			+ " | min_sep %.1f | gen %.0f ms search %.0f ms") % [
			seed, layout.landform["index"], str(layout.landform["offset"]), str(layout.landform["fallback"]),
			m["s_hero"], m["up_hero"], m["down_hero"], m["span_v"], m["p95_v"],
			span_storey.x, span_storey.y, slopes["p95"], slopes["max"], slopes["hero_ring"],
			path["deg"], path["door_exempt_deg"], _min_sep(layout), gen_ms,
			float(layout.terrain_diag.get("search_ms", 0.0))])
	var text := "\n".join(lines)
	print(text)
	if not out_path.is_empty():
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		if fa != null:
			fa.store_string(text + "\n")
			fa.close()
	quit(0)


func _span_storey(f) -> Vector2:
	var layout: VillageLayout = f.layout
	var g := layout.hamlet_centre_xz
	var pond_r: float = VillagePondSite.BANK_OUTER_M + f.params.pond_rim_extra_m + f.params.pond_skirt_m
	var lo := INF
	var hi := -INF
	for ix in range(-23, 24):
		for iz in range(-23, 24):
			var q := Vector2(ix, iz) * 2.0
			var xz := g + q
			if q.length() <= 46.0 and xz.distance_to(layout.pond_center) > pond_r:
				var y: float = f.sample_y(xz)
				lo = minf(lo, y)
				hi = maxf(hi, y)
	var storey := 0.0
	for s: Dictionary in f.sites:
		if s["kind"] == "cottage":
			storey = maxf(storey, absf(float(s["target"]) - float(f.y_hero)))
	return Vector2(hi - lo, storey)


func _open_slopes(f) -> Dictionary:
	var layout: VillageLayout = f.layout
	var g := layout.hamlet_centre_xz
	var sl: Array[float] = []
	var hero_ring := 0.0
	for ix in range(-23, 24):
		for iz in range(-23, 24):
			var q := Vector2(ix, iz) * 2.0
			if q.length() > 46.0:
				continue
			var xz := g + q
			var in_ring := false
			for s: Dictionary in f.sites:
				if s["kind"] != "hero" and s["kind"] != "cottage":
					continue
				var d: float = f.site_sdf(s, xz)
				if d <= float(s["w"]):
					in_ring = true
					if s["kind"] == "hero" and d > 0.0:
						hero_ring = maxf(hero_ring, f.sample_slope_deg(xz))
			if not in_ring:
				sl.append(f.sample_slope_deg(xz))
	sl.sort()
	return {"p95": sl[int(sl.size() * 0.95)], "max": sl[sl.size() - 1], "hero_ring": hero_ring}


func _min_sep(layout: VillageLayout) -> float:
	var best := INF
	for i in range(layout.cottages.size()):
		for j in range(i + 1, layout.cottages.size()):
			var a: Vector2 = (layout.cottages[i] as Dictionary)["centre"]
			var b: Vector2 = (layout.cottages[j] as Dictionary)["centre"]
			best = minf(best, a.distance_to(b))
	return best
