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
## Door nodes are 0..6 (parallel to cottages); hero node is 7.
const HERO_NODE := 7

# ── Placement constants (SD-VILLAGE-GEN-3, amended S2′) ───────────────────────
## Inner ring min/max radii (metres). +20% vs original SD annulus (2026-10-30 tuning).
const _R_IN_MIN  := 13.8
const _R_IN_MAX  := 15.6
## Outer ring min/max radii (metres).
const _R_OUT_MIN := 23.4
const _R_OUT_MAX := 25.8
## Minimum centre-to-centre spacing between any two cottages (metres). Fixed constant
## ≈1.5× the longest authored cottage run (~8 m); not computed from live footprints.
const _MIN_CENTRE_SEP_M := 12.0
## Hero keep-out distance: nearest grown-rect face must be ≥ this from origin (INV-1).
const _KEEP_OUT := 5.9
## Overlap / keep-out test grow margin (metres).
const _GROW := 0.8
## Maximum dart attempts per cottage before the whole attempt fails.
const _MAX_DARTS := 300
## Minimum door-faces-hero dot product; below this the candidate is re-darted.
const _MIN_DOT := 0.6
## Minimum angular separation within the inner ring (degrees).
const _MIN_ANG_INNER_DEG := 65.0
## Minimum angular separation within the outer ring (degrees).
const _MIN_ANG_OUTER_DEG := 50.0
## Number of re-derives allowed before falling back to authored() (SD: N_REDRAW=8).
const _N_REDRAW := 8
## Four candidate yaws evaluated per dart (SD-VILLAGE-GEN-3).
const _YAWS: Array[int] = [0, 90, 180, 270]

## Test-only override: when ≥ 0, replaces _MAX_DARTS inside _place_cottages.
## Set to 0 to force immediate failure (fallback test). Reset to -1 after each test.
## AR-VG-RISK-5: static so it persists within one headless Godot process run.
static var _test_max_darts: int = -1

## Test-only override: when true, _build_network always returns ok=false (network fallback test).
## Reset to false after each test.
static var _test_force_network_fail: bool = false

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
const GENERATED_LAWN_RADIUS := 36.0
const GENERATED_HILL_INNER := 36.0
const GENERATED_PINE_INNER := 34.2
const GENERATED_PINE_OUTER := 50.4
const GENERATED_PINE_COUNT := 33
const GENERATED_FOG_BEGIN := 16.8
const GENERATED_BUSH_FILLER_OUTER := 26.4
## Farthest outer-ring grown corner bound for INV-3 (metres).
const _OUTER_CORNER_MAX_M := 33.0
## Target extra loop edges beyond the spanning tree.
const _TARGET_LOOPS      := 4
## Minimum extra loop edges required; fewer → layout falls back.
const _MIN_LOOPS         := 3

# ── Layout data ───────────────────────────────────────────────────────────────
## 7 cottage spec Dictionaries (same shape as VillageBackdrop.COTTAGES).
var cottages: Array = []
## Ring assignment per cottage: 0 = inner, 1 = outer. Parallel to cottages[].
## Empty ([]) for authored() — the classic layout has no ring membership.
var cottage_rings: Array = []
## Array of Array[Vector2] polylines (one per cottage door → hero).
var paths: Array = []
## Graph edges as node-index pairs (door nodes 0..6, hero 7). Used by INV-5/INV-6.
var edges: Array[Vector2i] = []
## LCG seed for path_stone_transforms. Classic = 9999 (INV-15). Generated = sub-stream.
var stone_seed: int = 9999
## Minimum stone spacing for deduplication. Classic = 0.0 (dedupe off). Generated = 0.5 m.
var min_stone_spacing: float = 0.0
## True iff generate() exhausted its budget and fell back to authored() (push_warning issued).
var fallback: bool = false

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


# ── Constructors ──────────────────────────────────────────────────────────────

## Returns the authored classic layout: equivalent to COTTAGES + path_polylines().
## stone_seed=9999 and min_stone_spacing=0.0 preserve INV-15 byte-identical output.
## cottage_rings=[] because the classic layout has no ring membership.
static func authored() -> VillageLayout:
	var layout := VillageLayout.new()
	for spec in VillageBackdrop.COTTAGES:
		layout.cottages.append(spec.duplicate())
	layout.cottage_rings = []  # no ring data for classic
	layout.paths = VillageBackdrop.path_polylines()
	layout.stone_seed = 9999
	layout.min_stone_spacing = 0.0
	layout.fallback = false
	return layout


