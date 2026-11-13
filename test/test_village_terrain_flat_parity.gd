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


func test_outside_disc_returns_zero() -> void:
	# SD-VILLAGE-TERRAIN-3 step 1: r >= lawn_radius → Y_BASE = 0.0
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var outside := g + Vector2(layout.lawn_radius + 5.0, 0.0)
	var y := VillageTerrain.sample_y(outside, layout, params, t_seed)
	assert_almost_eq(y, 0.0, 0.001, "outside disc r>lawn_radius → 0.0")


func test_exact_rim_returns_zero() -> void:
	# At exactly r = lawn_radius, rim_taper should force h → 0
	var layout := VillageLayout.generate(7)
	if layout.fallback:
		pass_test("fallback skip")
		return
	var params := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, params)
	var g := layout.hamlet_centre_xz
	var xz := g + Vector2(layout.lawn_radius, 0.0)
	var y := VillageTerrain.sample_y(xz, layout, params, t_seed)
	# At exact boundary, step 1 returns Y_BASE = 0.0
	assert_almost_eq(y, 0.0, 0.001, "at r=lawn_radius → 0.0")
