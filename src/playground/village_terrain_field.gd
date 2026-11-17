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
var mesh_min_y := NAN
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
	var norm := layout.generation_seed if layout.generation_seed > 0 else params.layout_seed
	if layout.landform.is_empty():
		# Layouts built without generate(seed, params) (hand-built in tests / probes): search here.
		var best: Dictionary = VillageLandform.rank_offsets(norm, params)[0]
		layout.landform = {
			"index": best["index"], "offset": best["offset"], "rot_deg": best["rot_deg"], "rank": 0,
			"measures": best["measures"], "fallback": not bool(best["pass"]),
		}
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

func _build_sites() -> void:
	sites.clear()
	var unfit := Callable(self, "sample_unfit_y")
	# Plaza: least-squares plane of the capped field (2 m grid), tilt scaled to ≤ plaza_max_tilt.
	if layout.plaza_rect.has_area():
		var rect := layout.plaza_rect
		var pl := VillageLandform.site_plane_fn(unfit, rect, 2.0)
		var a := float(pl["a"])
		var b := float(pl["b"])
		var raw_tilt := float(pl["slope_deg"])
		var tilt := raw_tilt
		if raw_tilt > params.plaza_max_tilt_deg and raw_tilt > 1e-6:
			var k := tan(deg_to_rad(params.plaza_max_tilt_deg)) / tan(deg_to_rad(raw_tilt))
			a *= k
			b *= k
			tilt = params.plaza_max_tilt_deg
		var ctr := rect.get_center()
		# Plane through the fitted mean at the rect centre (the 2 m grid is symmetric about it).
		var c := float(pl["mean"]) - a * ctr.x - b * ctr.y
		if raw_tilt > VillageLandform.PLAZA_RAW_TILT_MAX_DEG:
			diag["plaza_steep"] = true
		sites.append({
			"kind": "plaza", "rect": rect, "a": a, "b": b, "c": c, "w": params.plaza_ring_m,
			"tilt_deg": tilt, "raw_tilt_deg": raw_tilt,
			"bound_c": ctr, "bound_r": rect.size.length() * 0.5 + params.plaza_ring_m,
		})
	# Pond: water level from the lowest bank point (SD-19, AR-LF-GAP-7).
	if layout.pond_placed:
		var pc := layout.pond_center
		var lo := INF
		for i in range(POND_BANK_SAMPLES):
			var ang := TAU * float(i) / float(POND_BANK_SAMPLES)
			lo = minf(lo, sample_unfit_y(pc + Vector2(cos(ang), sin(ang)) * VillagePondSite.BANK_OUTER_M))
		pond_bank_y = lo
		var r_core := VillagePondSite.MEAN_WATER_RADIUS_M * params.pond_floor_scale
		var r_outer := VillagePondSite.BANK_OUTER_M + params.pond_rim_extra_m + params.pond_skirt_m
		var site_pl := VillageLandform.disc_plane(unfit, pc, VillagePondSite.BANK_OUTER_M, 1.0)
		sites.append({
			"kind": "pond", "centre": pc, "r_c": r_core, "w": maxf(r_outer - r_core, 0.01),
			"level": lo, "s_deg": site_pl["slope_deg"], "bound_c": pc, "bound_r": r_outer,
		})
	# Cottage pads (layout order): mean of the capped field over the grown exterior rect.
	for i in range(layout.cottages.size()):
		var spec: Dictionary = layout.cottages[i]
		var core := VillageBackdrop.cottage_exterior_rect(spec).grow(params.pad_margin_m)
		var r_c := core.size.length() * 0.5
		var pl := VillageLandform.site_plane_fn(unfit, core, 1.0)
		var ring := VillageLandform.ring_width(r_c, float(pl["slope_deg"]), params.ring_max_slope_deg,
			params.pad_ring_min_m, params.pad_ring_max_m)
		sites.append({
			"kind": "cottage", "index": i, "rect": core, "r_c": r_c, "s_deg": pl["slope_deg"],
			"target": pl["mean"], "w": ring["w"], "ring_ok": ring["ok"],
			"bound_c": core.get_center(), "bound_r": r_c + float(ring["w"]),
		})
	# Hero (highest priority): mean of raw L + D over the core, ring by formula.
	var hring := VillageLandform.ring_width(params.hero_flat_r_m, s_hero, params.ring_max_slope_deg,
		params.hero_ring_min_m, params.hero_ring_max_m)
	sites.append({
		"kind": "hero", "centre": VillageLayout.HERO_DOOR_STOOP, "r_c": params.hero_flat_r_m,
		"s_deg": s_hero, "target": y_hero, "w": hring["w"], "ring_ok": hring["ok"],
		"bound_c": VillageLayout.HERO_DOOR_STOOP, "bound_r": params.hero_flat_r_m + float(hring["w"]),
	})


func site_sdf(s: Dictionary, xz: Vector2) -> float:
	## Signed distance to the site core (negative inside).
	if s.has("rect"):
		return VillageTerrain.rect_sdf(xz, s["rect"])
	return xz.distance_to(s["centre"]) - float(s["r_c"])


func site_target(s: Dictionary, xz: Vector2) -> float:
	match String(s["kind"]):
		"plaza":
			return float(s["a"]) * xz.x + float(s["b"]) * xz.y + float(s["c"])
		"pond":
			var d := xz.distance_to(s["centre"])
			var bank := VillagePondSite.BANK_OUTER_M
			var sigma := maxf(params.pond_lip_sigma_m, 0.01)
			var basin := params.pond_depth_m * (1.0 - VillageLandform.smooth01(d / bank))
			var lip := params.pond_lip_rise_m * exp(-((d - bank) * (d - bank)) / (2.0 * sigma * sigma))
			return float(s["level"]) + basin + lip
	return float(s["target"])


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


func max_path_slope(p_layout: VillageLayout = null) -> Dictionary:
	## Steepest sample_slope_deg along every path polyline at ≤ 1 m steps (SD-20 metric), split
	## into open path and the door-approach zone. {deg, at, door_exempt_deg}.
	var lay := p_layout if p_layout != null else layout
	var out := {"deg": 0.0, "at": Vector2.ZERO, "door_exempt_deg": 0.0}
	if flat:
		return out
	var doors: Array[Vector2] = []
	for spec: Dictionary in lay.cottages:
		doors.append(VillageBackdrop.cottage_door(spec)[0])
	for poly: Variant in lay.path_polylines():
		var pts: Array = poly as Array
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := maxi(1, ceili(a.distance_to(b)))
			for k in range(n + 1):
				var p := a.lerp(b, float(k) / float(n))
				var s := sample_slope_deg(p)
				var near_door := false
				for d: Vector2 in doors:
					if p.distance_to(d) <= params.door_approach_m:
						near_door = true
						break
				if near_door:
					out["door_exempt_deg"] = maxf(float(out["door_exempt_deg"]), s)
				elif s > float(out["deg"]):
					out["deg"] = s
					out["at"] = p
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


func note_mesh_min(y: float) -> void:
	mesh_min_y = y if is_nan(mesh_min_y) else minf(mesh_min_y, y)


func terrain_min_y() -> float:
	## Lowest built-mesh vertex; a coarse polar scan when no mesh has been built yet.
	if flat:
		return 0.0
	if not is_nan(mesh_min_y):
		return mesh_min_y
	var lo := INF
	var r_out := hills_params.r_outer_m
	for k in range(41):
		var r := r_out * float(k) / 40.0
		for i in range(96):
			var a := TAU * float(i) / 96.0
			lo = minf(lo, sample_y(_g + Vector2(cos(a), sin(a)) * r))
	return lo
