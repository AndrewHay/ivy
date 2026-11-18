## VillageTerrainField — the resolved generated-village terrain for one (layout, terrain params,
## hills params): sample_y = fit(cap_sun(L + D + Rg)) (SD-VILLAGE-TERRAIN-17 / -19, AR-LF-API).
## One object answers every height query in the generated world (lawn mesh, far mesh, forest,
## cottages, pond, plaza, stones, grass, fauna, wanderer, camera floor). Built and cached by
## VillageTerrain.field(layout, params, hills_params) on layout.terrain_field (AR-LF-D10).
class_name VillageTerrainField
extends RefCounted

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const VillageBackdrop = preload("res://src/world/village_backdrop.gd")

## Points on the pond bank circle used for the water level (min of the capped field).
const POND_BANK_SAMPLES := 72

var layout: VillageLayout
var params: VillageTerrainParams
var hills_params: HillsParams
var ctx: Dictionary = {}
var sun_az: Vector2 = Vector2.ZERO
## Flat (classic / variant 1): sample_y ≡ 0.
var flat := true
## Hero pad target (backdrop frame); World lowers the backdrop by it (datum option A).
var y_hero := 0.0
var s_hero := 0.0
## Fit sites in ascending priority (plaza < pond < cottages in layout order < hero). Each:
## {kind, target | plane, w, r_c, s_deg, bound_c, bound_r, ...} (SD-VILLAGE-TERRAIN-19).
var sites: Array[Dictionary] = []
## Water surface: lowest bank point − freeboard, never above the bank outline − 2 cm.
var pond_water_y := 0.0
## Bank level: min of the capped field on the circle r = BANK_OUTER_M.
var pond_bank_y := 0.0
## Lowest vertex of the built meshes (World/Ground sits below it, AR-LF-D7). NAN until built.
## mesh_min_y is the min over whatever is built; lawn_min_y / far_min_y per mesh.
var mesh_min_y := NAN
var lawn_min_y := NAN
var far_min_y := NAN
const MESH_LAWN := "lawn"
const MESH_FAR := "far"
var diag: Dictionary = {}
## Cache keys (VillageTerrain.field).
var signature := 0
var hills_signature := 0

var _g := Vector2.ZERO
var _hills_seed := 0
var _rg_on := false
var _rg_start := 70.0
var _rg_full := 100.0
var _outline_min := NAN


static func build(p_layout: VillageLayout, p_params: VillageTerrainParams, p_hills: HillsParams) -> VillageTerrainField:
	var f := VillageTerrainField.new()
	f.layout = p_layout
	f.params = p_params.duplicate_params()
	f.hills_params = p_hills.duplicate_params()
	f.flat = p_params.variant == 1 or not p_layout.is_generated
	if f.flat:
		f.pond_water_y = VillageBackdrop.POND_WATER_Y_OFFSET
		return f
	f._resolve()
	return f


func _resolve() -> void:
	_g = layout.hamlet_centre_xz
	var norm := _norm_seed()
	if layout.landform.is_empty():
		# Layouts built without generate(seed, params) (hand-built in tests / probes): search here.
		var ranked := VillageLandform.rank_offsets(norm, params)
		layout.landform = VillageGeneratorV3.landform_for_rank(norm, params, ranked, 0)
	var off: Vector2 = layout.landform.get("offset", Vector2.ZERO)
	var rot: float = float(layout.landform.get("rot_deg", 0.0))
	ctx = VillageLandform.make_ctx(norm, params, off, rot)
	sun_az = VillageTerrain.sun_corridor_azimuths()
	y_hero = float(ctx["y_hero_raw"])
	s_hero = float(ctx["s_hero"])
	_rg_on = hills_params.variant != 1
	_hills_seed = HillsHeightfield.terrain_seed(layout, hills_params)
	_rg_start = params.far_ridge_start_m
	_rg_full = maxf(params.far_ridge_full_m, _rg_start + 0.01)
	_build_sites()
	_outline_min = _pond_outline_min()
	pond_water_y = minf(pond_bank_y - params.pond_freeboard_m,
		_outline_min - VillageTerrain.POND_WATER_BANK_CLEAR_M)


# ── Sites (SD-VILLAGE-TERRAIN-19) ─────────────────────────────────────────────

## ── Shared site helpers (SD-19 step 2, ivy-82zn.14.23): ONE implementation of the plaza plane and
## the pond level / basin profile, used by this field and by the generator's VillageSiteTerrain
## (selection replay) and the offset search (plaza_ring_ok). u_fn = cap_sun(L + D) (+ Rg = 0 here).

