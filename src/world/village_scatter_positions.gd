class_name VillageScatterPositions
extends RefCounted

## Deterministic backdrop scatter transforms (Knuth LCG). Shared by VillageBackdrop
## MultiMesh setup and FaunaEnvironment export (SD-FAUNA-2).

const FLOWER_CLUSTER_PIECES: Array[String] = [
	"Flower_3_Group",
	"Flower_3_Single",
	"Flower_4_Group",
	"Flower_4_Single",
]

const PETAL_PIECES: Array[String] = [
	"Petal_1",
	"Petal_2",
	"Petal_3",
	"Petal_4",
	"Petal_5",
]

const PLANT_PIECES: Array[String] = [
	"Plant_7",
	"Plant_7_Big",
]

const CLOVER_PIECES: Array[String] = [
	"Clover_1",
	"Clover_2",
]

## Village pond metrics — sourced from VillagePondSite (ivy-86l placement).
const POND_WATER_RADIUS_M := VillagePondSite.MEAN_WATER_RADIUS_M
const POND_BANK_OUTER_M := VillagePondSite.BANK_OUTER_M
const POND_GRASS_CLEARANCE_M := VillagePondSite.SCATTER_CLEARANCE_M
const CLOVER_LCG_SEED := 8601
## Three jittered clover bands on the bank (inner → outer); outer band fades to lawn grass.
const CLOVER_RING_ALONG := [0.24, 0.46, 0.68]
const CLOVER_RING_SPACING_M := [0.40, 0.54, 0.72]
const CLOVER_RING_PLACE_CHANCE := [1.0, 0.85, 0.52]
const CLOVER_ARC_JITTER_M := 0.17
const CLOVER_RADIAL_JITTER_M := 0.11
const CLOVER_MIN_INSTANCES := 18

# SD-GRASS-2 blade tuft lawn + wispy accents (SD-GRASS-1 card tier superseded).
const GRASS_LCG_SEED := 42007
const GRASS_ACCENT_LCG_SEED := 42042
const GRASS_RING_INNER_M := 4.5
## Sparse short tufts inward of the hero lawn ring; no dynamic hero footprint in ctx.
const GRASS_HERO_FRINGE_INNER_M := 4.0
const GRASS_HERO_FOOTPRINT_R := 4.0
const GRASS_HERO_DENSITY_OUTER_M := 6.0
const GRASS_HERO_INNER_NOISE_M := 0.4
const GRASS_HERO_KEEP_MIN := 0.15
const GRASS_FULL_DENSITY_OUTER_M := 12.0
## Legacy hero-band outer (accents); radial fill uses GRASS_RADIAL_EDGE_* (ivy-k9r0).
const GRASS_RING_OUTER_M := 14.5
const GRASS_DENSITY_CORE_PER_M2 := 40.0
const GRASS_DENSITY_EDGE_PER_M2 := 15.0
const GRASS_DENSITY_FLAT_FRACTION := 0.7
## Playground / prod alias (uniform lawn uses core density).
const GRASS_DENSITY_PER_M2 := GRASS_DENSITY_CORE_PER_M2
const GRASS_GRID_STEP_M := 1.0 / sqrt(GRASS_DENSITY_CORE_PER_M2)
## Generated lawn plants this fraction of the classic density at every radius; at 1.0 its
## ~280k tufts (~8M tris, no distance cull) dominated frame time.
const GRASS_GENERATED_DENSITY_SCALE := 0.5
const GRASS_GRID_STEP_GENERATED_M := GRASS_GRID_STEP_M / sqrt(GRASS_GENERATED_DENSITY_SCALE)
const GRASS_GRID_STEP_GENERATED_FILL_M := GRASS_GRID_STEP_GENERATED_M
## Grass disk meets the inner pine ring (VillageLayout.pine_inner classic default).
const GRASS_RADIAL_EDGE_CLASSIC_M := 19.0
## Generated grass fills to the lawn disc before the forest collar (56 m).
const GRASS_RADIAL_EDGE_GENERATED_M := VillageLayout.GENERATED_LAWN_RADIUS
## Headroom ~15% over π·r_edge²·core (ivy-k9r0); must not truncate outer spiral.
const GRASS_MAX_INSTANCES := int(roundi(PI * GRASS_RADIAL_EDGE_CLASSIC_M * GRASS_RADIAL_EDGE_CLASSIC_M \
	* GRASS_DENSITY_CORE_PER_M2 * 1.15))
const GRASS_MAX_INSTANCES_GENERATED := int(roundi(PI \
	* GRASS_RADIAL_EDGE_GENERATED_M * GRASS_RADIAL_EDGE_GENERATED_M \
	* GRASS_DENSITY_CORE_PER_M2 * GRASS_GENERATED_DENSITY_SCALE * 1.15))
const GRASS_PATCH_CELL_M := 2.5
const GRASS_ANCHOR_HASH_CELL_M := 1.0
const GRASS_ACCENT_COUNT := 48
const GRASS_ACCENT_INNER_M := 6.0
const GRASS_ACCENT_OUTER_M := 11.5
const COTTAGE_MARGIN := 0.35
const PATH_CLEARANCE_M := 0.55
const PLANT_CLEARANCE_M := 0.45
const PATH_SPATIAL_CELL_M := 2.0
const GRASS_FORBIDDEN_CELL_M := 0.5
## Set true to accumulate stage timings in grass_profile_last_usec (headless profiling).
const GRASS_PROFILE := false
static var grass_profile_last_usec: Dictionary = {}
static var _grass_blocks_pond_center: Vector2 = Vector2(1e9, 1e9)
static var _grass_blocks_pond_far_sq: float = 0.0
static var _grass_pond_exclusion_rect: Rect2 = Rect2()
static var _grass_pond_water_rect: Rect2 = Rect2()
static var _grass_patch_noise_grid: Dictionary = {}
static var _grass_path_influence_rect: Rect2 = Rect2()
static var _grass_anchor_cache_sig: int = -1
static var _grass_anchor_cache: Array[Vector2] = []
const GRASS_GENERATED_FILL_CAP := GRASS_MAX_INSTANCES_GENERATED
## Per-blade shader dissolve (grass_blade.gdshader); ivy-k9r0 camera ring, ivy-j68r anchor.
const GRASS_BLADE_CHUNK_M := 6.0
const GRASS_BLADE_CHUNK_HALF_DIAGONAL_M := 3.0 * 1.4142135623730951
## Legacy names kept for FPS sweep tooling; shader measures distance from anchor_xz when active.
const GRASS_CAMERA_DISSOLVE_START_M := 14.0
const GRASS_CAMERA_DISSOLVE_END_DEFAULT_M := 30.0
const GRASS_CAMERA_DISSOLVE_END_GENERATED_M := GRASS_CAMERA_DISSOLVE_END_DEFAULT_M
const GRASS_CAMERA_DISSOLVE_END_CLASSIC_M := 131072.0
## If dissolve_active=1: fade band just outside placement ring (r_edge from plaza G).
const GRASS_ANCHOR_DISSOLVE_START_M := GRASS_RADIAL_EDGE_GENERATED_M - 4.0
const GRASS_ANCHOR_DISSOLVE_END_M := GRASS_RADIAL_EDGE_GENERATED_M + 2.0


static func grass_chunk_visibility_end_m(dissolve_end_m: float) -> float:
	return dissolve_end_m + GRASS_BLADE_CHUNK_HALF_DIAGONAL_M


