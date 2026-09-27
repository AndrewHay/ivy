extends Node

## One-off headless measurement tool for the ivy-wall archetype epic (bd epic, see
## work-items). NOT part of the acceptance suite: this is the "measure before setting
## targets" step. Builds the procedural test_wall, runs it to ~day 150 at a very high
## and a near-zero branch_rate, and prints wall coverage (rough wall-plane grid, since
## CoverageMetric is cylinder-only today), total stem length, tip count, leaf count,
## and whether leaf_cap / tip_cap_hard bind.
##
## Usage (headless, from project root):
##   Godot --headless res://tools/measure_wall_archetypes.tscn

const WallScript = preload("res://src/world/wall.gd")
const WallSpecScript = preload("res://src/world/wall_spec.gd")
const WallSdfScript = preload("res://src/world/wall_sdf.gd")
const SurfaceQueryScript = preload("res://src/world/surface_query.gd")
const SimRootScript = preload("res://src/sim/sim_root.gd")
const IvyParamsScript = preload("res://src/params/ivy_params.gd")

const TICKS_PER_DAY := 24
const TARGET_DAY := 150

## Rough wall-plane coverage grid, independent of CoverageMetric (which is cylinder-only
## and would silently mis-measure a flat wall — see epic notes). Bins x (length) and y
## (height) into cells and marks a cell "covered" if any leaf origin or segment midpoint
## falls in it. This is a measurement scratch tool, not the final acceptance metric.
const CELL_SIZE := 0.10


class WallCoverageEstimate:
	var length: float
	var height: float
	var nx: int
	var ny: int
	var grid: PackedByteArray

	func _init(wall_length: float, wall_height: float) -> void:
		length = wall_length
		height = wall_height
		nx = int(ceil(length / CELL_SIZE))
		ny = int(ceil(height / CELL_SIZE))
		grid = PackedByteArray()
		grid.resize(nx * ny)

	func _bin(x: float, y: float) -> int:
		var bx := int(floor((x + length * 0.5) / CELL_SIZE))
		var by := int(floor(y / CELL_SIZE))
		if bx < 0 or bx >= nx or by < 0 or by >= ny:
			return -1
		return by * nx + bx

	func mark(x: float, y: float) -> void:
		var idx := _bin(x, y)
		if idx >= 0:
			grid[idx] = 1

	func pct() -> float:
		var covered := 0
		for v in grid:
			if v != 0:
				covered += 1
		return 100.0 * float(covered) / float(max(grid.size(), 1))


## Findings from the ivy-68j.1 measurement pass (single ground-level midpoint-seed
## fallback, wall_spec_default.tres 20m x 10m, day 150 = 3600 ticks):
##
## - branch_rate in [0.001, 0.5] all produce a BIT-IDENTICAL dead network: the lone
##   non-branching trunk walks a fixed 49-segment (1.377 m) path and is forced DORMANT
##   by the ground_strikes>=5 rule (not the light-stall rule) before any branch event
##   fires. There is a sharp survival cliff between 0.5 and 0.8: below it the plant
##   dies at 1.4 m; at/above it growth resembles the same order of magnitude as
##   default. branch_rate is therefore not a smooth "sparser <-> denser" dial down at
##   the low end on this wall/seed — see epic notes before picking a "sparse" preset.
## - branch_rate=1.7 (shipped default) already produces 24,085 leaves at day 150 on
##   this wall — 120% of leaf_cap (20000) — and branch_rate=20.0 (12x) produces 29,588
##   (148%). leaf_cap is NOT a simulation-side cap (grep src/sim confirms only
##   plant_render.gd reads it, to size the static MultiMesh buffer); leaf_placer.gd
##   never checks it. Exceeding it is a latent render-buffer overflow, already live at
##   default params on this wall, not something the dense archetype introduces.
## - tip_cap_hard (160) is the binding constraint for density: 100% saturated at
##   branch_rate=20.0, 93% at default. Going 12x over default branch_rate only bought
##   +4.3 points of rough wall coverage (45.2% vs 40.9%) because branch_probability_scale
##   floors once live tips saturate tip_cap_hard — extra branch attempts mostly retire-
##   and-replace rather than add net coverage.
func _ready() -> void:
	print("[measure] wall archetype measurement — day %d" % TARGET_DAY)
	print("[measure] branch_rate default = %.4f" % IvyParamsScript.new().branch_rate)
	await _run_case("SPARSE-cliff-dead branch_rate (0.5)", 0.5)
	await _run_case("SPARSE-post-cliff branch_rate (0.8)", 0.8)
	await _run_case("DEFAULT branch_rate (1.7)", 1.7)
	await _run_case("DENSE-attempt branch_rate (20.0)", 20.0)
	print("[measure] done")
	get_tree().quit(0)


