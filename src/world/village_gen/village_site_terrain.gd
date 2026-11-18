## VillageSiteTerrain — the generator's view of the raw landform while it places the village
## (ivy-82zn.14.16, WP2): cottage site rejection (SD-VILLAGE-TERRAIN-19 table, measured ring with
## neighbour replay) and the pond site slope (SD-19 pond row, AR-LF-LAYOUT). One instance per
## offset rank; it is shared by that rank's generator attempts.
##
## U = cap_sun(L + D) (the field's sample_unfit_y inside 70 m, where Rg = 0), sampled exactly on
## the integer 1 m lattice and cached per node: this is the "raw LUT" of AR-LF-API, filled lazily.
## Plane fits read it bilinearly; the measured ring reads the lattice nodes directly, so the
## selection uses exact node values (AR-LF-GAP-5 fidelity).
class_name VillageSiteTerrain
extends RefCounted

const _Backdrop := preload("res://src/world/village_backdrop.gd")

var params
var hero := {}  # {centre, r_c, target, w}; empty = no hero replay
## Sites the field applies before the pads (SD-19 step 2, ivy-82zn.14.23), built with the field's
## own helpers (VillageTerrainField.plaza_site / pond_site) on U: plaza once per rank, pond per
## attempt (set_pond). Empty = not replayed.
var plaza := {}
var pond := {}
## Per-attempt counters (the generator resets them; readout / terrain_diag).
var stats := {"evaluated": 0, "rejected_slope": 0, "rejected_ring": 0}
var _u_fn: Callable
var _nodes := {}


static func for_landform(norm_seed: int, p_params, landform: Dictionary) -> VillageSiteTerrain:
	var ctx := VillageLandform.make_ctx(norm_seed, p_params, landform.get("offset", Vector2.ZERO),
		float(landform.get("rot_deg", 0.0)))
	var sun := VillageTerrain.sun_corridor_azimuths()
	var fn := func(xz: Vector2) -> float: return VillageLandform.capped_raw_y(xz, ctx, sun)
	var h := {
		"centre": VillageLayout.HERO_DOOR_STOOP, "r_c": float(p_params.hero_flat_r_m),
		"target": float(ctx["y_hero_raw"]), "w": float(landform.get("hero_ring_w", p_params.hero_ring_min_m)),
	}
	var st := from_fn(fn, p_params, h)
	var rect := VillageLayout.plaza_rect_at(VillageLayout.VILLAGE_GREEN_G, VillageLayout.PLAZA_SIDE_L)
	st.plaza = VillageTerrainField.plaza_site(fn, rect, p_params,
		float(landform.get("plaza_ring_w", p_params.plaza_ring_m)))
	return st


static func from_fn(u_fn: Callable, p_params, p_hero: Dictionary = {}) -> VillageSiteTerrain:
	var st := VillageSiteTerrain.new()
	st._u_fn = u_fn
	st.params = p_params
	st.hero = p_hero
	return st


func set_pond(centre: Vector2) -> void:
	## The attempt's pond (after the reserve stage): level / basin from the field's helper on exact U.
	pond = VillageTerrainField.pond_site(_u_fn, centre, params)


func u_exact(xz: Vector2) -> float:
	return float(_u_fn.call(xz))


func reset_stats() -> void:
	stats = {"evaluated": 0, "rejected_slope": 0, "rejected_ring": 0}


func site_fn() -> Callable:
	return Callable(self, "evaluate")


func u_node(i: int, j: int) -> float:
	var key := Vector2i(i, j)
	var v: Variant = _nodes.get(key)
	if v == null:
		v = float(_u_fn.call(Vector2(float(i), float(j))))
		_nodes[key] = v
	return v