## Returns a procedurally generated layout for the given seed (S2′: two-ring placement).
##
## Normalises seed to 31 bits (AR-VG-RISK-6), derives three independent sub-streams,
## then runs seeded dart-throwing placement of the 7 authored cottage types into two
## rings (inner r∈[11.5,13.0], outer r∈[19.5,21.5]). Ring membership: 3 inner (all
## 3-bay, seeded Fisher–Yates), 4 outer (both 4-bay + 2 3-bay).
## On per-cottage dart exhaustion the whole attempt re-derives the placement stream
## up to _N_REDRAW=8 times; if all attempts fail it falls back to authored() with
## `fallback=true` and a push_warning (never ships an invalid layout).
##
## Paths are empty in S2′ ([] placeholder); S3 fills them via _build_network.
static func generate(seed: int) -> VillageLayout:
	# AR-VG-RISK-6: normalise to 31-bit non-negative to match LCG domain.
	@warning_ignore("int_as_enum_without_cast")
	var norm := seed & 0x7FFFFFFF
	var cur_state := _derive(norm, PLACEMENT_SALT)

	for attempt in range(_N_REDRAW + 1):  # 0 = initial, 1.._N_REDRAW = re-derives
		if attempt > 0:
			# Re-derive: XOR the consumed state with the attempt index, then step once.
			# SD: placement_state = lcg_step(placement_state ⊕ attempt_index)
			cur_state = VillageScatterPositions.lcg_step(cur_state ^ attempt)

		var result := _place_cottages(cur_state)

		if result["ok"]:
			var layout := VillageLayout.new()
			layout.cottages = result["cottages"]
			layout.cottage_rings = result["cottage_rings"]

			# S3: build path network (MST + loop edges + Bézier polylines).
			var pathgraph_state := _derive(norm, PATHGRAPH_SALT)
			var network := _build_network(layout.cottages, layout.cottage_rings, pathgraph_state)
			if not network["ok"]:
				push_warning("VillageLayout.generate: network failed (seed=%d) — falling back to authored()" % seed)
				var fb := authored()
				fb.fallback = true
				return fb

			layout.paths = network["paths"]
			layout.edges = network["edges"]
			layout.stone_seed = _derive(norm, STONES_SALT)
			layout.min_stone_spacing = 0.5  # S3 spatial-hash dedupe in path_stone_transforms
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
			layout.fallback = false
			return layout

		# Advance cur_state to the consumed state for the next re-derivation
		cur_state = result["state"]

	# All _N_REDRAW + 1 attempts exhausted — fall back to authored()
	push_warning("VillageLayout.generate: placement exhausted after %d redraws (seed=%d) — falling back to authored()" % [_N_REDRAW, seed])
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
static func _derive(seed: int, salt: int) -> int:
	var s := (seed ^ salt) & 0x7FFFFFFF
	s = VillageScatterPositions.lcg_step(s)
	s = VillageScatterPositions.lcg_step(s)
	return s


## Fisher–Yates ring assignment (AR-VG-DECIDE §7).
##
## Collects the five 3-bay indices in COTTAGES order (CB=1,CC=2,CE=4,CF=5,CG=6),
## shuffles them on the placement LCG, and assigns the first three as inner (ring=0)
## and the last two as outer (ring=1). Both 4-bay types (CA=0, CD=3) are always outer.
##
## Returns {rings: Array (len=7, values 0/1), state: int}.
static func _assign_rings(state: int) -> Dictionary:
	var st := state

	# Collect 3-bay indices in COTTAGES order
	var three_bay: Array = []
	for i: int in VillageBackdrop.COTTAGES.size():
		if int(VillageBackdrop.COTTAGES[i]["bays"]) == 3:
			three_bay.append(i)
	# three_bay = [1, 2, 4, 5, 6] (CB, CC, CE, CF, CG)

	# Fisher–Yates: i from n-1 down to 1
	for i: int in range(three_bay.size() - 1, 0, -1):
		st = VillageScatterPositions.lcg_step(st)
		var j: int = int(VillageScatterPositions.lcg_f01(st) * float(i + 1))
		j = clampi(j, 0, i)
		var tmp: int = three_bay[i]
		three_bay[i] = three_bay[j]
		three_bay[j] = tmp

	# Build rings array: all outer (1) by default
	var rings: Array = []
	rings.resize(VillageBackdrop.COTTAGES.size())
	rings.fill(1)
	# First 3 of shuffled 3-bay list → inner (0)
	for k: int in range(3):
		rings[three_bay[k]] = 0

	return {"rings": rings, "state": st}


