## VillageLayout — authored or generated village geometry value object (ivy-80z).
##
## `authored()` wraps the classic COTTAGES constant and VillageBackdrop.path_polylines(),
## providing the S1 seam that lets VillageBackdrop instance code read from `_layout`
## instead of statics without changing the classic render at all (INV-15).
##
## `generate(seed)` is implemented in S2′: seeded dart-throwing placement of the
## 7 authored cottage types into two rings (inner r∈[11.5,13.0], outer r∈[19.5,21.5]).
## Path network is added in S3.
##
## AR-VG-STATIC: `VillageBackdrop.cottage_transform`, `cottage_exterior_rect`,
## `cottage_door`, `path_polylines`, and `inside_any_cottage` remain as statics
## with identical signatures. `inside_any_cottage` delegates here.
class_name VillageLayout
extends RefCounted

# ── Sub-stream salts (AR-VG-API) ──────────────────────────────────────────────
const PLACEMENT_SALT := 0x5011A9
const PATHGRAPH_SALT := 0x9A7B3
const STONES_SALT    := 0x5739C1
## Classic authored graph: 7 door nodes 0..6, hero stoop index 7 (INV-15; unchanged).
const CLASSIC_HAMLET_COUNT := 7
const CLASSIC_HERO_NODE := 7
## Legacy alias for classic/MST unit tests only — generated graph uses `generated_hero_node()`.
const HERO_NODE := CLASSIC_HERO_NODE

# ── Generated hamlet frame (ivy-3l6 §3l6-A) ───────────────────────────────────
const VILLAGE_AXIS := Vector2(0.0, -1.0)
const HERO_DOOR_STOOP := Vector2(0.0, 2.59)
const VILLAGE_GREEN_G := Vector2(0.0, -18.0)
const HAMLET_SEED := VILLAGE_GREEN_G
const PAIR_JIGGLE_MAX_M := 4.0
## Legacy pivot ring (classic docs); generated hamlet uses HAMLET_MAX_CORNER_FROM_G (ivy-3l6 rev).
const OUTER_CORNER_MAX_M := 38.0
## Grown cottage corners must stay inside lawn R=44 re-centred on G (ivy-3l6 v2 / INV-36′).
const HAMLET_MAX_CORNER_FROM_G := 54.0
const GENERATED_LAWN_RADIUS := 56.0
const HOUSE_SPACING_M := 18.0
const LATTICE_R_IN := 14.0
const LATTICE_R_OUT := 50.0
const _LATTICE_JITTER_M := 2.5
const _LATTICE_ROT_TRIES := 24
const _MIN_CENTRE_GAP_SANITY_M := 14.0
## Square plaza + 150° fan hamlet (ivy-3l6-A2).
const PLAZA_SIDE_L := 18.0
const PLAZA_SIDE_L_MIN := 16.0
const PLAZA_SIDE_L_MAX := 20.0
const GENERATED_HAMLET_COUNT := 8
## Generated path graph: N doors + hero + 4 plaza corners + 4 edge midpoints.
const GENERATED_GRAPH_NODE_COUNT := GENERATED_HAMLET_COUNT + 9
const FAN_PHI_MIN_DEG := -85.0
const FAN_PHI_MAX_DEG := 85.0
const FAN_R_IN := 15.5
const FAN_R_OUT := 40.0
const FAN_R_OUT_N_LE_8 := 37.0
## N-dependent pair spacing (ivy-3l6-A2b); never below 12 m centre floor.
const _GAP_FLOOR_N_LE_8 := 14.0
const _GAP_FLOOR_N_9_10 := 12.5
const _GAP_FLOOR_N_11_12 := 12.0
const _GAP_FLOOR_N_GE_13 := 12.0
const _FAN_RADIAL_BIAS_POW := 1.4
const _FAN_INNER_BAND_COUNT := 3
const _FAN_INNER_U_EXTRA_POW := 2.0
const _FAN_DARTS_PER_HOUSE := 384
## Mitchell best-candidate samples per house (generated fan placement).
const _MITCHELL_K := 48
const _PLAZA_KEEP_INSET_M := 0.5
## Cobble loop centreline inset from plaza grass rect + cottage standoff (INV-8 / keep-clear).
const _PLAZA_LOOP_CENTERLINE_INSET_M := 1.6
const _PLAZA_COTTAGE_VERGE_M := 2.0
const GENERATED_STONE_SPACING := 0.75
## Legacy dart path (classic tests only).

# ── Placement constants (shared classic / generated) ───────────────────────────
## Minimum centre-to-centre spacing floor (metres); pair jiggle adds up to PAIR_JIGGLE_MAX_M.
const _MIN_CENTRE_SEP_M := 15.0
## Hero keep-out distance: nearest grown-rect face must be ≥ this from origin (INV-1).
const _KEEP_OUT := 5.9
## Overlap / keep-out test grow margin (metres).
const _GROW := 0.8
## Classic dart tests; generated hamlet uses Poisson-disc (below).
const _MAX_DARTS := 128
## Minimum door dot (classic); generated uses _MIN_DOT_GENERATED.
const _MIN_DOT := 0.6
const _MIN_DOT_GENERATED := 0.5
const _N_REDRAW := 8
## Extra redraw tiers when fan is dense (N≥10 placement lab / A2b).
const _N_REDRAW_DENSE := 24
const _PERSONAL_R_N_LE_8 := Vector2(7.5, 9.0)
const _PERSONAL_R_N_9_12 := Vector2(5.5, 6.5)
const _PERSONAL_R_N_GE_13 := Vector2(5.0, 6.0)
const _HERO_LEG_PHI_DEG := 72.0
const _HERO_LEG_R_MAX := 18.0
## Pathgraph jitter rounds per successful placement (network before next lattice rotation).
const _NETWORK_RETRY_ROUNDS := 2
const _NETWORK_RETRIES_PER_ROUND := 8
## Hard cap on pathgraph tries per hamlet placement (rotate lattice before burning seconds).
const _MAX_NET_TRIES_PER_PLACEMENT := 10
## Abort pathgraph jitter when crossing/pond rejects repeat (rotate placement).
const _NET_POST_FAIL_STREAK_CAP := 5
## Safety net only (monotone spur build is O(N), no search retries).
const _NETWORK_TRY_BUDGET_US := 2400000
## Wall time cap per `generate(seed)` call (µs); worst-case seed aborts further rotation tries.
const _GENERATE_WALL_BUDGET_US := 4800000
## Lab tuning hooks (placement_lab.gd).
static var _lab_personal_r_min: float = -1.0
static var _lab_personal_r_max: float = -1.0
static var _lab_hamlet_count: int = -1
static var _lab_fan_r_out: float = -1.0
static var _lab_fan_phi_min_deg: float = NAN
static var _lab_fan_phi_max_deg: float = NAN
## B3: internal _build_network timing (`.tmp/profile_network20.gd`).
static var _net_profile_enabled: bool = false
static var _net_profile_acc: Dictionary = {}
## Four candidate yaws evaluated per dart (SD-VILLAGE-GEN-3).
const _YAWS: Array[int] = [0, 90, 180, 270]

## Test-only override: when ≥ 0, replaces _GROW_HOUSE_TRIES / _ANCHOR_TRIES (0 = instant fail).
## Set to 0 to force immediate failure (fallback test). Reset to -1 after each test.
## AR-VG-RISK-5: static so it persists within one headless Godot process run.
static var _test_max_darts: int = -1

## Test-only override: when true, _build_network always returns ok=false (network fallback test).
## Reset to false after each test.
static var _test_force_network_fail: bool = false
## When true, generate() accumulates microsecond totals into _profile_totals (B2 perf script).
static var _profile_generate: bool = false
static var _profile_totals: Dictionary = {}

## Instrumentation for `.tmp/fail_histogram.gd` (off by default).
static var _diag_enabled: bool = false
static var _diag_result: Dictionary = {}


static func _diag_begin(seed: int) -> void:
	if not _diag_enabled:
		return
	_diag_result = {"seed": seed, "attempts": [], "fallback": false, "success_tier": -1}


static func _diag_open_attempt(attempt: int) -> Dictionary:
	if not _diag_enabled:
		return {}
	var rec := {
		"attempt": attempt,
		"placement_ms": 0.0,
		"pond1_ms": 0.0,
		"network_ms": 0.0,
		"pond2_ms": 0.0,
		"net_tries": 0,
		"outcome": "",
	}
	_diag_result["attempts"].append(rec)
	return rec


static func _diag_set_outcome(rec: Dictionary, outcome: String) -> void:
	if not _diag_enabled or rec.is_empty():
		return
	rec["outcome"] = outcome


static func _profile_reset() -> void:
	_profile_totals = {
		"placement_us": 0,
		"pond_phase1_us": 0,
		"network_us": 0,
		"pond_after_paths_us": 0,
		"scrub_us": 0,
		"cross_check_us": 0,
		"network_retries": 0,
		"placement_attempts": 0,
		"seeds": 0,
	}


static func reset_net_profile() -> void:
	_net_profile_acc = {
		"route_us": 0,
		"cross_us": 0,
		"clear_us": 0,
		"scenic_us": 0,
		"calls_route": 0,
		"calls_cross": 0,
		"calls_clear": 0,
		"builds": 0,
	}


static func _net_prof_add(key: String, delta_us: int, extra: int = 0) -> void:
	if not _net_profile_enabled:
		return
	_net_profile_acc[key] = int(_net_profile_acc.get(key, 0)) + delta_us
	if extra != 0:
		var ck := key + "_n"
		_net_profile_acc[ck] = int(_net_profile_acc.get(ck, 0)) + extra


static func _profile_add(key: String, delta_us: int, extra: int = 0) -> void:
	if not _profile_generate:
		return
	_profile_totals[key] = int(_profile_totals.get(key, 0)) + delta_us
	if extra != 0:
		var ek := key + "_count"
		_profile_totals[ek] = int(_profile_totals.get(ek, 0)) + extra

# ── Path network constants (S3) ────────────────────────────────────────────────
## Hero-edge polyline clip radius: polyline ends here, samples inside are dropped.
const _HERO_RING_CLIP    := 6.5
## Cottage grow margin for path centreline avoidance check (m).
const _PATH_COTTAGE_GROW := 0.2
## Min distance from a centreline sample to a non-endpoint grown cottage rect (m).
const _PATH_CLEARANCE    := 0.35
## Target arc sample spacing for Bézier polylines (m).
const _BEZIER_SPACING    := 0.3
## Base |bend| magnitude for quadratic Bézier (m).
const _BEZIER_BASE_BEND  := 1.15
## Maximum |bend| after clamping (m).
const _BEZIER_BEND_MAX   := 3.5
## Bend adjustment step for cottage avoidance (m).
const _BEZIER_BEND_STEP  := 0.35
## Number of extra bend-adjust tries before waypoint reroute.
const _BEZIER_BEND_TRIES := 8
## Perpendicular waypoint push for MST edge reroute (m).
const _WAYPOINT_PUSH     := 2.2
## Generated world-scale preset (+20% vs ivy-80z S2b; scales with ring expansion).
const GENERATED_HILL_INNER := 56.0
const GENERATED_PINE_INNER := 41.8
const GENERATED_PINE_OUTER := 61.6
const GENERATED_PINE_COUNT := 40
const GENERATED_FOG_BEGIN := 20.5
const GENERATED_BUSH_FILLER_OUTER := 32.3
## Generated-only pond bank clearances (classic uses VillagePondSite defaults via layout fields).
const GENERATED_POND_COTTAGE_CLEARANCE_M := 3.0
const GENERATED_POND_PATH_CLEARANCE_M := 2.0
## Target extra loop edges beyond the spanning tree.
const _TARGET_SCENIC_LOOPS := 0
const _MIN_SCENIC_LOOPS := 0
const _SPUR_BEND_MAX_M := 1.5
const _SPUR_COTTAGE_CLEAR_M := 0.55
const _DOOR_SOUTH_PHI_ABS_DEG := 75.0
const _SCENIC_LEN_CHORD_MIN := 1.25
const _SCENIC_LEN_CHORD_MAX := 1.6
const _MAX_ALT_SPUR_DOORS := 4
const _PATH_ROUTE_ATTEMPTS := 4
const _MEANDER_RESAMPLE_M := 0.3
## Plaza loop node order (indices into N+1..N+8): SW,S,SE,E,NE,N,NW,W.
const _PLAZA_LOOP_OFFSETS: Array[int] = [0, 4, 1, 5, 2, 6, 3, 7]

# ── Layout data ───────────────────────────────────────────────────────────────
## 7 cottage spec Dictionaries (same shape as VillageBackdrop.COTTAGES).
var cottages: Array = []
## Legacy ring assignment; empty for classic and generated v2 (use is_generated).
var cottage_rings: Array = []
## Hamlet / lawn centre in layout XZ. Classic (0,0); generated VILLAGE_GREEN_G.
var hamlet_centre_xz: Vector2 = Vector2.ZERO
## True for VillageLayout.generate() success paths (not authored() fallback).
var is_generated: bool = false
## Array of Array[Vector2] polylines (one per cottage door → hero).
var paths: Array = []
## Parallel to `paths`: "plaza" | "hero" | "primary" | "secondary" | "door" (v3 generated); classic may use "door" per radial path or stay empty.
var path_kinds: Array[String] = []
## v3: junction positions for V3 crossing checks; classic empty.
var junction_points: Array[Vector2] = []
## Graph edges as node-index pairs (door nodes 0..6, hero 7). Used by INV-5/INV-6.
var edges: Array[Vector2i] = []
## LCG seed for path_stone_transforms. Classic = 9999 (INV-15). Generated = sub-stream.
var stone_seed: int = 9999
## Minimum stone spacing for deduplication. Classic = 0.0 (dedupe off). Generated = 0.5 m.
var min_stone_spacing: float = 0.0
## True iff generate() exhausted its budget and fell back to authored() (push_warning issued).
var fallback: bool = false
## Redraw attempt index when generate() succeeded (B3 metrics).
var placement_attempt: int = -1
## Legacy field (relaxation removed); always false on generated layouts.
var placement_relaxed: bool = false

## World-scale fields (AR-VG-DATA, ivy-80z S2b).
## Defaults are the classic source literals; authored() leaves them untouched so
## authored().field == old literal is a pure-value data test (no code path change).
## generate() writes the fixed generated preset (INV-20); values are NOT per-seed.
var lawn_radius: float = 20.0
var hill_inner: float = 20.0
var pine_inner: float = 19.0
var pine_outer: float = 28.0
var pine_count: int = 22
var fog_begin: float = 9.5
var fog_end: float = 95.0
var bush_filler_inner: float = 8.0
var bush_filler_outer: float = 15.0
## Resolved pond centre (XZ). Set during layout build before paths are routed.
var pond_center: Vector2 = Vector2.ZERO
var pond_placed: bool = false
## Pond bank clearance from cottages / paths. Defaults match classic (INV-15); generate() overrides.
var pond_cottage_clearance_m: float = VillagePondSite.COTTAGE_CLEARANCE_M
var pond_path_clearance_m: float = VillagePondSite.PATH_CLEARANCE_M
## Generated plaza (classic: side 0, empty rects).
var plaza_side_m: float = 0.0
var plaza_rect: Rect2 = Rect2()
var plaza_keep_clear: Rect2 = Rect2()


# ── Constructors ──────────────────────────────────────────────────────────────

## Returns the authored classic layout: cottages + pond slot, then door paths that
## detour around the pond bank (no centreline through water/bank).
static func authored() -> VillageLayout:
	var layout := VillageLayout.new()
	for spec in VillageBackdrop.COTTAGES:
		layout.cottages.append(spec.duplicate())
	layout.cottage_rings = []
	layout.hamlet_centre_xz = Vector2.ZERO
	layout.is_generated = false
	layout.pond_center = VillagePondSite.CLASSIC_CENTER
	layout.pond_placed = true
	layout.paths = build_radial_hero_paths(
		layout.cottages, layout.pond_center, layout.pond_path_clearance_m)
	layout.path_kinds = []
	for _i in range(layout.paths.size()):
		layout.path_kinds.append("door")
	layout.junction_points = []
	layout.stone_seed = 9999
	layout.min_stone_spacing = 0.0
	layout.fallback = false
	return layout


## Returns a procedurally generated layout (v3 path-first via `VillageGeneratorV3`).
static func generate(seed: int) -> VillageLayout:
	var gen_script: GDScript = load("res://src/world/village_gen/village_generator.gd") as GDScript
	return gen_script.generate(seed) as VillageLayout

