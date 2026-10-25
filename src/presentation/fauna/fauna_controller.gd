class_name FaunaController
extends Node3D

const FaunaAgentStateScript = preload("res://src/presentation/fauna/fauna_agent_state.gd")
const FaunaMotionScript = preload("res://src/presentation/fauna/fauna_motion.gd")
const FaunaProxyMeshesScript = preload("res://src/presentation/fauna/fauna_proxy_meshes.gd")

var _environment: FaunaEnvironment = null
var _backdrop: Node3D = null
var _enabled: bool = false
var _spawn_accum: float = 0.0
var _rng := RandomNumberGenerator.new()

var _agents: Array = []

var debug_last_lit: float = -1.0
var debug_last_hour: float = -1.0
var debug_last_paused: bool = true
var debug_anchor_count: int = 0
var debug_spawn_attempts: int = 0
var debug_fail_no_species: int = 0
var debug_fail_cap: int = 0
var debug_fail_anchor: int = 0
var debug_fail_weight: int = 0
var debug_fail_rng: int = 0
var debug_fail_distance: int = 0
var debug_spawn_ok: int = 0
var debug_peak_agents: int = 0

## Print spawn/status lines to the Godot Output panel (Inspector → World → FaunaController).
@export var console_log: bool = true

## TEMP: keep spawns beside the active building pivot (Squat house garden) for visibility QA.
@export var debug_spawn_near_pivot_only: bool = true
@export var debug_spawn_max_dist_from_pivot_m: float = 8.0

## When false, `_try_spawn` is a no-op (e.g. `test_fauna` scene uses `prefill_agents` only).
@export var ambient_spawn_enabled: bool = true
## Test Fauna: keep agents when the camera pulls back for overview.
@export var ignore_lod_despawn: bool = false
## Test Fauna: no per-species or global agent caps (main game keeps FaunaConstants limits).
@export var uncapped_population: bool = false

var _log_status_accum: float = 0.0
var _logged_spawn_near_pivot: bool = false
var _logged_inactive: bool = false
var _logged_dark: bool = false
var _logged_paused: bool = false
var _last_status_line: String = ""


func _ready() -> void:
	_rng.randomize()


func bind_backdrop(backdrop: VillageBackdrop) -> void:
	bind_environment(backdrop.export_fauna_anchors(), backdrop, "VillageBackdrop")


func bind_environment(
		env: FaunaEnvironment,
		backdrop_node: Node3D = null,
		label: String = "environment") -> void:
	clear_environment("backdrop_rebind")
	_backdrop = backdrop_node
	_environment = env
	debug_anchor_count = _environment.anchors.size() if _environment != null else 0
	_enabled = _environment != null and not _environment.anchors.is_empty()
	_logged_inactive = false
	_logged_dark = false
	_logged_spawn_near_pivot = false
	_log("bound %s anchors=%d enabled=%s" % [label, debug_anchor_count, _enabled])
	if console_log and debug_spawn_near_pivot_only:
		_log("TEMP spawn filter: flower/clover anchors within %.1fm of building pivot only"
			% debug_spawn_max_dist_from_pivot_m)


## Spawn fixed counts on flower anchors (test scenes; ignores hour/RNG/distance gates).
func prefill_agents(bee_count: int, butterfly_count: int, ctx: FaunaPresentationContext) -> void:
	if _environment == null:
		return
	var flower_indices: Array[int] = []
	for i in range(_environment.anchors.size()):
		var anchor := _environment.anchors[i]
		if anchor.kind != FaunaConstants.AnchorKind.FLOWER:
			continue
		if not FaunaGating.anchor_in_species_ring(FaunaConstants.Species.BEE, anchor):
			continue
		flower_indices.append(i)
	if flower_indices.is_empty():
		push_warning("[fauna] prefill: no flower anchors")
		return
	flower_indices.shuffle()
	var fi := 0
	for _n in range(bee_count):
		if not _may_spawn_species(FaunaConstants.Species.BEE):
			break
		var idx: int = flower_indices[fi % flower_indices.size()]
		fi += 1
		_spawn_agent(FaunaConstants.Species.BEE, idx, ctx)
	for _n in range(butterfly_count):
		if not _may_spawn_species(FaunaConstants.Species.BUTTERFLY):
			break
		var idx: int = flower_indices[fi % flower_indices.size()]
		fi += 1
		_spawn_agent(FaunaConstants.Species.BUTTERFLY, idx, ctx)
	if console_log:
		_log("prefill bees=%d butterflies=%d active=%d" % [
			_count_species(FaunaConstants.Species.BEE),
			_count_species(FaunaConstants.Species.BUTTERFLY),
			_agents.size()])