## Mirrors grass_blade.gdshader v_keep when dissolve_active; anchor is world-space plaza XZ.
static func grass_blade_dissolve_keep(
		root_xz: Vector2,
		anchor_xz: Vector2,
		dissolve_start: float,
		dissolve_end: float,
		dissolve_active: float) -> float:
	if dissolve_active <= 0.5:
		return 1.0
	var d := root_xz.distance_to(anchor_xz)
	return 1.0 - smoothstep(dissolve_start, dissolve_end, d)

const _GRASS_PATCH_SAMPLE_RADIUS_M := 1.5
const _GRASS_PATCH_EXCLUSION_CLEARANCE_M := 3.0


static func grass_radial_edge_m(ctx: VillageGrassExclusionContext) -> float:
	return GRASS_RADIAL_EDGE_GENERATED_M if ctx.generated_grass else GRASS_RADIAL_EDGE_CLASSIC_M


static func grass_radial_flat_m(r_edge: float) -> float:
	return GRASS_DENSITY_FLAT_FRACTION * r_edge


static func grass_target_density_m2(r: float, r_edge: float) -> float:
	var r_flat := grass_radial_flat_m(r_edge)
	if r <= r_flat:
		return GRASS_DENSITY_CORE_PER_M2
	if r >= r_edge:
		return GRASS_DENSITY_EDGE_PER_M2
	var t := (r - r_flat) / (r_edge - r_flat)
	t = clampf(t, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(GRASS_DENSITY_CORE_PER_M2, GRASS_DENSITY_EDGE_PER_M2, t)


static func grass_target_density_slope_at_flat(r_edge: float) -> float:
	var eps := 0.001
	return (grass_target_density_m2(grass_radial_flat_m(r_edge) + eps, r_edge) \
			- grass_target_density_m2(grass_radial_flat_m(r_edge), r_edge)) / eps


static func _grass_cell_u01(ix: int, iy: int, channel: int) -> float:
	var p := Vector2(float(ix) * 0.161803 + float(channel) * 2.71, float(iy) * 0.161803 + float(channel) * 5.23)
	return _hash21(p)


static func _grass_world_u01(world_p: Vector2, channel: int) -> float:
	var q := world_p + Vector2(float(channel) * 0.173, float(channel) * 0.291)
	return _hash21(q * 0.318309)


static func grass_radial_keep_p(r_g: float, r_edge: float) -> float:
	return grass_target_density_m2(r_g, r_edge) / GRASS_DENSITY_CORE_PER_M2


static func lcg_step(state: int) -> int:
	return (state * 1664525 + 1013904223) & 0x7FFFFFFF


static func lcg_f01(state: int) -> float:
	return float(state & 0x7FFFFFFF) / float(0x7FFFFFFF)


## ~45 plain-green bushes (Bush_Common). Same LCG layout as former VillageBackdrop private.
## [param cottages] defaults to VillageBackdrop.COTTAGES for byte-identical classic output.
## Generated layouts pass _layout.cottages to obtain per-layout collision rejection.
## [param bush_filler_inner] / [param bush_filler_outer] control the 10-bush filler ring radius
## (classic defaults 8.0 / 15.0; generated uses 8.0 / 22.0 — SD-VILLAGE-GEN-6).
static func bush_common_positions(
		cottages: Array = [],
		bush_filler_inner: float = 8.0,
		bush_filler_outer: float = 15.0,
		filler_centre_xz: Vector2 = Vector2.ZERO) -> Array[Transform3D]:
	# Resolve default: empty sentinel → use the authored classic COTTAGES.
	if cottages.is_empty():
		cottages = VillageBackdrop.COTTAGES
	var out: Array[Transform3D] = []
	var st := 1234
	for spec in cottages:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(0.8)
		var door: Vector2 = VillageBackdrop.cottage_door(spec)[0]
		var corners: Array[Vector2] = [
			rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y)]
		var count := 6
		st = lcg_step(st); count += (st & 1)  # 6 or 7
		for _j in range(count):
			st = lcg_step(st); var edge: int = int(lcg_f01(st) * 4.0) % 4
			st = lcg_step(st); var t: float = lcg_f01(st)
			var p: Vector2 = corners[edge].lerp(corners[(edge + 1) % 4], t)
			if p.distance_to(door) < 1.6 or p.length() < 5.0:
				continue
			if VillageLayout.inside_cottages(cottages, p, 0.3):
				continue
			if blocks_scatter_at(p):
				continue
			var cx: float = p.x
			var cz: float = p.y
			st = lcg_step(st); var s: float = lerpf(0.55, 0.80, lcg_f01(st))
			st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
			var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
			out.append(Transform3D(basis, Vector3(cx, 0.0, cz)))
	var st2 := 5678
	var placed_extra := 0
	while placed_extra < 10:
		st2 = lcg_step(st2); var angle: float = lcg_f01(st2) * TAU
		st2 = lcg_step(st2); var r: float = lerpf(bush_filler_inner, bush_filler_outer, lcg_f01(st2))
		var cx2: float = filler_centre_xz.x + cos(angle) * r
		var cz2: float = filler_centre_xz.y + sin(angle) * r
		if Vector2(cx2, cz2).distance_to(filler_centre_xz) < 5.0 \
				or VillageLayout.inside_cottages(cottages, Vector2(cx2, cz2), 1.0):
			continue
		if blocks_scatter_at(Vector2(cx2, cz2)):
			continue
		st2 = lcg_step(st2); var s2: float = lerpf(0.55, 0.80, lcg_f01(st2))
		st2 = lcg_step(st2); var rot2: float = lcg_f01(st2) * TAU
		var basis2 := Basis.from_euler(Vector3(0.0, rot2, 0.0)).scaled(Vector3(s2, s2, s2))
		out.append(Transform3D(basis2, Vector3(cx2, 0.0, cz2)))
		placed_extra += 1
	return out


static func _forest_placement_script() -> Script:
	return load("res://src/playground/forest_placement.gd") as Script


static func _forest_production_params() -> Resource:
	return (load("res://src/playground/forest_params.gd") as Script).call("production")


## Classic horizon ring at layout origin (INV-15 bit-identical).
static func classic_pine_ring_positions(layout: VillageLayout) -> Array[Transform3D]:
	return _forest_placement_script().call(
		"forest_tree_positions", layout, _forest_production_params())


static func forest_tree_xz(layout: VillageLayout) -> Array[Vector2]:
	return _forest_placement_script().call(
		"forest_tree_xz", layout, _forest_production_params())


## Generated: dense +Z wedge + G-centred collar; classic: pivot annulus (ivy-3l6-C).
static func forest_tree_positions(layout: VillageLayout) -> Array[Transform3D]:
	return _forest_placement_script().call(
		"forest_tree_positions", layout, _forest_production_params())


## True when a trunk at [param p] would sit in the CamSun → village sight corridor (tests + placement).
static func forest_blocks_camsun_view(p: Vector2) -> bool:
	return _forest_placement_script().call(
		"forest_blocks_camsun_view", p, _forest_production_params())


## Dense blade tuft instances (SD-GRASS-2).
static func grass_blade_positions(ctx: VillageGrassExclusionContext) -> Array[Transform3D]:
	return _grass_blade_grid_positions(ctx)


