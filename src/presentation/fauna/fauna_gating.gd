class_name FaunaGating
extends RefCounted

const VillagePresentationScale = preload("res://src/world/village_presentation_scale.gd")

## Human-readable hint when `_pick_species` fails (hour gates, etc.).
static func spawn_hour_hint(local_solar_hour: float) -> String:
	var bee := species_hour_gate(FaunaConstants.Species.BEE, local_solar_hour)
	var fly := species_hour_gate(FaunaConstants.Species.BUTTERFLY, local_solar_hour)
	if bee > 0.0 and fly > 0.0:
		return ""
	if bee <= 0.0 and fly <= 0.0:
		return ("no bees/butterflies at solar %.1fh (bees ~6:30–18:00, butterflies ~7:30–17:00)"
			% local_solar_hour)
	if bee <= 0.0:
		return "bees off at solar %.1fh (active ~6:30–18:00)" % local_solar_hour
	return "butterflies off at solar %.1fh (active ~7:30–17:00)" % local_solar_hour


static func hero_weight_at_xz(xz: Vector2) -> float:
	var r := xz.length()
	if r <= FaunaConstants.HERO_HARD_EXCLUSION_M:
		return 0.0
	if r >= FaunaConstants.HERO_SOFT_FADE_M:
		return 1.0
	return smoothstep(
		FaunaConstants.HERO_HARD_EXCLUSION_M,
		FaunaConstants.HERO_SOFT_FADE_M,
		r)


static func timelapse_density_scale(render_blend: float) -> float:
	return lerpf(0.25, 1.0, clampf(render_blend, 0.0, 1.0))


static func species_hour_gate(species: FaunaConstants.Species, hour: float) -> float:
	match species:
		FaunaConstants.Species.BEE:
			if hour < 6.5 or hour >= 18.0:
				return 0.0
			if hour < 8.0:
				return 0.45
			return _peak_boost(hour, 10.0, 15.0)
		FaunaConstants.Species.BUTTERFLY:
			if hour < 7.5 or hour >= 17.0:
				return 0.0
			if hour < 9.0:
				return 0.45
			return _peak_boost(hour, 11.0, 14.0)
		FaunaConstants.Species.LADYBIRD:
			if hour < 10.0 or hour >= 16.0:
				return 0.0
			return 1.0
		_:
			return 0.0


static func _peak_boost(hour: float, peak_start: float, peak_end: float) -> float:
	if hour >= peak_start and hour <= peak_end:
		return 1.0
	return 0.65


static func combined_activity(
		lit: float,
		render_blend: float,
		weather_activity_scale: float,
		species: FaunaConstants.Species,
		local_solar_hour: float) -> float:
	if lit < FaunaConstants.LIT_SPAWN_CUTOFF:
		return 0.0
	var gate := species_hour_gate(species, local_solar_hour)
	if gate <= 0.0:
		return 0.0
	return lit * gate * weather_activity_scale * timelapse_density_scale(render_blend)


static func camera_cap_scale(camera_global: Vector3, pivot_global: Vector3) -> float:
	var dx := camera_global.x - pivot_global.x
	var dz := camera_global.z - pivot_global.z
	if Vector2(dx, dz).length() < FaunaConstants.HERO_CAMERA_CAP_SCALE_DIST_M:
		return FaunaConstants.HERO_CAMERA_CAP_SCALE
	return 1.0


static func effective_species_cap(
		species: FaunaConstants.Species,
		lit: float,
		render_blend: float,
		weather_activity_scale: float,
		local_solar_hour: float,
		camera_global: Vector3,
		pivot_global: Vector3) -> int:
	var base := _base_cap(species)
	var activity := combined_activity(lit, render_blend, weather_activity_scale, species, local_solar_hour)
	if activity <= 0.0:
		return 0
	var scaled := int(floor(float(base) * activity * camera_cap_scale(camera_global, pivot_global)))
	if activity > 0.08 and scaled == 0:
		scaled = 1
	return maxi(scaled, 0)


static func _base_cap(species: FaunaConstants.Species) -> int:
	match species:
		FaunaConstants.Species.BEE:
			return FaunaConstants.MAX_BEE
		FaunaConstants.Species.BUTTERFLY:
			return FaunaConstants.MAX_BUTTERFLY
		FaunaConstants.Species.LADYBIRD:
			return FaunaConstants.MAX_LADYBIRD
		_:
			return 0


static func should_despawn_agent(camera_global: Vector3, agent_global: Vector3) -> bool:
	return _xz_distance(camera_global, agent_global) > VillagePresentationScale.scaled_lod_despawn_m()


static func spawn_distance_allowed(camera_global: Vector3, spawn_global: Vector3) -> bool:
	# Must match scaled LOD despawn — spawning in the forbid band caused one-frame
	# spawn→despawn (ivy-177 QA: spawn_ok>0 but FAUNA_COUNT 0).
	return _xz_distance(camera_global, spawn_global) <= VillagePresentationScale.scaled_lod_despawn_m()


static func anchor_in_species_ring(species: FaunaConstants.Species, anchor: FaunaAnchor) -> bool:
	var r := Vector2(anchor.local_transform.origin.x, anchor.local_transform.origin.z).length()
	match species:
		FaunaConstants.Species.LADYBIRD:
			if anchor.kind != FaunaConstants.AnchorKind.CLOVER:
				return false
			return r >= FaunaConstants.GARDEN_RING_INNER_M \
				and r <= VillagePresentationScale.scaled_clover_outer_m()
		_:
			if anchor.kind != FaunaConstants.AnchorKind.FLOWER:
				return false
			return r >= FaunaConstants.GARDEN_RING_INNER_M \
				and r <= VillagePresentationScale.scaled_garden_outer_m()


static func _xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
