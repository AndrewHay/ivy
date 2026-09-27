extends Node

## Systems-Designer measurement tool for the ivy-wall archetype epic (bd ivy-v4a).
##
## Sibling to tools/measure_wall_archetypes.gd (kept intact). That tool proved the
## branch_rate survival cliff on a SINGLE ground-level seed. This one:
##   - supports N seeds across the wall width AND an adjustable seed height
##     (to probe the "raise the seed so the lone runner survives the ground-strike
##      dormancy and reaches far before branching" hypothesis from ivy-68j.1),
##   - accepts the full archetype parameter set (caps, leaf_width_base, internode,
##     leaf_cap) so dense / mid / sparse can be measured on identical footing,
##   - reports the *wall-plane placement-occupancy coverage* that mirrors the AS-1
##     contract (fixed canonical leaf-"a" reference area per leaf, NO rendered
##     size/orientation/tint), so the numbers here are the numbers the eventual
##     CoverageMetric-for-walls will produce — not the old rough point-grid.
##
## One case per invocation, driven by cmdline args (after --). Redirect stdout to a
## log file; do NOT pipe through tail (headless Godot buffers and tail can swallow it).
##
## Usage (headless, from project root):
##   Godot --headless res://tools/measure_wall_sparse.tscn -- \
##     --branch_rate=0.3 --seeds=1 --seed_y=2.0 --day=150 --label=probe2
##
## Recognised args (all optional; defaults = engine IvyParams defaults):
##   --branch_rate=F --tip_cap_soft=N --tip_cap_hard=N --leaf_width_base=F
##   --internode_base=F --leaf_cap=N --seeds=N --seed_y=F --day=N --label=STR

const WallScript = preload("res://src/world/wall.gd")
const WallSpecScript = preload("res://src/world/wall_spec.gd")
const WallSdfScript = preload("res://src/world/wall_sdf.gd")
const SurfaceQueryScript = preload("res://src/world/surface_query.gd")
const SimRootScript = preload("res://src/sim/sim_root.gd")
const IvyParamsScript = preload("res://src/params/ivy_params.gd")
const AtlasScript = preload("res://src/render/leaf_atlas.gd")
const Conv = preload("res://src/core/conv.gd")

const TICKS_PER_DAY := 24

## Wall-plane placement-occupancy coverage (AS-1 philosophy, adapted to a flat wall).
## Bucket grid: CELL x CELL metres over x in [-L/2, L/2], y in [0, H].
## Each leaf attributes a FIXED canonical leaf-"a" reference area computed at
## REF_LEAF_WIDTH — NOT the preset's leaf_width_base — so a preset cannot inflate
## coverage by widening its leaves (the dense archetype's wide-leaf presentation
## trick). A bucket is "covered" once accumulated leaf area >= 50% of bucket area.
const CELL := 0.10
const COVERAGE_FRAC := 0.5
const REF_LEAF_WIDTH := 0.075  # engine-default leaf_width_base; the canonical yardstick