static func plaza_site(u_fn: Callable, rect: Rect2, p: VillageTerrainParams, w: float) -> Dictionary:
	## Plaza: least-squares plane of U over the rect (2 m grid), tilt scaled to ≤ plaza_max_tilt_deg,
	## through the fitted mean at the rect centre (the 2 m grid is symmetric about it).
	var pl := VillageLandform.site_plane_fn(u_fn, rect, 2.0)
	var a := float(pl["a"])
	var b := float(pl["b"])
	var raw_tilt := float(pl["slope_deg"])
	var tilt := raw_tilt
	if raw_tilt > p.plaza_max_tilt_deg and raw_tilt > 1e-6:
		var k := tan(deg_to_rad(p.plaza_max_tilt_deg)) / tan(deg_to_rad(raw_tilt))
		a *= k
		b *= k
		tilt = p.plaza_max_tilt_deg
	var ctr := rect.get_center()
	var c := float(pl["mean"]) - a * ctr.x - b * ctr.y
	return {
		"kind": "plaza", "rect": rect, "a": a, "b": b, "c": c, "w": w,
		"tilt_deg": tilt, "raw_tilt_deg": raw_tilt,
		"bound_c": ctr, "bound_r": rect.size.length() * 0.5 + w,
	}


static func pond_site(u_fn: Callable, centre: Vector2, p: VillageTerrainParams) -> Dictionary:
	## Pond: water level from the lowest U on the bank circle r = BANK_OUTER_M (SD-19, AR-LF-GAP-7);
	## core = water disc, ring out to BANK_OUTER_M + rim extra + skirt.
	var lo := INF
	for i in range(POND_BANK_SAMPLES):
		var ang := TAU * float(i) / float(POND_BANK_SAMPLES)
		lo = minf(lo, float(u_fn.call(centre + Vector2(cos(ang), sin(ang)) * VillagePondSite.BANK_OUTER_M)))
	var r_core := VillagePondSite.MEAN_WATER_RADIUS_M * p.pond_floor_scale
	var r_outer := VillagePondSite.BANK_OUTER_M + p.pond_rim_extra_m + p.pond_skirt_m
	return {
		"kind": "pond", "centre": centre, "r_c": r_core, "w": maxf(r_outer - r_core, 0.01),
		"level": lo, "bound_c": centre, "bound_r": r_outer,
	}


static func sdf_of(s: Dictionary, xz: Vector2) -> float:
	## Signed distance to a site core (negative inside).
	if s.has("rect"):
		return VillageTerrain.rect_sdf(xz, s["rect"])
	return xz.distance_to(s["centre"]) - float(s["r_c"])


static func target_of(s: Dictionary, xz: Vector2, p: VillageTerrainParams) -> float:
	## Site target at xz: plaza plane, pond basin profile about its level, else the scalar target.
	match String(s["kind"]):
		"plaza":
			return float(s["a"]) * xz.x + float(s["b"]) * xz.y + float(s["c"])
		"pond":
			var d := xz.distance_to(s["centre"])
			var bank := VillagePondSite.BANK_OUTER_M
			var sigma := maxf(p.pond_lip_sigma_m, 0.01)
			var basin := p.pond_depth_m * (1.0 - VillageLandform.smooth01(d / bank))
			var lip := p.pond_lip_rise_m * exp(-((d - bank) * (d - bank)) / (2.0 * sigma * sigma))
			return float(s["level"]) + basin + lip
	return float(s["target"])


static func apply_site(s: Dictionary, xz: Vector2, y: float, p: VillageTerrainParams) -> float:
	## One step of the SD-17 §5 fit chain: lerp(y, target, fer(sdf, 0, w)) inside the site bound.
	var br: float = s["bound_r"]
	if xz.distance_squared_to(s["bound_c"]) > br * br:
		return y
	var wgt := VillageLandform.fer(sdf_of(s, xz), 0.0, float(s["w"]))
	if wgt <= 0.0:
		return y
	return lerpf(y, target_of(s, xz, p), wgt)