## Legacy lattice + fan-band placement + hex network (unused by `generate()`; retained until cleanup).
static func _generate_legacy_lattice(seed: int) -> VillageLayout:
	# AR-VG-RISK-6: normalise to 31-bit non-negative to match LCG domain.
	@warning_ignore("int_as_enum_without_cast")
	var norm := seed & 0x7FFFFFFF
	var cur_state := _derive(norm, PLACEMENT_SALT)
	_diag_begin(seed)
	var gen_wall_start := Time.get_ticks_usec()

	for attempt in range(_LATTICE_ROT_TRIES):
		if Time.get_ticks_usec() - gen_wall_start > _GENERATE_WALL_BUDGET_US:
			break
		var diag_rec := _diag_open_attempt(attempt)
		if attempt > 0:
			cur_state = VillageScatterPositions.lcg_step(cur_state ^ (attempt + 1))

		var green_g: Vector2 = VILLAGE_GREEN_G
		var plaza_side: float = PLAZA_SIDE_L
		var t_place0 := Time.get_ticks_usec() if _profile_generate or _diag_enabled else 0
		var result := _place_hex_lattice_hamlet(cur_state, green_g, plaza_side, attempt)
		if _profile_generate:
			_profile_add("placement_us", Time.get_ticks_usec() - t_place0, 1)
		if _diag_enabled:
			diag_rec["placement_ms"] = float(Time.get_ticks_usec() - t_place0) / 1000.0

		if result["ok"] and result["cottages"].size() == _effective_hamlet_count():
			var layout := VillageLayout.new()
			layout.cottages = result["cottages"]
			layout.cottage_rings = []
			layout.hamlet_centre_xz = green_g
			layout.plaza_side_m = plaza_side
			layout.plaza_rect = plaza_rect_at(green_g, plaza_side)
			layout.plaza_keep_clear = plaza_cottage_keep_clear_rect(green_g, plaza_side)
			layout.is_generated = true
			layout.path_kinds = []
			# World-scale preset (SD-VILLAGE-GEN-6 / INV-20): fixed values, not per-seed.
			layout.lawn_radius = GENERATED_LAWN_RADIUS
			layout.hill_inner = GENERATED_HILL_INNER
			layout.pine_inner = GENERATED_PINE_INNER
			layout.pine_outer = GENERATED_PINE_OUTER
			layout.pine_count = GENERATED_PINE_COUNT
			layout.fog_begin = GENERATED_FOG_BEGIN
			layout.fog_end = 95.0
			layout.bush_filler_inner = 8.0
			layout.bush_filler_outer = GENERATED_BUSH_FILLER_OUTER
			layout.stone_seed = _derive(norm, STONES_SALT)
			layout.pond_cottage_clearance_m = GENERATED_POND_COTTAGE_CLEARANCE_M
			layout.pond_path_clearance_m = GENERATED_POND_PATH_CLEARANCE_M
			var t_pond0 := Time.get_ticks_usec() if _profile_generate or _diag_enabled else 0
			layout.pond_center = VillagePondPlacement.resolve_center(layout)
			layout.pond_placed = true
			if _profile_generate:
				_profile_add("pond_phase1_us", Time.get_ticks_usec() - t_pond0)
			if _diag_enabled:
				diag_rec["pond1_ms"] = float(Time.get_ticks_usec() - t_pond0) / 1000.0

			var network: Dictionary = {"ok": false}
			var network_accepted := false
			var last_net_outcome := "network_fail"
			var net_budget_start := Time.get_ticks_usec()
			var net_phase_us := 0
			var pond2_phase_us := 0
			var net_try_global := 0
			var post_fail_streak := 0
			var obs_pre := _make_network_obstacle_cache(
				_network_cottage_rects(layout.cottages), layout.pond_center, layout.pond_path_clearance_m)
			var door_normals_cached: Array[Vector2] = _network_door_normals(layout.cottages)
			for _net_round: int in _NETWORK_RETRY_ROUNDS:
				if network_accepted:
					break
				if Time.get_ticks_usec() - net_budget_start > _NETWORK_TRY_BUDGET_US:
					last_net_outcome = "network_budget"
					break
				for _net_try: int in _NETWORK_RETRIES_PER_ROUND:
					if net_try_global >= _MAX_NET_TRIES_PER_PLACEMENT:
						last_net_outcome = "network_budget"
						break
					if Time.get_ticks_usec() - net_budget_start > _NETWORK_TRY_BUDGET_US:
						last_net_outcome = "network_budget"
						break
					if _profile_generate:
						_profile_add("network_retries", 0, 1)
					var pathgraph_state := _derive(norm, PATHGRAPH_SALT)
					if net_try_global > 0:
						pathgraph_state = VillageScatterPositions.lcg_step(
							pathgraph_state ^ (net_try_global * 991 + attempt * 37 + int(norm) % 10007))
					net_try_global += 1
					var t_net0 := Time.get_ticks_usec() if _profile_generate or _diag_enabled else 0
					network = _build_network(
						layout.cottages, pathgraph_state,
						layout.pond_center, layout.pond_path_clearance_m,
						green_g, plaza_side)
					var net_us := Time.get_ticks_usec() - t_net0
					net_phase_us += net_us
					if _profile_generate:
						_profile_add("network_us", net_us)
					if not network["ok"]:
						last_net_outcome = str(network.get("fail_reason", "network_fail"))
						post_fail_streak = 0
						if _diag_enabled:
							diag_rec["net_tries"] = int(diag_rec.get("net_tries", 0)) + 1
						continue
					layout.paths = network["paths"]
					layout.edges = network["edges"]
					layout.min_stone_spacing = GENERATED_STONE_SPACING
					var mcount: int = int(network.get("mandatory_count", layout.paths.size()))
					var net_nodes: PackedVector2Array = network["nodes"]
					var pre_inv8 := inv8_violation_samples_for_paths(
						layout.paths, layout.edges, layout.cottages)
					var t_scrub := Time.get_ticks_usec() if _profile_generate else 0
					if not pre_inv8.is_empty():
						_repair_inv8_clipping_spurs(
							layout.paths, layout.edges, mcount, layout.cottages.size(),
							net_nodes, door_normals_cached, obs_pre, green_g, plaza_side,
							pathgraph_state)
						_soft_inv8_fixup_door_spurs(
							layout.paths, layout.edges, mcount, layout.cottages.size(), obs_pre)
						_nudge_mandatory_loop_paths_inv8(
							layout.paths, layout.edges, mcount, layout.cottages.size(), obs_pre)
						if _profile_generate:
							_profile_add("scrub_us", Time.get_ticks_usec() - t_scrub)
					elif _profile_generate:
						_profile_add("scrub_us", 0)
					_drop_scenic_paths_until_clear(layout.paths, layout.edges, mcount)
					var t_x := Time.get_ticks_usec() if _profile_generate else 0
					var cur_v := inv8_violation_samples_for_paths(
						layout.paths, layout.edges, layout.cottages)
					if _profile_generate:
						_profile_add("cross_check_us", Time.get_ticks_usec() - t_x)
					if not cur_v.is_empty():
						last_net_outcome = "inv8_after_scrub"
						if _diag_enabled:
							diag_rec["net_tries"] = int(diag_rec.get("net_tries", 0)) + 1
						continue
					if path_polylines_has_crossing(layout.paths):
						_resolve_mandatory_path_crossings(
							layout.paths, layout.edges, mcount, layout.cottages.size(),
							layout.cottages, net_nodes, door_normals_cached,
							obs_pre, green_g, plaza_side, pathgraph_state, 5)
					if path_polylines_has_crossing(layout.paths):
						last_net_outcome = "path_crossings"
						if _diag_enabled:
							diag_rec["net_tries"] = int(diag_rec.get("net_tries", 0)) + 1
						continue
					var t_pond2 := Time.get_ticks_usec() if _profile_generate or _diag_enabled else 0
					layout.pond_center = VillagePondPlacement.resolve_after_paths(layout)
					var p2_us := Time.get_ticks_usec() - t_pond2
					pond2_phase_us += p2_us
					if _profile_generate:
						_profile_add("pond_after_paths_us", p2_us)
					if VillagePondPlacement.validate(layout.pond_center, layout, true):
						network_accepted = true
						post_fail_streak = 0
						break
					else:
						last_net_outcome = "pond_after_paths"
						post_fail_streak += 1
					if _diag_enabled:
						diag_rec["net_tries"] = int(diag_rec.get("net_tries", 0)) + 1
					if post_fail_streak >= _NET_POST_FAIL_STREAK_CAP:
						break
				if network_accepted:
					break
				if net_try_global >= _MAX_NET_TRIES_PER_PLACEMENT:
					break
				if post_fail_streak >= _NET_POST_FAIL_STREAK_CAP:
					break
			if _diag_enabled:
				diag_rec["network_ms"] = float(net_phase_us) / 1000.0
				diag_rec["pond2_ms"] = float(pond2_phase_us) / 1000.0
			if not network_accepted:
				push_warning(
					"VillageLayout.generate: network/pond failed after %d tries (seed=%d, placement attempt=%d)" \
					% [_NETWORK_RETRY_ROUNDS * _NETWORK_RETRIES_PER_ROUND, seed, attempt])
				_diag_set_outcome(diag_rec, last_net_outcome)
				cur_state = result["state"]
				continue
			layout.fallback = false
			layout.placement_attempt = attempt
			layout.placement_relaxed = false
			if _diag_enabled:
				_diag_result["success_tier"] = attempt
				_diag_set_outcome(diag_rec, "success")
			if _profile_generate:
				_profile_add("seeds", 0, 1)
				_profile_add("placement_attempts", 0, attempt + 1)
			return layout

		_diag_set_outcome(diag_rec, "placement_fail")
		cur_state = result["state"]

	push_warning("VillageLayout.generate: lattice placement exhausted after %d tries (seed=%d) — falling back to authored()" % [
		_LATTICE_ROT_TRIES, seed])
	if _diag_enabled:
		_diag_result["fallback"] = true
	var fallback_layout := authored()
	fallback_layout.fallback = true
	return fallback_layout


# ── Geometry queries ──────────────────────────────────────────────────────────

## True if p lies inside any of `cottages`' wall exteriors grown by `margin` metres.
## Free function — VillageBackdrop.inside_any_cottage delegates here (AR-VG-STATIC).
static func inside_cottages(cottages: Array, p: Vector2, margin: float) -> bool:
	for spec in cottages:
		if VillageBackdrop.cottage_exterior_rect(spec).grow(margin).has_point(p):
			return true
	return false


## True if p lies inside any cottage in this layout grown by `margin` metres.
func inside_any_cottage(p: Vector2, margin: float) -> bool:
	return inside_cottages(cottages, p, margin)


## Returns this layout's path polylines (uniform read path for instance code).
func path_polylines() -> Array:
	return paths


# ── Internal helpers (names fixed by AR-VG-API; implemented in S2′–S3) ────────

## Derive a sub-stream seed: two LCG steps applied to (seed ^ salt) & 0x7FFFFFFF.
## AR-VG-RISK-6: stays within signed 64-bit at all intermediate values.
static func _hamlet_redraw_tiers(hamlet_count: int) -> int:
	return _N_REDRAW_DENSE if hamlet_count >= 10 else _N_REDRAW


static func _derive(seed: int, salt: int) -> int:
	var s := (seed ^ salt) & 0x7FFFFFFF
	s = VillageScatterPositions.lcg_step(s)
	s = VillageScatterPositions.lcg_step(s)
	return s


## Seeded pair jiggle for centre spacing (symmetric in cottage type indices).
static func _pair_jiggle_max_m(hamlet_count: int) -> float:
	return 3.0 if hamlet_count <= 8 else PAIR_JIGGLE_MAX_M


static func _pair_jiggle_m(
		type_a: int, type_b: int, placement_state: int, hamlet_count: int) -> float:
	var ia := mini(type_a, type_b)
	var ib := maxi(type_a, type_b)
	var h := (ia * 1597 + ib * 5179 + placement_state) & 0x7FFFFFFF
	h = VillageScatterPositions.lcg_step(h)
	return VillageScatterPositions.lcg_f01(h) * _pair_jiggle_max_m(hamlet_count)


static func _pair_gap_multiplier(type_a: int, type_b: int, placement_state: int) -> float:
	var ia := mini(type_a, type_b)
	var ib := maxi(type_a, type_b)
	var h := (ia * 2903 + ib * 7919 + placement_state * 3) & 0x7FFFFFFF
	h = VillageScatterPositions.lcg_step(h)
	return lerpf(0.82, 1.18, VillageScatterPositions.lcg_f01(h))


static func _required_centre_gap_m(type_a: int, type_b: int, placement_state: int) -> float:
	return _MIN_CENTRE_SEP_M + _pair_jiggle_m(type_a, type_b, placement_state, 7)


static func _personal_r_bounds_for_count(hamlet_count: int) -> Vector2:
	if hamlet_count <= 8:
		return _PERSONAL_R_N_LE_8
	if hamlet_count <= 10:
		return _PERSONAL_R_N_9_12
	return _PERSONAL_R_N_GE_13


static func _personal_r_bounds() -> Vector2:
	if _lab_personal_r_min >= 0.0 and _lab_personal_r_max >= 0.0:
		return Vector2(_lab_personal_r_min, _lab_personal_r_max)
	return _personal_r_bounds_for_count(_effective_hamlet_count())


static func _draw_personal_radii(st: int, count: int) -> Dictionary:
	var bounds := _personal_r_bounds()
	var radii: Array[float] = []
	var gap_scales: Array[float] = []
	for _i: int in count:
		st = VillageScatterPositions.lcg_step(st)
		var t: float = VillageScatterPositions.lcg_f01(st)
		radii.append(lerpf(bounds.x, bounds.y, t))
		st = VillageScatterPositions.lcg_step(st)
		gap_scales.append(lerpf(0.78, 1.22, VillageScatterPositions.lcg_f01(st)))
	return {"radii": radii, "gap_scales": gap_scales, "state": st}


static func _gap_floor_m(hamlet_count: int) -> float:
	var base := _GAP_FLOOR_N_GE_13
	if hamlet_count <= 8:
		base = _GAP_FLOOR_N_LE_8
	elif hamlet_count <= 10:
		base = _GAP_FLOOR_N_9_10
	elif hamlet_count <= 12:
		base = _GAP_FLOOR_N_11_12
	return maxf(12.0, base)


static func _pair_gap_m(
		r_new: float,
		r_placed: float,
		type_new: int,
		type_placed: int,
		placement_state: int,
		hamlet_count: int,
		gap_scales: Array,
		new_idx: int,
		placed_idx: int) -> float:
	var floor_eff := _gap_floor_m(hamlet_count) \
		* maxf(gap_scales[new_idx] as float, gap_scales[placed_idx] as float)
	var base := maxf(floor_eff, r_new + r_placed)
	var mult := _pair_gap_multiplier(type_new, type_placed, placement_state)
	return base + _pair_jiggle_m(type_new, type_placed, placement_state, hamlet_count) * mult


static func _min_centre_dist_to_placed(centre: Vector2, placed_specs: Array) -> float:
	var min_d := INF
	for ps: Dictionary in placed_specs:
		min_d = minf(min_d, centre.distance_to(ps["centre"] as Vector2))
	return min_d


static func _hamlet_pair_floor_ok(
		centre: Vector2,
		placed_specs: Array,
		placed_types: Array[int],
		personal_radii: Array,
		gap_scales: Array,
		new_idx: int,
		type_new: int,
		placement_state: int,
		hamlet_count: int) -> bool:
	var r_new: float = personal_radii[new_idx]
	for pi: int in placed_specs.size():
		var need := _pair_gap_m(
			r_new, personal_radii[pi], type_new, placed_types[pi], placement_state, hamlet_count,
			gap_scales, new_idx, pi)
		if centre.distance_to(placed_specs[pi]["centre"] as Vector2) < need - 1e-6:
			return false
	return true


static func _hamlet_centroid_from_specs(cottages: Array) -> Vector2:
	var sum := Vector2.ZERO
	for spec: Dictionary in cottages:
		sum += spec["centre"] as Vector2
	return sum / float(maxi(1, cottages.size()))


static func _pairwise_dist_std(specs: Array) -> float:
	if specs.size() < 2:
		return 0.0
	var dists: Array[float] = []
	for i: int in specs.size():
		for j: int in range(i + 1, specs.size()):
			var a: Vector2 = specs[i]["centre"] as Vector2
			var b: Vector2 = specs[j]["centre"] as Vector2
			dists.append(a.distance_to(b))
	var mean := 0.0
	for d: float in dists:
		mean += d
	mean /= float(dists.size())
	var var_sum := 0.0
	for d: float in dists:
		var_sum += (d - mean) * (d - mean)
	return sqrt(var_sum / float(dists.size()))


static func _nn_gap_cv_from_specs(cottages: Array) -> float:
	if cottages.size() < 2:
		return 0.0
	var centres: Array[Vector2] = []
	for spec: Dictionary in cottages:
		centres.append(spec["centre"] as Vector2)
	var dists: Array[float] = []
	for i: int in centres.size():
		var min_d := INF
		for j: int in centres.size():
			if i == j:
				continue
			min_d = minf(min_d, centres[i].distance_to(centres[j]))
		dists.append(min_d)
	var mean := 0.0
	for d: float in dists:
		mean += d
	mean /= float(dists.size())
	var var_sum := 0.0
	for d: float in dists:
		var_sum += (d - mean) * (d - mean)
	var std := sqrt(var_sum / float(dists.size()))
	return std / mean if mean > 1e-6 else 0.0


static func _inv34_ok(cottages: Array) -> bool:
	if cottages.size() < 2:
		return true
	return _nn_gap_cv_from_specs(cottages) >= 0.12


static func _hamlet_pick_yaw(trial: Dictionary) -> Dictionary:
	var best_yaw := 0
	var best_dot := -INF
	for yaw_deg: int in _YAWS:
		trial["yaw_deg"] = yaw_deg
		var door_info := VillageBackdrop.cottage_door(trial)
		var door_pos: Vector2 = door_info[0]
		var door_normal: Vector2 = door_info[1]
		var to_green := VILLAGE_GREEN_G - door_pos
		if to_green.length_squared() < 1e-8:
			continue
		var dot_val: float = door_normal.dot(to_green.normalized())
		if dot_val > best_dot:
			best_dot = dot_val
			best_yaw = yaw_deg
	if best_dot <= _MIN_DOT:
		return {"ok": false}
	return {"ok": true, "yaw": best_yaw, "dot": best_dot}


static func _hamlet_centre_floor_ok(centre: Vector2, placed_specs: Array, min_sep: float = _MIN_CENTRE_SEP_M) -> bool:
	for ps: Dictionary in placed_specs:
		if centre.distance_to(ps["centre"] as Vector2) < min_sep - 1e-6:
			return false
	return true


## INV-31′ anti-ring: std of centroid radii / mean; low ⇒ all houses at one radius (ring).
static func radial_spread_ratio(cottages: Array) -> float:
	if cottages.size() < 2:
		return 0.0
	var c := _hamlet_centroid_from_specs(cottages)
	var dists: Array[float] = []
	for spec: Dictionary in cottages:
		dists.append((spec["centre"] as Vector2).distance_to(c))
	var mean := 0.0
	for d: float in dists:
		mean += d
	mean /= float(dists.size())
	var var_sum := 0.0
	for d: float in dists:
		var_sum += (d - mean) * (d - mean)
	var std := sqrt(var_sum / float(dists.size()))
	return std / mean if mean > 1e-6 else 0.0


## Plaza helpers (generated hamlet consumers + tests).
static func plaza_rect_at(g: Vector2, side_l: float) -> Rect2:
	return Rect2(g.x - side_l * 0.5, g.y - side_l * 0.5, side_l, side_l)


static func plaza_keep_clear_rect(g: Vector2, side_l: float, inset: float = _PLAZA_KEEP_INSET_M) -> Rect2:
	return plaza_rect_at(g, side_l).grow(-inset)


## Cottage grown rects / centres must stay outside loop verge (B2 / INV-8).
static func plaza_cottage_keep_clear_rect(g: Vector2, side_l: float) -> Rect2:
	var inset := _PLAZA_KEEP_INSET_M + _PLAZA_LOOP_CENTERLINE_INSET_M + _PLAZA_COTTAGE_VERGE_M
	return plaza_rect_at(g, side_l).grow(-inset)


static func generated_hero_node() -> int:
	return GENERATED_HAMLET_COUNT


static func graph_node_count_for_hamlet(hamlet_n: int) -> int:
	return hamlet_n + 9


static func plaza_graph_node_index(hamlet_n: int, plaza_local: int) -> int:
	## plaza_local 0..7: corners SW,SE,NE,NW then mids S,E,N,W (see _PLAZA_LOOP_OFFSETS).
	return hamlet_n + 1 + plaza_local


## World positions for generated N+9 graph (doors, hero, plaza ring).
static func build_graph_node_positions(cottages: Array, g: Vector2, plaza_side_l: float) -> PackedVector2Array:
	var n := cottages.size()
	var nodes := PackedVector2Array()
	nodes.resize(n + 9)
	for i: int in n:
		var door_info := VillageBackdrop.cottage_door(cottages[i])
		nodes[i] = door_info[0]
	nodes[n] = HERO_DOOR_STOOP
	var rect := plaza_rect_at(g, plaza_side_l)
	var sw := Vector2(rect.position.x, rect.end.y)
	var se := rect.end
	var ne := Vector2(rect.end.x, rect.position.y)
	var nw := rect.position
	var mid_s := Vector2((rect.position.x + rect.end.x) * 0.5, rect.end.y)
	var mid_e := Vector2(rect.end.x, (rect.position.y + rect.end.y) * 0.5)
	var mid_n := Vector2((rect.position.x + rect.end.x) * 0.5, rect.position.y)
	var mid_w := Vector2(rect.position.x, (rect.position.y + rect.end.y) * 0.5)
	var plaza_pts: Array[Vector2] = [sw, se, ne, nw, mid_s, mid_e, mid_n, mid_w]
	for pi: int in 8:
		nodes[n + 1 + pi] = plaza_pts[pi]
	return nodes


static func plaza_loop_graph_edges(hamlet_n: int) -> Array[Vector2i]:
	var base := hamlet_n + 1
	var order: Array[int] = []
	for off: int in _PLAZA_LOOP_OFFSETS:
		order.append(base + off)
	var edges: Array[Vector2i] = []
	for i: int in order.size():
		var a: int = order[i]
		var b: int = order[(i + 1) % order.size()]
		edges.append(Vector2i(a, b))
	return edges