func _run_case(label: String, branch_rate: float) -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpecScript
	var wall := WallScript.new()
	add_child(wall)
	wall.build_from_spec(spec, true)
	await get_tree().process_frame

	var params := IvyParamsScript.new()
	params.branch_rate = branch_rate

	var sq := SurfaceQueryScript.new()
	sq.setup(
		wall.get_world_3d().direct_space_state,
		wall,
		WallSdfScript.new(spec),
		wall.face_material,
		params
	)
	var sim := SimRootScript.new()
	sim.setup(params, sq, null, 0, null, true)
	await get_tree().process_frame

	var t0 := Time.get_ticks_msec()
	sim.advance_ticks(TICKS_PER_DAY * TARGET_DAY)
	var elapsed_ms := Time.get_ticks_msec() - t0

	var plant = sim.plant
	var tips = sim.tips
	var live_count: int = tips.live_count()
	var total_tips: int = tips.tips.size()
	var dormant := 0
	var dead := 0
	var floating := 0
	for t in tips.tips:
		if t.state == 3:  # DORMANT
			dormant += 1
		elif t.state == 4:  # DEAD
			dead += 1
		elif t.state == 2:  # FLOATING
			floating += 1

	var cov := WallCoverageEstimate.new(spec.length, spec.height)
	var n_segs: int = plant.segment_count()
	for i in range(n_segs):
		var a: Vector3 = plant.seg_a[i]
		var b: Vector3 = plant.seg_b[i]
		cov.mark((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
	var n_leaves: int = plant.leaf_count()
	for i in range(n_leaves):
		var base := i * 12
		var ox: float = plant.leaf_xform[base + 3]
		var oy: float = plant.leaf_xform[base + 7]
		cov.mark(ox, oy)

	# branch_order histogram, cheap topology proxy for "reach before branching"
	var order_hist: Dictionary = {}
	var max_order := 0
	for t in tips.tips:
		var o: int = t.branch_order
		order_hist[o] = order_hist.get(o, 0) + 1
		max_order = maxi(max_order, o)

	print("")
	print("=== %s === (%d ms sim wall-clock)" % [label, elapsed_ms])
	print("  total_length      = %.3f m" % plant.total_length)
	print("  segment_count     = %d" % n_segs)
	print("  leaf_count        = %d  (leaf_cap=%d, %.1f%% of cap)"
		% [n_leaves, params.leaf_cap, 100.0 * float(n_leaves) / float(params.leaf_cap)])
	print("  tips total/live   = %d / %d  (tip_cap_hard=%d, %.1f%% of cap live)"
		% [total_tips, live_count, params.tip_cap_hard,
			100.0 * float(live_count) / float(params.tip_cap_hard)])
	print("  tips dormant/dead/floating = %d / %d / %d" % [dormant, dead, floating])
	print("  max branch_order  = %d" % max_order)
	print("  branch_order hist = %s" % [order_hist])
	print("  wall coverage (rough grid, %d x %d cells) = %.2f%%" % [cov.nx, cov.ny, cov.pct()])
	print("  leaf_cap BOUND    = %s" % [n_leaves >= params.leaf_cap])
	print("  tip_cap_hard BOUND at any point = %s (checked at end only: live=%d)"
		% [live_count >= params.tip_cap_hard, live_count])
	if total_tips <= 5:
		for t in tips.tips:
			print(("  tip[%d] state=%d order=%d pos=%s shoot_len=%.3f floating=%.3f "
				+ "stall_days=%d ground_strikes=%d normal=%s")
				% [t.id, t.state, t.branch_order, t.position, t.shoot_length,
					t.floating_length, t.stall_consecutive_days, t.ground_strikes,
					t.last_contact_normal])

	remove_child(wall)
	wall.queue_free()