## Sparse Grass_Wispy_Short accents in the garden band (not a full carpet).
static func grass_wispy_accent_positions(ctx: VillageGrassExclusionContext) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var anchors := collect_scatter_anchor_xz(ctx)
	var st := GRASS_ACCENT_LCG_SEED
	var attempts := 0
	while out.size() < GRASS_ACCENT_COUNT and attempts < GRASS_ACCENT_COUNT * 40:
		attempts += 1
		st = lcg_step(st); var angle: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r: float = lerpf(GRASS_ACCENT_INNER_M, GRASS_ACCENT_OUTER_M, lcg_f01(st))
		var p := Vector2(cos(angle) * r, sin(angle) * r)
		if not _grass_cell_accepted(p, ctx, anchors, GRASS_ACCENT_INNER_M, GRASS_ACCENT_OUTER_M):
			continue
		st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
		st = lcg_step(st); var s: float = lerpf(0.18, 0.24, lcg_f01(st))
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))
	return out


static func grass_positions(ctx: VillageGrassExclusionContext) -> Array[Transform3D]:
	return grass_blade_positions(ctx)


static func _grass_blade_grid_positions(ctx: VillageGrassExclusionContext) -> Array[Transform3D]:
	_grass_exclusion_session_begin(ctx)
	if GRASS_PROFILE:
		grass_profile_last_usec = {
			"setup": 0, "loop": 0, "path_setup": 0, "anchors": 0, "trim": 0}
	var t_setup := Time.get_ticks_usec() if GRASS_PROFILE else 0
	var grid_out := _grass_blade_grid_fill(ctx)
	if GRASS_PROFILE:
		grass_profile_last_usec["setup"] = Time.get_ticks_usec() - t_setup
	_grass_exclusion_session_end()
	return grid_out


static func _grass_blade_grid_fill(ctx: VillageGrassExclusionContext) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var t_anchors := Time.get_ticks_usec() if GRASS_PROFILE else 0
	var anchors := _grass_scatter_anchors_cached(ctx)
	if GRASS_PROFILE:
		grass_profile_last_usec["anchors"] = Time.get_ticks_usec() - t_anchors
	var anchor_hash := _build_anchor_spatial_hash(anchors, GRASS_ANCHOR_HASH_CELL_M)
	var t_path := Time.get_ticks_usec() if GRASS_PROFILE else 0
	var path_records := _path_segment_clearance_records(ctx.path_segments)
	var path_hash := _build_path_spatial_hash(path_records, PATH_SPATIAL_CELL_M)
	_grass_path_influence_rect = _path_clearance_influence_rect(path_records)
	if GRASS_PROFILE:
		grass_profile_last_usec["path_setup"] = Time.get_ticks_usec() - t_path
	var grid_step := GRASS_GRID_STEP_M if not ctx.generated_grass else GRASS_GRID_STEP_GENERATED_FILL_M
	var ring_outer := grass_radial_edge_m(ctx)
	var grass_cap := GRASS_MAX_INSTANCES_GENERATED if ctx.generated_grass else GRASS_MAX_INSTANCES
	if ctx.generated_grass:
		grass_cap = mini(grass_cap, GRASS_GENERATED_FILL_CAP)
	var g := ctx.grid_centre_xz if ctx.generated_grass else Vector2.ZERO
	var hero_ref := ctx.hero_reference_xz if ctx.generated_grass else Vector2.ZERO
	var t_forbid := Time.get_ticks_usec() if GRASS_PROFILE else 0
	var forbidden := _build_grass_forbidden_coarse(
		ctx, g, hero_ref, ring_outer, grid_step, path_records, path_hash, anchor_hash)
	if GRASS_PROFILE:
		grass_profile_last_usec["forbidden"] = Time.get_ticks_usec() - t_forbid
	var trust_forbidden := not forbidden.is_empty()
	var half := ring_outer + grid_step
	var n_cells := int(ceil((2.0 * half) / grid_step))
	var t_loop := Time.get_ticks_usec() if GRASS_PROFILE else 0
	for iy in range(n_cells):
		if out.size() >= grass_cap:
			break
		for ix in range(n_cells):
			if out.size() >= grass_cap:
				break
			_grass_blade_try_grid_ixiy(
				ctx, out, ix, iy, n_cells, g, half, grid_step,
				hero_ref, ring_outer, grass_cap, path_records, path_hash, anchor_hash,
				forbidden, trust_forbidden)
	if GRASS_PROFILE:
		grass_profile_last_usec["loop"] = Time.get_ticks_usec() - t_loop
	var t_trim := Time.get_ticks_usec() if GRASS_PROFILE else 0
	var trim_origin := g if ctx.generated_grass else hero_ref
	trim_grass_instances_to_cap(out, grass_cap, trim_origin)
	if GRASS_PROFILE:
		grass_profile_last_usec["trim"] = Time.get_ticks_usec() - t_trim
		_grass_profile_print("classic_grid" if not ctx.generated_grass else "generated_grid")
	return out


static func _build_grass_forbidden_coarse(
		ctx: VillageGrassExclusionContext,
		g: Vector2,
		hero_ref: Vector2,
		_ring_outer: float,
		grid_step: float,
		path_records: Array,
		_path_hash: Dictionary,
		anchor_hash: Dictionary) -> Dictionary:
	var cell := GRASS_FORBIDDEN_CELL_M
	var jitter_slack := grid_step * 0.75
	var anchor_clear := PLANT_CLEARANCE_M + jitter_slack
	var out: Dictionary = {}
	_forbidden_stamp_disk(out, hero_ref, GRASS_HERO_FOOTPRINT_R + jitter_slack, cell)
	var path_pad := jitter_slack + GRASS_FORBIDDEN_CELL_M * 0.866
	for rec in path_records:
		var rect: Rect2 = rec["rect"]
		_forbidden_stamp_rect(out, rect.grow(path_pad), cell)
	if not ctx.cottage_exclusion_rects.is_empty():
		for rect in ctx.cottage_exclusion_rects:
			_forbidden_stamp_rect(out, rect, cell)
	elif ctx.is_inside_cottage.is_valid():
		for spec in VillageBackdrop.COTTAGES:
			_forbidden_stamp_rect(
				out, VillageBackdrop.cottage_exterior_rect(spec).grow(COTTAGE_MARGIN), cell)
	_forbidden_stamp_rect(out, _grass_pond_water_rect.grow(POND_GRASS_CLEARANCE_M), cell)
	if not ctx.generated_grass:
		_forbidden_stamp_pond_bank(out, cell)
	for key in anchor_hash.keys():
		for a in anchor_hash[key] as Array[Vector2]:
			_forbidden_stamp_disk(out, a, anchor_clear, cell)
	return out