static func measure_plaza_ring(u_fn: Callable, plaza: Dictionary, p: VillageTerrainParams) -> Dictionary:
	## -18 plaza_ring_ok / -19 plaza row: the measured plaza ring, ladder [plaza_ring_m,
	## plaza_ring_max_m] on the plaza rect, per-node target = the plaza plane, nothing replayed (the
	## field applies the plaza first). Integer-aligned 1 m grid, lazy U.
	var rect: Rect2 = plaza["rect"]
	var w_max: float = p.plaza_ring_max_m
	var box := rect.grow(w_max + 2.0)
	var origin := Vector2(floor(box.position.x), floor(box.position.y))
	var nx := int(ceil(box.end.x) - origin.x) + 1
	var nz := int(ceil(box.end.y) - origin.y) + 1
	var grid := {"origin": origin, "nx": nx, "nz": nz,
		"u_fn": func(q: Vector2, _k: int) -> float: return float(u_fn.call(q))}
	var sdf := VillageLandform.grid_sdf_rect(grid, rect)
	var t := PackedFloat32Array()
	t.resize(nx * nz)
	for iz in range(nz):
		for ix in range(nx):
			t[iz * nx + ix] = target_of(plaza, origin + Vector2(float(ix), float(iz)), p)
	return VillageLandform.measured_ring(grid, sdf, t, p.plaza_ring_m, w_max, p.ring_max_slope_deg)


func _build_sites() -> void:
	sites.clear()
	var unfit := Callable(self, "sample_unfit_y")
	# Plaza: tilted plane; ring = the stored measured width (landform.plaza_ring_w, -18
	# plaza_ring_ok), measured here with the same helper only when missing.
	if layout.plaza_rect.has_area():
		var plaza := plaza_site(unfit, layout.plaza_rect, params, params.plaza_ring_m)
		var pw: float
		if layout.landform.has("plaza_ring_w"):
			pw = float(layout.landform["plaza_ring_w"])
		else:
			pw = float(measure_plaza_ring(unfit, plaza, params)["w"])
		plaza["w"] = pw
		plaza["bound_r"] = (plaza["rect"] as Rect2).size.length() * 0.5 + pw
		if float(plaza["raw_tilt_deg"]) > VillageLandform.PLAZA_RAW_TILT_MAX_DEG:
			diag["plaza_steep"] = true
		sites.append(plaza)
	# Pond: water level from the lowest bank point (SD-19, AR-LF-GAP-7).
	if layout.pond_placed:
		var pond := pond_site(unfit, layout.pond_center, params)
		pond_bank_y = float(pond["level"])
		pond["s_deg"] = VillageLandform.disc_plane(unfit, layout.pond_center, VillagePondSite.BANK_OUTER_M, 1.0)["slope_deg"]
		sites.append(pond)
	# Ring widths: the stored measured values (SD-19 step 6: landform.hero_ring_w from the search,
	# spec.ring_w from the plot sampler); measured here with the same helper only when missing
	# (hand-built layouts, manual mode without a search entry). On hero fallback the stored value
	# is the ladder's best width.
	var hero_w: float
	var hero_ok := true
	if layout.landform.has("hero_ring_w"):
		hero_w = float(layout.landform["hero_ring_w"])
		hero_ok = bool((layout.landform.get("measures", {}) as Dictionary).get("hero_ring_ok", true))
	else:
		var hr := VillageLandform.hero_ring(_norm_seed(), params, ctx["offset"], float(ctx["rot_deg"]))
		hero_w = float(hr["w"])
		hero_ok = bool(hr["ok"])
	var hero_site := {
		"kind": "hero", "centre": VillageLayout.HERO_DOOR_STOOP, "r_c": params.hero_flat_r_m,
		"s_deg": s_hero, "target": y_hero, "w": hero_w, "ring_ok": hero_ok,
		"bound_c": VillageLayout.HERO_DOOR_STOOP, "bound_r": params.hero_flat_r_m + hero_w,
	}
	# Cottage pads (layout order): mean of the capped field over the grown exterior rect.
	var pads: Array[Dictionary] = []
	for i in range(layout.cottages.size()):
		var spec: Dictionary = layout.cottages[i]
		var core := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var r_c := core.size.length() * 0.5
		var pl := VillageLandform.site_plane_fn(unfit, core, 1.0)
		var w: float
		var ok := true
		if spec.has("ring_w"):
			w = float(spec["ring_w"])
		else:
			var mr := _measure_pad_ring(core, float(pl["mean"]), pads, hero_site)
			w = float(mr["w"])
			ok = bool(mr["ok"])
		var pad := {
			"kind": "cottage", "index": i, "rect": core, "r_c": r_c, "s_deg": pl["slope_deg"],
			"target": pl["mean"], "w": w, "ring_ok": ok,
			"bound_c": core.get_center(), "bound_r": r_c + w,
		}
		pads.append(pad)
		sites.append(pad)
	sites.append(hero_site)


func _norm_seed() -> int:
	return layout.generation_seed if layout.generation_seed > 0 else params.layout_seed


