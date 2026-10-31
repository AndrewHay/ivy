extends Node

## Growth-step cost probe (ivy-0v1).
##
## Usage (from project root):
##   Godot --headless res://tools/profile_growth_step.tscn -- [--days=N] [--buildings=a,b,c]
##       [--pin-bake-key]
##
## Loads each building through main.tscn exactly as the picker does, plants one seed per
## compass side with a horizontal ray, then advances paused ticks and reports, per building:
## ms per growth step, physics raycasts / nearest() / project_to_shell() calls per step,
## env.tick ms per tick, and a SHA-256 fingerprint of every segment and leaf. A refactor that
## claims to be behaviour-neutral must leave the fingerprint unchanged.

const _MAIN_SCENE := "res://src/main/main.tscn"
const _DEFAULT_BUILDINGS := ["square", "overhang", "cylinder"]
const _DEFAULT_DAYS := 20
const SimClock = preload("res://src/core/sim_clock.gd")

func _ticks_for_days(days: int) -> int:
	return SimClock.ticks_for_game_days(float(days), SimClock.Speed.NORMAL)
const _SEED_RAY_Y := 0.3
const _SEED_RAY_REACH := 15.0
const _COUNTERS := ["raycast_count", "nearest_count", "project_count", "project_miss_count"]

var _main: Node = null


func _ready() -> void:
	var days := _DEFAULT_DAYS
	var buildings: Array = _DEFAULT_BUILDINGS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			days = int(arg.trim_prefix("--days="))
		elif arg.begins_with("--buildings="):
			buildings = Array(arg.trim_prefix("--buildings=").split(",", false))
		elif arg == "--pin-bake-key":
			# Fresh bakes are not bit-reproducible (ivy-2ey), so comparing two code versions
			# needs both to load the same cached bake. Pinning the code hash lets them share it.
			var pinned := PackedByteArray()
			pinned.resize(LightBakeCache.HASH_BYTES)
			LightBakeCache._code_hash_cache = pinned
	for id in buildings:
		await _profile_building(String(id), days)
	print("[gsp] done")
	get_tree().quit(0)


func _spawn_main() -> void:
	if _main != null:
		_main.queue_free()
		_main = null
		for _i in range(5):
			await get_tree().process_frame
	var ps := load(_MAIN_SCENE) as PackedScene
	_main = ps.instantiate()
	add_child(_main)
	await get_tree().process_frame


func _profile_building(id: String, days: int) -> void:
	await _spawn_main()
	await _main._on_building_selected(id)
	var sim: Node = _main.get_node("Sim")
	var world: Node = _main.get_node("World")
	var surface: SurfaceQuery = sim.surface
	sim.get_clock().set_speed(SimClock.Speed.PAUSE)
	var pivot: Vector3 = world.get_orbit_pivot()
	var planted := 0
	for dir in [Conv.SOUTH, -Conv.SOUTH, Vector3.RIGHT, Vector3.LEFT]:
		var target := Vector3(pivot.x, _SEED_RAY_Y, pivot.z)
		var hit := surface.raycast(target + dir * _SEED_RAY_REACH, target)
		if hit.hit:
			sim.plant_at(hit.position, hit.normal)
			planted += 1
	var clock: SimClock = sim.get_clock()
	clock.tick_index = 0
	clock._update_game_day()

	for counter in _COUNTERS:
		if counter in surface:
			surface.set(counter, 0)
	var env_us := 0
	var vigour_us := 0
	var budget_us := 0
	var lifecycle_us := 0
	var step_us := 0
	var tick_us := 0
	var max_live := 0
	var ticks := _ticks_for_days(days)
	var params: IvyParams = sim.params
	for _t in range(ticks):
		var t0 := Time.get_ticks_usec()
		sim.env.tick(clock.dt_sim(), clock.game_day)
		var t1 := Time.get_ticks_usec()
		env_us += t1 - t0
		var g_hat: float = sim.solar.diel_gate(clock.game_day)
		sim.tips.refresh_vigour(sim.ctx)
		var t2 := Time.get_ticks_usec()
		vigour_us += t2 - t1
		for tip in sim.tips.live_in_id_order():
			var b0 := Time.get_ticks_usec()
			Physiology.accumulate_budget(tip, g_hat, sim.ctx)
			budget_us += Time.get_ticks_usec() - b0
			var emitted := 0
			while tip.growth_budget >= params.segment_length and emitted < params.max_segments_per_tick:
				var s0 := Time.get_ticks_usec()
				GrowthStep.step_tip(tip, sim.ctx)
				step_us += Time.get_ticks_usec() - s0
				tip.growth_budget -= params.segment_length
				emitted += 1
		var l0 := Time.get_ticks_usec()
		sim.tips.apply_pending_branches()
		sim.tips.apply_lifecycle(sim.ctx)
		lifecycle_us += Time.get_ticks_usec() - l0
		clock.tick_index += 1
		clock._update_game_day()
		tick_us += Time.get_ticks_usec() - t0
		max_live = maxi(max_live, sim.tips.live_count())

	var plant: PlantData = sim.plant
	var steps := maxi(1, plant.segment_count())
	print(
		"[gsp] %s backend=%s seeds=%d days=%d tips=%d live=%d segments=%d leaves=%d length=%.4f"
		% [id, surface.backend_tag(), planted, days, sim.tips.tips.size(), sim.tips.live_count(),
			plant.segment_count(), plant.leaf_count(), plant.total_length]
	)
	print(
		"[gsp] %s step_ms=%.4f raycasts/step=%.2f nearest/step=%.2f project/step=%.2f project_miss/step=%.2f"
		% [id, step_us / 1000.0 / steps, _per_step(surface, "raycast_count", steps),
			_per_step(surface, "nearest_count", steps), _per_step(surface, "project_count", steps),
			_per_step(surface, "project_miss_count", steps)]
	)
	print(
		"[gsp] %s total_s=%.2f steps_s=%.2f env_s=%.2f vigour_s=%.2f budget_s=%.2f lifecycle_s=%.2f"
		% [id, tick_us / 1e6, step_us / 1e6, env_us / 1e6, vigour_us / 1e6, budget_us / 1e6,
			lifecycle_us / 1e6]
	)
	print(
		"[gsp] %s env_tick_ms=%.3f max_live=%d"
		% [id, env_us / 1000.0 / ticks, max_live]
	)
	print("[gsp] %s fingerprint=%s" % [id, _fingerprint(plant)])


## -1 when the SurfaceQuery under test predates the counter.
func _per_step(surface: SurfaceQuery, counter: String, steps: int) -> float:
	if not counter in surface:
		return -1.0
	return float(surface.get(counter)) / steps


func _fingerprint(plant: PlantData) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(plant.seg_a.to_byte_array())
	ctx.update(plant.seg_b.to_byte_array())
	ctx.update(plant.seg_normal.to_byte_array())
	ctx.update(plant.seg_tip.to_byte_array())
	ctx.update(plant.seg_material.to_byte_array())
	ctx.update(plant.leaf_xform.to_byte_array())
	ctx.update(plant.leaf_color.to_byte_array())
	ctx.update(PackedFloat64Array([plant.total_length]).to_byte_array())
	return ctx.finish().hex_encode()
