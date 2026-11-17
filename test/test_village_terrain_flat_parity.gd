## AC-VT1: variant=1 and authored/classic layout → sample_y ≡ 0.0 everywhere (INV-15).
## SD-VILLAGE-TERRAIN-3 flat-legacy gate; AR-VT-DECIDE-3.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const _SEEDS: Array[int] = [1, 7, 12]
const _PROBE_STEP := 8.0
const _PROBE_HALF := 40.0


static func _probes(centre: Vector2) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var x := -_PROBE_HALF
	while x <= _PROBE_HALF:
		var z := -_PROBE_HALF
		while z <= _PROBE_HALF:
			pts.append(centre + Vector2(x, z))
			z += _PROBE_STEP
		x += _PROBE_STEP
	return pts


func test_variant1_returns_zero_on_generated_layouts() -> void:
	# AC-VT1 — explicit variant=1 flat legacy
	for seed: int in _SEEDS:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			pass_test("fallback skip seed %d" % seed)
			continue
		var params := VillageTerrainParams.production()
		params.variant = 1
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		for p: Vector2 in _probes(layout.hamlet_centre_xz):
			var y := VillageTerrain.sample_y(p, layout, params, t_seed)
			if not is_zero_approx(y):
				fail_test("variant=1 seed=%d: expected 0 at %s, got %.4f" % [seed, str(p), y])
				return
	pass_test("all variant=1 probes returned 0.0")


func test_authored_layout_returns_zero() -> void:
	# AC-VT1 — authored (classic) layout must return 0.0 everywhere
	var layout := VillageLayout.authored()
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	for p: Vector2 in _probes(Vector2.ZERO):
		var y := VillageTerrain.sample_y(p, layout, params, t_seed)
		if not is_zero_approx(y):
			fail_test("authored layout: expected 0 at %s, got %.4f" % [str(p), y])
			return
	pass_test("all authored layout probes returned 0.0")


## ivy-82zn.14.14: the old "outside the disc / at the rim → 0" contract is retired for variant 0
## (one field from the hero to the far mesh edge, AC-LT-SEAM). Variant 1 and classic keep the flat
## lawn and the flat legacy hills (AR-LF-TESTS row test_village_terrain_flat_parity).

const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsParams = preload("res://src/playground/hills_params.gd")


func test_variant1_hills_are_flat_legacy() -> void:
	var p := VillageTerrainParams.production()
	p.variant = 1
	var layout := VillageLayout.generate(7, p)
	var hp := HillsParams.production()
	assert_false(HillsHeightfield.delegates_to_village_terrain(layout, hp), "variant 1 does not delegate")
	var legacy := HillsParams.production()
	legacy.variant = 1
	var g := layout.hamlet_centre_xz
	for r in [30.0, 70.0, 120.0, 200.0]:
		var xz := g + Vector2(r, 0.0)
		assert_eq(HillsHeightfield.sample_y(xz, layout, hp), HillsHeightfield.sample_y(xz, layout, legacy),
			"variant 1 hills == flat legacy at r %.0f" % r)
	var mesh := HillsHeightfield.build_mesh(layout, hp)
	var legacy_mesh := HillsHeightfield.build_flat_legacy_mesh(layout, hp)
	assert_eq(mesh.surface_get_array_len(0), legacy_mesh.surface_get_array_len(0), "flat legacy hills mesh")


func test_classic_hills_are_flat_legacy() -> void:
	var layout := VillageLayout.authored()
	var hp := HillsParams.production()
	assert_false(HillsHeightfield.delegates_to_village_terrain(layout, hp), "classic does not delegate")
	assert_almost_eq(HillsHeightfield.sample_y(Vector2(0.0, 10.0), layout, hp),
		VillageBackdrop.LAWN_GROUND_Y_OFFSET, 1e-6, "classic: inside hill_inner (20 m) at the lawn datum")
	assert_gt(HillsHeightfield.sample_y(Vector2(0.0, 60.0), layout, hp),
		VillageBackdrop.LAWN_GROUND_Y_OFFSET, "classic: the legacy ramp rises outside hill_inner")
