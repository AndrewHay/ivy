## ivy-9xp — the guard that keeps `LightBakeCache`'s key honest as the codebase moves.
##
## The cache is only safe if its key covers every input to the bake. Two ways that decays:
## someone adds an `@export` to `IvyParams` and nobody asks whether the bake reads it, or
## someone adds a geometry backend with no content identity. Both are silent — a too-narrow key
## produces a *hit*, not an error. These tests are the thing that makes them loud.
extends GutTest

const IvyParams = preload("res://src/params/ivy_params.gd")
const LightBakeCache = preload("res://src/env/light_bake_cache.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")
const WallSdf = preload("res://src/world/wall_sdf.gd")

const PARAMS_PATH := "res://src/params/ivy_params.gd"

## Parameters the coarse bake provably cannot observe, reviewed one at a time. The pairing with
## `IvyParams.BAKE_AFFECTING` must be exhaustive: a name in neither list fails the first test
## below, which is how a newly declared parameter forces the question "does the bake read this?"
## instead of defaulting to "no" the way an unlisted name silently would.
const BAKE_IRRELEVANT: Array[String] = [
	"adhesion_base",
	"adhesion_range",
	"branch_angle_max",
	"branch_angle_min",
	"branch_crowd_exponent",
	"branch_light_exponent",
	"branch_offset",
	"branch_rate",
	"branch_scale_floor",
	"contact_distance",
	"crowding_base",
	"crowding_decay",
	"crowding_gradient_scale",
	"dev_build",
	"diel_exponent",
	"diel_gate_enabled",
	"diel_night_floor",
	"direction_memory",
	"droop_base",
	"droop_shade_gain",
	"field_sample_jitter_ratio",
	"gradient_epsilon_ratio",
	"gravity_exponent",
	"ground_y_min",
	"internode_base",
	"internode_jitter",
	"internode_shade_gain",
	"leaf_cap",
	"leaf_crowd_floor",
	"leaf_crowd_floor_sun",
	"leaf_crowd_k",
	"leaf_crowd_sun_dense_c",
	"leaf_crowd_sun_dense_f_l",
	"leaf_crowd_sun_suppress_gain",
	"leaf_crowd_suppress",
	"leaf_expand_distance",
	"leaf_healthy_base",
	"leaf_healthy_gain",
	"leaf_jitter_roll",
	"leaf_jitter_tilt",
	"leaf_jitter_yaw",
	"leaf_light_scale_base",
	"leaf_light_scale_gain",
	"leaf_offset_base",
	"leaf_offset_ladder",
	"leaf_offset_step",
	"leaf_order_falloff",
	"leaf_out_of_plane",
	"leaf_photo_cant",
	"leaf_shade_tint",
	"leaf_size_sigma",
	"leaf_sun_tint",
	"leaf_tip_suppress",
	"leaf_weathered_tint",
	"leaf_width_base",
	"light_K",
	"light_elevation_exponent_diffuse",
	"light_gradient_scale",
	"light_memory",
	# Geometric escape fraction only — see the note on BAKE_AFFECTING for why this moved here.
	"light_p_leak",
	"light_p_max",
	"light_p_sky",
	"light_seek_max",
	"light_seek_min",
	"light_warmup_days",
	"max_float",
	"max_growth_rate",
	"max_segments_per_tick",
	"persistence_base",
	"phyllotaxy_divergence",
	"phyllotaxy_flatten",
	"random_base",
	"random_new_mix",
	"reference_DLI",
	"render_sun_blend_hi",
	"render_sun_blend_lo",
	"retire_margin",
	"segment_length",
	"silhouette_height_frac",
	"silhouette_min_tips",
	"sim_tick",
	"speed_fast",
	"speed_grow",
	"speed_watch",
	"stall_days",
	"stall_rate",
	"start_hour",
	"stem_order_falloff",
	"stem_radius_base",
	"stem_tip_taper",
	"tip_cap_hard",
	"tip_cap_soft",
	"upward_base",
	"weather_direct",
	"weather_sky",
]


## Parsed from the declarations rather than kept as a list here, following
## `test_params_conformance.gd`: a parameter added without being classified has to show up.
func _exported_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for line in FileAccess.get_file_as_string(PARAMS_PATH).split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("@export var "):
			continue
		var rest := trimmed.substr("@export var ".length())
		var cut := rest.find(":")
		if cut < 0:
			cut = rest.find(" ")
		if cut > 0:
			names.append(rest.substr(0, cut).strip_edges())
	return names


func _unclassified(names: PackedStringArray) -> PackedStringArray:
	var missing: PackedStringArray = []
	for name in names:
		if not IvyParams.BAKE_AFFECTING.has(name) and not BAKE_IRRELEVANT.has(name):
			missing.append(name)
	missing.sort()
	return missing