## Two-ring dart-throwing cottage placement (S2′).
##
## Calls _assign_rings first (Fisher–Yates over the 3-bay indices), then processes
## cottages in the authored CA…CG order. Each cottage samples (θ, d) in its assigned
## ring's annulus, evaluates 4 yaws, and accepts if it passes all guards:
##   - keep-out (nearest grown-0.8 face ≥ 5.9 m from origin)
##   - no overlap with any placed rect across BOTH rings
##   - same-ring angular separation ≥ ring threshold (65° inner / 50° outer)
##   - door dot > 0.6
##
## Returns {cottages: Array, cottage_rings: Array, ok: bool, state: int}.
## `state` is the final LCG state — used by generate() to re-derive on failure.
static func _place_cottages(placement_state: int) -> Dictionary:
	var st := placement_state
	var placed_specs: Array = []
	var placed_rects: Array[Rect2] = []
	var inner_angles: Array = []  # angles of accepted inner cottages
	var outer_angles: Array = []  # angles of accepted outer cottages

	# Honour the test-only override; -1 means use _MAX_DARTS.
	var max_darts: int = _test_max_darts if _test_max_darts >= 0 else _MAX_DARTS

	# ── Step 1: assign rings (Fisher–Yates, called first per AR-VG-DECIDE §7) ──
	var ring_result := _assign_rings(st)
	var cottage_rings: Array = ring_result["rings"]
	st = ring_result["state"]

	# ── Step 2: place each cottage in its assigned ring ────────────────────────
	for idx: int in VillageBackdrop.COTTAGES.size():
		var base_spec: Dictionary = VillageBackdrop.COTTAGES[idx].duplicate()
		var ring: int = cottage_rings[idx]  # 0 = inner, 1 = outer

		# Per-ring annulus parameters
		var r_min: float = _R_IN_MIN  if ring == 0 else _R_OUT_MIN
		var r_max: float = _R_IN_MAX  if ring == 0 else _R_OUT_MAX
		var min_ang_deg: float = _MIN_ANG_INNER_DEG if ring == 0 else _MIN_ANG_OUTER_DEG

		# Reference to the correct same-ring angle list (array is a reference type)
		var ring_angles: Array = inner_angles if ring == 0 else outer_angles

		var accepted := false

		# Reuse one trial dict across darts — only `centre` and `yaw_deg` are mutated.
		var trial := base_spec.duplicate()

		for _dart in range(max_darts):
			# ── Sample candidate centre (area-uniform in ring's annulus) ──────
			st = VillageScatterPositions.lcg_step(st)
			var theta: float = VillageScatterPositions.lcg_f01(st) * TAU
			st = VillageScatterPositions.lcg_step(st)
			var u: float = VillageScatterPositions.lcg_f01(st)
			var d: float = sqrt(r_min * r_min + u * (r_max * r_max - r_min * r_min))
			var centre := Vector2(cos(theta) * d, sin(theta) * d)
			trial["centre"] = centre

			# ── Yaw selection: pick yaw that maximises door-faces-origin dot ──
			var best_yaw := 0
			var best_dot := -INF
			for yaw_deg: int in _YAWS:
				trial["yaw_deg"] = yaw_deg
				var door_info := VillageBackdrop.cottage_door(trial)
				var door_pos: Vector2 = door_info[0]
				var door_normal: Vector2 = door_info[1]
				if door_pos.length_squared() < 1e-8:
					continue  # degenerate — skip (not reachable in annulus)
				var dot_val: float = door_normal.dot((-door_pos).normalized())
				if dot_val > best_dot:
					best_dot = dot_val
					best_yaw = yaw_deg

			# Require best dot > _MIN_DOT=0.6 (above the INV-4 bar of 0.5)
			if best_dot <= _MIN_DOT:
				continue

			trial["yaw_deg"] = best_yaw

			# ── Same-ring angular-separation guard ───────────────────────────
			var centre_angle_deg: float = rad_to_deg(atan2(centre.y, centre.x))
			var ang_ok := true
			for prev_angle: float in ring_angles:
				var diff := fmod(absf(centre_angle_deg - prev_angle), 360.0)
				if diff > 180.0:
					diff = 360.0 - diff
				if diff < min_ang_deg:
					ang_ok = false
					break
			if not ang_ok:
				continue

			# ── Geometry guards ────────────────────────────────────────────
			var grown_rect := VillageBackdrop.cottage_exterior_rect(trial).grow(_GROW)

			# INV-1: nearest grown-rect face ≥ 5.9 m from origin
			if _rect2_dist_from_origin(grown_rect) < _KEEP_OUT:
				continue

			# INV-2: no overlap with any already-placed grown rect (both rings)
			var overlap := false
			for pr: Rect2 in placed_rects:
				if grown_rect.intersects(pr, false):
					overlap = true
					break
			if overlap:
				continue

			# Minimum spacing: fixed centre-to-centre floor (_MIN_CENTRE_SEP_M).
			for prev_spec: Dictionary in placed_specs:
				var other: Vector2 = prev_spec["centre"]
				if centre.distance_to(other) < _MIN_CENTRE_SEP_M:
					overlap = true
					break
			if overlap:
				continue

			# ── Accept dart ───────────────────────────────────────────────
			var accepted_spec := base_spec.duplicate()
			accepted_spec["centre"] = centre
			accepted_spec["yaw_deg"] = best_yaw
			placed_specs.append(accepted_spec)
			placed_rects.append(grown_rect)
			ring_angles.append(centre_angle_deg)  # modifies inner_angles or outer_angles
			accepted = true
			break

		if not accepted:
			return {"cottages": placed_specs, "cottage_rings": cottage_rings, "ok": false, "state": st}

	return {"cottages": placed_specs, "cottage_rings": cottage_rings, "ok": true, "state": st}


