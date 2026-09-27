## Fast unit tests for ArchetypePreset (ivy-agc).
extends GutTest

const ArchetypePreset = preload("res://src/params/archetype_preset.gd")
const IvyParams = preload("res://src/params/ivy_params.gd")
const WallSpec = preload("res://src/world/wall_spec.gd")


# ── all() ──────────────────────────────────────────────────────────────────

func test_all_has_exactly_dense_mid_sparse() -> void:
	var a := ArchetypePreset.all()
	assert_true(a.has("dense"),  "all() must contain 'dense'")
	assert_true(a.has("mid"),    "all() must contain 'mid'")
	assert_true(a.has("sparse"), "all() must contain 'sparse'")
	assert_eq(a.size(), 3, "all() must have exactly 3 entries")


# ── Dense frozen values ────────────────────────────────────────────────────

func test_dense_frozen_seeds() -> void:
	assert_eq(ArchetypePreset.for_name("dense").seeds, 7)

func test_dense_frozen_seed_y() -> void:
	assert_almost_eq(ArchetypePreset.for_name("dense").seed_y, 0.02, 1e-9)

func test_dense_frozen_day() -> void:
	assert_eq(ArchetypePreset.for_name("dense").day, 400)

func test_dense_frozen_branch_rate() -> void:
	assert_almost_eq(float(ArchetypePreset.for_name("dense").param_overrides["branch_rate"]), 1.7, 1e-9)

func test_dense_frozen_tip_cap_soft() -> void:
	assert_eq(int(ArchetypePreset.for_name("dense").param_overrides["tip_cap_soft"]), 360)

func test_dense_frozen_tip_cap_hard() -> void:
	assert_eq(int(ArchetypePreset.for_name("dense").param_overrides["tip_cap_hard"]), 600)

func test_dense_frozen_leaf_width_base() -> void:
	assert_almost_eq(float(ArchetypePreset.for_name("dense").param_overrides["leaf_width_base"]), 0.22, 1e-9)

func test_dense_frozen_internode_base() -> void:
	assert_almost_eq(float(ArchetypePreset.for_name("dense").param_overrides["internode_base"]), 0.02, 1e-9)

func test_dense_frozen_leaf_cap() -> void:
	assert_eq(int(ArchetypePreset.for_name("dense").param_overrides["leaf_cap"]), 400000)


# ── param_overrides keys are real IvyParams @export fields ────────────────

func test_all_override_keys_are_real_ivy_params_exports() -> void:
	var ref_params := IvyParams.new()
	# Build the property list once so we can check by name
	var prop_names: Array[String] = []
	for prop in ref_params.get_property_list():
		prop_names.append(prop["name"])

	for name in ArchetypePreset.names():
		var preset := ArchetypePreset.for_name(name)
		for key: String in preset.param_overrides.keys():
			# get() returning a non-null value means the property exists on the object
			var found := prop_names.has(key)
			assert_true(found,
				"%s: param_overrides key '%s' is not a declared IvyParams property" % [name, key])


# ── build_params() ─────────────────────────────────────────────────────────

func test_build_params_applies_overrides() -> void:
	var preset := ArchetypePreset.for_name("mid")
	var p := preset.build_params()
	assert_almost_eq(p.branch_rate, 1.0, 1e-9, "mid branch_rate must be applied")
	assert_eq(p.tip_cap_soft, 96,           "mid tip_cap_soft must be applied")

func test_build_params_leaves_non_overridden_at_default() -> void:
	var defaults := load("res://src/params/ivy_params_default.tres") as IvyParams
	var preset := ArchetypePreset.for_name("mid")
	var p := preset.build_params()
	# branch_light_exponent is never in any preset's overrides
	assert_almost_eq(p.branch_light_exponent, defaults.branch_light_exponent, 1e-9,
		"non-overridden field must match shipped default")

func test_build_params_returns_independent_copy() -> void:
	var p1 := ArchetypePreset.for_name("mid").build_params()
	var p2 := ArchetypePreset.for_name("mid").build_params()
	p1.branch_rate = 99.0
	assert_almost_eq(p2.branch_rate, 1.0, 1e-9,
		"build_params() must return an independent duplicate each call")


# ── seed_positions() ───────────────────────────────────────────────────────

func test_seed_positions_count_matches_seeds() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	for name in ArchetypePreset.names():
		var preset := ArchetypePreset.for_name(name)
		var positions := preset.seed_positions(spec)
		assert_eq(positions.size(), preset.seeds,
			"%s: seed_positions().size() must equal preset.seeds" % name)


func test_seed_positions_symmetric_about_x0() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	for name in ArchetypePreset.names():
		var preset := ArchetypePreset.for_name(name)
		if preset.seeds <= 1:
			continue
		var positions := preset.seed_positions(spec)
		var first := positions[0]
		var last := positions[positions.size() - 1]
		assert_almost_eq(first.x, -last.x, 1e-5,
			"%s: seed positions should be symmetric about x=0" % name)


func test_seed_positions_within_wall_bounds() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	var half_len := spec.length * 0.5
	for name in ArchetypePreset.names():
		var preset := ArchetypePreset.for_name(name)
		for pos in preset.seed_positions(spec):
			assert_true(absf(pos.x) <= half_len + 1e-5,
				"%s: seed x=%.3f exceeds half wall length %.3f" % [name, pos.x, half_len])


func test_seed_positions_seed_y_correct() -> void:
	var spec := load("res://src/world/wall_spec_default.tres") as WallSpec
	for name in ArchetypePreset.names():
		var preset := ArchetypePreset.for_name(name)
		for pos in preset.seed_positions(spec):
			assert_almost_eq(pos.y, preset.seed_y, 1e-9,
				"%s: seed y should equal preset.seed_y" % name)


# ── M-3 regression: seed_positions(null) must not crash ───────────────────
# Regression for ivy-6bq M-3: the preset-driven path in capture_wall_archetype.gd
# passes spec directly to seed_positions(); spec can be null if the world node
# doesn't expose wall_spec yet.  The legacy raw-override path in that tool
# guards with `spec.length * 0.5 if spec != null else 9.0`; seed_positions()
# must mirror that guard — returning the same count of positions it would with
# the default 20 m wall (half_len = 9.0) rather than null-dereffing.

func test_seed_positions_null_spec_returns_correct_count() -> void:
	# All three presets must survive a null spec and return preset.seeds positions.
	for name in ArchetypePreset.names():
		var preset := ArchetypePreset.for_name(name)
		var positions := preset.seed_positions(null)
		assert_eq(positions.size(), preset.seeds,
			"%s: seed_positions(null) must return preset.seeds positions, not crash" % name)

func test_seed_positions_null_spec_uses_fallback_half_len() -> void:
	# With null spec the fallback half_len is 9.0 (matching the legacy capture-tool
	# guard).  For a multi-seed preset the first position's x should equal
	# -(half_len - half_len*0.15) = -(9.0 * 0.85) = -7.65.
	var preset := ArchetypePreset.for_name("dense")   # seeds=7, multi-seed
	var positions := preset.seed_positions(null)
	var expected_usable := 9.0 * 0.85  # half_len=9.0, margin=9.0*0.15
	assert_almost_eq(positions[0].x, -expected_usable, 1e-5,
		"dense seed_positions(null): first x should use fallback half_len=9.0")