func test_every_exported_parameter_is_classified_for_the_bake_cache() -> void:
	var names := _exported_names()
	assert_gt(names.size(), 30, "the exported parameter list must be non-trivial to scan")
	assert_eq(
		_unclassified(names), PackedStringArray(),
		("every IvyParams export must be listed in IvyParams.BAKE_AFFECTING or in this test's "
		+ "BAKE_IRRELEVANT. An unlisted parameter is treated as not affecting the bake, which "
		+ "means a cached bake survives a change to it — decide which list it belongs in.")
	)


## Negative control. A conformance test that cannot fail is decoration, so feed the checker a
## parameter it has never heard of and confirm it reports it.
func test_the_classification_guard_reports_an_unclassified_parameter() -> void:
	var names := _exported_names()
	names.append("ghost_parameter_added_without_review")
	assert_eq(
		_unclassified(names),
		PackedStringArray(["ghost_parameter_added_without_review"]),
		"the guard must name a parameter that appears in neither list"
	)


## The other direction: a classified name that no longer exists means the lists are drifting
## from the declarations and a stale entry could be masking a renamed parameter.
func test_no_classified_name_has_been_deleted_or_renamed() -> void:
	var names := _exported_names()
	var orphans: PackedStringArray = []
	for name in IvyParams.BAKE_AFFECTING:
		if not names.has(name):
			orphans.append(name)
	for name in BAKE_IRRELEVANT:
		if not names.has(name):
			orphans.append(name)
	assert_eq(orphans, PackedStringArray(), "classified names must still be declared")


func test_the_two_classifications_do_not_overlap() -> void:
	var both: PackedStringArray = []
	for name in IvyParams.BAKE_AFFECTING:
		if BAKE_IRRELEVANT.has(name):
			both.append(name)
	assert_eq(both, PackedStringArray(), "a parameter must be in exactly one classification")


# --- Backend identity (ivy-9xp layer 1) ---


func test_spec_hash_is_determined_by_values_not_by_instance() -> void:
	var a := WallSpec.new()
	var b := WallSpec.new()
	assert_eq(
		SpecHash.of("WallSdf", a), SpecHash.of("WallSdf", b),
		"two specs holding the same values must hash the same, or the cache never hits"
	)
	var loaded := load("res://src/world/wall_spec_default.tres") as WallSpec
	assert_eq(
		SpecHash.of("WallSdf", loaded), SpecHash.of("WallSdf", a),
		("a spec loaded from disk must hash like an equal one built in code — resource_path and "
		+ "other engine-side properties must stay out of the digest")
	)


func test_spec_hash_moves_with_every_exported_field() -> void:
	var base := SpecHash.of("WallSdf", WallSpec.new())
	for field in ["length", "height", "thickness"]:
		var spec := WallSpec.new()
		spec.set(field, float(spec.get(field)) + 0.5)
		assert_ne(SpecHash.of("WallSdf", spec), base, "%s changes the geometry" % field)
	var brick := WallSpec.new()
	brick.brick_physical_size = Vector2(2.0, 1.0)
	assert_ne(
		SpecHash.of("WallSdf", brick), base,
		"reflection must cover non-scalar fields too, without anyone listing them"
	)


func test_analytic_backends_supply_distinct_identities() -> void:
	var wall := SurfaceQuery.new()
	wall.setup(null, null, WallSdf.new(WallSpec.new()), PackedByteArray(), IvyParams.new())
	var tower := SurfaceQuery.new()
	tower.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), IvyParams.new())
	assert_eq(wall.bake_identity().size(), LightBakeCache.HASH_BYTES, "WallSdf must identify itself")
	assert_eq(tower.bake_identity().size(), LightBakeCache.HASH_BYTES, "TowerSdf must identify itself")
	assert_ne(wall.bake_identity(), tower.bake_identity(), "backends must not share a key")


## Occlusion comes from the physics space, so a query without one bakes a world where every ray
## escapes. Those bakes are real cache entries in the unit suite and must never be handed to a
## session that has collision geometry attached.
func test_identity_separates_bakes_with_and_without_a_physics_space() -> void:
	var spec := WallSpec.new()
	var holder := Node3D.new()
	add_child_autofree(holder)
	await get_tree().physics_frame
	var spaceless := SurfaceQuery.new()
	spaceless.setup(null, null, WallSdf.new(spec), PackedByteArray(), IvyParams.new())
	var spaced := SurfaceQuery.new()
	spaced.setup(
		holder.get_world_3d().direct_space_state,
		null,
		WallSdf.new(spec),
		PackedByteArray(),
		IvyParams.new()
	)
	assert_ne(
		spaceless.bake_identity(), spaced.bake_identity(),
		"a space-less bake must not share a cache key with a bake that can see occluders"
	)