static func _plaza_mid_s_index(hamlet_n: int) -> int:
	return plaza_graph_node_index(hamlet_n, 4)


static func _plaza_sw_index(hamlet_n: int) -> int:
	return plaza_graph_node_index(hamlet_n, 0)


static func _plaza_se_index(hamlet_n: int) -> int:
	return plaza_graph_node_index(hamlet_n, 1)


## Bearing φ (degrees): 0° = north (−Z), +90° = east (+X) — SD §1.2.
static func bearing_phi_deg(c: Vector2, g: Vector2) -> float:
	return rad_to_deg(atan2(c.x - g.x, -(c.y - g.y)))


static func _centre_from_bearing(g: Vector2, phi_deg: float, r: float) -> Vector2:
	var phi_rad := deg_to_rad(phi_deg)
	return g + Vector2(r * sin(phi_rad), -r * cos(phi_rad))


static func _effective_hamlet_count() -> int:
	if _lab_hamlet_count > 0:
		return _lab_hamlet_count
	return GENERATED_HAMLET_COUNT


static func spacing_gap_floor_m(hamlet_count: int) -> float:
	return _gap_floor_m(hamlet_count)


static func spacing_personal_r_bounds(hamlet_count: int) -> Vector2:
	return _personal_r_bounds_for_count(hamlet_count)


static func _effective_fan_r_out() -> float:
	if _lab_fan_r_out > 0.0:
		return _lab_fan_r_out
	var n := _effective_hamlet_count()
	var base := FAN_R_OUT_N_LE_8 if n <= 8 else FAN_R_OUT
	return minf(41.0, base)


static func _effective_fan_phi_min_deg() -> float:
	if not is_nan(_lab_fan_phi_min_deg):
		return _lab_fan_phi_min_deg
	return FAN_PHI_MIN_DEG


static func _effective_fan_phi_max_deg() -> float:
	if not is_nan(_lab_fan_phi_max_deg):
		return _lab_fan_phi_max_deg
	return FAN_PHI_MAX_DEG


static func _centre_in_fan(c: Vector2, g: Vector2, r_out: float) -> bool:
	var phi := bearing_phi_deg(c, g)
	var phi_min := _effective_fan_phi_min_deg()
	var phi_max := _effective_fan_phi_max_deg()
	if phi < phi_min - 1e-6 or phi > phi_max + 1e-6:
		return false
	var r := c.distance_to(g)
	return r >= FAN_R_IN - 1e-6 and r <= r_out + 1e-6


static func fan_radial_span_m(cottages: Array, g: Vector2) -> float:
	if cottages.is_empty():
		return 0.0
	var min_r := INF
	var max_r := 0.0
	for spec: Dictionary in cottages:
		var r: float = (spec["centre"] as Vector2).distance_to(g)
		min_r = minf(min_r, r)
		max_r = maxf(max_r, r)
	return max_r - min_r


static func fan_angular_coverage_deg(cottages: Array, g: Vector2) -> float:
	if cottages.is_empty():
		return 0.0
	var min_phi := INF
	var max_phi := -INF
	for spec: Dictionary in cottages:
		var phi: float = bearing_phi_deg(spec["centre"] as Vector2, g)
		min_phi = minf(min_phi, phi)
		max_phi = maxf(max_phi, phi)
	return max_phi - min_phi


static func fan_radial_stdev_m(cottages: Array, g: Vector2) -> float:
	if cottages.size() < 2:
		return 0.0
	var radii: Array[float] = []
	for spec: Dictionary in cottages:
		radii.append((spec["centre"] as Vector2).distance_to(g))
	var mean := 0.0
	for r: float in radii:
		mean += r
	mean /= float(radii.size())
	var var_sum := 0.0
	for r: float in radii:
		var_sum += (r - mean) * (r - mean)
	return sqrt(var_sum / float(radii.size()))


static func fan_anti_ring_ok(cottages: Array, g: Vector2) -> bool:
	return fan_radial_span_m(cottages, g) >= 8.0


static func _placement_config_for_attempt(attempt: int) -> Dictionary:
	var sides: Array[float] = [18.0, 17.0, 19.0, 16.0, 20.0, 18.0, 17.0, 19.0]
	var idx := attempt % sides.size()
	return {"g": VILLAGE_GREEN_G, "plaza_side_m": sides[idx]}


static func _hamlet_pick_yaw_plaza(
		trial: Dictionary, centre: Vector2, g: Vector2, plaza_side: float) -> Dictionary:
	var preferred: Array[int] = []
	if centre.y < g.y - 1.0:
		preferred = [180]
	elif centre.x > g.x + 1.0:
		preferred = [270]
	elif centre.x < g.x - 1.0:
		preferred = [90]
	for pass_all: int in 2:
		var candidates: Array = []
		if pass_all == 0 and not preferred.is_empty():
			candidates = preferred.duplicate()
		else:
			for yaw_deg: int in _YAWS:
				candidates.append(yaw_deg)
		var best_yaw := 0
		var best_dot := -INF
		for yaw_deg: int in candidates:
			trial["yaw_deg"] = yaw_deg
			if not _grown_rect_clear_of_plaza(trial, g, plaza_side):
				continue
			var door_info := VillageBackdrop.cottage_door(trial)
			var door_pos: Vector2 = door_info[0]
			var door_normal: Vector2 = door_info[1]
			var to_g := g - door_pos
			if to_g.length_squared() < 1e-8:
				continue
			var dot_val: float = door_normal.dot(to_g.normalized())
			if dot_val > best_dot:
				best_dot = dot_val
				best_yaw = yaw_deg
		if best_dot > _MIN_DOT_GENERATED:
			return {"ok": true, "yaw": best_yaw, "dot": best_dot}
		if preferred.is_empty():
			break
	return {"ok": false}


## Placement-only standoff from plaza grass rect (network handles loop verge).
static func _plaza_placement_exclusion_rect(g: Vector2, side_l: float) -> Rect2:
	return plaza_rect_at(g, side_l).grow(_PLAZA_COTTAGE_VERGE_M)


static func _grown_rect_clear_of_plaza(spec: Dictionary, g: Vector2, plaza_side: float) -> bool:
	var excl := _plaza_placement_exclusion_rect(g, plaza_side)
	var grown := VillageBackdrop.cottage_exterior_rect(spec).grow(_GROW)
	if excl.intersects(grown, false):
		return false
	# Also forbid grown overlap with inner plaza keep (centres stay outside grass).
	var keep := plaza_cottage_keep_clear_rect(g, plaza_side)
	return not keep.intersects(grown, false)


static func _max_grown_corner_dist_from_g(spec: Dictionary, g: Vector2) -> float:
	var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(_GROW)
	var max_d := 0.0
	for corner: Vector2 in [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)]:
		max_d = maxf(max_d, corner.distance_to(g))
	return max_d


static func _hamlet_pond_phase1_ok(placed_specs: Array, g: Vector2, plaza_side: float) -> bool:
	var layout := VillageLayout.new()
	layout.is_generated = true
	layout.hamlet_centre_xz = g
	layout.plaza_side_m = plaza_side
	layout.plaza_rect = plaza_rect_at(g, plaza_side)
	layout.lawn_radius = GENERATED_LAWN_RADIUS
	layout.pond_cottage_clearance_m = GENERATED_POND_COTTAGE_CLEARANCE_M
	layout.pond_path_clearance_m = GENERATED_POND_PATH_CLEARANCE_M
	layout.stone_seed = 1
	for spec: Dictionary in placed_specs:
		layout.cottages.append(spec)
	return VillagePondPlacement.has_phase1_slot(layout)


static func _hamlet_body_geometry_ok(
		trial: Dictionary,
		placed_rects: Array[Rect2],
		placed_specs: Array,
		g: Vector2,
		plaza_side: float,
		r_out: float) -> bool:
	var centre: Vector2 = trial["centre"] as Vector2
	if not _centre_in_fan(centre, g, r_out):
		return false
	var excl := _plaza_placement_exclusion_rect(g, plaza_side)
	if excl.has_point(centre):
		return false
	var yaw_pick := _hamlet_pick_yaw_plaza(trial, centre, g, plaza_side)
	if not yaw_pick["ok"]:
		return false
	trial["yaw_deg"] = yaw_pick["yaw"]
	var grown_rect := VillageBackdrop.cottage_exterior_rect(trial).grow(_GROW)
	if _rect2_dist_from_origin(grown_rect) < _KEEP_OUT:
		return false
	if _max_grown_corner_dist_from_g(trial, g) > HAMLET_MAX_CORNER_FROM_G:
		return false
	for pr: Rect2 in placed_rects:
		if grown_rect.intersects(pr, false):
			return false
	return true


static func _sample_fan_dart(
		st: int, g: Vector2, r_out: float, inner_band: bool, hero_leg_bias: bool = false) -> Dictionary:
	st = VillageScatterPositions.lcg_step(st)
	var phi: float
	var r: float
	if hero_leg_bias:
		st = VillageScatterPositions.lcg_step(st)
		var side: float = 1.0 if VillageScatterPositions.lcg_f01(st) > 0.5 else -1.0
		st = VillageScatterPositions.lcg_step(st)
		var t_leg: float = VillageScatterPositions.lcg_f01(st)
		phi = side * lerpf(_HERO_LEG_PHI_DEG, FAN_PHI_MAX_DEG, pow(t_leg, 0.65))
		st = VillageScatterPositions.lcg_step(st)
		var t_r: float = VillageScatterPositions.lcg_f01(st)
		r = lerpf(FAN_R_IN, minf(_HERO_LEG_R_MAX, r_out), pow(t_r, 1.2))
	else:
		var t_phi: float = VillageScatterPositions.lcg_f01(st)
		phi = lerpf(_effective_fan_phi_min_deg(), _effective_fan_phi_max_deg(), t_phi)
		st = VillageScatterPositions.lcg_step(st)
		var u_r: float = VillageScatterPositions.lcg_f01(st)
		if inner_band:
			u_r = pow(u_r, _FAN_INNER_U_EXTRA_POW)
		u_r = pow(u_r, _FAN_RADIAL_BIAS_POW)
		r = FAN_R_IN + (r_out - FAN_R_IN) * u_r
	var centre := _centre_from_bearing(g, phi, r)
	return {"centre": centre, "state": st}


static func _build_type_order(st: int, hamlet_count: int) -> Dictionary:
	var n_types := VillageBackdrop.COTTAGES.size()
	var order: Array[int] = []
	if hamlet_count == n_types:
		for i: int in n_types:
			order.append(i)
		for i: int in range(order.size() - 1, 0, -1):
			st = VillageScatterPositions.lcg_step(st)
			var j: int = int(VillageScatterPositions.lcg_f01(st) * float(i + 1))
			j = clampi(j, 0, i)
			var tmp: int = order[i]
			order[i] = order[j]
			order[j] = tmp
	else:
		for i: int in hamlet_count:
			order.append(i % n_types)
		for i: int in range(order.size() - 1, 0, -1):
			st = VillageScatterPositions.lcg_step(st)
			var j: int = int(VillageScatterPositions.lcg_f01(st) * float(i + 1))
			j = clampi(j, 0, i)
			var tmp: int = order[i]
			order[i] = order[j]
			order[j] = tmp
	return {"order": order, "state": st}


## Seeded cosmetic deltas on duplicated COTTAGES archetypes (generated hamlet only).
static func _apply_hamlet_kit_variety(st: int, spec: Dictionary, slot_i: int) -> Dictionary:
	st = VillageScatterPositions.lcg_step(st ^ (slot_i * 131 + 17))
	var roll := VillageScatterPositions.lcg_f01(st)
	st = VillageScatterPositions.lcg_step(st)
	var out: Dictionary = spec.duplicate(true)
	# Optional yard clutter — does not alter INV-13 type fingerprint (bays/door/brick/chimney).
	if roll < 0.38:
		out["yard_prop"] = "Prop_Crate"
	return {"spec": out, "state": st}


static func _lattice_site_valid(centre: Vector2, g: Vector2, plaza_side: float) -> bool:
	var phi := bearing_phi_deg(centre, g)
	if phi < FAN_PHI_MIN_DEG - 0.01 or phi > FAN_PHI_MAX_DEG + 0.01:
		return false
	var r := centre.distance_to(g)
	if r < LATTICE_R_IN or r > LATTICE_R_OUT:
		return false
	return not _plaza_placement_exclusion_rect(g, plaza_side).has_point(centre)


static func _centres_collinear(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab := b - a
	var ac := c - a
	if ab.length_squared() < 1e-4 or ac.length_squared() < 1e-4:
		return false
	return absf(ab.x * ac.y - ab.y * ac.x) / (ab.length() * ac.length()) < 0.08


static func _build_hex_lattice_sites(st: int, g: Vector2, rot_attempt: int) -> Dictionary:
	st = VillageScatterPositions.lcg_step(st ^ (rot_attempt * 7919))
	var phi_shift := (VillageScatterPositions.lcg_f01(st) - 0.5) * 24.0
	st = VillageScatterPositions.lcg_step(st)
	var ring_step := HOUSE_SPACING_M * 0.866
	var sites: Array[Vector2] = []
	var r := LATTICE_R_IN
	while r <= LATTICE_R_OUT + 0.01:
		var arc := TAU * r * (FAN_PHI_MAX_DEG - FAN_PHI_MIN_DEG) / 360.0
		var n_phi := maxi(3, int(round(arc / HOUSE_SPACING_M)))
		for pi: int in n_phi:
			st = VillageScatterPositions.lcg_step(st)
			var t := float(pi) / float(maxi(1, n_phi - 1))
			var phi := lerpf(FAN_PHI_MIN_DEG, FAN_PHI_MAX_DEG, t) + phi_shift
			var centre := _centre_from_bearing(g, phi, r)
			st = VillageScatterPositions.lcg_step(st)
			var jx := (VillageScatterPositions.lcg_f01(st) - 0.5) * 2.0 * _LATTICE_JITTER_M
			st = VillageScatterPositions.lcg_step(st)
			var jy := (VillageScatterPositions.lcg_f01(st) - 0.5) * 2.0 * _LATTICE_JITTER_M
			sites.append(centre + Vector2(jx, jy))
		r += ring_step
	return {"sites": sites, "state": st}


static func _pick_lattice_centres(
		valid: Array[Vector2], target_n: int, g: Vector2, st: int) -> Array[Vector2]:
	var picked: Array[Vector2] = []
	if valid.is_empty():
		return picked
	var by_r: Array = []
	for c: Vector2 in valid:
		by_r.append({"c": c, "r": c.distance_to(g)})
	by_r.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["r"]) < float(b["r"]))
	picked.append(by_r[0]["c"] as Vector2)
	for _frame: int in 2:
		var best_i := -1
		var best_sep := -1.0
		for k: int in range(1, mini(by_r.size(), 24)):
			var cand: Vector2 = by_r[k]["c"]
			if picked.has(cand):
				continue
			var min_sep := INF
			for p: Vector2 in picked:
				var a1 := atan2(p.x - g.x, -(p.y - g.y))
				var a2 := atan2(cand.x - g.x, -(cand.y - g.y))
				min_sep = minf(min_sep, absf(a1 - a2))
			if min_sep > best_sep:
				best_sep = min_sep
				best_i = k
		if best_i >= 0:
			picked.append(by_r[best_i]["c"] as Vector2)
	var pool: Array[Vector2] = []
	for k: int in range(by_r.size()):
		var c: Vector2 = by_r[k]["c"]
		if not picked.has(c):
			pool.append(c)
	for _i: int in pool.size() - 1:
		st = VillageScatterPositions.lcg_step(st)
		var j := int(VillageScatterPositions.lcg_f01(st) * float(_i + 1))
		j = clampi(j, 0, _i)
		var tmp: Vector2 = pool[_i]
		pool[_i] = pool[j]
		pool[j] = tmp
	while picked.size() < target_n and not pool.is_empty():
		var best_idx := -1
		var best_score := -1.0
		for pi: int in pool.size():
			var cand: Vector2 = pool[pi]
			if picked.size() >= 2:
				var col := false
				for a: int in picked.size():
					for b: int in range(a + 1, picked.size()):
						if _centres_collinear(picked[a], picked[b], cand):
							col = true
							break
					if col:
						break
				if col:
					continue
			var r: float = cand.distance_to(g)
			var score := pow(maxf(0.01, LATTICE_R_OUT - r), 1.3)
			if score > best_score:
				best_score = score
				best_idx = pi
		if best_idx < 0:
			best_idx = 0
		picked.append(pool[best_idx])
		pool.remove_at(best_idx)
	return picked


static func _specs_from_lattice_centres(
		centres: Array[Vector2], g: Vector2, plaza_side: float, st: int, hamlet_count: int) -> Dictionary:
	var type_shuffle := _build_type_order(st, hamlet_count)
	st = type_shuffle["state"]
	var type_order: Array = type_shuffle["order"]
	var specs: Array = []
	var rects: Array[Rect2] = []
	for i: int in centres.size():
		var type_idx: int = type_order[i]
		var spec: Dictionary = VillageBackdrop.COTTAGES[type_idx].duplicate()
		spec["centre"] = centres[i]
		var yaw_pick := _hamlet_pick_yaw_plaza(spec, centres[i], g, plaza_side)
		if not yaw_pick["ok"]:
			return {"ok": false, "state": st}
		spec["yaw_deg"] = yaw_pick["yaw"]
		var kit := _apply_hamlet_kit_variety(st, spec, i)
		st = kit["state"]
		spec = kit["spec"]
		var grown := VillageBackdrop.cottage_exterior_rect(spec).grow(_GROW)
		if _rect2_dist_from_origin(grown) < _KEEP_OUT:
			return {"ok": false, "state": st}
		for pr: Rect2 in rects:
			if grown.intersects(pr, false):
				return {"ok": false, "state": st}
		for j: int in range(i):
			if centres[i].distance_to(centres[j]) < _MIN_CENTRE_GAP_SANITY_M - 1e-3:
				return {"ok": false, "state": st}
		specs.append(spec)
		rects.append(grown)
	return {"ok": true, "specs": specs, "state": st}


## Jittered hex lattice subset (generated hamlet).
static func _place_hex_lattice_hamlet(
		placement_state: int,
		g: Vector2 = VILLAGE_GREEN_G,
		plaza_side: float = PLAZA_SIDE_L,
		rot_attempt: int = 0) -> Dictionary:
	if _test_max_darts == 0:
		return {"cottages": [], "cottage_rings": [], "ok": false, "state": placement_state}

	var hamlet_count := _effective_hamlet_count()
	var st := placement_state
	var lattice := _build_hex_lattice_sites(st, g, rot_attempt)
	st = lattice["state"]
	var valid: Array[Vector2] = []
	for c_raw in lattice["sites"]:
		var c: Vector2 = c_raw
		if _lattice_site_valid(c, g, plaza_side):
			valid.append(c)
	if valid.size() < hamlet_count:
		return {"cottages": [], "cottage_rings": [], "ok": false, "state": st}
	var centres := _pick_lattice_centres(valid, hamlet_count, g, st)
	if centres.size() != hamlet_count:
		return {"cottages": [], "cottage_rings": [], "ok": false, "state": st}
	var built := _specs_from_lattice_centres(centres, g, plaza_side, st, hamlet_count)
	st = built["state"]
	if not built["ok"]:
		return {"cottages": [], "cottage_rings": [], "ok": false, "state": st}
	var specs: Array = built["specs"]
	if not _hamlet_pond_phase1_ok(specs, g, plaza_side):
		return {"cottages": [], "cottage_rings": [], "ok": false, "state": st}
	return {"cottages": specs, "cottage_rings": [], "ok": true, "state": st}


