class_name FaunaMotion
extends RefCounted

## Presentation-only trajectories for garden insects (SD-FAUNA, leaf-relative scale).


static func init_agent(agent, species: FaunaConstants.Species, rng: RandomNumberGenerator) -> void:
	agent.wing_phase = rng.randf() * TAU
	agent.travel_phase = rng.randf() * TAU
	agent.heading = rng.randf() * TAU
	agent.bee_trip_target_index = -1
	agent.flit_wobble_phase = rng.randf() * TAU
	agent.flit_heading = rng.randf() * TAU
	var span := FaunaConstants.butterfly_wingspan_m()
	match species:
		FaunaConstants.Species.BEE:
			agent.hover_radius = 0.0
			agent.travel_speed = 0.0
			agent.wing_beat_hz = rng.randf_range(14.0, 20.0)
			agent.cruise_speed_mps = rng.randf_range(0.32, 0.52)
		FaunaConstants.Species.BUTTERFLY:
			agent.hover_radius = rng.randf_range(span * 0.35, span * 0.65)
			agent.travel_speed = rng.randf_range(0.65, 1.05)
			agent.wing_beat_hz = FaunaConstants.BUTTERFLY_WING_FLAP_HZ
			agent.cruise_speed_mps = rng.randf_range(
				FaunaConstants.BUTTERFLY_FLIT_CRUISE_MPS * 0.85,
				FaunaConstants.BUTTERFLY_FLIT_CRUISE_MPS * 1.15)
			agent.butterfly_mode = FaunaAgentState.ButterflyMode.FLIT_AT_FLOWER
			agent.butterfly_linger_sec = rng.randf_range(0.8, 2.0)
		_:
			agent.hover_radius = FaunaConstants.bee_body_length_m()
			agent.travel_speed = 1.0
			agent.wing_beat_hz = 10.0


static func begin_bee_at_flower(
		agent,
		anchor_index: int,
		environment: FaunaEnvironment,
		backdrop: Transform3D,
		rng: RandomNumberGenerator) -> void:
	agent.anchor_index = anchor_index
	agent.path_to = anchor_world_pos(environment, anchor_index, backdrop, FaunaConstants.Species.BEE)
	agent.path_from = agent.path_to
	agent.path_segment_u = 1.0
	agent.bee_linger_sec = rng.randf_range(0.5, 1.2)


static func begin_butterfly_at_flower(
		agent,
		anchor_index: int,
		environment: FaunaEnvironment,
		backdrop: Transform3D,
		rng: RandomNumberGenerator) -> void:
	agent.anchor_index = anchor_index
	agent.path_to = anchor_world_pos(
		environment, anchor_index, backdrop, FaunaConstants.Species.BUTTERFLY)
	agent.path_from = agent.path_to
	agent.path_segment_u = 1.0
	agent.butterfly_mode = FaunaAgentState.ButterflyMode.FLIT_AT_FLOWER
	agent.butterfly_linger_sec = rng.randf_range(0.8, 2.0)
	agent.butterfly_partner = null
	agent.butterfly_is_race_leader = false


static func anchor_hover_y(species: FaunaConstants.Species) -> float:
	match species:
		FaunaConstants.Species.BEE:
			return 0.42 + FaunaConstants.bee_body_length_m() * 1.8 * FaunaConstants.BEE_VISUAL_SCALE
		FaunaConstants.Species.BUTTERFLY:
			return 0.48 + FaunaConstants.butterfly_wingspan_m() * 0.55
		_:
			return 0.45


static func anchor_world_pos(
		environment: FaunaEnvironment,
		anchor_index: int,
		backdrop: Transform3D,
		species: FaunaConstants.Species) -> Vector3:
	var anchor := environment.anchors[anchor_index]
	var p: Vector3 = backdrop * anchor.local_transform.origin
	p.y = anchor_hover_y(species)
	return p