static func _forbidden_stamp_rect(out: Dictionary, rect: Rect2, cell_m: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var ix0 := int(floor(rect.position.x / cell_m))
	var ix1 := int(floor((rect.position.x + rect.size.x) / cell_m))
	var iy0 := int(floor(rect.position.y / cell_m))
	var iy1 := int(floor((rect.position.y + rect.size.y) / cell_m))
	for ix in range(ix0, ix1 + 1):
		for iy in range(iy0, iy1 + 1):
			out[Vector2i(ix, iy)] = true


static func _forbidden_stamp_disk(
		out: Dictionary, centre: Vector2, radius: float, cell_m: float) -> void:
	if radius <= 0.0:
		return
	var rect := Rect2(centre.x - radius, centre.y - radius, radius * 2.0, radius * 2.0)
	var r_sq := radius * radius
	var ix0 := int(floor(rect.position.x / cell_m))
	var ix1 := int(floor((rect.position.x + rect.size.x) / cell_m))
	var iy0 := int(floor(rect.position.y / cell_m))
	var iy1 := int(floor((rect.position.y + rect.size.y) / cell_m))
	for ix in range(ix0, ix1 + 1):
		for iy in range(iy0, iy1 + 1):
			var p := Vector2((float(ix) + 0.5) * cell_m, (float(iy) + 0.5) * cell_m)
			if p.distance_squared_to(centre) <= r_sq:
				out[Vector2i(ix, iy)] = true


static func _forbidden_stamp_pond_bank(out: Dictionary, cell_m: float) -> void:
	var rect := _grass_pond_exclusion_rect
	if rect.size.x <= 0.0:
		return
	var c := _grass_blocks_pond_center
	var far_sq := _grass_blocks_pond_far_sq
	var ix0 := int(floor(rect.position.x / cell_m))
	var ix1 := int(floor((rect.position.x + rect.size.x) / cell_m))
	var iy0 := int(floor(rect.position.y / cell_m))
	var iy1 := int(floor((rect.position.y + rect.size.y) / cell_m))
	for ix in range(ix0, ix1 + 1):
		for iy in range(iy0, iy1 + 1):
			var p := Vector2((float(ix) + 0.5) * cell_m, (float(iy) + 0.5) * cell_m)
			if p.distance_squared_to(c) > far_sq:
				continue
			if _grass_pond_water_rect.has_point(p):
				continue
			if not rect.has_point(p):
				continue
			if blocks_grass_at(p):
				out[Vector2i(ix, iy)] = true


static func _grass_coarse_forbidden(forbidden: Dictionary, p: Vector2) -> bool:
	if forbidden.is_empty():
		return false
	var cell := GRASS_FORBIDDEN_CELL_M
	return forbidden.has(Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell))))


static func _grass_blade_try_grid_ixiy(
		ctx: VillageGrassExclusionContext,
		out: Array[Transform3D],
		ix: int,
		iy: int,
		n_cells: int,
		g: Vector2,
		half: float,
		grid_step: float,
		hero_ref: Vector2,
		ring_outer: float,
		grass_cap: int,
		path_records: Array,
		path_hash: Dictionary,
		anchor_hash: Dictionary,
		forbidden: Dictionary,
		trust_forbidden: bool) -> void:
	if out.size() >= grass_cap:
		return
	if ix < 0 or iy < 0 or ix >= n_cells or iy >= n_cells:
		return
	var cx := g.x - half + (float(ix) + 0.5) * grid_step
	var cz := g.y - half + (float(iy) + 0.5) * grid_step
	var center := Vector2(cx, cz)
	var r_g_center := center.distance_to(g)
	var r_h_center := center.distance_to(hero_ref)
	if r_g_center > ring_outer:
		return
	if not ctx.generated_grass and r_h_center < GRASS_HERO_FRINGE_INNER_M:
		return
	if _grass_coarse_forbidden(forbidden, center):
		return
	var jx: float = (_grass_cell_u01(ix, iy, 0) - 0.5) * grid_step
	var jz: float = (_grass_cell_u01(ix, iy, 1) - 0.5) * grid_step
	var p := center + Vector2(jx, jz)
	var r_g := p.distance_to(g)
	var r_h := p.distance_to(hero_ref)
	if r_g > ring_outer:
		return
	if not ctx.generated_grass and r_h < GRASS_HERO_FRINGE_INNER_M:
		return
	if r_h < GRASS_HERO_FOOTPRINT_R:
		return
	if trust_forbidden and _grass_coarse_forbidden(forbidden, p):
		return
	if not trust_forbidden:
		if _grass_path_influence_rect.has_point(p):
			if _min_xz_dist_path_spatial(p, path_records, path_hash, PATH_SPATIAL_CELL_M) \
					< PATH_CLEARANCE_M:
				return
	if not trust_forbidden:
		if blocks_grass_at(p):
			return
		if _grass_cottage_blocks(p, ctx):
			return
	var anchor_clear := PLANT_CLEARANCE_M + grid_step * 0.75
	if _anchor_blocks(p, anchor_hash, anchor_clear, GRASS_ANCHOR_HASH_CELL_M):
		return
	var hero_keep := _grass_hero_fringe_keep(r_h, p) if r_h < GRASS_RING_INNER_M \
			else _grass_hero_density_keep(r_h, p)
	if _grass_cell_u01(ix, iy, 2) > hero_keep:
		return
	var radial_p := grass_radial_keep_p(r_g, ring_outer)
	if _grass_cell_u01(ix, iy, 3) > radial_p:
		return
	var rot: float = _grass_cell_u01(ix, iy, 4) * TAU
	var s_rand: float = lerpf(0.8, 1.1, _grass_cell_u01(ix, iy, 5))
	var patch_noise := _grass_patch_noise(p)
	var patch := lerpf(0.8, 1.15, patch_noise)
	var hero := _grass_hero_height_scale(r_h)
	var s: float = s_rand * patch * hero
	if ctx.generated_grass:
		s *= lerpf(1.08, 1.22, patch_noise)
	if not ctx.generated_grass and VillagePondShape.classic()._is_in_water(p, 0.0):
		return
	var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
	out.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))


static func _grass_scatter_anchors_light(ctx: VillageGrassExclusionContext) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for t in ctx.path_stones:
		out.append(Vector2(t.origin.x, t.origin.z))
	for t in ctx.bush_transforms:
		out.append(Vector2(t.origin.x, t.origin.z))
	return out


static func _grass_exclusion_session_begin(ctx: VillageGrassExclusionContext) -> void:
	_grass_blocks_pond_center = pond_center_xz()
	_grass_blocks_pond_far_sq = (POND_BANK_OUTER_M + 2.5) * (POND_BANK_OUTER_M + 2.5)
	_grass_pond_exclusion_rect = _pond_grass_exclusion_rect()
	_grass_pond_water_rect = _pond_water_exclusion_rect()
	_grass_patch_noise_grid.clear()


static func _grass_exclusion_session_end() -> void:
	_grass_blocks_pond_center = Vector2(1e9, 1e9)
	_grass_blocks_pond_far_sq = 0.0
	_grass_pond_exclusion_rect = Rect2()
	_grass_pond_water_rect = Rect2()
	_grass_patch_noise_grid.clear()


static func _prewarm_grass_patch_noise(hero_ref: Vector2, ring_outer: float) -> void:
	var cell := GRASS_PATCH_CELL_M
	var extent := ring_outer + cell * 2.0
	var ix0 := int(floor((hero_ref.x - extent) / cell))
	var ix1 := int(floor((hero_ref.x + extent) / cell))
	var iz0 := int(floor((hero_ref.y - extent) / cell))
	var iz1 := int(floor((hero_ref.y + extent) / cell))
	var r_sq := ring_outer * ring_outer
	for ix in range(ix0, ix1 + 1):
		for iz in range(iz0, iz1 + 1):
			var cx := (float(ix) + 0.5) * cell
			var cz := (float(iz) + 0.5) * cell
			var p := Vector2(cx, cz)
			if p.distance_squared_to(hero_ref) > r_sq + cell * cell * 2.0:
				continue
			_grass_patch_noise_grid[Vector2i(ix, iz)] = _grass_patch_noise(p)


static func _grass_patch_noise_at(p: Vector2) -> float:
	var cell := GRASS_PATCH_CELL_M
	var key := Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))
	if _grass_patch_noise_grid.has(key):
		return _grass_patch_noise_grid[key]
	var v := _grass_patch_noise(p)
	_grass_patch_noise_grid[key] = v
	return v