## Lab alias — hex lattice placement.
static func _place_fan_hamlet(
		placement_state: int,
		g: Vector2 = VILLAGE_GREEN_G,
		plaza_side: float = PLAZA_SIDE_L) -> Dictionary:
	return _place_hex_lattice_hamlet(placement_state, g, plaza_side, 0)


## Shortest distance from the world origin (0, 0) to the nearest point on `rect`.
## Used for the keep-out test (INV-1). rect must have non-negative size (always
## true after Rect2.grow()).
static func _max_grown_corner_dist_from_origin(spec: Dictionary) -> float:
	var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(_GROW)
	var max_d := 0.0
	for corner: Vector2 in [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)]:
		max_d = maxf(max_d, corner.length())
	return max_d


static func _rect2_dist_from_origin(rect: Rect2) -> float:
	var nx := clampf(0.0, rect.position.x, rect.end.x)
	var ny := clampf(0.0, rect.position.y, rect.end.y)
	return sqrt(nx * nx + ny * ny)


## Build the full MST + loop path network (S3).
##
## `cottages` — 7-element cottage spec array (same shape as VillageBackdrop.COTTAGES).
## `cottage_rings` — parallel ring-assignment array (0=inner, 1=outer).
## `_pathgraph_state` — reserved for future per-seed bend variation; currently unused.
##
## Returns {paths: Array of Array[Vector2], edges: Array[Vector2i], ok: bool}.
## ok=false when an MST edge cannot clear cottages or too few loop edges survive.
## Classic door → hero-ring polylines (one per cottage), avoiding pond bank clearance.
static func build_radial_hero_paths(
		cottages: Array,
		pond_center: Vector2,
		path_clearance_m: float = VillagePondSite.PATH_CLEARANCE_M) -> Array:
	var cottage_rects: Array[Rect2] = []
	for spec: Dictionary in cottages:
		cottage_rects.append(VillageBackdrop.cottage_exterior_rect(spec).grow(_PATH_COTTAGE_GROW))
	var out: Array = []
	var bend_sign := 1.0
	for ci: int in range(cottages.size()):
		var spec: Dictionary = cottages[ci]
		var door := VillageBackdrop.cottage_door(spec)
		var stoop: Vector2 = door[0] + door[1] * 0.5
		var turn: Vector2 = door[0] + door[1] * 2.0
		var finish: Vector2 = turn.normalized() * _HERO_RING_CLIP
		var route_part := _route_edge(
			turn, finish, _BEZIER_BASE_BEND * bend_sign,
			cottage_rects, [ci], true, true, pond_center, path_clearance_m)
		bend_sign = -bend_sign
		var poly: Array
		if route_part.is_empty():
			var dir := (finish - turn).normalized()
			var mid: Vector2 = (turn + finish) * 0.5 + Vector2(-dir.y, dir.x) * 0.7 * -bend_sign
			poly = [stoop, turn, mid, finish]
		else:
			poly = [stoop, turn]
			for ri: int in range(1, route_part.size()):
				poly.append(route_part[ri])
		out.append(poly)
	return out


const _CROSSING_GRID_CELL_M := 4.0


static func _polyline_self_crosses(poly: Array) -> bool:
	if poly.size() < 4:
		return false
	for i: int in range(poly.size() - 1):
		var a0: Vector2 = poly[i]
		var a1: Vector2 = poly[i + 1]
		for j: int in range(i + 2, poly.size() - 1):
			if j == i + 1:
				continue
			if _segment_pair_crosses(a0, a1, poly[j], poly[j + 1]):
				return true
	return false


## True if any segment of `poly` crosses any segment of polylines already in `paths`.
static func _polyline_crosses_paths(poly: Array, paths: Array) -> bool:
	if poly.size() < 2 or paths.is_empty():
		return false
	for si: int in range(poly.size() - 1):
		var a0: Vector2 = poly[si]
		var a1: Vector2 = poly[si + 1]
		for poly_raw in paths:
			var other := poly_raw as Array
			for j: int in range(other.size() - 1):
				if _segment_pair_crosses(a0, a1, other[j] as Vector2, other[j + 1] as Vector2):
					return true
	return false


static func _segment_aabb_cells(a0: Vector2, a1: Vector2, cell_m: float) -> Array:
	var out: Array = []
	var min_x := minf(a0.x, a1.x)
	var max_x := maxf(a0.x, a1.x)
	var min_y := minf(a0.y, a1.y)
	var max_y := maxf(a0.y, a1.y)
	var ix0 := int(floor(min_x / cell_m))
	var ix1 := int(floor(max_x / cell_m))
	var iy0 := int(floor(min_y / cell_m))
	var iy1 := int(floor(max_y / cell_m))
	for ix: int in range(ix0, ix1 + 1):
		for iy: int in range(iy0, iy1 + 1):
			out.append(Vector2i(ix, iy))
	return out


## Early-exit crossing test (hot path in generate / scrub).
static func path_polylines_has_crossing(paths: Array) -> bool:
	var segs: Array = []
	for poly_raw in paths:
		var poly := poly_raw as Array
		for i: int in range(poly.size() - 1):
			segs.append([poly[i] as Vector2, poly[i + 1] as Vector2])
	var n := segs.size()
	if n < 2:
		return false
	var cell_m := _CROSSING_GRID_CELL_M
	var grid: Dictionary = {}
	for si: int in range(n):
		for cell: Vector2i in _segment_aabb_cells(segs[si][0], segs[si][1], cell_m):
			var key := "%d,%d" % [cell.x, cell.y]
			if not grid.has(key):
				grid[key] = []
			(grid[key] as Array).append(si)
	for si: int in range(n):
		var seen: Dictionary = {}
		for cell: Vector2i in _segment_aabb_cells(segs[si][0], segs[si][1], cell_m):
			var key := "%d,%d" % [cell.x, cell.y]
			if not grid.has(key):
				continue
			for sj_raw in grid[key]:
				var sj: int = int(sj_raw)
				if sj <= si:
					continue
				var pair_key := "%d,%d" % [si, sj]
				if seen.has(pair_key):
					continue
				seen[pair_key] = true
				if _segment_pair_crosses(
						segs[si][0], segs[si][1], segs[sj][0], segs[sj][1]):
					return true
	return false


## True if `poly` crosses any path in `paths` except index `skip_pi`.
static func _polyline_crosses_other_paths(
		poly: Array, paths: Array, skip_pi: int) -> bool:
	for pi: int in range(paths.size()):
		if pi == skip_pi:
			continue
		var other := paths[pi] as Array
		for i: int in range(poly.size() - 1):
			var a0: Vector2 = poly[i]
			var a1: Vector2 = poly[i + 1]
			for j: int in range(other.size() - 1):
				if _segment_pair_crosses(a0, a1, other[j] as Vector2, other[j + 1] as Vector2):
					return true
	return false


static func _empty_crossing_grid() -> Dictionary:
	return {"cell_m": _CROSSING_GRID_CELL_M, "grid": {}, "segs": []}


static func _crossing_grid_add_poly(cross_g: Dictionary, poly: Array) -> void:
	if poly.size() < 2:
		return
	var segs: Array = cross_g["segs"]
	var grid: Dictionary = cross_g["grid"]
	var cell_m: float = cross_g["cell_m"]
	for i: int in range(poly.size() - 1):
		var si := segs.size()
		segs.append([poly[i] as Vector2, poly[i + 1] as Vector2])
		for cell: Vector2i in _segment_aabb_cells(
				poly[i] as Vector2, poly[i + 1] as Vector2, cell_m):
			var key := "%d,%d" % [cell.x, cell.y]
			if not grid.has(key):
				grid[key] = []
			(grid[key] as Array).append(si)


static func _polyline_crosses_crossing_grid(poly: Array, cross_g: Dictionary) -> bool:
	if poly.size() < 2:
		return false
	var segs: Array = cross_g["segs"]
	if segs.is_empty():
		return false
	var cell_m: float = cross_g["cell_m"]
	var grid: Dictionary = cross_g["grid"]
	for i: int in range(poly.size() - 1):
		var a0: Vector2 = poly[i]
		var a1: Vector2 = poly[i + 1]
		var seen: Dictionary = {}
		for cell: Vector2i in _segment_aabb_cells(a0, a1, cell_m):
			var key := "%d,%d" % [cell.x, cell.y]
			if not grid.has(key):
				continue
			for si_raw in grid[key]:
				var si: int = int(si_raw)
				if seen.has(si):
					continue
				seen[si] = true
				var seg := segs[si] as Array
				if _segment_pair_crosses(a0, a1, seg[0] as Vector2, seg[1] as Vector2):
					return true
	return false


static func _polyline_crosses_existing(
		poly: Array, paths: Array, cross_g: Dictionary = {}) -> bool:
	if not cross_g.is_empty():
		return _polyline_crosses_crossing_grid(poly, cross_g)
	return _polyline_crosses_paths(poly, paths)


## Segment–segment crossing count across path polylines (shared endpoints allowed).
static func path_polylines_crossing_count(paths: Array) -> int:
	var segs: Array = []
	for poly_raw in paths:
		var poly := poly_raw as Array
		for i: int in range(poly.size() - 1):
			segs.append([poly[i] as Vector2, poly[i + 1] as Vector2])
	var n := segs.size()
	if n < 2:
		return 0
	var cell_m := _CROSSING_GRID_CELL_M
	var grid: Dictionary = {}
	for si: int in range(n):
		for cell: Vector2i in _segment_aabb_cells(segs[si][0], segs[si][1], cell_m):
			var key := "%d,%d" % [cell.x, cell.y]
			if not grid.has(key):
				grid[key] = []
			(grid[key] as Array).append(si)
	var crosses := 0
	for si: int in range(n):
		var seen: Dictionary = {}
		for cell: Vector2i in _segment_aabb_cells(segs[si][0], segs[si][1], cell_m):
			var key := "%d,%d" % [cell.x, cell.y]
			if not grid.has(key):
				continue
			for sj_raw in grid[key]:
				var sj: int = int(sj_raw)
				if sj <= si:
					continue
				var pair_key := "%d,%d" % [si, sj]
				if seen.has(pair_key):
					continue
				seen[pair_key] = true
				var a0: Vector2 = segs[si][0]
				var a1: Vector2 = segs[si][1]
				var b0: Vector2 = segs[sj][0]
				var b1: Vector2 = segs[sj][1]
				if _segment_pair_crosses(a0, a1, b0, b1):
					crosses += 1
	return crosses


static func _is_door_spur_edge(e: Vector2i, hamlet_n: int) -> bool:
	return (e.x < hamlet_n and e.y >= hamlet_n + 1) or (e.y < hamlet_n and e.x >= hamlet_n + 1)


static func _first_crossing_path_pair(paths: Array) -> Vector2i:
	var segs: Array = []
	for pi: int in range(paths.size()):
		var poly := paths[pi] as Array
		for i: int in range(poly.size() - 1):
			segs.append([pi, poly[i] as Vector2, poly[i + 1] as Vector2])
	var n := segs.size()
	if n < 2:
		return Vector2i(-1, -1)
	var cell_m := _CROSSING_GRID_CELL_M
	var grid: Dictionary = {}
	for si: int in range(n):
		var pi: int = int(segs[si][0])
		var a0: Vector2 = segs[si][1]
		var a1: Vector2 = segs[si][2]
		for cell: Vector2i in _segment_aabb_cells(a0, a1, cell_m):
			var key := "%d,%d" % [cell.x, cell.y]
			if not grid.has(key):
				grid[key] = []
			(grid[key] as Array).append(si)
	for si: int in range(n):
		var pi_a: int = int(segs[si][0])
		var a0: Vector2 = segs[si][1]
		var a1: Vector2 = segs[si][2]
		var seen: Dictionary = {}
		for cell: Vector2i in _segment_aabb_cells(a0, a1, cell_m):
			var key := "%d,%d" % [cell.x, cell.y]
			if not grid.has(key):
				continue
			for sj_raw in grid[key]:
				var sj: int = int(sj_raw)
				if sj <= si:
					continue
				var pi_b: int = int(segs[sj][0])
				if pi_a == pi_b:
					continue
				var pair_key := "%d,%d" % [mini(pi_a, pi_b), maxi(pi_a, pi_b)]
				if seen.has(pair_key):
					continue
				seen[pair_key] = true
				var b0: Vector2 = segs[sj][1]
				var b1: Vector2 = segs[sj][2]
				if _segment_pair_crosses(a0, a1, b0, b1):
					return Vector2i(mini(pi_a, pi_b), maxi(pi_a, pi_b))
	return Vector2i(-1, -1)


static func _paths_excluding(paths: Array, skip_pi: int) -> Array:
	var out: Array = []
	for pi: int in range(paths.size()):
		if pi != skip_pi:
			out.append(paths[pi])
	return out


static func _touch_up_path_inv8(
		paths: Array,
		pi: int,
		final_edges: Array[Vector2i],
		hamlet_n: int,
		obs_cache: Dictionary,
		nodes: PackedVector2Array,
		door_normals: Array[Vector2],
		g: Vector2,
		plaza_side_m: float) -> void:
	var e: Vector2i = final_edges[pi]
	var ep := _edge_endpoint_indices(e, hamlet_n)
	var cottage_rects: Array[Rect2] = obs_cache["cottage_check_rects"]
	if _is_door_spur_edge(e, hamlet_n):
		if _polyline_inv8_violates(paths[pi], ep, cottage_rects):
			_repair_one_door_spur_inv8(
				paths, final_edges, pi, hamlet_n, nodes, door_normals,
				obs_cache, g, plaza_side_m, 0)
	else:
		paths[pi] = _nudge_polyline_inv8_samples(paths[pi], ep, cottage_rects)
		if _polyline_inv8_violates(paths[pi], ep, cottage_rects):
			paths[pi] = _prune_polyline_inv8_samples(paths[pi], ep, obs_cache)


static func _reroute_mandatory_path_index(
		paths: Array,
		final_edges: Array[Vector2i],
		pi: int,
		hamlet_n: int,
		nodes: PackedVector2Array,
		door_normals: Array[Vector2],
		cottage_rects: Array[Rect2],
		obs_cache: Dictionary,
		g: Vector2,
		plaza_side_m: float,
		pathgraph_state: int,
		bend_sign: float) -> bool:
	var e: Vector2i = final_edges[pi]
	var others := _paths_excluding(paths, pi)
	var pg := pathgraph_state
	if _is_door_spur_edge(e, hamlet_n):
		var di := e.x if e.x < hamlet_n else e.y
		var plaza_idx := e.y if e.x == di else e.x
		var ep := _edge_endpoint_indices(e, hamlet_n)
		for try_i: int in range(8):
			pg = VillageScatterPositions.lcg_step(pg ^ (try_i + pi * 31))
			var bs := bend_sign if try_i % 2 == 0 else -bend_sign
			var poly := _build_door_spur_poly(
				di, plaza_idx, hamlet_n, nodes, g, plaza_side_m, door_normals, cottage_rects,
				obs_cache, others, pg, bs)
			if poly.is_empty():
				continue
			if _polyline_crosses_paths(poly, others):
				continue
			if _polyline_inv8_violates(poly, ep, cottage_rects):
				continue
			paths[pi] = poly
			return true
		return false
	if e.x == hamlet_n or e.y == hamlet_n:
		for try_i: int in range(4):
			pg = VillageScatterPositions.lcg_step(pg ^ (try_i + 113))
			var bs := bend_sign if try_i % 2 == 0 else -bend_sign
			var poly := _build_hero_to_plaza_poly(
				hamlet_n, nodes, g, plaza_side_m, obs_cache, others, pg, bs)
			if poly.is_empty() or _polyline_crosses_paths(poly, others):
				continue
			paths[pi] = poly
			return true
		return false
	var is_loop := _is_plaza_graph_node(e.x, hamlet_n) and _is_plaza_graph_node(e.y, hamlet_n)
	var poly_loop := _build_loop_or_hero_poly(e, hamlet_n, nodes, g, obs_cache, others, is_loop)
	if poly_loop.is_empty() or _polyline_crosses_paths(poly_loop, others):
		return false
	paths[pi] = poly_loop
	return true


## Rebuild every door spur (straight / meander fallbacks) to fix INV-8 or crossings.
static func _rebuild_all_mandatory_door_spurs(
		paths: Array,
		final_edges: Array[Vector2i],
		mandatory_count: int,
		hamlet_n: int,
		nodes: PackedVector2Array,
		door_normals: Array[Vector2],
		cottage_rects: Array[Rect2],
		obs_cache: Dictionary,
		g: Vector2,
		plaza_side_m: float,
		pathgraph_state: int,
		max_tries_per_spur: int = 8) -> void:
	var spur_rects := _spur_obstacle_rects(obs_cache)
	var mcount := mini(mandatory_count, paths.size())
	for pi: int in range(mcount):
		var e: Vector2i = final_edges[pi]
		if not _is_door_spur_edge(e, hamlet_n):
			continue
		var di := e.x if e.x < hamlet_n else e.y
		var plaza_idx := e.y if e.x == di else e.x
		var ep := _edge_endpoint_indices(e, hamlet_n)
		var stoop: Vector2 = nodes[di] + door_normals[di] * 0.5
		var target: Vector2 = _inset_plaza_point(nodes[plaza_idx], g, _PLAZA_LOOP_CENTERLINE_INSET_M)
		var others := _paths_excluding(paths, pi)
		var best: Array = []
		var pg := pathgraph_state ^ (pi * 41)
		for try_i: int in range(maxi(1, max_tries_per_spur)):
			pg = VillageScatterPositions.lcg_step(pg ^ try_i)
			var bs := 1.0 if try_i % 2 == 0 else -1.0
			var poly := _build_door_spur_poly(
				di, plaza_idx, hamlet_n, nodes, g, plaza_side_m, door_normals, cottage_rects,
				obs_cache, others, pg, bs)
			if poly.is_empty() or _polyline_crosses_paths(poly, others):
				continue
			if _polyline_inv8_violates(poly, ep, obs_cache["cottage_check_rects"]):
				continue
			best = poly
			break
		if not best.is_empty():
			paths[pi] = best


## Reroute later door/hero spurs after scrub/collapse introduced a crossing.
static func _resolve_mandatory_path_crossings(
		paths: Array,
		final_edges: Array[Vector2i],
		mandatory_count: int,
		hamlet_n: int,
		_cottages: Array,
		nodes: PackedVector2Array,
		door_normals: Array[Vector2],
		obs_cache: Dictionary,
		g: Vector2,
		plaza_side_m: float,
		pathgraph_state: int,
		max_attempts: int = 8) -> void:
	var cottage_rects: Array[Rect2] = obs_cache["cottage_check_rects"]
	var mcount := mini(mandatory_count, paths.size())
	for attempt: int in range(maxi(1, max_attempts)):
		if not path_polylines_has_crossing(paths):
			return
		while paths.size() > mcount:
			paths.pop_back()
			final_edges.pop_back()
		var pair := _first_crossing_path_pair(paths)
		if pair.x < 0:
			return
		var pi_a := pair.x
		var pi_b := pair.y
		var reroute_pi := pi_b
		var e_b: Vector2i = final_edges[pi_b]
		var e_a: Vector2i = final_edges[pi_a]
		if _is_door_spur_edge(e_a, hamlet_n) and not _is_door_spur_edge(e_b, hamlet_n):
			reroute_pi = pi_a
		elif _is_door_spur_edge(e_b, hamlet_n):
			reroute_pi = pi_b
		var bs := 1.0 if attempt % 2 == 0 else -1.0
		var pg := VillageScatterPositions.lcg_step(pathgraph_state ^ (attempt * 17 + reroute_pi))
		if not _reroute_mandatory_path_index(
				paths, final_edges, reroute_pi, hamlet_n, nodes, door_normals,
				cottage_rects, obs_cache, g, plaza_side_m, pg, bs):
			continue
		_touch_up_path_inv8(
			paths, reroute_pi, final_edges, hamlet_n, obs_cache,
			nodes, door_normals, g, plaza_side_m)