func _measure_pad_ring(core: Rect2, target: float, prev: Array[Dictionary], hero_site: Dictionary) -> Dictionary:
	## The plot sampler's measured ring (VillageLandform.measured_ring) on exact sample_unfit_y, with
	## the earlier pads (layout order) and the hero replayed; same integer-aligned 1 m grid.
	var w_max: float = params.pad_ring_max_m
	var box := core.grow(w_max + 2.0)
	var origin := Vector2(floor(box.position.x), floor(box.position.y))
	var nx := int(ceil(box.end.x) - origin.x) + 1
	var nz := int(ceil(box.end.y) - origin.y) + 1
	# Plaza and pond (already in `sites`, field order) are baked into U (SD-19 step 2).
	var bake: Array = []
	for s: Dictionary in sites:
		if s["kind"] == "plaza" or s["kind"] == "pond":
			bake.append(s)
	var p_ref := params
	var grid := {"origin": origin, "nx": nx, "nz": nz,
		"u_fn": func(p: Vector2, _k: int) -> float:
			var u := sample_unfit_y(p)
			for s: Dictionary in bake:
				u = apply_site(s, p, u, p_ref)
			return u}
	var sdf := VillageLandform.grid_sdf_rect(grid, core)
	var before: Array = []
	for s: Dictionary in prev:
		var r: Rect2 = s["rect"]
		if not r.grow(float(s["w"])).intersects(box):
			continue
		before.append({"sdf": VillageLandform.grid_sdf_rect(grid, r), "target": float(s["target"]), "w": float(s["w"])})
	var after := [{"sdf": VillageLandform.grid_sdf_disc(grid, hero_site["centre"], float(hero_site["r_c"])),
		"target": float(hero_site["target"]), "w": float(hero_site["w"])}]
	return VillageLandform.measured_ring(grid, sdf, target, params.pad_ring_min_m, w_max,
		params.ring_max_slope_deg, before, after)


func site_sdf(s: Dictionary, xz: Vector2) -> float:
	## Signed distance to the site core (negative inside).
	return sdf_of(s, xz)


func site_target(s: Dictionary, xz: Vector2) -> float:
	return target_of(s, xz, params)


func cottage_site(index: int) -> Dictionary:
	for s: Dictionary in sites:
		if s["kind"] == "cottage" and int(s["index"]) == index:
			return s
	return {}


# ── Sampling ──────────────────────────────────────────────────────────────────

func far_ridges(xz: Vector2) -> float:
	## Rg: the north-wedge ridge core, gated in over far_ridge_start_m → far_ridge_full_m.
	if not _rg_on:
		return 0.0
	var r := xz.distance_to(_g)
	if r <= _rg_start:
		return 0.0
	var gate := VillageLandform.smooth01((r - _rg_start) / (_rg_full - _rg_start))
	var w := HillsHeightfield.azimuth_weight(xz, _g, hills_params)
	if w <= 0.0:
		return 0.0
	return HillsHeightfield.ridge_core(xz, r, layout, hills_params, _hills_seed) * w * gate


func sample_unfit_y(xz: Vector2) -> float:
	## cap_sun(L + D + Rg).
	if flat:
		return 0.0
	var f := VillageLandform.raw_y(xz, ctx) + far_ridges(xz)
	return VillageLandform.cap_sun(f, xz, ctx, sun_az)


func sample_y(xz: Vector2) -> float:
	## fit(cap_sun(L + D + Rg)); the fit chain is C1 (fer weights), last site wins.
	if flat:
		return 0.0
	var f := sample_unfit_y(xz)
	for s: Dictionary in sites:
		var br: float = s["bound_r"]
		if xz.distance_squared_to(s["bound_c"]) > br * br:
			continue
		var w := VillageLandform.fer(site_sdf(s, xz), 0.0, float(s["w"]))
		if w <= 0.0:
			continue
		f = lerpf(f, site_target(s, xz), w)
	return f


func sample_normal(xz: Vector2, eps: float = 0.35) -> Vector3:
	var dx := (sample_y(xz + Vector2(eps, 0.0)) - sample_y(xz - Vector2(eps, 0.0))) / maxf(2.0 * eps, 0.01)
	var dz := (sample_y(xz + Vector2(0.0, eps)) - sample_y(xz - Vector2(0.0, eps))) / maxf(2.0 * eps, 0.01)
	if not is_finite(dx) or not is_finite(dz):
		return Vector3.UP
	return Vector3(-dx, 1.0, -dz).normalized()


func sample_slope_deg(xz: Vector2, eps: float = 0.4) -> float:
	var dx := (sample_y(xz + Vector2(eps, 0.0)) - sample_y(xz - Vector2(eps, 0.0))) / maxf(2.0 * eps, 0.01)
	var dz := (sample_y(xz + Vector2(0.0, eps)) - sample_y(xz - Vector2(0.0, eps))) / maxf(2.0 * eps, 0.01)
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