static func _grass_profile_print(label: String) -> void:
	var u: Dictionary = grass_profile_last_usec
	print(
		"GRASS_PROFILE %s ms: setup=%.2f anchors=%.2f path=%.2f forbid=%.2f loop=%.2f trim=%.2f" % [
			label,
			float(u.get("setup", 0)) / 1000.0,
			float(u.get("anchors", 0)) / 1000.0,
			float(u.get("path_setup", 0)) / 1000.0,
			float(u.get("forbidden", 0)) / 1000.0,
			float(u.get("loop", 0)) / 1000.0,
			float(u.get("trim", 0)) / 1000.0,
		])


static func _grass_cottage_blocks(p: Vector2, ctx: VillageGrassExclusionContext) -> bool:
	if not ctx.cottage_exclusion_rects.is_empty():
		for rect in ctx.cottage_exclusion_rects:
			if rect.has_point(p):
				return true
		return false
	if ctx.is_inside_cottage.is_valid():
		return ctx.is_inside_cottage.call(p)
	return false


static func trim_grass_instances_to_cap(
		out: Array[Transform3D], cap: int, sort_origin_xz: Vector2 = Vector2.ZERO) -> void:
	if out.size() <= cap:
		return
	out.sort_custom(func(a: Transform3D, b: Transform3D) -> bool:
		var ra := Vector2(a.origin.x, a.origin.z).distance_squared_to(sort_origin_xz)
		var rb := Vector2(b.origin.x, b.origin.z).distance_squared_to(sort_origin_xz)
		return ra < rb)
	out.resize(cap)


static func _grass_hero_fringe_keep(r: float, p: Vector2) -> float:
	if r >= GRASS_RING_INNER_M:
		return 1.0
	var inner_eff := GRASS_HERO_FRINGE_INNER_M \
			+ (_grass_patch_noise(p) - 0.5) * (2.0 * GRASS_HERO_INNER_NOISE_M)
	var t := smoothstep(inner_eff, GRASS_RING_INNER_M, r)
	return lerpf(0.0, GRASS_HERO_KEEP_MIN, t)


static func _grass_hero_density_keep(r: float, p: Vector2) -> float:
	if r < GRASS_RING_INNER_M:
		return 1.0
	if r >= GRASS_HERO_DENSITY_OUTER_M:
		return 1.0
	var inner_eff := GRASS_RING_INNER_M \
			+ (_grass_patch_noise(p) - 0.5) * (2.0 * GRASS_HERO_INNER_NOISE_M)
	var t := smoothstep(inner_eff, GRASS_HERO_DENSITY_OUTER_M, r)
	return lerpf(GRASS_HERO_KEEP_MIN, 1.0, t)


static func _grass_hero_height_scale(r: float) -> float:
	if r <= GRASS_HERO_FRINGE_INNER_M:
		return 0.35
	if r <= GRASS_RING_INNER_M:
		return lerpf(0.35, 0.6, (r - GRASS_HERO_FRINGE_INNER_M) \
				/ (GRASS_RING_INNER_M - GRASS_HERO_FRINGE_INNER_M))
	if r >= GRASS_RING_INNER_M + 1.0:
		return 1.0
	return lerpf(0.6, 1.0, (r - GRASS_RING_INNER_M) / 1.0)


static func _grass_fade_height_scale(r: float, ring_outer: float = GRASS_RING_OUTER_M) -> float:
	if r <= GRASS_FULL_DENSITY_OUTER_M:
		return 1.0
	if r >= ring_outer:
		return 0.6
	return lerpf(1.0, 0.6, (r - GRASS_FULL_DENSITY_OUTER_M) \
			/ (ring_outer - GRASS_FULL_DENSITY_OUTER_M))