static func advance(
		agent,
		environment: FaunaEnvironment,
		ctx: FaunaPresentationContext,
		anchor_base: Vector3,
		delta: float,
		rng: RandomNumberGenerator,
		spawn_near_pivot_only: bool,
		spawn_max_dist_from_pivot_m: float,
		all_agents: Array = []) -> void:
	agent.wing_phase += delta * agent.wing_beat_hz * TAU
	var wind_dir := Vector2.ZERO
	var wind_strength := 0.0
	var wind_phase := 0.0
	if ctx.wind != null:
		wind_dir = ctx.wind.get_horizontal_direction()
		wind_strength = ctx.wind.strength_for_species(agent.species)
		wind_phase = ctx.wind.get_phase()
	match agent.species:
		FaunaConstants.Species.BEE:
			_advance_bee(agent, environment, ctx, delta, rng, spawn_near_pivot_only, spawn_max_dist_from_pivot_m,
				wind_dir, wind_strength, wind_phase)
		FaunaConstants.Species.BUTTERFLY:
			_advance_butterfly(
				agent, environment, ctx, anchor_base, delta, rng,
				spawn_near_pivot_only, spawn_max_dist_from_pivot_m,
				wind_dir, wind_strength, wind_phase, all_agents)
		_:
			_advance_butterfly(
				agent, environment, ctx, anchor_base, delta, rng,
				spawn_near_pivot_only, spawn_max_dist_from_pivot_m,
				wind_dir, wind_strength, wind_phase, all_agents)


static func unlink_butterfly_partner(agent) -> void:
	if agent.butterfly_partner == null:
		return
	var other = agent.butterfly_partner
	agent.butterfly_partner = null
	if other.butterfly_partner == agent:
		other.butterfly_partner = null
		if other.butterfly_mode == FaunaAgentState.ButterflyMode.FOLLOWING \
				or other.butterfly_mode == FaunaAgentState.ButterflyMode.RACING:
			other.butterfly_mode = FaunaAgentState.ButterflyMode.FLIT_AT_FLOWER
			other.butterfly_race_sec = 0.0