func u_at(xz: Vector2) -> float:
	## Bilinear read of the lattice.
	var i := int(floor(xz.x))
	var j := int(floor(xz.y))
	var tx := xz.x - float(i)
	var tz := xz.y - float(j)
	var a := lerpf(u_node(i, j), u_node(i + 1, j), tx)
	var b := lerpf(u_node(i, j + 1), u_node(i + 1, j + 1), tx)
	return lerpf(a, b, tz)


func pad_core(spec: Dictionary) -> Rect2:
	return _Backdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)


func evaluate(cand: Dictionary, picked: Array) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var r := _evaluate(cand, picked)
	stats["eval_us"] = int(stats.get("eval_us", 0)) + Time.get_ticks_usec() - t0
	return r


func _evaluate(cand: Dictionary, picked: Array) -> Dictionary:
	## terrain_site_fn for PlotSampler.select / append_to_selection: {ok, reason, s_deg, w, target,
	## peak_deg, core}. Rejects site slope > max_site_slope_deg ("slope") or a failing measured ring
	## with the selected pads (layout order) and the hero replayed ("ring"). Memoised on the
	## candidate dict ("_site": the plane, a slope rejection, and ring results per neighbour set).
	var memo: Dictionary = cand.get("_site", {})
	if memo.is_empty():
		cand["_site"] = memo
	if memo.has("slope_reject"):
		return memo["slope_reject"]
	var core := pad_core(cand["spec"] as Dictionary)
	if not memo.has("plane"):
		var pl := VillageLandform.site_plane_fn(Callable(self, "u_at"), core, 1.0)
		memo["plane"] = {"s_deg": float(pl["slope_deg"]), "target": float(pl["mean"])}
		stats["evaluated"] = int(stats["evaluated"]) + 1
	var plane: Dictionary = memo["plane"]
	var s_deg: float = plane["s_deg"]
	var target: float = plane["target"]
	if s_deg > params.max_site_slope_deg:
		var rej := {"ok": false, "reason": "slope", "s_deg": s_deg, "w": params.pad_ring_max_m,
			"target": target, "peak_deg": NAN, "core": core}
		memo["slope_reject"] = rej
		stats["rejected_slope"] = int(stats["rejected_slope"]) + 1
		return rej
	# Measured ring grid: integer-aligned 1 m nodes over the core grown by w_max + 2.
	var w_max: float = params.pad_ring_max_m
	var box := core.grow(w_max + 2.0)
	var origin := Vector2(floor(box.position.x), floor(box.position.y))
	var nx := int(ceil(box.end.x) - origin.x) + 1
	var nz := int(ceil(box.end.y) - origin.y) + 1
	var before: Array = []
	# Plaza then pond, baked into U (per-node targets; replayed only when they reach the box).
	var bake: Array = []
	for s: Dictionary in [plaza, pond]:
		if s.is_empty():
			continue
		var bc: Vector2 = s["bound_c"]
		var near_pt := Vector2(clampf(bc.x, box.position.x, box.end.x), clampf(bc.y, box.position.y, box.end.y))
		if near_pt.distance_to(bc) < float(s["bound_r"]):
			bake.append(s)
	var nkey := "pond@%s;" % (str(pond["centre"]) if not pond.is_empty() else "-")
	for e: Variant in picked:
		var pad: Dictionary = (e as Dictionary).get("_pad", {})
		if pad.is_empty():
			continue
		var nr: Rect2 = pad["rect"]
		if not nr.grow(float(pad["w"])).intersects(box):
			continue
		before.append(pad)
		nkey += "%s|%.4f|%.3f;" % [str(nr), float(pad["target"]), float(pad["w"])]
	if memo.has(nkey):
		return memo[nkey]
	var p_ref = params
	var grid := {"origin": origin, "nx": nx, "nz": nz,
		"u_fn": func(p: Vector2, _k: int) -> float:
			var u := u_node(roundi(p.x), roundi(p.y))
			for s: Dictionary in bake:
				u = VillageTerrainField.apply_site(s, p, u, p_ref)
			return u}
	var sdf := VillageLandform.grid_sdf_rect(grid, core)
	var b_sites: Array = []
	for pad: Dictionary in before:
		b_sites.append({"sdf": VillageLandform.grid_sdf_rect(grid, pad["rect"]), "target": float(pad["target"]),
			"w": float(pad["w"])})
	var a_sites: Array = []
	if not hero.is_empty():
		var hc: Vector2 = hero["centre"]
		var hr: float = float(hero["r_c"]) + float(hero["w"])
		var near := Vector2(clampf(hc.x, box.position.x, box.end.x), clampf(hc.y, box.position.y, box.end.y))
		if near.distance_to(hc) < hr:
			a_sites.append({"sdf": VillageLandform.grid_sdf_disc(grid, hc, float(hero["r_c"])),
				"target": float(hero["target"]), "w": float(hero["w"])})
	var ring := VillageLandform.measured_ring(grid, sdf, target, params.pad_ring_min_m, w_max,
		params.ring_max_slope_deg, b_sites, a_sites)
	var res := {"ok": bool(ring["ok"]), "reason": "" if bool(ring["ok"]) else "ring", "s_deg": s_deg,
		"w": float(ring["w"]), "target": target, "peak_deg": float(ring["peak_deg"]), "core": core}
	if not bool(ring["ok"]):
		stats["rejected_ring"] = int(stats["rejected_ring"]) + 1
	memo[nkey] = res
	return res