static func _polyline_crosses_any(poly: Array, paths: Array) -> bool:
	for i: int in range(poly.size() - 1):
		var a0: Vector2 = poly[i]
		var a1: Vector2 = poly[i + 1]
		for poly_raw in paths:
			var other := poly_raw as Array
			for j: int in range(other.size() - 1):
				if _segment_pair_crosses(a0, a1, other[j] as Vector2, other[j + 1] as Vector2):
					return true
	return false


static func _crossing_probe_poly(poly: Array) -> Array:
	if poly.size() <= 4:
		return poly
	var out: Array = [poly[0]]
	var stride := maxi(1, (poly.size() - 2) / 6)
	for i: int in range(1, poly.size() - 1, stride):
		out.append(poly[i])
	out.append(poly[-1])
	return out


static func _polyline_crosses_segment_list(poly: Array, segments: Array) -> bool:
	var probe := _crossing_probe_poly(poly)
	for i: int in range(probe.size() - 1):
		var a0: Vector2 = probe[i]
		var a1: Vector2 = probe[i + 1]
		for seg_raw in segments:
			var seg := seg_raw as Array
			if _segment_pair_crosses(a0, a1, seg[0] as Vector2, seg[1] as Vector2):
				return true
	return false


## Dense polylines (meander resample): test every segment, not the coarse probe.
static func _polyline_crosses_segment_list_dense(poly: Array, segments: Array) -> bool:
	for i: int in range(poly.size() - 1):
		var a0: Vector2 = poly[i]
		var a1: Vector2 = poly[i + 1]
		for seg_raw in segments:
			var seg := seg_raw as Array
			if _segment_pair_crosses(a0, a1, seg[0] as Vector2, seg[1] as Vector2):
				return true
	return false


static func _append_crossing_segments(poly: Array, segments: Array) -> void:
	for i: int in range(poly.size() - 1):
		segments.append([poly[i], poly[i + 1]])


static func _segment_pair_crosses(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	if a0.distance_to(b0) < 0.05 or a0.distance_to(b1) < 0.05 \
			or a1.distance_to(b0) < 0.05 or a1.distance_to(b1) < 0.05:
		return false
	return Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null


static func _inset_plaza_point(p: Vector2, g: Vector2, inset_m: float) -> Vector2:
	var v := p - g
	if v.length_squared() < 1e-8:
		return p
	return p - v.normalized() * inset_m


static func _door_spur_facing_plaza_local(centre: Vector2, g: Vector2) -> int:
	var dx := centre.x - g.x
	var dy := centre.y - g.y
	if dy < -1.0 and absf(dy) >= absf(dx):
		return 6
	if dy > 1.0 and absf(dy) >= absf(dx):
		return 4
	if dx > 1.0 and absf(dx) >= absf(dy):
		return 5
	if dx < -1.0 and absf(dx) >= absf(dy):
		return 7
	if dy < 0.0:
		return 6
	return 4


static func _door_spur_alternate_locals(primary_local: int) -> Array[int]:
	match primary_local:
		6:
			return [3, 2]
		4:
			return [0, 1]
		5:
			return [1, 2]
		7:
			return [0, 3]
		_:
			return []


static func _circular_deg_delta(a_deg: float, b_deg: float) -> float:
	var d := absf(a_deg - b_deg)
	return minf(d, 360.0 - d)


static func _plaza_nodes_ranked_by_phi(g: Vector2, plaza_side_m: float, hamlet_n: int) -> Array:
	var ring := _plaza_ring_points(g, plaza_side_m)
	var out: Array = []
	for local: int in 8:
		var p: Vector2 = ring[local]
		out.append({
			"local": local,
			"idx": plaza_graph_node_index(hamlet_n, local),
			"phi": bearing_phi_deg(p, g),
			"pos": p,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["phi"]) < float(b["phi"]))
	return out


## Plaza locals a door may use (south arc for |φ|>75°; else primary + alternates).
static func _door_allowed_plaza_locals(centre: Vector2, g: Vector2) -> Array[int]:
	var phi := bearing_phi_deg(centre, g)
	if absf(phi) >= _DOOR_SOUTH_PHI_ABS_DEG:
		return [0, 1, 4, 3, 7]
	var primary := _door_spur_facing_plaza_local(centre, g)
	var out: Array[int] = [primary]
	for alt: int in _door_spur_alternate_locals(primary):
		if not out.has(alt):
			out.append(alt)
	return out


## Monotone φ-order door → plaza graph node (non-crossing straight spurs by geometry).
static func assign_monotone_door_plaza_spurs(
		cottages: Array, g: Vector2, plaza_side_m: float) -> Array[Vector2i]:
	var n := cottages.size()
	var plaza_ranked := _plaza_nodes_ranked_by_phi(g, plaza_side_m, n)
	var doors: Array = []
	for di: int in n:
		var door_pt: Vector2 = VillageBackdrop.cottage_door(cottages[di])[0]
		doors.append({
			"di": di,
			"phi": bearing_phi_deg(door_pt, g),
			"allowed": _door_allowed_plaza_locals(cottages[di]["centre"] as Vector2, g),
		})
	doors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["phi"]) < float(b["phi"]))
	var last_slot := 0
	var pairs: Array[Vector2i] = []
	for rec_raw in doors:
		var rec: Dictionary = rec_raw
		var di: int = int(rec["di"])
		var phi_d: float = float(rec["phi"])
		var allowed: Array = rec["allowed"]
		var pick_slot := last_slot
		var pick_dist := INF
		for slot: int in range(last_slot, plaza_ranked.size()):
			var pl: Dictionary = plaza_ranked[slot]
			if not allowed.has(int(pl["local"])):
				continue
			var dist := _circular_deg_delta(phi_d, float(pl["phi"]))
			if dist < pick_dist:
				pick_dist = dist
				pick_slot = slot
		if pick_dist == INF:
			for slot: int in range(last_slot, plaza_ranked.size()):
				var pl2: Dictionary = plaza_ranked[slot]
				var dist2 := _circular_deg_delta(phi_d, float(pl2["phi"]))
				if dist2 < pick_dist:
					pick_dist = dist2
					pick_slot = slot
		var target_idx: int = int(plaza_ranked[pick_slot]["idx"])
		pairs.append(Vector2i(di, target_idx))
		last_slot = pick_slot
	return pairs


static func _polyline_length(poly: Array) -> float:
	var len := 0.0
	for i: int in range(poly.size() - 1):
		len += (poly[i] as Vector2).distance_to(poly[i + 1])
	return len


## Max perpendicular distance from polyline samples to the chord first→last (metres).
static func polyline_max_lateral_deviation(poly: Array) -> float:
	if poly.size() < 2:
		return 0.0
	var a: Vector2 = poly[0]
	var b: Vector2 = poly[-1]
	var chord := b - a
	var clen := chord.length()
	if clen < 1e-6:
		return 0.0
	var perp := Vector2(-chord.y, chord.x) / clen
	var max_dev := 0.0
	for pt_raw in poly:
		var p: Vector2 = pt_raw
		max_dev = maxf(max_dev, absf((p - a).dot(perp)))
	return max_dev


## True when a door spur polyline lacks the gentle meander contract (deviation or len/chord).
static func door_spur_is_straight_fallback(poly: Array) -> bool:
	if poly.size() < 2:
		return true
	return polyline_max_lateral_deviation(poly) < 1.0 \
			or polyline_len_over_chord(poly) < 1.08


## Count door spurs on a generated layout that fell back to near-straight routing.
static func count_straight_door_spurs(layout: VillageLayout) -> int:
	if layout.fallback:
		return -1
	var n := layout.cottages.size()
	var hero := generated_hero_node()
	var mcount := mandatory_path_count(layout.edges, n)
	var straight := 0
	for pi: int in layout.paths.size():
		if pi >= layout.edges.size():
			break
		if path_edge_kind(layout.edges[pi], n, hero, pi, mcount, layout.path_kinds) != "door_spur":
			continue
		if door_spur_is_straight_fallback(layout.paths[pi] as Array):
			straight += 1
	return straight


## Arc length divided by chord length (≥ 1.0 for non-degenerate open polylines).
static func polyline_len_over_chord(poly: Array) -> float:
	if poly.size() < 2:
		return 1.0
	var a: Vector2 = poly[0]
	var b: Vector2 = poly[-1]
	var chord := a.distance_to(b)
	if chord < 1e-6:
		return 1.0
	return _polyline_length(poly) / chord


static func _is_door_door_edge(e: Vector2i, hamlet_n: int) -> bool:
	return e.x < hamlet_n and e.y < hamlet_n


static func _edge_endpoint_indices(e: Vector2i, hamlet_n: int) -> Array[int]:
	var ep: Array[int] = []
	if e.x < hamlet_n:
		ep.append(e.x)
	if e.y < hamlet_n:
		ep.append(e.y)
	return ep


static func _scenic_edge_count(edges: Array[Vector2i], hamlet_n: int) -> int:
	var c := 0
	for e: Vector2i in edges:
		if _is_door_door_edge(e, hamlet_n):
			c += 1
	return c


## Remove interior centreline samples that violate INV-8 (endpoints preserved).
static func _prune_polyline_inv8_samples(poly: Array, endpoint_indices: Array[int], obs_cache: Dictionary) -> Array:
	if poly.size() < 3:
		return poly
	var out: Array = poly.duplicate()
	var cottage_rects: Array[Rect2] = obs_cache["cottage_check_rects"]
	var changed := true
	var removals := 0
	const _MAX_INV8_PRUNE_REMOVES := 6
	while changed and out.size() >= 3 and removals < _MAX_INV8_PRUNE_REMOVES:
		changed = false
		for i: int in range(1, out.size() - 1):
			var pt := out[i] as Vector2
			for ci: int in range(cottage_rects.size()):
				if endpoint_indices.has(ci):
					continue
				if _pt_dist_to_rect(pt, cottage_rects[ci]) < _PATH_CLEARANCE:
					out.remove_at(i)
					removals += 1
					changed = true
					break
			if changed:
				break
	return out


static func _scrub_layout_paths_inv8(
		paths: Array,
		final_edges: Array[Vector2i],
		mandatory_count: int,
		hamlet_n: int,
		obs_cache: Dictionary,
		nodes: PackedVector2Array = PackedVector2Array(),
		door_normals: Array[Vector2] = [],
		g: Vector2 = VILLAGE_GREEN_G,
		plaza_side_m: float = PLAZA_SIDE_L) -> void:
	for pi: int in range(paths.size() - 1, mandatory_count - 1, -1):
		var ep_drop := _edge_endpoint_indices(final_edges[pi], hamlet_n)
		if not _polyline_vertices_clear_cached(paths[pi], ep_drop, obs_cache):
			paths.remove_at(pi)
			final_edges.remove_at(pi)
	for pi: int in range(mini(mandatory_count, paths.size())):
		var ep := _edge_endpoint_indices(final_edges[pi], hamlet_n)
		var before: Array = (paths[pi] as Array).duplicate()
		paths[pi] = _prune_polyline_inv8_samples(paths[pi], ep, obs_cache)
		if _polyline_crosses_other_paths(paths[pi], paths, pi):
			var cottage_rects: Array[Rect2] = obs_cache["cottage_check_rects"]
			if _polyline_inv8_violates(before, ep, cottage_rects):
				pass
			else:
				paths[pi] = before
	var cottage_rects: Array[Rect2] = obs_cache["cottage_check_rects"]
	var need_inv8_touch := false
	for pi: int in range(mini(mandatory_count, paths.size())):
		var ep := _edge_endpoint_indices(final_edges[pi], hamlet_n)
		if _polyline_inv8_violates(paths[pi], ep, cottage_rects):
			need_inv8_touch = true
			break
	if not need_inv8_touch:
		return
	if nodes.size() > 0 and door_normals.size() == hamlet_n:
		_repair_inv8_clipping_spurs(
			paths, final_edges, mandatory_count, hamlet_n,
			nodes, door_normals, obs_cache, g, plaza_side_m)
	for pi: int in range(mini(mandatory_count, paths.size())):
		var e: Vector2i = final_edges[pi]
		if _is_door_spur_edge(e, hamlet_n):
			continue
		var ep := _edge_endpoint_indices(e, hamlet_n)
		if _polyline_inv8_violates(paths[pi], ep, cottage_rects):
			paths[pi] = _nudge_polyline_inv8_samples(paths[pi], ep, cottage_rects)


## Nudge/prune door spurs for INV-8 without collapsing to chord (preserve meander).
static func _soft_inv8_fixup_door_spurs(
		paths: Array,
		final_edges: Array[Vector2i],
		mandatory_count: int,
		hamlet_n: int,
		obs_cache: Dictionary) -> void:
	var cottage_rects: Array[Rect2] = obs_cache["cottage_check_rects"]
	for pi: int in range(mini(mandatory_count, paths.size())):
		var e: Vector2i = final_edges[pi]
		if not _is_door_spur_edge(e, hamlet_n):
			continue
		var ep := _edge_endpoint_indices(e, hamlet_n)
		if not _polyline_inv8_violates(paths[pi], ep, cottage_rects):
			continue
		var before: Array = (paths[pi] as Array).duplicate()
		paths[pi] = _nudge_polyline_inv8_samples(paths[pi], ep, cottage_rects)
		if _polyline_crosses_other_paths(paths[pi], paths, pi):
			paths[pi] = before


static func _nudge_mandatory_loop_paths_inv8(
		paths: Array,
		final_edges: Array[Vector2i],
		mandatory_count: int,
		hamlet_n: int,
		obs_cache: Dictionary) -> void:
	var cottage_rects: Array[Rect2] = obs_cache["cottage_check_rects"]
	for pi: int in range(mini(mandatory_count, paths.size())):
		var e: Vector2i = final_edges[pi]
		if _is_door_spur_edge(e, hamlet_n):
			continue
		var ep := _edge_endpoint_indices(e, hamlet_n)
		if _polyline_inv8_violates(paths[pi], ep, cottage_rects):
			paths[pi] = _nudge_polyline_inv8_samples(paths[pi], ep, cottage_rects)


## Push interior samples away from cottage grown rects (preserve meander shape).
static func _nudge_polyline_inv8_samples(
		poly: Array, endpoint_indices: Array[int], cottage_rects: Array[Rect2]) -> Array:
	var out: Array = (poly as Array).duplicate()
	for _pass: int in range(8):
		var moved := false
		for i: int in range(1, out.size() - 1):
			var pt: Vector2 = out[i]
			for ci: int in range(cottage_rects.size()):
				if endpoint_indices.has(ci):
					continue
				var d := _pt_dist_to_rect(pt, cottage_rects[ci])
				if d >= _PATH_CLEARANCE:
					continue
				var rect: Rect2 = cottage_rects[ci]
				var cx := clampf(pt.x, rect.position.x, rect.end.x)
				var cy := clampf(pt.y, rect.position.y, rect.end.y)
				var closest := Vector2(cx, cy)
				var away := pt - closest
				if away.length_squared() < 1e-8:
					away = Vector2(1.0, 0.0)
				out[i] = pt + away.normalized() * (_PATH_CLEARANCE - d + 0.05)
				moved = true
				break
			if moved:
				break
		if not moved:
			break
	return out


static func _collapse_polyline_until_inv8_clear(
		poly: Array, endpoint_indices: Array[int], cottage_rects: Array[Rect2]) -> Array:
	var out: Array = (poly as Array).duplicate()
	while out.size() > 2 and _polyline_inv8_violates(out, endpoint_indices, cottage_rects):
		var worst_i := -1
		var worst_dist := INF
		for i: int in range(1, out.size() - 1):
			var pt: Vector2 = out[i]
			for ci: int in range(cottage_rects.size()):
				if endpoint_indices.has(ci):
					continue
				var d := _pt_dist_to_rect(pt, cottage_rects[ci])
				if d < worst_dist:
					worst_dist = d
					worst_i = i
		if worst_i < 0:
			break
		out.remove_at(worst_i)
	if out.size() >= 2 and _polyline_inv8_violates(out, endpoint_indices, cottage_rects):
		var chord: Array = [out[0], out[-1]]
		if not _polyline_inv8_violates(chord, endpoint_indices, cottage_rects):
			return chord
	return out


## Re-route clipping door spurs with alternate meander seeds (never collapse to chord).
static func _repair_inv8_clipping_spurs(
		paths: Array,
		final_edges: Array[Vector2i],
		mandatory_count: int,
		hamlet_n: int,
		nodes: PackedVector2Array,
		door_normals: Array[Vector2],
		obs_cache: Dictionary,
		g: Vector2,
		plaza_side_m: float,
		pathgraph_state: int = 0) -> void:
	for pi: int in range(mini(mandatory_count, paths.size())):
		var e: Vector2i = final_edges[pi]
		if not _is_door_spur_edge(e, hamlet_n):
			continue
		var ep := _edge_endpoint_indices(e, hamlet_n)
		if not _polyline_inv8_violates(paths[pi], ep, obs_cache["cottage_check_rects"]):
			continue
		_repair_one_door_spur_inv8(
			paths, final_edges, pi, hamlet_n, nodes, door_normals,
			obs_cache, g, plaza_side_m, pathgraph_state)


static func _repair_one_door_spur_inv8(
		paths: Array,
		final_edges: Array[Vector2i],
		pi: int,
		hamlet_n: int,
		nodes: PackedVector2Array,
		door_normals: Array[Vector2],
		obs_cache: Dictionary,
		g: Vector2,
		plaza_side_m: float,
		pathgraph_state: int) -> void:
	var cottage_rects: Array[Rect2] = obs_cache["cottage_check_rects"]
	var e: Vector2i = final_edges[pi]
	var di := e.x if e.x < hamlet_n else e.y
	var plaza_idx := e.y if e.x == di else e.x
	var ep := _edge_endpoint_indices(e, hamlet_n)
	var others: Array = _paths_excluding(paths, pi)
	var pg := pathgraph_state ^ (pi * 53 + di * 7)
	for try_i: int in range(8):
		pg = VillageScatterPositions.lcg_step(pg ^ try_i)
		var bs := 1.0 if try_i % 2 == 0 else -1.0
		var poly := _build_door_spur_poly(
			di, plaza_idx, hamlet_n, nodes, g, plaza_side_m, door_normals, cottage_rects,
			obs_cache, others, pg, bs)
		if poly.is_empty():
			continue
		if _polyline_crosses_paths(poly, others):
			continue
		if _polyline_inv8_violates(poly, ep, cottage_rects):
			continue
		paths[pi] = poly
		return
	var nudged := _nudge_polyline_inv8_samples(paths[pi], ep, cottage_rects)
	if not _polyline_crosses_paths(nudged, others) \
			and not _polyline_inv8_violates(nudged, ep, cottage_rects) \
			and not door_spur_is_straight_fallback(nudged):
		paths[pi] = nudged