func set_all_agent_lifetimes(seconds: float) -> void:
	for a in _agents:
		a.lifetime = seconds
		a.age = 0.0


func count_species(species: FaunaConstants.Species) -> int:
	return _count_species(species)


## Spawn one insect at backdrop-local XZ (Test Fauna flower box).
func spawn_at_hover_local(
		species: FaunaConstants.Species,
		ctx: FaunaPresentationContext,
		hover_xz: Vector2) -> bool:
	if _environment == null or not _enabled:
		return false
	if not _may_spawn_species(species):
		return false
	var anchor_idx := _nearest_anchor_index_xz(hover_xz)
	_spawn_agent(species, anchor_idx, ctx)
	var agent = _agents[_agents.size() - 1]
	agent.lifetime = 600.0
	agent.age = 0.0
	agent.test_use_custom_hover = true
	agent.test_hover_xz = hover_xz
	var world: Vector3 = ctx.backdrop_global_transform * Vector3(hover_xz.x, 0.0, hover_xz.y)
	world.y = FaunaMotionScript.anchor_hover_y(species)
	if species == FaunaConstants.Species.BEE:
		agent.path_from = world
		agent.path_to = world
		agent.path_segment_u = 1.0
		agent.bee_linger_sec = _rng.randf_range(0.5, 1.2)
	elif species == FaunaConstants.Species.BUTTERFLY:
		agent.path_from = world
		agent.path_to = world
		agent.path_segment_u = 1.0
		agent.butterfly_mode = FaunaAgentState.ButterflyMode.FLIT_AT_FLOWER
		agent.butterfly_linger_sec = _rng.randf_range(0.8, 2.0)
	if agent.mesh != null:
		agent.mesh.global_position = world
	return true


func despawn_one(species: FaunaConstants.Species) -> bool:
	for i in range(_agents.size() - 1, -1, -1):
		if _agents[i].species != species:
			continue
		FaunaMotionScript.unlink_butterfly_partner(_agents[i])
		if _agents[i].mesh != null and is_instance_valid(_agents[i].mesh):
			_agents[i].mesh.queue_free()
		_agents.remove_at(i)
		return true
	return false


func get_active_agent_count() -> int:
	return _agents.size()


func clear_environment(reason: String = "clear") -> void:
	var had := _agents.size()
	_enabled = false
	_environment = null
	_backdrop = null
	for a in _agents:
		if a.mesh != null and is_instance_valid(a.mesh):
			a.mesh.queue_free()
	_agents.clear()
	if console_log and (had > 0 or reason != "backdrop_rebind"):
		_log("cleared (%s, removed %d agents)" % [reason, had])


func tick(ctx: FaunaPresentationContext, delta: float) -> void:
	debug_last_lit = ctx.lit
	debug_last_hour = ctx.local_solar_hour
	debug_last_paused = ctx.paused
	if not _enabled or _environment == null:
		if console_log and not _logged_inactive:
			_logged_inactive = true
			_log(("inactive — no fauna environment (pick mesh building \"Squat house\" "
				+ "so VillageBackdrop binds; procedural-only has no garden fauna)"))
		return
	_logged_inactive = false
	if ctx.lit < FaunaConstants.LIT_SPAWN_CUTOFF:
		if not _logged_dark and console_log:
			_logged_dark = true
			_log("night/dusk — despawn all (lit=%.3f < %.3f)" % [ctx.lit, FaunaConstants.LIT_SPAWN_CUTOFF])
		_despawn_all()
		_maybe_log_status(ctx, delta)
		return
	_logged_dark = false
	if ctx.paused:
		if console_log and not _logged_paused:
			_logged_paused = true
			_log("sim paused — insects hold still; press Watch/Grow or Space to unpause for spawns")
		_maybe_log_status(ctx, delta)
		return
	_logged_paused = false
	_update_agents(ctx, delta)
	_spawn_accum += delta
	var spawn_interval := 1.0 / FaunaConstants.SPAWN_TICK_HZ
	while _spawn_accum >= spawn_interval:
		_spawn_accum -= spawn_interval
		_try_spawn(ctx)
	debug_peak_agents = maxi(debug_peak_agents, _agents.size())
	_maybe_log_status(ctx, delta)