## Open-land band beyond a site's ring (SD-20 restated: the eps 0.4 slope stencil stays outside
## every blend).
const PATH_ZONE_BAND_M := 0.4


func max_path_slope(p_layout: VillageLayout = null) -> Dictionary:
	## AC-LT-PATH on the field (readout / tests): {deg = open-land max, at, n_open, zone_deg,
	## door_exempt_deg (= zone_deg, kept for old readers)}; sample_slope_deg (eps 0.4) everywhere.
	var lay := p_layout if p_layout != null else layout
	if flat:
		return {"deg": 0.0, "at": Vector2.ZERO, "n_open": 0, "zone_deg": 0.0, "door_exempt_deg": 0.0}
	var fn := Callable(self, "sample_slope_deg")
	var out := path_scan(lay, params, sites, fn, fn)
	out["door_exempt_deg"] = out["zone_deg"]
	return out


static func path_scan(lay: VillageLayout, p: VillageTerrainParams, zone_sites: Array,
		open_slope_fn: Callable, zone_slope_fn: Callable = Callable()) -> Dictionary:
	## SD-VILLAGE-TERRAIN-20 (restated ivy-82zn.14.23), one classification for the generator and
	## the field: ≤ 1 m samples on every polyline (door connectors included). A sample is in the fit
	## zone when it is within door_approach_m of a door, or sdf_j < w_j + 0.4 for any site j
	## (bounding-circle pre-test); otherwise open land, read with open_slope_fn. Zone samples are
	## read only if zone_slope_fn is given. {deg, at, n_open, zone_deg}.
	var out := {"deg": 0.0, "at": Vector2.ZERO, "n_open": 0, "zone_deg": 0.0}
	var doors: Array[Vector2] = []
	for spec: Dictionary in lay.cottages:
		doors.append(VillageBackdrop.cottage_door(spec)[0])
	var door2 := p.door_approach_m * p.door_approach_m
	var band := PATH_ZONE_BAND_M
	var has_zone_fn := zone_slope_fn.is_valid()
	for poly: Variant in lay.path_polylines():
		var pts: Array = poly as Array
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := maxi(1, ceili(a.distance_to(b)))
			for k in range(n + 1):
				var q := a.lerp(b, float(k) / float(n))
				var zone := false
				for d: Vector2 in doors:
					if q.distance_squared_to(d) <= door2:
						zone = true
						break
				if not zone:
					for s: Dictionary in zone_sites:
						var br: float = float(s["bound_r"]) + band
						if q.distance_squared_to(s["bound_c"]) > br * br:
							continue
						if sdf_of(s, q) < float(s["w"]) + band:
							zone = true
							break
				if zone:
					if has_zone_fn:
						out["zone_deg"] = maxf(float(out["zone_deg"]), float(zone_slope_fn.call(q)))
					continue
				out["n_open"] = int(out["n_open"]) + 1
				var sl := float(open_slope_fn.call(q))
				if sl > float(out["deg"]):
					out["deg"] = sl
					out["at"] = q
	return out


func pond_outline_min_y() -> float:
	return _outline_min


func _pond_outline_min() -> float:
	if not layout.pond_placed:
		return INF
	var lo := INF
	for xz in VillagePondShape.at(layout.pond_center).bank_outer_outline_world_xz():
		lo = minf(lo, sample_y(xz))
	return lo


func note_mesh_min(y: float, which: String) -> void:
	## Record the lowest vertex of a built mesh: which = MESH_LAWN or MESH_FAR.
	if which == MESH_LAWN:
		lawn_min_y = y if is_nan(lawn_min_y) else minf(lawn_min_y, y)
	else:
		far_min_y = y if is_nan(far_min_y) else minf(far_min_y, y)
	mesh_min_y = y if is_nan(mesh_min_y) else minf(mesh_min_y, y)


func terrain_min_y() -> float:
	## Lowest vertex of the lawn + far meshes once both are built; until then the coarse polar scan
	## (min'd with any mesh already built), so World/Ground never sits above an unbuilt far valley
	## (ivy-82zn.14.21 F6).
	if flat:
		return 0.0
	if not is_nan(lawn_min_y) and not is_nan(far_min_y):
		return minf(lawn_min_y, far_min_y)
	var lo := mesh_min_y if not is_nan(mesh_min_y) else INF
	var r_out := hills_params.r_outer_m
	for k in range(41):
		var r := r_out * float(k) / 40.0
		for i in range(96):
			var a := TAU * float(i) / 96.0
			lo = minf(lo, sample_y(_g + Vector2(cos(a), sin(a)) * r))
	return lo