## Drop failing scenic edges; reroute mandatory polylines until INV-8 samples pass.
static func _network_mandatory_inv8_ok(
		paths: Array,
		final_edges: Array[Vector2i],
		mandatory_count: int,
		n: int,
		hero_i: int,
		nodes: PackedVector2Array,
		g: Vector2,
		door_normals: Array[Vector2],
		cottage_rects: Array[Rect2],
		obs_cache: Dictionary,
		path_clearance_m: float,
		pathgraph_state: int) -> bool:
	_scrub_layout_paths_inv8(paths, final_edges, mandatory_count, n, obs_cache)
	var pg_st := pathgraph_state
	for pi: int in range(mandatory_count):
		var ep := _edge_endpoint_indices(final_edges[pi], n)
		if _polyline_vertices_clear_cached(paths[pi], ep, obs_cache):
			continue
		var e: Vector2i = final_edges[pi]
		var is_loop := _is_plaza_graph_node(e.x, n) and _is_plaza_graph_node(e.y, n)
		var fixed := false
		for try_i: int in 12:
			pg_st = VillageScatterPositions.lcg_step(pg_st ^ (try_i + pi * 5))
			var bs := 1.0 if try_i % 2 == 0 else -1.0
			var routed := _route_graph_edge(
				e, n, hero_i, nodes, g, door_normals, cottage_rects, obs_cache, pg_st,
				path_clearance_m, bs, is_loop)
			var poly: Array = routed["poly"]
			if poly.is_empty():
				var pa: Vector2 = nodes[e.x]
				var pb: Vector2 = nodes[e.y]
				if is_loop:
					pa = _inset_plaza_point(pa, g, _PLAZA_LOOP_CENTERLINE_INSET_M)
					pb = _inset_plaza_point(pb, g, _PLAZA_LOOP_CENTERLINE_INSET_M)
				poly = _route_edge(
					pa, pb, _BEZIER_BASE_BEND * bs, cottage_rects, ep, false, true,
					obs_cache["pond_center"], path_clearance_m)
				if poly.is_empty():
					poly = _route_edge_fast(
						pa, pb, _BEZIER_BASE_BEND * bs, ep, obs_cache, false, not is_loop)
			if poly.is_empty():
				continue
			if _polyline_vertices_clear_cached(poly, ep, obs_cache):
				paths[pi] = poly
				fixed = true
				break
		if not fixed:
			return false
	return true


## Prune scenic paths that fail INV-8 samples; reroute mandatory edges if needed.
static func _network_finalize_paths(
		paths: Array,
		final_edges: Array[Vector2i],
		mandatory_count: int,
		n: int,
		hero_i: int,
		nodes: PackedVector2Array,
		g: Vector2,
		door_normals: Array[Vector2],
		cottage_rects: Array[Rect2],
		obs_cache: Dictionary,
		path_clearance_m: float,
		pathgraph_state: int) -> bool:
	for pi: int in range(paths.size() - 1, mandatory_count - 1, -1):
		var ep := _edge_endpoint_indices(final_edges[pi], n)
		if not _polyline_vertices_clear_cached(paths[pi], ep, obs_cache):
			paths.remove_at(pi)
			final_edges.remove_at(pi)
	if _scenic_edge_count(final_edges, n) < _MIN_SCENIC_LOOPS:
		return false
	var pg_st := pathgraph_state
	for pi: int in range(mandatory_count):
		var ep := _edge_endpoint_indices(final_edges[pi], n)
		if _polyline_vertices_clear_cached(paths[pi], ep, obs_cache):
			continue
		var e: Vector2i = final_edges[pi]
		var is_loop := _is_plaza_graph_node(e.x, n) and _is_plaza_graph_node(e.y, n)
		var fixed := false
		for try_i: int in 6:
			pg_st = VillageScatterPositions.lcg_step(pg_st ^ (try_i + pi * 5))
			var bs := 1.0 if try_i % 2 == 0 else -1.0
			var routed := _route_graph_edge(
				e, n, hero_i, nodes, g, door_normals, cottage_rects, obs_cache, pg_st,
				path_clearance_m, bs, is_loop)
			var poly: Array = routed["poly"]
			if poly.is_empty():
				var pa: Vector2 = nodes[e.x]
				var pb: Vector2 = nodes[e.y]
				if is_loop:
					pa = _inset_plaza_point(pa, g, _PLAZA_LOOP_CENTERLINE_INSET_M)
					pb = _inset_plaza_point(pb, g, _PLAZA_LOOP_CENTERLINE_INSET_M)
				poly = _route_edge_fast(
					pa, pb, _BEZIER_BASE_BEND * bs, ep, obs_cache, false, not is_loop)
			if poly.is_empty():
				continue
			if _polyline_vertices_clear_cached(poly, ep, obs_cache):
				paths[pi] = poly
				fixed = true
				break
		if not fixed:
			return false
	return true


static func _angular_neighbor_door_pairs(cottages: Array, g: Vector2) -> Array[Vector2i]:
	var ranked: Array = []
	for i: int in cottages.size():
		ranked.append({
			"i": i,
			"phi": bearing_phi_deg(cottages[i]["centre"] as Vector2, g),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["phi"]) < float(b["phi"]))
	var out: Array[Vector2i] = []
	for k: int in range(ranked.size() - 1):
		out.append(Vector2i(int(ranked[k]["i"]), int(ranked[k + 1]["i"])))
	return out


## Returns false if `poly` is empty or crosses existing paths (unless allow_cross).
static func _push_network_path(
		poly: Array,
		e: Vector2i,
		paths: Array,
		final_edges: Array[Vector2i],
		allow_cross: bool = false,
		cross_g: Dictionary = {}) -> bool:
	if poly.size() < 2:
		return false
	if _polyline_self_crosses(poly):
		return false
	if not allow_cross and _polyline_crosses_existing(poly, paths, cross_g):
		return false
	paths.append(poly)
	final_edges.append(e)
	if not cross_g.is_empty():
		_crossing_grid_add_poly(cross_g, poly)
	return true


static func _drop_scenic_paths_until_clear(
		paths: Array,
		final_edges: Array[Vector2i],
		mandatory_count: int) -> void:
	while paths.size() > mandatory_count and path_polylines_has_crossing(paths):
		paths.pop_back()
		final_edges.pop_back()


static func _coarse_poly_clears(
		coarse: Array,
		endpoint_indices: Array[int],
		obs_cache: Dictionary,
		paths: Array) -> bool:
	if coarse.size() < 2:
		return false
	if not _polyline_clears_obstacles_cached(coarse, endpoint_indices, obs_cache):
		return false
	if _polyline_crosses_existing(coarse, paths, obs_cache.get("cross_g", {})):
		return false
	return true


static func _waypoint_around_cottage_rect(
		a: Vector2, b: Vector2, ci: int, obs_cache: Dictionary) -> Vector2:
	var rect: Rect2 = obs_cache["clearance_rects"][ci]
	var centre := rect.get_center()
	var mid := (a + b) * 0.5
	var out_dir := (mid - centre).normalized()
	if out_dir.length_squared() < 1e-6:
		out_dir = Vector2(0.0, 1.0)
	return centre + out_dir * (maxf(rect.size.x, rect.size.y) * 0.65 + 0.8)


static func _plaza_radial_gate(door: Vector2, g: Vector2, plaza_side_m: float) -> Vector2:
	var dir := (door - g)
	if dir.length_squared() < 1e-6:
		dir = Vector2(0.0, 1.0)
	else:
		dir = dir.normalized()
	var rect := plaza_rect_at(g, plaza_side_m).grow(2.2)
	for step: int in range(8, 90):
		var p := g + dir * float(step)
		if not rect.has_point(p):
			return p
	return g + dir * 22.0


static func _shorten_toward_plaza_border(
		stoop: Vector2, target: Vector2, g: Vector2, plaza_side_m: float) -> Vector2:
	var rect := plaza_rect_at(g, plaza_side_m)
	for t: float in [1.0, 0.85, 0.7, 0.55, 0.4, 0.25]:
		var p := stoop.lerp(target, t)
		if rect.has_point(p):
			return p
	# nearest point on rect border from stoop
	var nx := clampf(stoop.x, rect.position.x, rect.end.x)
	var ny := clampf(stoop.y, rect.position.y, rect.end.y)
	if rect.has_point(stoop):
		return Vector2(nx, ny)
	return target


static func _spur_obstacle_rects(obs_cache: Dictionary) -> Array[Rect2]:
	var grow := maxf(0.0, _SPUR_COTTAGE_CLEAR_M - _PATH_COTTAGE_GROW)
	var out: Array[Rect2] = []
	for rect: Rect2 in obs_cache["cottage_check_rects"]:
		out.append(rect.grow(grow))
	return out


static func _spur_polyline_ok(
		coarse: Array,
		ep: Array[int],
		obs_cache: Dictionary,
		spur_rects: Array[Rect2]) -> bool:
	if coarse.size() < 2:
		return false
	for si: int in range(coarse.size() - 1):
		var a: Vector2 = coarse[si]
		var b: Vector2 = coarse[si + 1]
		for ci: int in spur_rects.size():
			if ep.has(ci):
				continue
			if not _segment_clears_inflated_rect(a, b, spur_rects[ci]):
				return false
		if not _segment_clears_obstacles_cached(a, b, ep, obs_cache):
			return false
	return true


static func _spur_meander_poly_ok(
		poly: Array,
		ep: Array[int],
		obs_cache: Dictionary,
		spur_rects: Array[Rect2]) -> bool:
	if poly.size() < 2:
		return false
	for si: int in range(poly.size() - 1):
		var a: Vector2 = poly[si]
		var b: Vector2 = poly[si + 1]
		for ci: int in spur_rects.size():
			if ep.has(ci):
				continue
			if not _segment_clears_inflated_rect(a, b, spur_rects[ci]):
				return false
		if not _segment_clears_obstacles_cached(a, b, ep, obs_cache):
			return false
	if not _polyline_vertices_clear_cached(poly, ep, obs_cache):
		return false
	var clearance: Array = obs_cache.get("clearance_rects", [])
	for idx: int in range(1, poly.size()):
		var pt: Vector2 = poly[idx]
		for rect_raw in clearance:
			if (rect_raw as Rect2).has_point(pt):
				return false
	return true


static func _door_spur_shape_ok(poly: Array, min_dev: float, min_ratio: float) -> bool:
	if poly.size() < 2:
		return false
	if polyline_max_lateral_deviation(poly) < min_dev:
		return false
	if polyline_len_over_chord(poly) < min_ratio:
		return false
	return _polyline_length(poly) >= 3.0


static func _try_door_spur_coarse(
		coarse: Array,
		ep: Array[int],
		obs_cache: Dictionary,
		spur_rects: Array[Rect2],
		paths: Array,
		min_dev: float,
		min_ratio: float) -> Array:
	if not _spur_polyline_ok(coarse, ep, obs_cache, spur_rects):
		return []
	var poly := _finalize_network_poly(coarse)
	if not _spur_meander_poly_ok(poly, ep, obs_cache, spur_rects):
		return []
	if _polyline_self_crosses(poly):
		return []
	if not _door_spur_shape_ok(poly, min_dev, min_ratio):
		return []
	if _polyline_crosses_existing(poly, paths, obs_cache.get("cross_g", {})):
		return []
	return poly


## Door stoop → plaza loop vertex (meandering route with Bézier / waypoint fallback).
static func _build_door_spur_poly(
		door_i: int,
		plaza_idx: int,
		n: int,
		nodes: PackedVector2Array,
		g: Vector2,
		plaza_side_m: float,
		door_normals: Array[Vector2],
		cottage_rects: Array[Rect2],
		obs_cache: Dictionary,
		paths: Array,
		pathgraph_state: int,
		bend_sign: float) -> Array:
	var ep: Array[int] = [door_i]
	var stoop: Vector2 = nodes[door_i] + door_normals[door_i] * 0.5
	var target: Vector2 = _inset_plaza_point(nodes[plaza_idx], g, _PLAZA_LOOP_CENTERLINE_INSET_M)
	var spur_rects := _spur_obstacle_rects(obs_cache)
	var pond_center: Vector2 = obs_cache["pond_center"]
	var path_clearance_m: float = obs_cache["pond_path_clearance_m"]
	var chord := target - stoop
	var pg_try := pathgraph_state
	for try_i: int in _PATH_ROUTE_ATTEMPTS:
		pg_try = VillageScatterPositions.lcg_step(pg_try ^ (try_i + door_i * 13 + plaza_idx))
		var bs := bend_sign if try_i % 2 == 0 else -bend_sign
		var poly: Array = _route_meandering_edge(
			stoop, target, pg_try, cottage_rects, ep,
			pond_center, path_clearance_m, bs, obs_cache)
		if poly.is_empty():
			poly = _route_edge_fast(
				stoop, target, _BEZIER_BASE_BEND * bs, ep, obs_cache, false, false)
		if poly.is_empty():
			continue
		if not _spur_meander_poly_ok(poly, ep, obs_cache, spur_rects):
			continue
		if _polyline_self_crosses(poly):
			continue
		if not _door_spur_shape_ok(poly, 1.0, 1.08):
			continue
		if _polyline_crosses_existing(poly, paths, obs_cache.get("cross_g", {})):
			continue
		return poly
	if chord.length_squared() > 1e-4:
		var perp := Vector2(-chord.y, chord.x).normalized()
		for sign: float in [1.0, -1.0]:
			for mag: float in [1.0, 2.0, 3.0]:
				var wp := stoop.lerp(target, 0.5) + perp * _SPUR_BEND_MAX_M * sign * mag
				var got := _try_door_spur_coarse(
					[stoop, wp, target], ep, obs_cache, spur_rects, paths, 1.0, 1.08)
				if not got.is_empty():
					return got
			for scale: float in [2.0]:
				var w1 := stoop.lerp(target, 0.3) + perp * _SPUR_BEND_MAX_M * sign * scale
				var w2 := stoop.lerp(target, 0.7) - perp * _SPUR_BEND_MAX_M * sign * scale * 0.85
				var got_s := _try_door_spur_coarse(
					[stoop, w1, w2, target], ep, obs_cache, spur_rects, paths, 1.0, 1.08)
				if not got_s.is_empty():
					return got_s
	for ci: int in spur_rects.size():
		if ep.has(ci):
			continue
		if not _segment_clears_inflated_rect(stoop, target, spur_rects[ci]):
			var wp2 := _waypoint_around_cottage_rect(stoop, target, ci, obs_cache)
			var got_w := _try_door_spur_coarse(
				[stoop, wp2, target], ep, obs_cache, spur_rects, paths, 1.0, 1.08)
			if not got_w.is_empty():
				return got_w
	if chord.length_squared() > 1e-4:
		var perp_t := Vector2(-chord.y, chord.x).normalized()
		for sign: float in [1.0, -1.0]:
			var wp := stoop.lerp(target, 0.5) + perp_t * _SPUR_BEND_MAX_M * sign * 0.75
			var got_t := _try_door_spur_coarse(
				[stoop, wp, target], ep, obs_cache, spur_rects, paths, 1.0, 1.08)
			if not got_t.is_empty():
				return got_t
	if _spur_polyline_ok([stoop, target], ep, obs_cache, spur_rects):
		return _finalize_network_poly([stoop, target])
	return _finalize_network_poly([stoop, stoop.lerp(target, 0.5), target])


static func _spur_resampled_poly_ok(
		poly: Array,
		ep: Array[int],
		obs_cache: Dictionary,
		spur_rects: Array[Rect2]) -> bool:
	if poly.size() < 2:
		return false
	var coarse: Array = []
	for p_raw in poly:
		coarse.append(p_raw)
	return _spur_polyline_ok(coarse, ep, obs_cache, spur_rects)


static func _build_hero_to_plaza_poly(
		n: int,
		nodes: PackedVector2Array,
		g: Vector2,
		plaza_side_m: float,
		obs_cache: Dictionary,
		paths: Array,
		pathgraph_state: int,
		bend_sign: float) -> Array:
	var hero_i := n
	var e := Vector2i(hero_i, _plaza_mid_s_index(n))
	var ep := _edge_endpoint_indices(e, n)
	var pa: Vector2 = nodes[hero_i]
	var pb: Vector2 = _inset_plaza_point(nodes[e.y], g, _PLAZA_LOOP_CENTERLINE_INSET_M)
	var cottage_rects: Array[Rect2] = obs_cache["cottage_check_rects"]
	var pond_center: Vector2 = obs_cache["pond_center"]
	var path_clearance_m: float = obs_cache["pond_path_clearance_m"]
	var pg_try := pathgraph_state
	for try_i: int in _PATH_ROUTE_ATTEMPTS:
		pg_try = VillageScatterPositions.lcg_step(pg_try ^ (try_i + 97))
		var bs := bend_sign if try_i % 2 == 0 else -bend_sign
		var poly: Array = _route_meandering_edge(
			pa, pb, pg_try, cottage_rects, ep,
			pond_center, path_clearance_m, bs, obs_cache)
		if poly.is_empty():
			poly = _route_edge_fast(pa, pb, _BEZIER_BASE_BEND * bs, ep, obs_cache, false, false)
		if poly.is_empty():
			continue
		if _polyline_crosses_existing(poly, paths, obs_cache.get("cross_g", {})):
			continue
		if not _polyline_vertices_clear_cached(poly, ep, obs_cache):
			continue
		return poly
	var via_w := Vector2(g.x - plaza_side_m * 0.55, g.y + plaza_side_m * 0.15)
	var via_s := Vector2(g.x, pb.y + 1.2)
	var candidates: Array = [
		[pa, via_w, pb],
		[pa, via_s, pb],
		[pa, via_w, via_s, pb],
		[pa, pb],
	]
	for coarse_raw in candidates:
		var coarse: Array = coarse_raw
		if _coarse_poly_clears(coarse, ep, obs_cache, paths):
			return _finalize_network_poly(coarse)
	return _build_loop_or_hero_poly(e, n, nodes, g, obs_cache, paths, false)


static func _build_loop_or_hero_poly(
		e: Vector2i,
		n: int,
		nodes: PackedVector2Array,
		g: Vector2,
		obs_cache: Dictionary,
		paths: Array,
		is_loop: bool) -> Array:
	var ep := _edge_endpoint_indices(e, n)
	var pa: Vector2 = nodes[e.x]
	var pb: Vector2 = nodes[e.y]
	if is_loop:
		pa = _inset_plaza_point(pa, g, _PLAZA_LOOP_CENTERLINE_INSET_M)
		pb = _inset_plaza_point(pb, g, _PLAZA_LOOP_CENTERLINE_INSET_M)
	var coarse: Array = [pa, pb]
	if _coarse_poly_clears(coarse, ep, obs_cache, paths):
		return _finalize_network_poly(coarse)
	var chord := pb - pa
	if chord.length_squared() > 1e-4:
		var perp := Vector2(-chord.y, chord.x).normalized()
		for sign: float in [1.0, -1.0]:
			for frac: float in [0.25, 0.4, 0.55, 0.7]:
				for mag: float in [1.0, 2.0, 3.0]:
					var wp := pa.lerp(pb, frac) + perp * _SPUR_BEND_MAX_M * sign * mag
					var bent: Array = [pa, wp, pb]
					if _coarse_poly_clears(bent, ep, obs_cache, paths):
						return _finalize_network_poly(bent)
	return _finalize_network_poly(coarse)


static func _plaza_ring_points(g: Vector2, plaza_side_m: float) -> Array[Vector2]:
	var rect := plaza_rect_at(g, plaza_side_m)
	return [
		Vector2(rect.position.x, rect.end.y),
		rect.end,
		Vector2(rect.end.x, rect.position.y),
		rect.position,
		Vector2((rect.position.x + rect.end.x) * 0.5, rect.end.y),
		Vector2(rect.end.x, (rect.position.y + rect.end.y) * 0.5),
		Vector2((rect.position.x + rect.end.x) * 0.5, rect.position.y),
		Vector2(rect.position.x, (rect.position.y + rect.end.y) * 0.5),
	]