static func _advance_bee(
		agent,
		environment: FaunaEnvironment,
		ctx: FaunaPresentationContext,
		delta: float,
		rng: RandomNumberGenerator,
		spawn_near_pivot_only: bool,
		spawn_max_dist_from_pivot_m: float,
		wind_dir: Vector2,
		wind_strength: float,
		wind_phase: float) -> void:
	var l := FaunaConstants.bee_body_length_m() * FaunaConstants.BEE_VISUAL_SCALE
	var world_pos: Vector3
	var yaw: float = agent.heading
	if agent.path_segment_u < 1.0:
		var seg_len := Vector2(agent.path_to.x - agent.path_from.x, agent.path_to.z - agent.path_from.z).length()
		seg_len = maxf(seg_len, 0.08)
		agent.path_segment_u += delta * agent.cruise_speed_mps / seg_len
		var u: float = clampf(agent.path_segment_u, 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		world_pos = agent.path_from.lerp(agent.path_to, u)
		world_pos.y += sin(agent.wing_phase) * l * 0.12
		var vel: Vector3 = agent.path_to - agent.path_from
		if Vector2(vel.x, vel.z).length_squared() > 1e-8:
			yaw = atan2(vel.x, vel.z)
		if agent.path_segment_u >= 1.0:
			if agent.bee_trip_target_index >= 0:
				agent.anchor_index = agent.bee_trip_target_index
			agent.bee_linger_sec = rng.randf_range(0.4, 1.0)
	else:
		world_pos = agent.path_to
		world_pos.y += sin(agent.wing_phase) * l * 0.08 + sin(agent.travel_phase) * l * 0.05
		agent.travel_phase += delta
		agent.bee_linger_sec -= delta
		if agent.bee_linger_sec <= 0.0:
			var next_idx := _pick_next_flower_index(
				environment, agent.anchor_index, ctx, spawn_near_pivot_only, spawn_max_dist_from_pivot_m, rng)
			if next_idx >= 0:
				agent.bee_trip_target_index = next_idx
				agent.path_from = world_pos
				agent.path_to = anchor_world_pos(
					environment, next_idx, ctx.backdrop_global_transform, FaunaConstants.Species.BEE)
				agent.path_segment_u = 0.0
				var vel2: Vector3 = agent.path_to - agent.path_from
				if Vector2(vel2.x, vel2.z).length_squared() > 1e-8:
					yaw = atan2(vel2.x, vel2.z)
	world_pos.x += wind_dir.x * sin(wind_phase) * wind_strength * l * 0.4
	world_pos.z += wind_dir.y * sin(wind_phase * 0.9) * wind_strength * l * 0.4
	_set_visual_transform(agent, world_pos, yaw, sin(agent.wing_phase) * 8.0, 0.0)


static func _advance_butterfly(
		agent,
		environment: FaunaEnvironment,
		ctx: FaunaPresentationContext,
		anchor_base: Vector3,
		delta: float,
		rng: RandomNumberGenerator,
		spawn_near_pivot_only: bool,
		spawn_max_dist_from_pivot_m: float,
		wind_dir: Vector2,
		wind_strength: float,
		wind_phase: float,
		all_agents: Array) -> void:
	var span := FaunaConstants.butterfly_wingspan_m()
	var world_pos: Vector3 = _agent_world_pos(agent)
	var yaw: float = agent.heading
	match agent.butterfly_mode:
		FaunaAgentState.ButterflyMode.RACING:
			world_pos = _advance_butterfly_race_leader(
				agent, world_pos, delta, span, wind_dir, wind_strength, wind_phase)
			yaw = atan2(agent.butterfly_race_dir_xz.x, agent.butterfly_race_dir_xz.y)
			agent.butterfly_race_sec -= delta
			if agent.butterfly_race_sec <= 0.0:
				_end_butterfly_chase(
					agent, environment, ctx, rng, spawn_near_pivot_only, spawn_max_dist_from_pivot_m)
		FaunaAgentState.ButterflyMode.FOLLOWING:
			world_pos = _advance_butterfly_follower(
				agent, world_pos, delta, span, wind_dir, wind_strength, wind_phase)
			agent.butterfly_race_sec -= delta
			if agent.butterfly_race_sec <= 0.0:
				_end_butterfly_chase(
					agent, environment, ctx, rng, spawn_near_pivot_only, spawn_max_dist_from_pivot_m)
			else:
				var leader = agent.butterfly_partner
				if leader != null and leader.mesh != null:
					var lp: Vector3 = leader.mesh.global_position
					yaw = atan2(lp.x - world_pos.x, lp.z - world_pos.z)
		FaunaAgentState.ButterflyMode.TO_FLOWER:
			world_pos = _advance_butterfly_to_flower(
				agent, world_pos, delta, span, rng, environment, ctx,
				spawn_near_pivot_only, spawn_max_dist_from_pivot_m, wind_dir, wind_strength, wind_phase)
			var vel: Vector3 = agent.path_to - agent.path_from
			if Vector2(vel.x, vel.z).length_squared() > 1e-8:
				yaw = atan2(vel.x, vel.z)
		_:
			world_pos = _advance_butterfly_flit_at_flower(
				agent, anchor_base, delta, span, rng, environment, ctx,
				spawn_near_pivot_only, spawn_max_dist_from_pivot_m,
				wind_dir, wind_strength, wind_phase, all_agents)
			yaw = agent.flit_heading
	var pitch: float = -6.0 + sin(agent.travel_phase * 1.3) * 8.0
	var roll: float = sin(agent.flit_wobble_phase * 2.1) * 22.0
	_set_visual_transform(agent, world_pos, yaw, pitch, roll)
	_apply_butterfly_wing_flap(agent)


static func _advance_butterfly_to_flower(
		agent,
		world_pos: Vector3,
		delta: float,
		span: float,
		rng: RandomNumberGenerator,
		environment: FaunaEnvironment,
		ctx: FaunaPresentationContext,
		spawn_near_pivot_only: bool,
		spawn_max_dist_from_pivot_m: float,
		wind_dir: Vector2,
		wind_strength: float,
		wind_phase: float) -> Vector3:
	agent.travel_phase += delta * agent.travel_speed
	if agent.path_segment_u < 1.0:
		var seg_len := Vector2(agent.path_to.x - agent.path_from.x, agent.path_to.z - agent.path_from.z).length()
		seg_len = maxf(seg_len, 0.06)
		agent.path_segment_u += delta * agent.cruise_speed_mps / seg_len
		var u: float = clampf(agent.path_segment_u, 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		world_pos = agent.path_from.lerp(agent.path_to, u)
		var vel: Vector3 = agent.path_to - agent.path_from
		var perp := Vector3(-vel.z, 0.0, vel.x)
		if perp.length_squared() > 1e-10:
			perp = perp.normalized()
		world_pos += perp * sin(agent.wing_phase * 1.4 + agent.travel_phase) * span * 0.55
		world_pos.y += sin(agent.wing_phase) * span * 0.18 + sin(agent.travel_phase * 2.7) * span * 0.08
		if agent.path_segment_u >= 1.0:
			agent.butterfly_mode = FaunaAgentState.ButterflyMode.FLIT_AT_FLOWER
			agent.butterfly_linger_sec = rng.randf_range(0.7, 1.8)
	else:
		agent.butterfly_mode = FaunaAgentState.ButterflyMode.FLIT_AT_FLOWER
		agent.butterfly_linger_sec = rng.randf_range(0.7, 1.8)
	world_pos.x += wind_dir.x * sin(wind_phase) * wind_strength * span * 0.5
	world_pos.z += wind_dir.y * sin(wind_phase * 0.85) * wind_strength * span * 0.5
	return world_pos


static func _advance_butterfly_flit_at_flower(
		agent,
		anchor_base: Vector3,
		delta: float,
		span: float,
		rng: RandomNumberGenerator,
		environment: FaunaEnvironment,
		ctx: FaunaPresentationContext,
		spawn_near_pivot_only: bool,
		spawn_max_dist_from_pivot_m: float,
		wind_dir: Vector2,
		wind_strength: float,
		wind_phase: float,
		all_agents: Array) -> Vector3:
	agent.travel_phase += delta * agent.travel_speed
	agent.flit_wobble_phase += delta * (2.8 + agent.travel_speed * 0.6)
	agent.flit_heading += sin(agent.flit_wobble_phase * 3.7) * delta * 4.5
	agent.flit_heading += cos(agent.flit_wobble_phase * 2.1) * delta * 2.2
	var r: float = agent.hover_radius
	var off := Vector3(
		sin(agent.flit_wobble_phase * 2.3) * r + sin(agent.travel_phase * 1.7) * r * 0.5,
		sin(agent.wing_phase) * span * 0.14 + sin(agent.travel_phase * 3.1) * span * 0.06,
		cos(agent.flit_wobble_phase * 1.9) * r * 0.9 + cos(agent.travel_phase * 2.3) * r * 0.35)
	var world_pos := anchor_base + off
	world_pos.x += wind_dir.x * sin(wind_phase) * wind_strength * span * 0.35
	world_pos.z += wind_dir.y * sin(wind_phase * 0.9) * wind_strength * span * 0.35
	agent.butterfly_linger_sec -= delta
	if agent.butterfly_linger_sec > 0.0:
		return world_pos
	if rng.randf() < FaunaConstants.BUTTERFLY_CHASE_PROB:
		var partner = _pick_butterfly_chase_partner(agent, all_agents, rng)
		if partner != null:
			_start_butterfly_chase(agent, partner, rng)
			return _agent_world_pos(agent)
	_schedule_butterfly_trip_to_flower(
		agent, environment, ctx, world_pos, rng, spawn_near_pivot_only, spawn_max_dist_from_pivot_m)
	return world_pos


static func _advance_butterfly_race_leader(
		agent,
		world_pos: Vector3,
		delta: float,
		span: float,
		wind_dir: Vector2,
		wind_strength: float,
		wind_phase: float) -> Vector3:
	var speed: float = agent.cruise_speed_mps * 4.2
	var dir: Vector2 = agent.butterfly_race_dir_xz
	agent.travel_phase += delta * 2.4
	var wobble := Vector2(
		sin(agent.travel_phase * 5.3) * 0.35,
		cos(agent.travel_phase * 4.7) * 0.35)
	var move_dir: Vector2 = (dir + wobble).normalized()
	world_pos.x += move_dir.x * speed * delta
	world_pos.z += move_dir.y * speed * delta
	world_pos.y = anchor_hover_y(FaunaConstants.Species.BUTTERFLY) \
		+ sin(agent.wing_phase) * span * 0.22 + sin(agent.travel_phase * 6.0) * span * 0.1
	world_pos.x += wind_dir.x * sin(wind_phase) * wind_strength * span * 0.25
	world_pos.z += wind_dir.y * sin(wind_phase) * wind_strength * span * 0.25
	return world_pos


static func _advance_butterfly_follower(
		agent,
		world_pos: Vector3,
		delta: float,
		span: float,
		wind_dir: Vector2,
		wind_strength: float,
		wind_phase: float) -> Vector3:
	var leader = agent.butterfly_partner
	if leader == null or leader.mesh == null:
		return world_pos
	var target: Vector3 = leader.mesh.global_position
	var to := target - world_pos
	var dist := Vector2(to.x, to.z).length()
	var speed: float = agent.cruise_speed_mps * 3.8
	var step: float = minf(dist, speed * delta)
	if dist > 0.001:
		world_pos.x += to.x / dist * step
		world_pos.z += to.z / dist * step
	world_pos.y = lerpf(
		world_pos.y,
		target.y + sin(agent.wing_phase) * span * 0.12,
		clampf(delta * 4.0, 0.0, 1.0))
	world_pos.x += wind_dir.x * sin(wind_phase) * wind_strength * span * 0.2
	world_pos.z += wind_dir.y * sin(wind_phase) * wind_strength * span * 0.2
	return world_pos


static func _start_butterfly_chase(follower, leader, rng: RandomNumberGenerator) -> void:
	var dir := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if dir.length_squared() < 0.01:
		dir = Vector2(1.0, 0.0)
	dir = dir.normalized()
	follower.butterfly_mode = FaunaAgentState.ButterflyMode.FOLLOWING
	follower.butterfly_is_race_leader = false
	follower.butterfly_partner = leader
	follower.butterfly_race_sec = FaunaConstants.BUTTERFLY_RACE_DURATION_SEC
	leader.butterfly_mode = FaunaAgentState.ButterflyMode.RACING
	leader.butterfly_is_race_leader = true
	leader.butterfly_partner = follower
	leader.butterfly_race_sec = FaunaConstants.BUTTERFLY_RACE_DURATION_SEC
	leader.butterfly_race_dir_xz = dir


static func _end_butterfly_chase(
		agent,
		environment: FaunaEnvironment,
		ctx: FaunaPresentationContext,
		rng: RandomNumberGenerator,
		spawn_near_pivot_only: bool,
		spawn_max_dist_from_pivot_m: float) -> void:
	if agent.butterfly_mode != FaunaAgentState.ButterflyMode.RACING \
			and agent.butterfly_mode != FaunaAgentState.ButterflyMode.FOLLOWING:
		return
	var partner = agent.butterfly_partner
	unlink_butterfly_partner(agent)
	var pos := _agent_world_pos(agent)
	_schedule_butterfly_trip_to_flower(
		agent, environment, ctx, pos, rng, spawn_near_pivot_only, spawn_max_dist_from_pivot_m)
	if partner != null and partner.species == FaunaConstants.Species.BUTTERFLY:
		var ppos := _agent_world_pos(partner)
		if partner.butterfly_mode != FaunaAgentState.ButterflyMode.TO_FLOWER:
			_schedule_butterfly_trip_to_flower(
				partner, environment, ctx, ppos, rng, spawn_near_pivot_only, spawn_max_dist_from_pivot_m)


static func _schedule_butterfly_trip_to_flower(
		agent,
		environment: FaunaEnvironment,
		ctx: FaunaPresentationContext,
		from_world: Vector3,
		rng: RandomNumberGenerator,
		spawn_near_pivot_only: bool,
		spawn_max_dist_from_pivot_m: float) -> void:
	var next_idx := _pick_next_flower_index(
		environment, agent.anchor_index, ctx, spawn_near_pivot_only, spawn_max_dist_from_pivot_m, rng)
	if next_idx < 0:
		agent.butterfly_mode = FaunaAgentState.ButterflyMode.FLIT_AT_FLOWER
		agent.butterfly_linger_sec = rng.randf_range(0.5, 1.2)
		return
	agent.bee_trip_target_index = next_idx
	agent.path_from = from_world
	agent.path_to = anchor_world_pos(
		environment, next_idx, ctx.backdrop_global_transform, FaunaConstants.Species.BUTTERFLY)
	agent.path_segment_u = 0.0
	agent.butterfly_mode = FaunaAgentState.ButterflyMode.TO_FLOWER


static func _pick_butterfly_chase_partner(agent, all_agents: Array, rng: RandomNumberGenerator):
	var candidates: Array = []
	for other in all_agents:
		if other == agent:
			continue
		if other.species != FaunaConstants.Species.BUTTERFLY:
			continue
		if other.butterfly_mode == FaunaAgentState.ButterflyMode.RACING \
				or other.butterfly_mode == FaunaAgentState.ButterflyMode.FOLLOWING:
			continue
		if other.butterfly_partner != null:
			continue
		candidates.append(other)
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _agent_world_pos(agent) -> Vector3:
	if agent.mesh == null:
		return Vector3.ZERO
	if agent.mesh.is_inside_tree():
		return agent.mesh.global_position
	return agent.mesh.position


static func _apply_butterfly_wing_flap(agent) -> void:
	if agent.wing_left == null or agent.wing_right == null:
		return
	var amp := FaunaConstants.BUTTERFLY_WING_FLAP_AMPLITUDE
	var flap: float = 1.0 + amp * sin(agent.wing_phase)
	if agent.butterfly_mode == FaunaAgentState.ButterflyMode.RACING:
		flap = 1.0 + amp * 1.35 * sin(agent.wing_phase)
	agent.wing_left.scale = Vector3(-flap, 1.0, flap)
	agent.wing_right.scale = Vector3(flap, 1.0, flap)


static func _set_visual_transform(agent, world_pos: Vector3, yaw: float, pitch: float, roll: float) -> void:
	if agent.mesh == null:
		return
	if agent.mesh.is_inside_tree():
		agent.mesh.global_position = world_pos
	else:
		agent.mesh.position = world_pos
	agent.mesh.basis = Basis.from_euler(Vector3(deg_to_rad(pitch), yaw, deg_to_rad(roll)))


static func _pick_next_flower_index(
		environment: FaunaEnvironment,
		current_index: int,
		ctx: FaunaPresentationContext,
		spawn_near_pivot_only: bool,
		spawn_max_dist_from_pivot_m: float,
		rng: RandomNumberGenerator) -> int:
	var candidates: Array[int] = []
	var pivot_xz := Vector2(ctx.pivot_global_position.x, ctx.pivot_global_position.z)
	for i in range(environment.anchors.size()):
		if i == current_index:
			continue
		var anchor := environment.anchors[i]
		if anchor.kind != FaunaConstants.AnchorKind.FLOWER:
			continue
		if not FaunaGating.anchor_in_species_ring(FaunaConstants.Species.BEE, anchor):
			continue
		if anchor.hero_weight <= 0.0:
			continue
		var world: Vector3 = ctx.backdrop_global_transform * anchor.local_transform.origin
		if spawn_near_pivot_only:
			var d := Vector2(world.x - pivot_xz.x, world.z - pivot_xz.y).length()
			if d > spawn_max_dist_from_pivot_m:
				continue
		candidates.append(i)
	if candidates.is_empty():
		return -1
	return candidates[rng.randi_range(0, candidates.size() - 1)]
