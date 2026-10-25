class_name FaunaController
extends Node3D

var _environment: FaunaEnvironment = null
var _backdrop: Node3D = null
var _enabled: bool = false
var _spawn_accum: float = 0.0
var _rng := RandomNumberGenerator.new()

class _Agent:
	var species: FaunaConstants.Species
	var mesh: MeshInstance3D
	var anchor_index: int
	var orbit_phase: float
	var lifetime: float
	var age: float

var _agents: Array[_Agent] = []


func _ready() -> void:
	_rng.randomize()


func bind_backdrop(backdrop: VillageBackdrop) -> void:
	clear_environment()
	_backdrop = backdrop
	_environment = backdrop.export_fauna_anchors()
	_enabled = _environment != null and not _environment.anchors.is_empty()


func clear_environment() -> void:
	_enabled = false
	_environment = null
	_backdrop = null
	for a in _agents:
		if a.mesh != null and is_instance_valid(a.mesh):
			a.mesh.queue_free()
	_agents.clear()


func tick(ctx: FaunaPresentationContext, delta: float) -> void:
	if not _enabled or _environment == null:
		return
	if ctx.lit < FaunaConstants.LIT_SPAWN_CUTOFF:
		_despawn_all()
		return
	if not ctx.paused:
		_update_agents(ctx, delta)
		_spawn_accum += delta
		var spawn_interval := 1.0 / FaunaConstants.SPAWN_TICK_HZ
		while _spawn_accum >= spawn_interval:
			_spawn_accum -= spawn_interval
			_try_spawn(ctx)


func _update_agents(ctx: FaunaPresentationContext, delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(_agents.size()):
		var a := _agents[i]
		a.age += delta
		if a.age >= a.lifetime:
			to_remove.append(i)
			continue
		if FaunaGating.should_despawn_agent(ctx.camera_global_position, a.mesh.global_position):
			to_remove.append(i)
			continue
		_advance_agent(a, ctx, delta)
	for i in range(to_remove.size() - 1, -1, -1):
		var idx: int = to_remove[i]
		_agents[idx].mesh.queue_free()
		_agents.remove_at(idx)


func _advance_agent(a: _Agent, ctx: FaunaPresentationContext, delta: float) -> void:
	var anchor := _environment.anchors[a.anchor_index]
	var base: Vector3 = ctx.backdrop_global_transform * anchor.local_transform.origin
	base.y += 0.45
	a.orbit_phase += delta * (2.5 if a.species == FaunaConstants.Species.BUTTERFLY else 4.0)
	var orbit_r := 0.25 if a.species == FaunaConstants.Species.LADYBIRD else 0.45
	var offset := Vector3(cos(a.orbit_phase) * orbit_r, sin(a.orbit_phase * 0.7) * 0.08, sin(a.orbit_phase) * orbit_r)
	if ctx.wind != null:
		var w := ctx.wind.get_horizontal_direction() * ctx.wind.strength_for_species(a.species)
		offset.x += w.x * sin(ctx.wind.get_phase()) * 0.15
		offset.z += w.y * sin(ctx.wind.get_phase()) * 0.15
	a.mesh.global_position = base + offset


func _try_spawn(ctx: FaunaPresentationContext) -> void:
	if _agents.size() >= FaunaConstants.GLOBAL_MAX_AGENTS:
		return
	var species := _pick_species(ctx)
	if species < 0:
		return
	var cap := FaunaGating.effective_species_cap(
		species, ctx.lit, ctx.render_blend, ctx.weather_activity_scale,
		ctx.game_day, ctx.camera_global_position, ctx.pivot_global_position)
	if _count_species(species) >= cap:
		return
	var anchor_idx := _pick_anchor(species, ctx)
	if anchor_idx < 0:
		return
	var anchor := _environment.anchors[anchor_idx]
	if anchor.hero_weight <= 0.0:
		return
	if _rng.randf() > anchor.hero_weight:
		return
	var spawn_pos: Vector3 = ctx.backdrop_global_transform * anchor.local_transform.origin
	spawn_pos.y += 0.45
	if not FaunaGating.spawn_distance_allowed(ctx.camera_global_position, spawn_pos):
		return
	_spawn_agent(species, anchor_idx, ctx)


func _pick_species(ctx: FaunaPresentationContext) -> int:
	var weights: Array[float] = []
	var species_list: Array[int] = []
	for sp in [FaunaConstants.Species.BEE, FaunaConstants.Species.BUTTERFLY, FaunaConstants.Species.LADYBIRD]:
		var act := FaunaGating.combined_activity(
			ctx.lit, ctx.render_blend, ctx.weather_activity_scale, sp, ctx.game_day)
		if act <= 0.0:
			continue
		var cap := FaunaGating.effective_species_cap(
			sp, ctx.lit, ctx.render_blend, ctx.weather_activity_scale,
			ctx.game_day, ctx.camera_global_position, ctx.pivot_global_position)
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
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _spawn_agent(species: FaunaConstants.Species, anchor_index: int, ctx: FaunaPresentationContext) -> void:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.collision_layer = 0
	mi.collision_mask = 0
	var mesh: Mesh
	match species:
		FaunaConstants.Species.BEE:
			mesh = SphereMesh.new()
			(mesh as SphereMesh).radius = 0.10
			(mesh as SphereMesh).height = 0.18
			mi.mesh = mesh
			mi.set_surface_override_material(0, _color_mat(Color(0.95, 0.85, 0.2)))
		FaunaConstants.Species.BUTTERFLY:
			mesh = BoxMesh.new()
			(mesh as BoxMesh).size = Vector3(0.28, 0.04, 0.20)
			mi.mesh = mesh
			mi.set_surface_override_material(0, _color_mat(Color(0.98, 0.98, 1.0)))
		FaunaConstants.Species.LADYBIRD:
			mesh = SphereMesh.new()
			(mesh as SphereMesh).radius = 0.06
			(mesh as SphereMesh).height = 0.10
			mi.mesh = mesh
			mi.set_surface_override_material(0, _color_mat(Color(0.85, 0.15, 0.12)))
	add_child(mi)
	var agent := _Agent.new()
	agent.species = species
	agent.mesh = mi
	agent.anchor_index = anchor_index
	agent.orbit_phase = _rng.randf() * TAU
	agent.lifetime = _rng.randf_range(8.0, 14.0) if species == FaunaConstants.Species.BEE else _rng.randf_range(12.0, 20.0)
	if species == FaunaConstants.Species.LADYBIRD:
		agent.lifetime = _rng.randf_range(15.0, 25.0)
	agent.age = 0.0
	_agents.append(agent)
	_advance_agent(agent, ctx, 0.0)


func _color_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c * 0.35
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _count_species(species: FaunaConstants.Species) -> int:
	var n := 0
	for a in _agents:
		if a.species == species:
			n += 1
	return n


func _despawn_all() -> void:
	for a in _agents:
		if a.mesh != null and is_instance_valid(a.mesh):
			a.mesh.queue_free()
	_agents.clear()