func zone_sites(layout: VillageLayout) -> Array:
	## The fit sites with their stored widths, as the field builds them: plaza, pond (re-read at the
	## layout's pond centre: resolve_after_paths may have moved it), pads (spec.ring_w), hero.
	var out: Array = []
	if not plaza.is_empty():
		out.append(plaza)
	if layout.pond_placed:
		if pond.is_empty() or pond["centre"] != layout.pond_center:
			set_pond(layout.pond_center)
		out.append(pond)
	for spec: Dictionary in layout.cottages:
		var core := pad_core(spec)
		var w := float(spec.get("ring_w", params.pad_ring_max_m))
		out.append({"kind": "cottage", "rect": core, "w": w, "bound_c": core.get_center(),
			"bound_r": core.size.length() * 0.5 + w})
	if not hero.is_empty():
		var r_out := float(hero["r_c"]) + float(hero["w"])
		out.append({"kind": "hero", "centre": hero["centre"], "r_c": hero["r_c"], "w": hero["w"],
			"bound_c": hero["centre"], "bound_r": r_out})
	return out


func open_path_slope(layout: VillageLayout) -> Dictionary:
	## SD-20 / AR-LF-PERF P1: the generator's path check. Open-land samples only (shared
	## classification, VillageTerrainField.path_scan), slope from 4 EXACT U samples (eps 0.4, the
	## field's sample_slope_deg stencil): on open land the field equals U, so no field is built.
	## {deg, at, n_open, zone_deg (0: not read)}.
	var eps := 0.4
	var inv := 1.0 / maxf(2.0 * eps, 0.01)
	var fn := func(q: Vector2) -> float:
		var dx := (u_exact(q + Vector2(eps, 0.0)) - u_exact(q - Vector2(eps, 0.0))) * inv
		var dz := (u_exact(q + Vector2(0.0, eps)) - u_exact(q - Vector2(0.0, eps))) * inv
		return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))
	return VillageTerrainField.path_scan(layout, params, zone_sites(layout), fn)


func pond_site(centre: Vector2) -> Dictionary:
	## Pond centre site (SD-19 pond row): plane fit of U over r ≤ BANK_OUTER_M on a 1 m grid.
	## {slope_deg, mean}.
	var pl := VillageLandform.disc_plane(Callable(self, "u_at"), centre, VillagePondSite.BANK_OUTER_M, 1.0)
	return {"slope_deg": float(pl["slope_deg"]), "mean": float(pl["mean"])}