## Shortest distance from the world origin (0, 0) to the nearest point on `rect`.
## Used for the keep-out test (INV-1). rect must have non-negative size (always
## true after Rect2.grow()).
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
static func _build_network(
		cottages: Array,
		cottage_rings: Array,
		_pathgraph_state: int) -> Dictionary:
	if _test_force_network_fail:
		return {"paths": [], "edges": [], "ok": false}

	var n := cottages.size()  # 7

	# ── 1. Build node positions at door exteriors (paths connect house-to-house at doors).
	# Node 7 (HERO_NODE): world origin (0, 0).
	var nodes: PackedVector2Array = PackedVector2Array()
	var door_normals: Array[Vector2] = []
	for i: int in range(n):
		var spec: Dictionary = cottages[i]
		var door_info := VillageBackdrop.cottage_door(spec)
		var door_pos: Vector2 = door_info[0]
		var door_normal: Vector2 = door_info[1]
		nodes.append(door_pos)
		door_normals.append(door_normal)
	nodes.append(Vector2.ZERO)

	var pg_st := _pathgraph_state

	# ── 2. Inner-door index set (for hero candidate mask) ───────────────────
	var inner_set: Array[int] = []
	for i: int in range(n):
		if int(cottage_rings[i]) == 0:
			inner_set.append(i)

	# Candidate mask: hero (7) may only connect to inner doors (INV-18).
	var candidate_mask := func(a: int, b: int) -> bool:
		if a == HERO_NODE or b == HERO_NODE:
			var door_node: int = b if a == HERO_NODE else a
			return inner_set.has(door_node)
		return true

	# ── 3. Prim MST ─────────────────────────────────────────────────────────
	var mst: Array = _mst_edges(nodes, candidate_mask)

	# ── 4. Pre-build avoidance rects (cottage exterior grown by _PATH_COTTAGE_GROW) ─
	var cottage_rects: Array[Rect2] = []
	for spec: Dictionary in cottages:
		cottage_rects.append(VillageBackdrop.cottage_exterior_rect(spec).grow(_PATH_COTTAGE_GROW))

	# ── 5. Build polylines for MST edges ────────────────────────────────────
	var paths: Array = []
	var final_edges: Array[Vector2i] = []
	var bend_sign := 1.0

	for me_raw in mst:
		var me := me_raw as Vector2i
		var ai := me.x
		var bi := me.y
		var is_hero_edge: bool = (ai == HERO_NODE or bi == HERO_NODE)

		# For hero edges, route from door stoop (high r) → hero (r=0) so
		# _clip_hero_edge can trim the inner tail correctly.
		var pa: Vector2
		var pb: Vector2
		if ai == HERO_NODE:
			pa = nodes[bi]   # door stoop
			pb = nodes[ai]   # hero
		else:
			pa = nodes[ai]
			pb = nodes[bi]

		var endpoint_indices: Array[int] = []
		if ai < n:
			endpoint_indices.append(ai)
		if bi < n:
			endpoint_indices.append(bi)

		pg_st = VillageScatterPositions.lcg_step(pg_st)
		var meander_scale := lerpf(0.85, 1.45, VillageScatterPositions.lcg_f01(pg_st))
		pg_st = VillageScatterPositions.lcg_step(pg_st)
		var extra_wiggle := (VillageScatterPositions.lcg_f01(pg_st) - 0.5) * 0.9
		var edge_bend := (bend_sign + extra_wiggle) * _BEZIER_BASE_BEND * meander_scale

		var poly := _route_edge(
			pa, pb, edge_bend,
			cottage_rects, endpoint_indices, is_hero_edge, true)
		bend_sign = -bend_sign

		if poly.is_empty():
			return {"paths": [], "edges": [], "ok": false}  # MST edge failed

		poly = _ensure_door_approach(poly, ai, bi, n, nodes, door_normals, is_hero_edge)
		paths.append(poly)
		final_edges.append(me)

	# ── 6. Build candidate loop edges (non-MST door–door) ───────────────────
	# Build MST edge key set for fast lookup.
	var mst_key_set: Dictionary = {}
	for me_raw in mst:
		var me := me_raw as Vector2i
		var mk := "%d_%d" % [mini(me.x, me.y), maxi(me.x, me.y)]
		mst_key_set[mk] = true

	var loop_candidates: Array = []
	for i: int in range(n):
		for j: int in range(i + 1, n):
			var ck := "%d_%d" % [i, j]
			if mst_key_set.has(ck):
				continue
			loop_candidates.append({
				"edge": Vector2i(i, j),
				"len": nodes[i].distance_to(nodes[j])
			})

	# Sort by length ascending, tie-break by (min, max) node index.
	loop_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la: float = a["len"]
		var lb: float = b["len"]
		if absf(la - lb) > 1e-6:
			return la < lb
		var ea: Vector2i = a["edge"]
		var eb: Vector2i = b["edge"]
		var mina := mini(ea.x, ea.y)
		var minb := mini(eb.x, eb.y)
		if mina != minb:
			return mina < minb
		return maxi(ea.x, ea.y) < maxi(eb.x, eb.y))

	# ── 7. Add loop edges ────────────────────────────────────────────────────
	var current_key_set := mst_key_set.duplicate()
	var loop_count := 0

	for lc: Dictionary in loop_candidates:
		if loop_count >= _TARGET_LOOPS:
			break
		var e: Vector2i = lc["edge"]
		var ek := "%d_%d" % [mini(e.x, e.y), maxi(e.x, e.y)]
		if current_key_set.has(ek):
			continue

		# Check ≥3-node cycle: MST path from e.x to e.y must span ≥2 hops.
		var hops := _mst_path_hops(mst, nodes.size(), e.x, e.y)
		if hops < 2:
			continue

		var ai := e.x
		var bi := e.y
		var a: Vector2 = nodes[ai]
		var b: Vector2 = nodes[bi]
		var endpoint_indices: Array[int] = [ai, bi]

		pg_st = VillageScatterPositions.lcg_step(pg_st)
		var meander_scale := lerpf(0.85, 1.45, VillageScatterPositions.lcg_f01(pg_st))
		pg_st = VillageScatterPositions.lcg_step(pg_st)
		var extra_wiggle := (VillageScatterPositions.lcg_f01(pg_st) - 0.5) * 0.9
		var edge_bend := (bend_sign + extra_wiggle) * _BEZIER_BASE_BEND * meander_scale

		var poly := _route_edge(
			a, b, edge_bend,
			cottage_rects, endpoint_indices, false, false)
		bend_sign = -bend_sign

		if poly.is_empty():
			continue  # drop this loop edge; try the next candidate

		poly = _ensure_door_approach(poly, ai, bi, n, nodes, door_normals, false)
		paths.append(poly)
		final_edges.append(e)
		current_key_set[ek] = true
		loop_count += 1

	if loop_count < _MIN_LOOPS:
		return {"paths": [], "edges": [], "ok": false}

	return {"paths": paths, "edges": final_edges, "ok": true}