static func _build_network(
		cottages: Array,
		pathgraph_state: int,
		pond_center: Vector2,
		path_clearance_m: float = VillagePondSite.PATH_CLEARANCE_M,
		g: Vector2 = VILLAGE_GREEN_G,
		plaza_side_m: float = PLAZA_SIDE_L) -> Dictionary:
	if _test_force_network_fail:
		return {"paths": [], "edges": [], "nodes": PackedVector2Array(), "ok": false}

	var n := cottages.size()
	var hero_i := n
	var nodes := build_graph_node_positions(cottages, g, plaza_side_m)
	var door_normals: Array[Vector2] = _network_door_normals(cottages)
	var cottage_rects: Array[Rect2] = _network_cottage_rects(cottages)
	var obs_cache := _make_network_obstacle_cache(cottage_rects, pond_center, path_clearance_m)
	var cross_g := _empty_crossing_grid()
	obs_cache["cross_g"] = cross_g
	if _net_profile_enabled:
		_net_profile_acc["builds"] = int(_net_profile_acc.get("builds", 0)) + 1

	var paths: Array = []
	var final_edges: Array[Vector2i] = []

	for e: Vector2i in plaza_loop_graph_edges(n):
		var lp := _build_loop_or_hero_poly(e, n, nodes, g, obs_cache, paths, true)
		if not _push_network_path(lp, e, paths, final_edges, false, cross_g):
			return {
				"paths": [], "edges": [], "nodes": nodes,
				"ok": false, "fail_reason": "plaza_crossing", "mandatory_count": 0,
			}

	var spur_pairs := assign_monotone_door_plaza_spurs(cottages, g, plaza_side_m)
	spur_pairs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pa: Vector2 = VillageBackdrop.cottage_door(cottages[a.x])[0]
		var pb: Vector2 = VillageBackdrop.cottage_door(cottages[b.x])[0]
		return bearing_phi_deg(pa, g) < bearing_phi_deg(pb, g))
	var pg_st := pathgraph_state
	var bend_sign := 1.0
	for sp: Vector2i in spur_pairs:
		var di := sp.x
		var plaza_idx := sp.y
		var e := Vector2i(di, plaza_idx)
		var chosen: Array = []
		var best_dev := -1.0
		var straight_fallback: Array = []
		for try_i: int in range(4):
			var pg_alt := VillageScatterPositions.lcg_step(
				pg_st ^ (di * 17 + plaza_idx + try_i * 31))
			var bs := bend_sign if try_i % 2 == 0 else -bend_sign
			var cand := _build_door_spur_poly(
				di, plaza_idx, n, nodes, g, plaza_side_m, door_normals, cottage_rects,
				obs_cache, paths, pg_alt, bs)
			if cand.is_empty() or _polyline_crosses_paths(cand, paths):
				continue
			if straight_fallback.is_empty():
				straight_fallback = cand
			if door_spur_is_straight_fallback(cand):
				continue
			var dev := polyline_max_lateral_deviation(cand)
			if dev > best_dev:
				best_dev = dev
				chosen = cand
		if chosen.is_empty():
			chosen = straight_fallback
		if chosen.is_empty() or not _push_network_path(
				chosen, e, paths, final_edges, false, cross_g):
			return {
				"paths": [],
				"edges": [],
				"nodes": nodes,
				"ok": false,
				"fail_reason": "spur_crossing",
				"mandatory_count": 0,
			}
		pg_st = VillageScatterPositions.lcg_step(pg_st)
		bend_sign = -bend_sign

	for e: Vector2i in [Vector2i(hero_i, _plaza_mid_s_index(n))]:
		var hp := _build_hero_to_plaza_poly(
			n, nodes, g, plaza_side_m, obs_cache, paths, pg_st, bend_sign)
		if not _push_network_path(hp, e, paths, final_edges, false, cross_g):
			return {
				"paths": [], "edges": [], "nodes": nodes,
				"ok": false, "fail_reason": "hero_crossing", "mandatory_count": 0,
			}

	var mandatory_count := paths.size()
	if _TARGET_SCENIC_LOOPS > 0:
		var scenic_added := 0
		for e: Vector2i in _angular_neighbor_door_pairs(cottages, g):
			if scenic_added >= _TARGET_SCENIC_LOOPS:
				break
			var ep := _edge_endpoint_indices(e, n)
			var pa: Vector2 = nodes[e.x]
			var pb: Vector2 = nodes[e.y]
			var coarse: Array = [pa, pb]
			if not _coarse_poly_clears(coarse, ep, obs_cache, paths):
				continue
			var trial_poly := _finalize_network_poly(coarse)
			if not _polyline_vertices_clear_cached(trial_poly, ep, obs_cache):
				continue
			if _push_network_path(trial_poly, e, paths, final_edges, false, cross_g):
				scenic_added += 1
		_drop_scenic_paths_until_clear(paths, final_edges, mandatory_count)

	return {
		"paths": paths,
		"edges": final_edges,
		"nodes": nodes,
		"ok": true,
		"mandatory_count": mandatory_count,
	}


## Returns 1 on success, 0 on route failure, 2 on crossing rejection.
static func _append_graph_edge(
		e: Vector2i,
		n: int,
		hero_i: int,
		nodes: PackedVector2Array,
		g: Vector2,
		door_normals: Array[Vector2],
		cottage_rects: Array[Rect2],
		obs_cache: Dictionary,
		pathgraph_state: int,
		path_clearance_m: float,
		bend_sign: float,
		paths: Array,
		final_edges: Array[Vector2i],
		is_loop: bool,
		max_tries: int = 1) -> int:
	var last_code := 0
	var pg_try := pathgraph_state
	for try_i: int in maxi(1, max_tries):
		if try_i > 0:
			pg_try = VillageScatterPositions.lcg_step(pg_try ^ (try_i + int(e.x) * 7 + int(e.y)))
		var bs := bend_sign if try_i % 2 == 0 else -bend_sign
		var routed := _route_graph_edge(
			e, n, hero_i, nodes, g, door_normals, cottage_rects, obs_cache, pg_try,
			path_clearance_m, bs, is_loop)
		if routed["poly"].is_empty():
			last_code = 0
			continue
		var t0 := Time.get_ticks_usec() if _net_profile_enabled else 0
		if _push_network_path(routed["poly"], e, paths, final_edges):
			if _net_profile_enabled:
				_net_prof_add("cross_us", Time.get_ticks_usec() - t0, 1)
			return 1
		if _net_profile_enabled:
			_net_prof_add("cross_us", Time.get_ticks_usec() - t0, 1)
		last_code = 2
	return last_code


static func _is_plaza_graph_node(idx: int, hamlet_n: int) -> bool:
	return idx >= hamlet_n + 1 and idx <= hamlet_n + 8


static func _route_graph_edge(
		e: Vector2i,
		n: int,
		hero_i: int,
		nodes: PackedVector2Array,
		g: Vector2,
		door_normals: Array[Vector2],
		cottage_rects: Array[Rect2],
		obs_cache: Dictionary,
		pathgraph_state: int,
		path_clearance_m: float,
		bend_sign: float,
		is_loop: bool) -> Dictionary:
	var t_route0 := Time.get_ticks_usec() if _net_profile_enabled else 0
	var ai := e.x
	var bi := e.y
	var is_hero := ai == hero_i or bi == hero_i
	var endpoint_indices: Array[int] = []
	if ai < n:
		endpoint_indices.append(ai)
	if bi < n:
		endpoint_indices.append(bi)
	var pg_st := pathgraph_state
	pg_st = VillageScatterPositions.lcg_step(pg_st)
	var pa: Vector2 = nodes[ai]
	var pb: Vector2 = nodes[bi]
	if is_loop:
		pa = _inset_plaza_point(pa, g, _PLAZA_LOOP_CENTERLINE_INSET_M)
		pb = _inset_plaza_point(pb, g, _PLAZA_LOOP_CENTERLINE_INSET_M)
	var poly: Array = []
	var pond_center: Vector2 = obs_cache["pond_center"]
	if is_loop or (_is_plaza_graph_node(ai, n) and _is_plaza_graph_node(bi, n)):
		if _segment_clears_obstacles_cached(pa, pb, endpoint_indices, obs_cache):
			poly = _finalize_network_poly([pa, pb])
	elif _segment_clears_obstacles_cached(pa, pb, endpoint_indices, obs_cache):
		poly = _finalize_network_poly([pa, pb])
	else:
		poly = _route_meandering_edge(
			pa, pb, pg_st, cottage_rects, endpoint_indices,
			pond_center, path_clearance_m, bend_sign, obs_cache)
		if poly.is_empty():
			poly = _route_edge_fast(
				pa, pb, _BEZIER_BASE_BEND * bend_sign,
				endpoint_indices, obs_cache, false, not is_hero)
	if not is_hero and not poly.is_empty():
		poly = _ensure_door_approach(poly, ai, bi, n, nodes, door_normals, false)
	if _net_profile_enabled:
		_net_prof_add("route_us", Time.get_ticks_usec() - t_route0, 1)
	return {"poly": poly, "state": pg_st}


## Prim MST over `nodes`. Only edges where candidate_mask(a, b) returns true
## are considered. Returns Array[Vector2i] (7 edges for 8 nodes).
## Starts from HERO_NODE to ensure hero connectivity comes first.
## Tie-breaks equal-length edges by lower (min, max) node index pair.
static func _mst_edges(
		nodes: PackedVector2Array,
		candidate_mask: Callable,
		start_node: int = -1) -> Array:
	var n := nodes.size()
	if n <= 1:
		return []

	var in_tree: Array[bool] = []
	in_tree.resize(n)
	in_tree.fill(false)

	var start := start_node if start_node >= 0 else mini(CLASSIC_HERO_NODE, n - 1)
	if start >= n:
		start = 0
	in_tree[start] = true

	var result: Array = []

	for _iter: int in range(n - 1):
		var best_dist := INF
		var best_u := -1
		var best_v := -1

		for u: int in range(n):
			if not in_tree[u]:
				continue
			for v: int in range(n):
				if in_tree[v]:
					continue
				if not candidate_mask.call(u, v):
					continue
				var d := nodes[u].distance_to(nodes[v])
				if d < best_dist - 1e-9:
					best_dist = d
					best_u = u
					best_v = v
				elif absf(d - best_dist) <= 1e-9 and best_u >= 0:
					# Tie-break: lower (min, max) index wins
					var mna := mini(u, v)
					var mxa := maxi(u, v)
					var mnb := mini(best_u, best_v)
					var mxb := maxi(best_u, best_v)
					if mna < mnb or (mna == mnb and mxa < mxb):
						best_u = u
						best_v = v

		if best_u < 0:
			break  # disconnected under mask

		result.append(Vector2i(best_u, best_v))
		in_tree[best_v] = true

	return result


## Quadratic Bézier from a to b, control point at chord midpoint offset perpendicular
## by `bend` metres. Returns Array[Vector2] at ~_BEZIER_SPACING arc spacing.
static func _bezier_polyline(a: Vector2, b: Vector2, bend: float, spacing: float = _BEZIER_SPACING) -> Array:
	var chord := b - a
	var chord_len := chord.length()
	if chord_len < 0.001:
		return [a, b]
	var mid := (a + b) * 0.5
	var perp := Vector2(-chord.y, chord.x) / chord_len
	var ctrl := mid + perp * bend

	# Estimate arc length with 32 samples.
	const N_EST := 32
	var arc_len := 0.0
	var prev := a
	for i: int in range(1, N_EST + 1):
		var t := float(i) / float(N_EST)
		var p := _bezier_pt(a, ctrl, b, t)
		arc_len += prev.distance_to(p)
		prev = p

	var n_segs := maxi(1, int(round(arc_len / spacing)))
	var out: Array = [a]
	for i: int in range(1, n_segs):
		var t := float(i) / float(n_segs)
		out.append(_bezier_pt(a, ctrl, b, t))
	out.append(b)
	return out


# ── S3 helpers ────────────────────────────────────────────────────────────────

## Prepend a short outward run from each door so stones meet the threshold (0.5 m stoop).
static func _ensure_door_approach(
		poly: Array,
		ai: int,
		bi: int,
		n: int,
		nodes: PackedVector2Array,
		door_normals: Array[Vector2],
		is_hero: bool) -> Array:
	if poly.is_empty():
		return poly
	var out: Array = poly.duplicate()
	if ai < n:
		var stoop_a: Vector2 = nodes[ai] + door_normals[ai] * 0.5
		if (out[0] as Vector2).distance_to(stoop_a) > 0.05:
			out.insert(0, stoop_a)
	if bi < n and not is_hero:
		var last_i := out.size() - 1
		var stoop_b: Vector2 = nodes[bi] + door_normals[bi] * 0.5
		if (out[last_i] as Vector2).distance_to(stoop_b) > 0.05:
			out.append(stoop_b)
	return out


## Evaluate quadratic Bézier point at parameter t ∈ [0,1].
static func _bezier_pt(a: Vector2, ctrl: Vector2, b: Vector2, t: float) -> Vector2:
	var mt := 1.0 - t
	return mt * mt * a + 2.0 * mt * t * ctrl + t * t * b


## Catmull-Rom-ish meander + Chaikin + resample; falls back to empty (caller tries Bézier).
static func _route_meandering_edge(
		a: Vector2,
		b: Vector2,
		pathgraph_state: int,
		cottage_rects: Array[Rect2],
		endpoint_indices: Array[int],
		pond_center: Vector2,
		path_clearance_m: float,
		bend_sign: float,
		obs_cache: Dictionary = {}) -> Array:
	var st := pathgraph_state
	st = VillageScatterPositions.lcg_step(st)
	var wobble_mag := lerpf(1.45, 3.0, VillageScatterPositions.lcg_f01(st))
	st = VillageScatterPositions.lcg_step(st)
	var wobble := wobble_mag * bend_sign
	var chord := b - a
	var clen := chord.length()
	if clen < 1e-4:
		return [a, b]
	var perp := Vector2(-chord.y, chord.x) / clen
	var p1 := a.lerp(b, 0.25) + perp * wobble * 0.6
	var p2 := a.lerp(b, 0.75) - perp * wobble * 0.4
	var ctrl: Array[Vector2] = [a, p1, p2, b]
	var smooth := _chaikin_open(ctrl, 1)
	var poly := _resample_polyline_open(smooth, _MEANDER_RESAMPLE_M)
	if not obs_cache.is_empty():
		if _polyline_clears_obstacles_cached(poly, endpoint_indices, obs_cache):
			return _finalize_network_poly(poly)
		return []
	if _polyline_clears_obstacles(poly, endpoint_indices, cottage_rects, pond_center, path_clearance_m):
		return poly
	return []


static func _route_edge_fast(
		a: Vector2,
		b: Vector2,
		base_bend: float,
		endpoint_indices: Array[int],
		obs_cache: Dictionary,
		is_hero: bool,
		is_mst: bool) -> Array:
	var path_clearance_m: float = obs_cache["pond_path_clearance_m"]
	for step: int in mini(5, _BEZIER_BEND_TRIES + 1):
		var delta := float(step) * _BEZIER_BEND_STEP
		var tries: Array[float] = [base_bend + delta]
		if step > 0:
			tries.append(base_bend - delta)
		for bend_raw: float in tries:
			var bend := clampf(bend_raw, -_BEZIER_BEND_MAX, _BEZIER_BEND_MAX)
			var coarse := _bezier_polyline(a, b, bend, 1.2)
			if _polyline_clears_obstacles_cached(coarse, endpoint_indices, obs_cache):
				return _finalize_network_poly(coarse)
	return []


static func _chaikin_open(pts: Array[Vector2], iterations: int) -> Array[Vector2]:
	var cur := pts.duplicate()
	for _it: int in iterations:
		if cur.size() < 3:
			break
		var nxt: Array[Vector2] = [cur[0]]
		for i: int in range(cur.size() - 1):
			var p0: Vector2 = cur[i]
			var p1: Vector2 = cur[i + 1]
			nxt.append(p0.lerp(p1, 0.25))
			nxt.append(p0.lerp(p1, 0.75))
		nxt.append(cur[-1])
		cur = nxt
	return cur


static func _resample_polyline_open(pts: Array[Vector2], spacing: float) -> Array:
	if pts.size() < 2:
		return pts.duplicate()
	var out: Array = [pts[0]]
	var carry := 0.0
	for i: int in range(pts.size() - 1):
		var seg_a: Vector2 = pts[i]
		var seg_b: Vector2 = pts[i + 1]
		var seg_len := seg_a.distance_to(seg_b)
		if seg_len < 1e-6:
			continue
		var t := maxf(0.0, (spacing - carry) / seg_len)
		while t <= 1.0:
			var p := seg_a.lerp(seg_b, t)
			if (out[-1] as Vector2).distance_to(p) >= spacing * 0.85:
				out.append(p)
			t += spacing / seg_len
		carry = fmod(seg_len + carry, spacing)
	if (out[-1] as Vector2).distance_to(pts[-1]) > 0.05:
		out.append(pts[-1])
	return out


## Try to build a routed polyline from a to b avoiding non-endpoint cottage rects.
## Tries base_bend then ±_BEZIER_BEND_STEP increments up to _BEZIER_BEND_TRIES.
## For MST edges (is_mst=true): on exhaustion inserts a perpendicular waypoint.
## For loop edges (is_mst=false): returns [] on failure (caller drops the edge).
## Hero-incident polylines (is_hero=true) are clipped to the _HERO_RING_CLIP ring.
static func _route_edge(
		a: Vector2, b: Vector2,
		base_bend: float,
		cottage_rects: Array[Rect2],
		endpoint_indices: Array[int],
		is_hero: bool,
		is_mst: bool,
		pond_center: Vector2 = Vector2.ZERO,
		path_clearance_m: float = VillagePondSite.PATH_CLEARANCE_M) -> Array:
	var pond_for_route := pond_center
	if pond_center != Vector2.ZERO and not _segment_near_pond(a, b, pond_center, path_clearance_m):
		pond_for_route = Vector2.ZERO

	# Try base bend then alternating ± increments.
	for step: int in range(_BEZIER_BEND_TRIES + 1):
		var delta := float(step) * _BEZIER_BEND_STEP
		var tries: Array[float] = [base_bend + delta]
		if step > 0:
			tries.append(base_bend - delta)
		for bend_raw: float in tries:
			var bend := clampf(bend_raw, -_BEZIER_BEND_MAX, _BEZIER_BEND_MAX)
			var poly := _bezier_polyline(a, b, bend)
			if _polyline_clears_obstacles(
					poly, endpoint_indices, cottage_rects, pond_for_route, path_clearance_m):
				return poly

	if not is_mst:
		return []

	# MST waypoint reroute: push midpoint perpendicular by _WAYPOINT_PUSH.
	var chord := b - a
	var chord_len := chord.length()
	if chord_len < 0.001:
		return []
	var perp := Vector2(-chord.y, chord.x) / chord_len

	for side: float in [1.0, -1.0]:
		var wp := (a + b) * 0.5 + perp * side * _WAYPOINT_PUSH
		var combined := _combine_routed_legs(
			a, wp, b, base_bend, cottage_rects, endpoint_indices, is_hero,
			pond_for_route, path_clearance_m)
		if not combined.is_empty():
			return combined
		wp = (a + b) * 0.5 + perp * side * _WAYPOINT_PUSH * 2.0
		combined = _combine_routed_legs(
			a, wp, b, base_bend, cottage_rects, endpoint_indices, is_hero,
			pond_for_route, path_clearance_m)
		if not combined.is_empty():
			return combined

	# Pond detour: push waypoint to just outside the bank on the long arc side.
	if pond_for_route != Vector2.ZERO:
		var mid := (a + b) * 0.5
		var radial := mid - pond_for_route
		if radial.length_squared() < 1e-6:
			radial = Vector2(1.0, 0.0)
		var radial_n := radial.normalized()
		for orbit_extra: float in [0.35, 1.4]:
			var orbit_r := VillagePondSite.BANK_OUTER_M + path_clearance_m + orbit_extra
			for tang_m: float in [1.2, 2.5]:
				for sign: float in [1.0, -1.0]:
					var tangent := Vector2(-radial_n.y, radial_n.x) * sign
					var wp_pond := pond_for_route + radial_n * orbit_r + tangent * tang_m
					var pond_combined := _combine_routed_legs(
						a, wp_pond, b, base_bend, cottage_rects, endpoint_indices, is_hero,
						pond_for_route, path_clearance_m)
					if not pond_combined.is_empty():
						return pond_combined

	return []  # MST edge irrecoverable — caller should fall back