func _ready() -> void:
	var args := _parse_args()
	var branch_rate := float(args.get("branch_rate", -1.0))
	var seeds := int(args.get("seeds", 1))
	var seed_y := float(args.get("seed_y", 0.02))
	var day := int(args.get("day", 150))
	var label := String(args.get("label", "case"))

	var atlas := AtlasScript.new()
	var ref_area := atlas.alpha_fill_for("a") * REF_LEAF_WIDTH * REF_LEAF_WIDTH / atlas.aspect_for("a")

	print("[measure-sparse] label=%s" % label)

	var spec := load("res://src/world/wall_spec_default.tres") as WallSpecScript
	var wall := WallScript.new()
	add_child(wall)
	wall.build_from_spec(spec, true)
	await get_tree().process_frame

	var params := IvyParamsScript.new()
	if branch_rate >= 0.0:
		params.branch_rate = branch_rate
	if args.has("tip_cap_soft"):
		params.tip_cap_soft = int(args["tip_cap_soft"])
	if args.has("tip_cap_hard"):
		params.tip_cap_hard = int(args["tip_cap_hard"])
	if args.has("leaf_width_base"):
		params.leaf_width_base = float(args["leaf_width_base"])
	if args.has("internode_base"):
		params.internode_base = float(args["internode_base"])
	if args.has("leaf_cap"):
		params.leaf_cap = int(args["leaf_cap"])

	print(("[measure-sparse] branch_rate=%.4f seeds=%d seed_y=%.3f day=%d "
		+ "tip_cap_soft=%d tip_cap_hard=%d leaf_width_base=%.4f internode_base=%.4f leaf_cap=%d")
		% [params.branch_rate, seeds, seed_y, day, params.tip_cap_soft, params.tip_cap_hard,
			params.leaf_width_base, params.internode_base, params.leaf_cap])
	print("[measure-sparse] canonical ref_area per leaf = %.6f m^2 (REF_LEAF_WIDTH=%.3f), bucket=%.2fx%.2f m, threshold=%.6f m^2"
		% [ref_area, REF_LEAF_WIDTH, CELL, CELL, CELL * CELL * COVERAGE_FRAC])

	var sq := SurfaceQueryScript.new()
	sq.setup(
		wall.get_world_3d().direct_space_state,
		wall,
		WallSdfScript.new(spec),
		wall.face_material,
		params
	)
	var sim := SimRootScript.new()
	add_child(sim)
	sim.setup(params, sq, null, 0, null, false)  # auto_seed=false: we place seeds ourselves
	sim.env.warm_up(params.light_warmup_days)
	await get_tree().process_frame

	# Seed placement: N seeds evenly spaced across the wall width at height seed_y,
	# inset from the raw edges (mirrors tools/capture_wall_archetype.gd so measured
	# numbers match the eventual capture flow), normal facing outward (+z, SOUTH).
	var half_len := spec.length * 0.5
	if seeds <= 1:
		sim.plant_at(Vector3(0.0, seed_y, 0.01), Conv.SOUTH)
	else:
		var margin := half_len * 0.15
		var usable := half_len - margin
		for i in range(seeds):
			var t := float(i) / float(seeds - 1) * 2.0 - 1.0
			sim.plant_at(Vector3(t * usable, seed_y, 0.01), Conv.SOUTH)

	var t0 := Time.get_ticks_msec()
	sim.advance_ticks(TICKS_PER_DAY * day)
	var elapsed_ms := Time.get_ticks_msec() - t0

	var plant = sim.plant
	var tips = sim.tips
	var live_count: int = tips.live_count()
	var total_tips: int = tips.tips.size()
	var dormant := 0
	var dead := 0
	var floating := 0
	for t in tips.tips:
		if t.state == Tip.State.DORMANT:
			dormant += 1
		elif t.state == Tip.State.DEAD:
			dead += 1
		elif t.state == Tip.State.FLOATING:
			floating += 1

	# ---- Wall-plane placement-occupancy coverage (AS-1-style) ----
	var nx := int(ceil(spec.length / CELL))
	var ny := int(ceil(spec.height / CELL))
	var leaf_accum := PackedFloat32Array()
	leaf_accum.resize(nx * ny)
	var stem_has := PackedByteArray()
	stem_has.resize(nx * ny)

	var n_segs: int = plant.segment_count()
	for i in range(n_segs):
		var a: Vector3 = plant.seg_a[i]
		var b: Vector3 = plant.seg_b[i]
		var idx := _bucket(( a.x + b.x) * 0.5, (a.y + b.y) * 0.5, spec.length, spec.height, nx, ny)
		if idx >= 0:
			stem_has[idx] = 1

	var n_leaves: int = plant.leaf_count()
	for i in range(n_leaves):
		var base := i * 12
		var ox: float = plant.leaf_xform[base + 3]
		var oy: float = plant.leaf_xform[base + 7]
		var idx := _bucket(ox, oy, spec.length, spec.height, nx, ny)
		if idx >= 0:
			leaf_accum[idx] += ref_area

	var threshold := CELL * CELL * COVERAGE_FRAC
	var covered := 0
	var stem_cov := 0
	for i in range(nx * ny):
		if leaf_accum[i] >= threshold:
			covered += 1
		if stem_has[i] != 0:
			stem_cov += 1
	var total_buckets := nx * ny
	var cov_pct := 100.0 * float(covered) / float(total_buckets)
	var stem_pct := 100.0 * float(stem_cov) / float(total_buckets)

	# ---- Reach-before-branch topology proxies (no new bookkeeping) ----
	var order_hist: Dictionary = {}
	var max_order := 0
	var order0_tips := 0
	var order0_shoot_sum := 0.0
	var live_shoot_sum := 0.0
	for t in tips.tips:
		var o: int = t.branch_order
		order_hist[o] = order_hist.get(o, 0) + 1
		max_order = maxi(max_order, o)
		if o == 0:
			order0_tips += 1
			order0_shoot_sum += t.shoot_length
		if t.is_live():
			live_shoot_sum += t.shoot_length
	var mean_len_per_tip: float = plant.total_length / float(max(total_tips, 1))
	var frac_order0 := 100.0 * float(order0_tips) / float(max(total_tips, 1))
	var mean_order0_shoot := order0_shoot_sum / float(max(order0_tips, 1))

	print("")
	print("=== %s === (%d ms sim wall-clock)" % [label, elapsed_ms])
	print("  total_length      = %.3f m" % plant.total_length)
	print("  segment_count     = %d" % n_segs)
	print("  leaf_count        = %d  (leaf_cap=%d, %.1f%% of cap)"
		% [n_leaves, params.leaf_cap, 100.0 * float(n_leaves) / float(params.leaf_cap)])
	print("  tips total/live   = %d / %d  (tip_cap_hard=%d, %.1f%% of hard cap live)"
		% [total_tips, live_count, params.tip_cap_hard,
			100.0 * float(live_count) / float(params.tip_cap_hard)])
	print("  tips dormant/dead/floating = %d / %d / %d" % [dormant, dead, floating])
	print("  WALL COVERAGE (placement occupancy) = %.2f%%  (%d/%d buckets, %dx%d)"
		% [cov_pct, covered, total_buckets, nx, ny])
	print("  stem bucket occupancy               = %.2f%%  (%d/%d)"
		% [stem_pct, stem_cov, total_buckets])
	print("  max branch_order  = %d" % max_order)
	print("  branch_order hist = %s" % [order_hist])
	print("  frac tips order0  = %.1f%%  (%d/%d)" % [frac_order0, order0_tips, total_tips])
	print("  mean length/tip   = %.3f m" % mean_len_per_tip)
	print("  mean shoot_len order0 tips = %.3f m" % mean_order0_shoot)
	print("  leaf_cap BOUND    = %s" % [n_leaves >= params.leaf_cap])
	if total_tips <= 8:
		for t in tips.tips:
			print(("  tip[%d] state=%d order=%d pos=%s shoot_len=%.3f floating=%.3f "
				+ "stall_days=%d ground_strikes=%d")
				% [t.id, t.state, t.branch_order, t.position, t.shoot_length,
					t.floating_length, t.stall_consecutive_days, t.ground_strikes])

	print("[measure-sparse] done")
	get_tree().quit(0)


func _bucket(x: float, y: float, length: float, height: float, nx: int, ny: int) -> int:
	var bx := int(floor((x + length * 0.5) / CELL))
	var by := int(floor(y / CELL))
	if bx < 0 or bx >= nx or by < 0 or by >= ny:
		return -1
	return by * nx + bx


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