## Prim MST over `nodes`. Only edges where candidate_mask(a, b) returns true
## are considered. Returns Array[Vector2i] (7 edges for 8 nodes).
## Starts from HERO_NODE to ensure hero connectivity comes first.
## Tie-breaks equal-length edges by lower (min, max) node index pair.
static func _mst_edges(nodes: PackedVector2Array, candidate_mask: Callable) -> Array:
	var n := nodes.size()
	if n <= 1:
		return []

	var in_tree: Array[bool] = []
	in_tree.resize(n)
	in_tree.fill(false)

	var start := mini(HERO_NODE, n - 1)
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
static func _bezier_polyline(a: Vector2, b: Vector2, bend: float) -> Array:
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

	var n_segs := maxi(1, int(round(arc_len / _BEZIER_SPACING)))
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
		if (out[0] as Vector2).distance_to(nodes[ai]) > 0.05:
			out.insert(0, nodes[ai])
	if bi < n and not is_hero:
		var last_i := out.size() - 1
		var stoop_b: Vector2 = nodes[bi] + door_normals[bi] * 0.5
		if (out[last_i] as Vector2).distance_to(stoop_b) > 0.05:
			out.append(stoop_b)
		if (out[out.size() - 1] as Vector2).distance_to(nodes[bi]) > 0.05:
			out.append(nodes[bi])
	return out