func _update_agents(ctx: FaunaPresentationContext, delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(_agents.size()):
		var a = _agents[i]
		a.age += delta
		if a.age >= a.lifetime:
			to_remove.append(i)
			continue
		if not ignore_lod_despawn \
				and FaunaGating.should_despawn_agent(ctx.camera_global_position, a.mesh.global_position):
			to_remove.append(i)
			continue
		_advance_agent(a, ctx, delta)
	for i in range(to_remove.size() - 1, -1, -1):
		var idx: int = to_remove[i]
		FaunaMotionScript.unlink_butterfly_partner(_agents[idx])
		_agents[idx].mesh.queue_free()
		_agents.remove_at(idx)


func _advance_agent(a, ctx: FaunaPresentationContext, delta: float) -> void:
	var base: Vector3
	if a.test_use_custom_hover:
		base = ctx.backdrop_global_transform * Vector3(a.test_hover_xz.x, 0.0, a.test_hover_xz.y)
	else:
		var anchor := _environment.anchors[a.anchor_index]
		base = ctx.backdrop_global_transform * anchor.local_transform.origin
	base.y = FaunaMotionScript.anchor_hover_y(a.species)
	FaunaMotionScript.advance(
		a, _environment, ctx, base, delta, _rng,
		debug_spawn_near_pivot_only, debug_spawn_max_dist_from_pivot_m, _agents)


func _try_spawn(ctx: FaunaPresentationContext) -> void:
	if not ambient_spawn_enabled:
		return
	debug_spawn_attempts += 1
	if _agents.size() >= FaunaConstants.GLOBAL_MAX_AGENTS:
		return
	var species := _pick_species(ctx)
	if species < 0:
		debug_fail_no_species += 1
		return
	var cap := FaunaGating.effective_species_cap(
		species, ctx.lit, ctx.render_blend, ctx.weather_activity_scale,
		ctx.local_solar_hour, ctx.camera_global_position, ctx.pivot_global_position)
	if _count_species(species) >= cap:
		debug_fail_cap += 1
		return
	var anchor_idx := _pick_anchor(species, ctx)
	if anchor_idx < 0:
		debug_fail_anchor += 1
		return
	var anchor := _environment.anchors[anchor_idx]
	if anchor.hero_weight <= 0.0:
		debug_fail_weight += 1
		return
	if _rng.randf() > anchor.hero_weight:
		debug_fail_rng += 1
		return
	var spawn_pos: Vector3 = ctx.backdrop_global_transform * anchor.local_transform.origin
	spawn_pos.y = FaunaMotionScript.anchor_hover_y(species)
	if not FaunaGating.spawn_distance_allowed(ctx.camera_global_position, spawn_pos):
		debug_fail_distance += 1
		return
	debug_spawn_ok += 1
	_spawn_agent(species, anchor_idx, ctx)


func _pick_species(ctx: FaunaPresentationContext) -> int:
	var weights: Array[float] = []
	var species_list: Array[int] = []
	for sp in [FaunaConstants.Species.BEE, FaunaConstants.Species.BUTTERFLY]:
		var act := FaunaGating.combined_activity(
			ctx.lit, ctx.render_blend, ctx.weather_activity_scale, sp, ctx.local_solar_hour)
		if act <= 0.0:
			continue
		var cap := FaunaGating.effective_species_cap(
			sp, ctx.lit, ctx.render_blend, ctx.weather_activity_scale,
			ctx.local_solar_hour, ctx.camera_global_position, ctx.pivot_global_position)
		if _count_species(sp) >= cap:
			continue
		weights.append(act)
		species_list.append(sp)
	if weights.is_empty():
		return -1
	var total := 0.0
	for w in weights:
		total += w
	var pick := _rng.randf() * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += weights[i]
		if pick <= acc:
			return species_list[i]
	return species_list[species_list.size() - 1]


func _pick_anchor(species: FaunaConstants.Species, ctx: FaunaPresentationContext) -> int:
	var candidates: Array[int] = []
	for i in range(_environment.anchors.size()):
		var anchor := _environment.anchors[i]
		if not FaunaGating.anchor_in_species_ring(species, anchor):
			continue
		if anchor.hero_weight <= 0.0:
			continue
		candidates.append(i)
	if candidates.is_empty():
		return -1
	if debug_spawn_near_pivot_only:
		var near: Array[int] = []
		var pivot_xz := Vector2(ctx.pivot_global_position.x, ctx.pivot_global_position.z)
		for idx in candidates:
			var anchor := _environment.anchors[idx]
			var world: Vector3 = ctx.backdrop_global_transform * anchor.local_transform.origin
			var d := Vector2(world.x - pivot_xz.x, world.z - pivot_xz.y).length()
			if d <= debug_spawn_max_dist_from_pivot_m:
				near.append(idx)
		if not near.is_empty():
			candidates = near
		elif console_log and not _logged_spawn_near_pivot:
			_logged_spawn_near_pivot = true
			_log("TEMP no anchors within %.1fm of pivot — using full garden ring"
				% debug_spawn_max_dist_from_pivot_m)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _spawn_agent(species: FaunaConstants.Species, anchor_index: int, ctx: FaunaPresentationContext) -> void:
	var rig: Dictionary = FaunaProxyMeshesScript.make_visual_rig(species)
	var root: Node3D = rig["root"]
	add_child(root)
	var agent = FaunaAgentStateScript.new()
	agent.species = species
	agent.mesh = root
	agent.wing_left = rig.get("wing_left")
	agent.wing_right = rig.get("wing_right")
	agent.anchor_index = anchor_index
	FaunaMotionScript.init_agent(agent, species, _rng)
	if species == FaunaConstants.Species.BEE:
		FaunaMotionScript.begin_bee_at_flower(agent, anchor_index, _environment, ctx.backdrop_global_transform, _rng)
	elif species == FaunaConstants.Species.BUTTERFLY:
		FaunaMotionScript.begin_butterfly_at_flower(
			agent, anchor_index, _environment, ctx.backdrop_global_transform, _rng)
	agent.lifetime = _rng.randf_range(14.0, 22.0) if species == FaunaConstants.Species.BEE \
		else _rng.randf_range(18.0, 28.0)
	agent.age = 0.0
	_agents.append(agent)
	_advance_agent(agent, ctx, 0.0)
	if console_log:
		var sp := _species_label(species)
		_log("spawn %s at %s  active=%d" % [sp, agent.mesh.global_position, _agents.size()])


func _may_spawn_species(species: FaunaConstants.Species) -> bool:
	if uncapped_population:
		return true
	if _agents.size() >= FaunaConstants.GLOBAL_MAX_AGENTS:
		return false
	var cap := FaunaConstants.MAX_BEE if species == FaunaConstants.Species.BEE \
		else FaunaConstants.MAX_BUTTERFLY
	return _count_species(species) < cap


func _nearest_anchor_index_xz(xz: Vector2) -> int:
	var best_idx := 0
	var best_d := INF
	for i in range(_environment.anchors.size()):
		var o: Vector3 = _environment.anchors[i].local_transform.origin
		var d := Vector2(o.x - xz.x, o.z - xz.y).length_squared()
		if d < best_d:
			best_d = d
			best_idx = i
	return best_idx


func _count_species(species: FaunaConstants.Species) -> int:
	var n := 0
	for a in _agents:
		if a.species == species:
			n += 1
	return n


func _despawn_all() -> void:
	if _agents.is_empty():
		return
	var n := _agents.size()
	for a in _agents:
		if a.mesh != null and is_instance_valid(a.mesh):
			a.mesh.queue_free()
	_agents.clear()
	if console_log:
		_log("despawn all (%d agents)" % n)


func _maybe_log_status(ctx: FaunaPresentationContext, delta: float) -> void:
	if not console_log:
		return
	_log_status_accum += delta
	if _log_status_accum < 2.5:
		return
	_log_status_accum = 0.0
	var line := ("status agents=%d lit=%.2f hour=%.1f paused=%s spawn_tries=%d ok=%d "
		+ "fail(species=%d cap=%d anchor=%d weight=%d rng=%d dist=%d) cam_dist_hint=%.1fm") % [
		_agents.size(), ctx.lit, ctx.local_solar_hour, ctx.paused,
		debug_spawn_attempts, debug_spawn_ok,
		debug_fail_no_species, debug_fail_cap, debug_fail_anchor,
		debug_fail_weight, debug_fail_rng, debug_fail_distance,
		_nearest_agent_cam_dist(ctx)]
	if line != _last_status_line:
		_last_status_line = line
		_log(line)
	var hint := FaunaGating.spawn_hour_hint(ctx.local_solar_hour)
	if _agents.is_empty() and debug_spawn_ok == 0 and debug_fail_no_species > 0 and not hint.is_empty():
		_log("spawn blocked: %s" % hint)


func _nearest_agent_cam_dist(ctx: FaunaPresentationContext) -> float:
	if _agents.is_empty():
		return -1.0
	var best := INF
	for a in _agents:
		if a.mesh == null:
			continue
		var p: Vector3 = a.mesh.global_position
		var d := Vector2(p.x - ctx.camera_global_position.x, p.z - ctx.camera_global_position.z).length()
		best = minf(best, d)
	return best


func _species_label(species: FaunaConstants.Species) -> String:
	match species:
		FaunaConstants.Species.BEE:
			return "bee"
		FaunaConstants.Species.BUTTERFLY:
			return "butterfly"
		_:
			return "ladybird"


func _log(message: String) -> void:
	print("[fauna] ", message)