static func _combine_routed_legs(
		a: Vector2, wp: Vector2, b: Vector2,
		base_bend: float,
		cottage_rects: Array[Rect2],
		endpoint_indices: Array[int],
		is_hero: bool,
		pond_center: Vector2,
		path_clearance_m: float) -> Array:
	var poly1 := _route_sub_edge(
		a, wp, base_bend, cottage_rects, endpoint_indices, pond_center, path_clearance_m)
	if poly1.is_empty():
		return []
	var poly2 := _route_sub_edge(
		wp, b, -base_bend, cottage_rects, endpoint_indices, pond_center, path_clearance_m)
	if poly2.is_empty():
		return []
	var combined: Array = poly1.duplicate()
	for k: int in range(1, poly2.size()):
		combined.append(poly2[k])
	if is_hero:
		combined = _clip_hero_edge(combined)
	return combined


## Like _route_edge but without the waypoint reroute (used for sub-edges to avoid recursion).
static func _route_sub_edge(
		a: Vector2, b: Vector2,
		base_bend: float,
		cottage_rects: Array[Rect2],
		endpoint_indices: Array[int],
		pond_center: Vector2 = Vector2.ZERO,
		path_clearance_m: float = VillagePondSite.PATH_CLEARANCE_M) -> Array:
	for step: int in range(_BEZIER_BEND_TRIES + 1):
		var delta := float(step) * _BEZIER_BEND_STEP
		var tries: Array[float] = [base_bend + delta]
		if step > 0:
			tries.append(base_bend - delta)
		for bend_raw: float in tries:
			var bend := clampf(bend_raw, -_BEZIER_BEND_MAX, _BEZIER_BEND_MAX)
			var poly := _bezier_polyline(a, b, bend)
			if _polyline_clears_obstacles(
					poly, endpoint_indices, cottage_rects, pond_center, path_clearance_m):
				return poly
	return []


static func _network_cottage_rects(cottages: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for spec: Dictionary in cottages:
		out.append(VillageBackdrop.cottage_exterior_rect(spec).grow(_PATH_COTTAGE_GROW))
	return out


static func _network_door_normals(cottages: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for spec: Dictionary in cottages:
		out.append(VillageBackdrop.cottage_door(spec)[1])
	return out


static func _make_network_obstacle_cache(
		cottage_rects: Array[Rect2],
		pond_center: Vector2,
		path_clearance_m: float) -> Dictionary:
	var clearance_rects: Array[Rect2] = []
	var grow_extra := maxf(0.0, _PATH_CLEARANCE - _PATH_COTTAGE_GROW)
	for rect: Rect2 in cottage_rects:
		clearance_rects.append(rect.grow(grow_extra))
	return {
		"clearance_rects": clearance_rects,
		"cottage_check_rects": cottage_rects,
		"pond_center": pond_center,
		"pond_path_clearance_m": path_clearance_m,
		"pond_corridor_r": VillagePondSite.BANK_OUTER_M + path_clearance_m + 2.0,
		"pond_bank": PackedVector2Array(),
		"pond_bank_ready": false,
	}


static func _segment_clears_inflated_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return false
	var corners: Array[Vector2] = [
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]
	for c: Vector2 in corners:
		if _dist_point_to_segment(c, a, b) < 0.02:
			return false
	var steps := mini(16, maxi(2, int(a.distance_to(b) / 0.35) + 1))
	for i: int in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		if _pt_dist_to_rect(p, rect) < 0.02:
			return false
	return true


static func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return VillagePondPlacement.segment_point_distance(p, a, b)


static func _segment_clears_obstacles_cached(
		a: Vector2,
		b: Vector2,
		endpoint_indices: Array[int],
		cache: Dictionary) -> bool:
	var t0 := Time.get_ticks_usec() if _net_profile_enabled else 0
	var clearance_rects: Array[Rect2] = cache["clearance_rects"]
	for ci: int in range(clearance_rects.size()):
		if endpoint_indices.has(ci):
			continue
		if not _segment_clears_inflated_rect(a, b, clearance_rects[ci]):
			if _net_profile_enabled:
				_net_prof_add("clear_us", Time.get_ticks_usec() - t0, 1)
			return false
	var pc: Vector2 = cache["pond_center"]
	if pc != Vector2.ZERO:
		if VillagePondPlacement.segment_point_distance(pc, a, b) < float(cache["pond_corridor_r"]):
			if not cache["pond_bank_ready"]:
				cache["pond_bank"] = VillagePondShape.at(pc).bank_outer_outline_world_xz()
				cache["pond_bank_ready"] = true
			var need: float = cache["pond_path_clearance_m"]
			var steps := mini(5, maxi(2, int(a.distance_to(b) / 2.0) + 1))
			for i: int in range(steps + 1):
				var p := a.lerp(b, float(i) / float(steps))
				if _min_dist_point_to_closed_poly(p, cache["pond_bank"]) < need:
					if _net_profile_enabled:
						_net_prof_add("clear_us", Time.get_ticks_usec() - t0, 1)
					return false
	if _net_profile_enabled:
		_net_prof_add("clear_us", Time.get_ticks_usec() - t0, 1)
	return true


static func _polyline_clears_obstacles_cached(
		poly: Array,
		endpoint_indices: Array[int],
		cache: Dictionary) -> bool:
	for i: int in range(poly.size() - 1):
		if not _segment_clears_obstacles_cached(
				poly[i] as Vector2, poly[i + 1] as Vector2, endpoint_indices, cache):
			return false
	return true


## Final accept check: matches INV-8 point samples on resampled centreline vertices.
static func _polyline_vertices_clear_cached(
		poly: Array,
		endpoint_indices: Array[int],
		cache: Dictionary) -> bool:
	var cottage_rects: Array[Rect2] = cache["cottage_check_rects"]
	for pt_raw in poly:
		var pt := pt_raw as Vector2
		for ci: int in range(cottage_rects.size()):
			if endpoint_indices.has(ci):
				continue
			if _pt_dist_to_rect(pt, cottage_rects[ci]) < _PATH_CLEARANCE:
				return false
	for i: int in range(poly.size() - 1):
		if not _segment_clears_pond_cached(
				poly[i] as Vector2, poly[i + 1] as Vector2, cache):
			return false
	return true


static func _segment_clears_pond_cached(a: Vector2, b: Vector2, cache: Dictionary) -> bool:
	var pc: Vector2 = cache["pond_center"]
	if pc == Vector2.ZERO:
		return true
	if VillagePondPlacement.segment_point_distance(pc, a, b) >= float(cache["pond_corridor_r"]):
		return true
	if not cache["pond_bank_ready"]:
		cache["pond_bank"] = VillagePondShape.at(pc).bank_outer_outline_world_xz()
		cache["pond_bank_ready"] = true
	var need: float = cache["pond_path_clearance_m"]
	var steps := mini(8, maxi(2, int(a.distance_to(b) / 0.35) + 1))
	for i: int in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		if _min_dist_point_to_closed_poly(p, cache["pond_bank"]) < need:
			return false
	return true


static func _finalize_network_poly(coarse: Array) -> Array:
	if coarse.size() < 2:
		return coarse
	var pts: Array[Vector2] = []
	for p_raw in coarse:
		pts.append(p_raw as Vector2)
	return _resample_polyline_open(pts, _MEANDER_RESAMPLE_M)


static func _polyline_clears_obstacles(
		poly: Array,
		endpoint_indices: Array[int],
		cottage_rects: Array[Rect2],
		pond_center: Vector2,
		path_clearance_m: float = VillagePondSite.PATH_CLEARANCE_M) -> bool:
	var cache := _make_network_obstacle_cache(cottage_rects, pond_center, path_clearance_m)
	return _polyline_clears_obstacles_cached(poly, endpoint_indices, cache)


## Return true if every point of `poly` is at least _PATH_CLEARANCE from every
## non-endpoint cottage rect (grown by _PATH_COTTAGE_GROW, pre-built in cottage_rects).
static func _polyline_clears_cottages(
		poly: Array,
		endpoint_indices: Array[int],
		cottage_rects: Array[Rect2]) -> bool:
	for pt_raw in poly:
		var pt := pt_raw as Vector2
		for ci: int in range(cottage_rects.size()):
			if endpoint_indices.has(ci):
				continue
			if _pt_dist_to_rect(pt, cottage_rects[ci]) < _PATH_CLEARANCE:
				return false
	return true


static func _segment_near_pond(
		a: Vector2, b: Vector2, pond_center: Vector2, path_clearance_m: float) -> bool:
	var corridor := VillagePondSite.BANK_OUTER_M + path_clearance_m + 2.5
	return VillagePondPlacement.segment_point_distance(pond_center, a, b) < corridor


static func _polyline_clears_pond(
		poly: Array, pond_center: Vector2, path_clearance_m: float) -> bool:
	var need := path_clearance_m
	var near_band := VillagePondSite.BANK_OUTER_M + need + 3.0
	var touches_pond := false
	for pt_raw in poly:
		var pt := pt_raw as Vector2
		if pt.distance_to(pond_center) < near_band:
			touches_pond = true
			break
	if not touches_pond:
		return true
	var bank := VillagePondShape.at(pond_center).bank_outer_outline_world_xz()
	for pt_raw in poly:
		var pt := pt_raw as Vector2
		if _min_dist_point_to_closed_poly(pt, bank) < need:
			return false
	return true


static func _min_dist_point_to_closed_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	var n := poly.size()
	if n == 0:
		return best
	for i in range(n):
		best = minf(best, VillagePondPlacement.segment_point_distance(p, poly[i], poly[(i + 1) % n]))
	return best


## Distance from point p to axis-aligned rect (0 if inside).
static func _pt_dist_to_rect(p: Vector2, rect: Rect2) -> float:
	var dx := maxf(0.0, maxf(rect.position.x - p.x, p.x - rect.end.x))
	var dy := maxf(0.0, maxf(rect.position.y - p.y, p.y - rect.end.y))
	return sqrt(dx * dx + dy * dy)


## Clip a hero-incident polyline to end at the _HERO_RING_CLIP radius.
## Points with |p| < _HERO_RING_CLIP are dropped; the exact ring crossing is appended.
## The polyline is expected to go from a stoop (high r) toward the hero (r→0).
static func _clip_hero_edge(poly: Array) -> Array:
	var r := _HERO_RING_CLIP
	var out: Array = []
	for i: int in range(poly.size()):
		var p := poly[i] as Vector2
		if p.length() >= r:
			out.append(p)
		else:
			# Entered the clip zone — find crossing with previous segment.
			if i > 0:
				var prev := poly[i - 1] as Vector2
				var t := _segment_ring_entry(prev, p, r)
				if t >= 0.0:
					out.append(prev.lerp(p, t))
			break
	return out


## Find the parametric t ∈ [0,1] at which segment a→b first enters the circle of radius r
## (i.e., the point at which |p| = r going from outside to inside). Returns -1 if none.
static func _segment_ring_entry(a: Vector2, b: Vector2, r: float) -> float:
	var d := b - a
	var dlen_sq := d.length_squared()
	if dlen_sq < 1e-12:
		return -1.0
	var A2 := dlen_sq
	var B2 := 2.0 * a.dot(d)
	var C2 := a.length_squared() - r * r
	var disc := B2 * B2 - 4.0 * A2 * C2
	if disc < 0.0:
		return -1.0
	var sqrt_d := sqrt(disc)
	for t_raw: float in [(-B2 - sqrt_d) / (2.0 * A2), (-B2 + sqrt_d) / (2.0 * A2)]:
		if t_raw >= 0.0 and t_raw <= 1.0 + 1e-6:
			return clampf(t_raw, 0.0, 1.0)
	return -1.0


## BFS hop count between `start` and `goal` in an undirected edge list (Array[Vector2i]).
## Returns -1 if unreachable. Used for the ≥3-node cycle check.
static func _mst_path_hops(edges: Array, n_nodes: int, start: int, goal: int) -> int:
	# Build adjacency list. v3 edges can use junction ids past the legacy `n_nodes` slice
	# (plaza loop + spurs); size from observed max index so BFS never OOBs.
	var max_id: int = maxi(0, n_nodes - 1)
	for e_raw in edges:
		var e := e_raw as Vector2i
		max_id = maxi(max_id, e.x)
		max_id = maxi(max_id, e.y)
	var adj_n: int = max_id + 1
	if start < 0 or goal < 0 or start >= adj_n or goal >= adj_n:
		return -1
	var adj: Array = []
	adj.resize(adj_n)
	for i: int in range(adj_n):
		adj[i] = [] as Array[int]
	for e_raw in edges:
		var e := e_raw as Vector2i
		if e.x < 0 or e.y < 0 or e.x >= adj_n or e.y >= adj_n:
			continue
		(adj[e.x] as Array[int]).append(e.y)
		(adj[e.y] as Array[int]).append(e.x)

	# BFS.
	var dist: Array[int] = []
	dist.resize(adj_n)
	dist.fill(-1)
	dist[start] = 0
	var queue: Array[int] = [start]
	var qi := 0
	while qi < queue.size():
		var cur: int = queue[qi]
		qi += 1
		for nb_raw in adj[cur]:
			var nb: int = nb_raw
			if dist[nb] >= 0:
				continue
			dist[nb] = dist[cur] + 1
			if nb == goal:
				return dist[nb]
			queue.append(nb)
	return -1  # unreachable


## Classify a path edge for INV-8 / fail histogram (`plaza_loop`, `hero`, `door_spur`, `scenic`, `network`).
## When `path_kinds` is non-empty (v3 layouts), use explicit kinds — legacy `mandatory_count` slicing
## misclassified door paths past the first door-door edge as `scenic`.
static func path_edge_kind(
		e: Vector2i,
		hamlet_n: int,
		hero_i: int,
		path_index: int,
		mandatory_count: int,
		path_kinds: Array = [],
) -> String:
	if path_kinds.size() > path_index:
		var pk := str(path_kinds[path_index])
		match pk:
			"door":
				return "door_spur"
			"plaza":
				return "plaza_loop"
			"hero":
				return "hero"
			"primary", "secondary":
				return "network"
			_:
				return "scenic"
	if path_index >= mandatory_count:
		return "scenic"
	if _is_plaza_graph_node(e.x, hamlet_n) and _is_plaza_graph_node(e.y, hamlet_n):
		return "plaza_loop"
	if e.x == hero_i or e.y == hero_i:
		return "hero"
	return "door_spur"


## Door path polyline starts at stoop — map to cottage index for INV-8 exemption (`ep`).
static func _inv8_door_cottage_index(poly: Array, cottages: Array) -> int:
	if poly.is_empty():
		return -1
	var stoop: Vector2 = poly[0] as Vector2
	var best := -1
	var best_d := INF
	for ci: int in range(cottages.size()):
		var dr := VillageBackdrop.cottage_door(cottages[ci] as Dictionary)
		var door_pos: Vector2 = dr[0] as Vector2
		var d := stoop.distance_to(door_pos)
		if d < best_d:
			best_d = d
			best = ci
	return best if best_d <= 2.0 else -1


## INV-8 sample hits on a successful layout (same rules as sweep / metrics_pooled).
static func _layout_paths_inv8_clean(layout: VillageLayout) -> bool:
	return inv8_violation_samples(layout).is_empty()


static func inv8_violation_samples(layout: VillageLayout) -> Array:
	if layout.fallback or layout.paths.is_empty():
		return []
	return inv8_violation_samples_for_paths(
		layout.paths, layout.edges, layout.cottages, layout.path_kinds)


## Same rules as `inv8_violation_samples` without a layout wrapper (probe / scrub).
static func inv8_violation_samples_for_paths(
		paths: Array, edges: Array, cottages: Array, path_kinds: Array = []) -> Array:
	var out: Array = []
	if paths.is_empty() or cottages.is_empty():
		return out
	var n := cottages.size()
	var hero_i := n
	var mandatory_count := mandatory_path_count(edges, n)
	var cottage_rects: Array[Rect2] = []
	for spec: Dictionary in cottages:
		cottage_rects.append(VillageBackdrop.cottage_exterior_rect(spec).grow(_PATH_COTTAGE_GROW))
	for pi: int in paths.size():
		var poly := paths[pi] as Array
		## v3: INV-8 point sampling targeted legacy MST spurs; `VillageLayoutValidate.v2` already guards
		## all polylines vs cottage grown rects — skip non-door here to avoid false hits on routed primary/secondary.
		if path_kinds.size() > pi and str(path_kinds[pi]) != "door":
			continue
		var ep: Array[int] = []
		if pi < edges.size():
			var e: Vector2i = edges[pi]
			if e.x < n:
				ep.append(e.x)
			if e.y < n:
				ep.append(e.y)
		if path_kinds.size() > pi and str(path_kinds[pi]) == "door":
			var dci := _inv8_door_cottage_index(poly, cottages)
			if dci >= 0:
				ep = [dci]
		var kind := "unknown"
		if pi < edges.size():
			kind = path_edge_kind(edges[pi], n, hero_i, pi, mandatory_count, path_kinds)
		for pt_raw in poly:
			var pt := pt_raw as Vector2
			for ci: int in range(cottage_rects.size()):
				if ep.has(ci):
					continue
				var dist := _pt_dist_to_rect(pt, cottage_rects[ci])
				if dist < _PATH_CLEARANCE:
					var door_ci := -1
					if ep.size() == 1:
						door_ci = int(ep[0])
					out.append({
						"path_i": pi,
						"kind": kind,
						"dist": dist,
						"cottage_i": ci,
						"door_cottage_i": door_ci,
						"pt": pt,
					})
	return out


static func _polyline_inv8_violates(
		poly: Array, endpoint_indices: Array[int], cottage_rects: Array[Rect2]) -> bool:
	for pt_raw in poly:
		var pt := pt_raw as Vector2
		for ci: int in range(cottage_rects.size()):
			if endpoint_indices.has(ci):
				continue
			if _pt_dist_to_rect(pt, cottage_rects[ci]) < _PATH_CLEARANCE:
				return true
	return false


static func mandatory_path_count(edges: Array[Vector2i], hamlet_n: int) -> int:
	var count := 0
	for e: Vector2i in edges:
		if e.x < hamlet_n and e.y < hamlet_n:
			break
		count += 1
	return count