## Evaluate quadratic Bézier point at parameter t ∈ [0,1].
static func _bezier_pt(a: Vector2, ctrl: Vector2, b: Vector2, t: float) -> Vector2:
	var mt := 1.0 - t
	return mt * mt * a + 2.0 * mt * t * ctrl + t * t * b


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
		is_mst: bool) -> Array:

	# Try base bend then alternating ± increments.
	for step: int in range(_BEZIER_BEND_TRIES + 1):
		var delta := float(step) * _BEZIER_BEND_STEP
		var tries: Array[float] = [base_bend + delta]
		if step > 0:
			tries.append(base_bend - delta)
		for bend_raw: float in tries:
			var bend := clampf(bend_raw, -_BEZIER_BEND_MAX, _BEZIER_BEND_MAX)
			var poly := _bezier_polyline(a, b, bend)
			if _polyline_clears_cottages(poly, endpoint_indices, cottage_rects):
				if is_hero:
					poly = _clip_hero_edge(poly)
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

		var poly1 := _route_sub_edge(a, wp, base_bend, cottage_rects, endpoint_indices)
		if poly1.is_empty():
			continue
		var poly2 := _route_sub_edge(wp, b, -base_bend, cottage_rects, endpoint_indices)
		if poly2.is_empty():
			continue

		# Combine (skip duplicate waypoint at junction).
		var combined: Array = poly1.duplicate()
		for k: int in range(1, poly2.size()):
			combined.append(poly2[k])
		if is_hero:
			combined = _clip_hero_edge(combined)
		return combined

	return []  # MST edge irrecoverable — caller should fall back


## Like _route_edge but without the waypoint reroute (used for sub-edges to avoid recursion).
static func _route_sub_edge(
		a: Vector2, b: Vector2,
		base_bend: float,
		cottage_rects: Array[Rect2],
		endpoint_indices: Array[int]) -> Array:
	for step: int in range(_BEZIER_BEND_TRIES + 1):
		var delta := float(step) * _BEZIER_BEND_STEP
		var tries: Array[float] = [base_bend + delta]
		if step > 0:
			tries.append(base_bend - delta)
		for bend_raw: float in tries:
			var bend := clampf(bend_raw, -_BEZIER_BEND_MAX, _BEZIER_BEND_MAX)
			var poly := _bezier_polyline(a, b, bend)
			if _polyline_clears_cottages(poly, endpoint_indices, cottage_rects):
				return poly
	return []


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
	# Build adjacency list.
	var adj: Array = []
	adj.resize(n_nodes)
	for i: int in range(n_nodes):
		adj[i] = [] as Array[int]
	for e_raw in edges:
		var e := e_raw as Vector2i
		(adj[e.x] as Array[int]).append(e.y)
		(adj[e.y] as Array[int]).append(e.x)

	# BFS.
	var dist: Array[int] = []
	dist.resize(n_nodes)
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