static func _grass_patch_noise(p: Vector2) -> float:
	var cell := GRASS_PATCH_CELL_M
	var i0 := Vector2(floor(p.x / cell), floor(p.y / cell))
	var f := Vector2(
		(p.x / cell) - i0.x,
		(p.y / cell) - i0.y)
	f.x = f.x * f.x * (3.0 - 2.0 * f.x)
	f.y = f.y * f.y * (3.0 - 2.0 * f.y)
	var a := _hash21(i0)
	var b := _hash21(i0 + Vector2(1.0, 0.0))
	var c := _hash21(i0 + Vector2(0.0, 1.0))
	var d := _hash21(i0 + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


static func _hash21(p: Vector2) -> float:
	var v := sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453
	return v - floor(v)


static func _build_anchor_spatial_hash(anchors: Array[Vector2], cell_m: float) -> Dictionary:
	var grid: Dictionary = {}
	for a in anchors:
		var key := Vector2i(int(floor(a.x / cell_m)), int(floor(a.y / cell_m)))
		if not grid.has(key):
			grid[key] = [] as Array[Vector2]
		(grid[key] as Array[Vector2]).append(a)
	return grid


static func _anchor_blocks(
		p: Vector2, grid: Dictionary, clearance: float, cell_m: float) -> bool:
	var cx := int(floor(p.x / cell_m))
	var cz := int(floor(p.y / cell_m))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var key := Vector2i(cx + dx, cz + dz)
			if not grid.has(key):
				continue
			for a in grid[key] as Array[Vector2]:
				if p.distance_to(a) < clearance - 1e-6:
					return true
	return false


static func min_xz_dist_to_path_segments(p: Vector2, segments: Array) -> float:
	var best := INF
	for seg_raw in segments:
		var seg := seg_raw as Array
		for i in range(seg.size() - 1):
			var a := seg[i] as Vector2
			var b := seg[i + 1] as Vector2
			best = minf(best, _dist_point_to_segment(p, a, b))
	return best


static func _path_clearance_influence_rect(records: Array) -> Rect2:
	if records.is_empty():
		return Rect2(-1e6, -1e6, 2e6, 2e6)
	var merged: Rect2 = records[0]["rect"]
	for i in range(1, records.size()):
		merged = merged.merge(records[i]["rect"])
	return merged


static func _path_segment_clearance_records(segments: Array) -> Array:
	var out: Array = []
	for seg_raw in segments:
		var seg := seg_raw as Array
		for i in range(seg.size() - 1):
			var a := seg[i] as Vector2
			var b := seg[i + 1] as Vector2
			var min_x := minf(a.x, b.x) - PATH_CLEARANCE_M
			var min_y := minf(a.y, b.y) - PATH_CLEARANCE_M
			var max_x := maxf(a.x, b.x) + PATH_CLEARANCE_M
			var max_y := maxf(a.y, b.y) + PATH_CLEARANCE_M
			var rect := Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
			out.append({"a": a, "b": b, "rect": rect})
	return out


static func _build_path_spatial_hash(records: Array, cell_m: float) -> Dictionary:
	var grid: Dictionary = {}
	for idx in range(records.size()):
		var rect: Rect2 = records[idx]["rect"]
		var ix0 := int(floor(rect.position.x / cell_m))
		var ix1 := int(floor((rect.position.x + rect.size.x) / cell_m))
		var iz0 := int(floor(rect.position.y / cell_m))
		var iz1 := int(floor((rect.position.y + rect.size.y) / cell_m))
		for ix in range(ix0, ix1 + 1):
			for iz in range(iz0, iz1 + 1):
				var key := Vector2i(ix, iz)
				if not grid.has(key):
					grid[key] = [] as Array[int]
				(grid[key] as Array[int]).append(idx)
	return grid


static func _min_xz_dist_path_spatial(
		p: Vector2, records: Array, grid: Dictionary, cell_m: float) -> float:
	var best := INF
	var cx := int(floor(p.x / cell_m))
	var cz := int(floor(p.y / cell_m))
	var cell_radius := int(ceil(PATH_CLEARANCE_M / cell_m)) + 1
	for dx in range(-cell_radius, cell_radius + 1):
		for dz in range(-cell_radius, cell_radius + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if not grid.has(key):
				continue
			for idx in grid[key] as Array[int]:
				var rec = records[idx]
				var rect: Rect2 = rec["rect"]
				if not rect.has_point(p):
					continue
				best = minf(best, _dist_point_to_segment(p, rec["a"], rec["b"]))
	return best


static func _min_xz_dist_to_path_records(p: Vector2, records: Array) -> float:
	return _min_xz_dist_path_spatial(
		p, records, _build_path_spatial_hash(records, PATH_SPATIAL_CELL_M), PATH_SPATIAL_CELL_M)


static func _grass_scatter_anchors_cached(ctx: VillageGrassExclusionContext) -> Array[Vector2]:
	var sig := (1 if ctx.generated_grass else 0) \
			^ (ctx.path_stones.size() << 1) \
			^ (ctx.bush_transforms.size() << 9) \
			^ (ctx.cottage_exclusion_rects.size() << 17)
	if sig != _grass_anchor_cache_sig:
		_grass_anchor_cache_sig = sig
		_grass_anchor_cache = collect_scatter_anchor_xz(ctx)
	return _grass_anchor_cache


static func collect_scatter_anchor_xz(ctx: VillageGrassExclusionContext) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var clusters := flower_cluster_layers()
	for piece in FLOWER_CLUSTER_PIECES:
		for t in clusters[piece] as Array[Transform3D]:
			out.append(Vector2(t.origin.x, t.origin.z))
	var petals := petal_layers(ctx.path_stones)
	for piece in PETAL_PIECES:
		for t in petals[piece] as Array[Transform3D]:
			out.append(Vector2(t.origin.x, t.origin.z))
	var plants := plant_layers()
	for piece in PLANT_PIECES:
		for t in plants[piece] as Array[Transform3D]:
			out.append(Vector2(t.origin.x, t.origin.z))
	for t in ctx.path_stones:
		out.append(Vector2(t.origin.x, t.origin.z))
	for t in ctx.bush_transforms:
		out.append(Vector2(t.origin.x, t.origin.z))
	var clover := clover_layers()
	for piece in CLOVER_PIECES:
		for t in clover[piece] as Array[Transform3D]:
			out.append(Vector2(t.origin.x, t.origin.z))
	return out


static func _grass_cell_accepted(
		p: Vector2,
		ctx: VillageGrassExclusionContext,
		anchors: Array[Vector2],
		inner_m: float = GRASS_RING_INNER_M,
		outer_m: float = GRASS_RING_OUTER_M) -> bool:
	var r := p.length()
	if r < inner_m or r > outer_m:
		return false
	if ctx.is_inside_cottage.is_valid() and ctx.is_inside_cottage.call(p):
		return false
	if min_xz_dist_to_path_segments(p, ctx.path_segments) < PATH_CLEARANCE_M:
		return false
	for a in anchors:
		if p.distance_to(a) < PLANT_CLEARANCE_M:
			return false
	return true


static func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	var t := 0.0
	if ab_len_sq > 0.0:
		t = clampf(p.dot(ab) / ab_len_sq, 0.0, 1.0)
	return p.distance_to(a.lerp(b, t))


## Path stepping stones (~0.9 m). [param reject_xz] returns true to skip a candidate stone.
## [param stone_seed] defaults to 9999 (INV-15: byte-identical classic output).
## [param min_stone_spacing] defaults to 0.0 (dedupe off). When > 0, a spatial-hash dedupe
## removes any candidate closer than min_stone_spacing to an already-placed stone. With 0.0
## the output is bit-identical to the pre-S3 classic path (rot_y LCG consumed only on accept).
static func path_stone_transforms(
		path_segments: Array,
		reject_xz: Callable,
		stone_seed: int = 9999,
		min_stone_spacing: float = 0.0) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := stone_seed
	# Spatial-hash for dedup (only allocated when min_stone_spacing > 0).
	# Cell size = min_stone_spacing; a 3×3 neighbour check covers all conflicts.
	var dedup_hash: Dictionary = {}
	var dedup_cell: float = min_stone_spacing  # 0.0 → dedup skipped entirely

	for seg_raw in path_segments:
		var seg := seg_raw as Array
		for i in range(seg.size() - 1):
			var a := seg[i] as Vector2
			var b := seg[i + 1] as Vector2
			var seg_len: float = a.distance_to(b)
			var n_stones := maxi(1, int(seg_len / 0.9))
			for k in range(n_stones):
				var t: float = float(k) / float(n_stones)
				var pos: Vector2 = a.lerp(b, t)
				st = lcg_step(st); var jx: float = (lcg_f01(st) - 0.5) * 0.35
				st = lcg_step(st); var jz: float = (lcg_f01(st) - 0.5) * 0.35
				var cx: float = pos.x + jx
				var cz: float = pos.y + jz
				if reject_xz.call(cx, cz):
					continue
				# Spatial-hash dedupe (only when min_stone_spacing > 0).
				# Classic min_stone_spacing=0.0 takes the else branch → no check,
				# rot_y consumed identically to the pre-S3 code → bit-identical output.
				if min_stone_spacing > 0.0:
					var p2 := Vector2(cx, cz)
					var dk := Vector2i(int(floor(cx / dedup_cell)), int(floor(cz / dedup_cell)))
					var blocked := false
					for di: int in range(-1, 2):
						if blocked:
							break
						for dj: int in range(-1, 2):
							var nk := Vector2i(dk.x + di, dk.y + dj)
							if not dedup_hash.has(nk):
								continue
							for pp: Vector2 in (dedup_hash[nk] as Array[Vector2]):
								if p2.distance_to(pp) < min_stone_spacing:
									blocked = true
									break
							if blocked:
								break
					if blocked:
						continue
					# Accept stone — register in hash before appending.
					if not dedup_hash.has(dk):
						dedup_hash[dk] = [] as Array[Vector2]
					(dedup_hash[dk] as Array[Vector2]).append(p2)
				st = lcg_step(st); var rot_y: float = lcg_f01(st) * TAU
				var basis := Basis.from_euler(Vector3(0.0, rot_y, 0.0))
				out.append(Transform3D(basis, Vector3(cx, 0.0, cz)))
	return out


## Groups of 3–4 mixed flower meshes in the garden ring (FLORA_DESIGN).
static func flower_cluster_layers() -> Dictionary:
	var layers: Dictionary = {}
	for piece in FLOWER_CLUSTER_PIECES:
		layers[piece] = [] as Array[Transform3D]

	var st := 137
	const CLUSTER_COUNT := 10
	for _c in range(CLUSTER_COUNT):
		st = lcg_step(st); var angle: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r: float = lerpf(5.5, 11.4, lcg_f01(st))
		var center_xz := Vector2(cos(angle) * r, sin(angle) * r)
		if blocks_scatter_at(center_xz):
			continue
		var center := Vector3(center_xz.x, 0.0, center_xz.y)
		st = lcg_step(st)
		var member_count := 3 if lcg_f01(st) < 0.45 else 4
		for _m in range(member_count):
			st = lcg_step(st); var piece_idx: int = int(lcg_f01(st) * 4.0) % 4
			st = lcg_step(st); var off_a: float = lcg_f01(st) * TAU
			st = lcg_step(st); var off_r: float = lerpf(0.06, 0.32, lcg_f01(st))
			st = lcg_step(st); var s: float = lerpf(0.17, 0.23, lcg_f01(st))
			st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
			var pos := center + Vector3(cos(off_a) * off_r, 0.0, sin(off_a) * off_r)
			if blocks_scatter_at(Vector2(pos.x, pos.z)):
				continue
			var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
			var piece: String = FLOWER_CLUSTER_PIECES[piece_idx]
			(layers[piece] as Array[Transform3D]).append(Transform3D(basis, pos))

	return layers


## Tiny petals beside path stones, not on the stones (FLORA_DESIGN).
static func petal_layers(path_stones: Array[Transform3D]) -> Dictionary:
	var layers: Dictionary = {}
	for piece in PETAL_PIECES:
		layers[piece] = [] as Array[Transform3D]

	var st := 8801
	for i in range(path_stones.size()):
		if i % 2 != 0:
			continue
		var stone := path_stones[i]
		var p := Vector2(stone.origin.x, stone.origin.z)
		st = lcg_step(st)
		var outward := p
		if outward.length_squared() < 0.04:
			continue
		outward = outward.normalized()
		var tangent := Vector2(-outward.y, outward.x)
		st = lcg_step(st)
		var side: float = 1.0 if lcg_f01(st) > 0.5 else -1.0
		st = lcg_step(st)
		var offset: float = lerpf(0.48, 0.72, lcg_f01(st))
		var xz := p + tangent * side * offset
		var r := xz.length()
		if r < FaunaConstants.GARDEN_RING_INNER_M or r > FaunaConstants.GARDEN_RING_OUTER_M:
			continue
		st = lcg_step(st); var piece_idx: int = int(lcg_f01(st) * 5.0) % 5
		st = lcg_step(st); var s: float = lerpf(0.14, 0.19, lcg_f01(st))
		st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		var piece: String = PETAL_PIECES[piece_idx]
		(layers[piece] as Array[Transform3D]).append(Transform3D(basis, Vector3(xz.x, 0.0, xz.y)))

	return layers


static func pond_center_xz() -> Vector2:
	return VillagePondShape.active().center_xz()


static func is_in_pond_water(p: Vector2, margin_m: float = 0.0) -> bool:
	return VillagePondShape.is_in_water(p, margin_m)


static func is_on_pond_clover_bank(p: Vector2) -> bool:
	return VillagePondShape.is_on_clover_bank(p)


static func blocks_scatter_at(p: Vector2) -> bool:
	return VillagePondShape.blocks_scatter_at(p)


static func _poly_padded_rect(poly: PackedVector2Array, pad: float) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var min_x := poly[0].x
	var max_x := poly[0].x
	var min_y := poly[0].y
	var max_y := poly[0].y
	for v in poly:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
	return Rect2(min_x - pad, min_y - pad, (max_x - min_x) + pad * 2.0, (max_y - min_y) + pad * 2.0)


static func _pond_water_exclusion_rect() -> Rect2:
	return _poly_padded_rect(
		VillagePondShape.water_render_outline_xz(), POND_GRASS_CLEARANCE_M)


static func _pond_grass_exclusion_rect() -> Rect2:
	var poly := VillagePondShape.bank_outer_outline_xz()
	return _poly_padded_rect(poly, POND_GRASS_CLEARANCE_M + 0.5)


static func blocks_grass_at(p: Vector2) -> bool:
	var pond_c := _grass_blocks_pond_center if _grass_blocks_pond_center.x < 1e8 else pond_center_xz()
	if p.distance_squared_to(pond_c) > _grass_blocks_pond_far_sq if _grass_blocks_pond_center.x < 1e8 \
			else (POND_BANK_OUTER_M + 2.5) * (POND_BANK_OUTER_M + 2.5):
		return false
	if is_in_pond_water(p, POND_GRASS_CLEARANCE_M):
		return true
	var bank_rect := _grass_pond_exclusion_rect if _grass_blocks_pond_center.x < 1e8 \
			else _pond_grass_exclusion_rect()
	if not bank_rect.has_point(p):
		return false
	var along := VillagePondShape.bank_shoreline_along_grass(p)
	if along < 0.0:
		return false
	return along < VillagePondSite.GRASS_BANK_MIN_ALONG


static func _closed_polyline_length(poly: PackedVector2Array) -> float:
	var total := 0.0
	var n := poly.size()
	if n < 2:
		return 0.0
	for i in range(n):
		total += poly[i].distance_to(poly[(i + 1) % n])
	return total


static func _point_on_closed_polyline(poly: PackedVector2Array, dist: float) -> Vector2:
	var n := poly.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1:
		return poly[0]
	var total := _closed_polyline_length(poly)
	if total <= 1e-6:
		return poly[0]
	var t := fposmod(dist, total)
	var acc := 0.0
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var seg_len := a.distance_to(b)
		if seg_len <= 1e-6:
			continue
		if acc + seg_len >= t - 1e-8:
			return a.lerp(b, (t - acc) / seg_len)
		acc += seg_len
	return poly[0]


static func _pond_bank_ring_polyline(ring_along: float) -> PackedVector2Array:
	var inner := VillagePondShape.water_render_outline_xz()
	var outer := VillagePondShape.bank_outer_outline_xz()
	var n := mini(inner.size(), outer.size())
	var ring := PackedVector2Array()
	ring.resize(n)
	for i in range(n):
		ring[i] = inner[i].lerp(outer[i], ring_along)
	return ring


static func clover_bank_instance_count() -> int:
	var total := 0
	var layers := clover_layers()
	for piece in CLOVER_PIECES:
		total += (layers[piece] as Array).size()
	return total


## Clover_1 / Clover_2 in three jittered rings on the bank (FLORA #3–4, ivy-86l).
static func clover_layers() -> Dictionary:
	var layers: Dictionary = {}
	for piece in CLOVER_PIECES:
		layers[piece] = [] as Array[Transform3D]

	var inner := VillagePondShape.water_render_outline_xz()
	var outer := VillagePondShape.bank_outer_outline_xz()
	var n := mini(inner.size(), outer.size())
	if n == 0:
		return layers

	var st := CLOVER_LCG_SEED
	for ring_idx in range(CLOVER_RING_ALONG.size()):
		var ring_along: float = CLOVER_RING_ALONG[ring_idx]
		var spacing: float = CLOVER_RING_SPACING_M[ring_idx]
		var place_chance: float = CLOVER_RING_PLACE_CHANCE[ring_idx]
		var ring_poly := _pond_bank_ring_polyline(ring_along)
		var perimeter := _closed_polyline_length(ring_poly)
		if perimeter <= 1e-3:
			continue
		var slots := maxi(4, int(perimeter / spacing))
		for k in range(slots):
			st = lcg_step(st)
			if lcg_f01(st) > place_chance:
				continue
			st = lcg_step(st)
			var dist := float(k) * perimeter / float(slots)
			dist += (lcg_f01(st) - 0.5) * CLOVER_ARC_JITTER_M
			st = lcg_step(st)
			var xz := _point_on_closed_polyline(ring_poly, dist)
			st = lcg_step(st)
			var seg_idx := int(lcg_f01(st) * float(n)) % n
			var radial := (outer[seg_idx] - inner[seg_idx])
			if radial.length_squared() > 1e-8:
				radial = radial.normalized()
				st = lcg_step(st)
				xz += radial * (lcg_f01(st) - 0.5) * 2.0 * CLOVER_RADIAL_JITTER_M
			if not VillagePondShape.is_on_clover_bank(xz):
				continue
			st = lcg_step(st)
			var piece_idx: int = int(lcg_f01(st) * 2.0) % 2
			st = lcg_step(st)
			var s: float = lerpf(0.10, 0.16, lcg_f01(st))
			st = lcg_step(st)
			var rot: float = lcg_f01(st) * TAU
			var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
			var piece: String = CLOVER_PIECES[piece_idx]
			(layers[piece] as Array[Transform3D]).append(
				Transform3D(basis, Vector3(xz.x, 0.0, xz.y)))

	return layers


static func fauna_clover_anchor_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var layers := clover_layers()
	for piece in CLOVER_PIECES:
		for t in layers[piece] as Array[Transform3D]:
			out.append(t)
	return out


## Classic polar garden plants (pivot-centred); pond checks use [method VillagePondShape.classic]
## so placement cannot drift when [method VillagePondShape.active] was left on a generated pond.
static func blocks_grass_at_for_shape(p: Vector2, shape: VillagePondShape) -> bool:
	var pond_c := shape.center_xz()
	var far_sq := (POND_BANK_OUTER_M + 2.5) * (POND_BANK_OUTER_M + 2.5)
	if p.distance_squared_to(pond_c) > far_sq:
		return false
	if shape._is_in_water(p, POND_GRASS_CLEARANCE_M):
		return true
	var bank_rect := _poly_padded_rect(
		shape._bank_outer_outline_local(), POND_GRASS_CLEARANCE_M + 0.5)
	if not bank_rect.has_point(p):
		return false
	var along := shape._bank_shoreline_along_grass(p)
	if along < 0.0:
		return false
	return along < VillagePondSite.GRASS_BANK_MIN_ALONG


## Fixed-seed polar placement (14 small + 8 big). Candidates inside the ACTIVE pond's water
## are rejected and redrawn (the backdrop sets the active pond before scatter runs), so no
## plant ever stands in water. Rejection reads only [method is_in_pond_water] — no
## grass-session statics — so it cannot leak state between callers.
static func plant_layers() -> Dictionary:
	var layers: Dictionary = {
		"Plant_7": [] as Array[Transform3D],
		"Plant_7_Big": [] as Array[Transform3D],
	}
	var st := 5503
	var placed_7 := 0
	var attempts_7 := 0
	while placed_7 < 14 and attempts_7 < 14 * 40:
		attempts_7 += 1
		st = lcg_step(st); var angle: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r: float = lerpf(6.0, 14.5, lcg_f01(st))
		var p := Vector2(cos(angle) * r, sin(angle) * r)
		if is_in_pond_water(p):
			continue
		st = lcg_step(st); var s: float = lerpf(0.16, 0.22, lcg_f01(st))
		st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		(layers["Plant_7"] as Array[Transform3D]).append(
			Transform3D(basis, Vector3(p.x, 0.0, p.y)))
		placed_7 += 1
	var placed_big := 0
	var attempts_big := 0
	while placed_big < 8 and attempts_big < 8 * 40:
		attempts_big += 1
		st = lcg_step(st); var angle2: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r2: float = lerpf(7.0, 13.0, lcg_f01(st))
		var p2 := Vector2(cos(angle2) * r2, sin(angle2) * r2)
		if is_in_pond_water(p2):
			continue
		st = lcg_step(st); var s2: float = lerpf(0.14, 0.18, lcg_f01(st))
		st = lcg_step(st); var rot2: float = lcg_f01(st) * TAU
		var basis2 := Basis.from_euler(Vector3(0.0, rot2, 0.0)).scaled(Vector3(s2, s2, s2))
		(layers["Plant_7_Big"] as Array[Transform3D]).append(
			Transform3D(basis2, Vector3(p2.x, 0.0, p2.y)))
		placed_big += 1
	return layers


## Bee/butterfly flower anchors: cluster blooms + path-side petals only (FLORA_DESIGN).
static func fauna_flower_anchor_transforms_with_paths(
		path_stones: Array[Transform3D]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var clusters := flower_cluster_layers()
	for piece in FLOWER_CLUSTER_PIECES:
		for t in clusters[piece] as Array[Transform3D]:
			out.append(t)
	var petals := petal_layers(path_stones)
	for piece in PETAL_PIECES:
		for t in petals[piece] as Array[Transform3D]:
			out.append(t)
	return out


static func measure_patch_density_cv(
		grass: Array[Transform3D], lawn_centre: Vector2, sample_r: float,
		radius: float = _GRASS_PATCH_SAMPLE_RADIUS_M, n_samples: int = 36) -> float:
	var densities: Array[float] = []
	for i in range(n_samples):
		var ang := float(i) * (TAU / float(n_samples))
		var centre := lawn_centre + Vector2(cos(ang), sin(ang)) * sample_r
		densities.append(measure_patch_density_m2(grass, centre, radius))
	var mean := 0.0
	for d in densities:
		mean += d
	mean /= float(n_samples)
	if mean < 1e-6:
		return 0.0
	var var_sum := 0.0
	for d in densities:
		var_sum += (d - mean) * (d - mean)
	var_sum /= float(n_samples)
	return sqrt(var_sum) / mean


static func measure_patch_density_m2(
		grass: Array[Transform3D], patch_centre: Vector2,
		radius: float = _GRASS_PATCH_SAMPLE_RADIUS_M) -> float:
	var r_sq := radius * radius
	var n := 0
	for t in grass:
		var p := Vector2(t.origin.x, t.origin.z)
		if p.distance_squared_to(patch_centre) <= r_sq:
			n += 1
	var area := PI * radius * radius
	return float(n) / area if area > 0.0 else 0.0


static func grass_patch_exclusion_clear(p: Vector2, ctx: VillageGrassExclusionContext) -> bool:
	var pad := _GRASS_PATCH_EXCLUSION_CLEARANCE_M
	if _grass_cottage_blocks(p, ctx):
		return false
	if blocks_grass_at(p):
		return false
	if min_xz_dist_to_path_segments(p, ctx.path_segments) < PATH_CLEARANCE_M + pad:
		return false
	for a in collect_scatter_anchor_xz(ctx):
		if p.distance_to(a) < PLANT_CLEARANCE_M + pad:
			return false
	return true


static func find_open_grass_patch_centre(
		ctx: VillageGrassExclusionContext,
		lawn_centre: Vector2,
		target_r: float,
		seed_salt: int = 0) -> Vector2:
	var r_edge := grass_radial_edge_m(ctx)
	const RADIAL_STEPS := 12
	const ANGLE_STEPS := 64
	for ri in range(RADIAL_STEPS):
		var dr := (float(ri) / float(RADIAL_STEPS - 1) - 0.5) * 3.5
		var r := target_r + dr
		if r < 1.0 or r > r_edge - 0.25:
			continue
		for ai in range(ANGLE_STEPS):
			var angle := float(ai) * (TAU / float(ANGLE_STEPS)) + float(seed_salt) * 0.041
			var p := lawn_centre + Vector2(cos(angle), sin(angle)) * r
			if p.distance_to(lawn_centre) > r_edge - 0.25:
				continue
			if grass_patch_exclusion_clear(p, ctx):
				return p
	return Vector2(INF, INF)
