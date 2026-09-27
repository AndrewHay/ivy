## SD-ENV-11 — Opening-aware shell projection (W-031 north D_L, W-035 east gradient).
extends GutTest

const IvyParams = preload("res://src/params/ivy_params.gd")
const IvyEnvironment = preload("res://src/env/environment.gd")
const Solar = preload("res://src/env/solar.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const OpeningFootprintScript = preload("res://src/world/opening_footprint.gd")

const NORTH_DOOR_PROBE := Vector3(0.0, 1.75, -2.0)
const EAST_WINDOW_PROBE := Vector3(2.0, 1.75, 0.0)
const DL_TARGET_NORTH := 2.5

var _params: IvyParams
var _spec: TowerSpec
var _surface: SurfaceQuery


func before_each() -> void:
	_params = IvyParams.new()
	_spec = TowerSpec.new()
	_surface = SurfaceQuery.new()
	_surface.setup(null, null, TowerSdf.new(_spec), PackedByteArray(), _params)


func _assert_on_exterior_shell(projected: Vector3) -> void:
	assert_false(
		OpeningFootprintScript.in_any_opening(projected, _spec),
		"projected point must lie outside opening footprints (SD-ENV-11)"
	)
	assert_almost_eq(
		_surface.signed_distance(projected), 0.0, 0.001,
		"projected point must satisfy |Φ|≤1 mm (AR-FIELD-3)"
	)
	var r_xz := Vector2(projected.x, projected.z).length()
	assert_almost_eq(
		r_xz, _spec.radius_outer, 0.001,
		"projected point must lie on radius_outer cylinder"
	)


func _make_env() -> IvyEnvironment:
	var solar := Solar.new(_params)
	var env := IvyEnvironment.new()
	env.build(_params, _surface, solar)
	return env


func test_project_to_shell_snaps_north_door_probe_w031() -> void:
	var projected := _surface.project_to_shell(NORTH_DOOR_PROBE)
	_assert_on_exterior_shell(projected)


func test_project_to_shell_snaps_east_window_probe_w035() -> void:
	var projected := _surface.project_to_shell(EAST_WINDOW_PROBE)
	_assert_on_exterior_shell(projected)


func test_project_to_shell_exterior_outside_door_still_on_shell() -> void:
	# AR-FIELD-3 regression: solid north wall above the door band must still Newton-project.
	var outside := Vector3(
		0.0,
		_spec.door_height + 0.35,
		-(_spec.radius_outer + 0.35)
	)
	assert_false(
		OpeningFootprintScript.in_any_opening(outside, _spec),
		"regression probe must start outside the door footprint"
	)
	var projected := _surface.project_to_shell(outside)
	_assert_on_exterior_shell(projected)


func test_north_probe_d_l_w031_after_env_build() -> void:
	# W-031: north doorway probe D_L within ±30% of SD-ENV-10 target (test_light_bake bar).
	var env := _make_env()
	var d_l := env.sample_D_L(NORTH_DOOR_PROBE, 0, 0)
	gut.p("north door probe D_L = %f (target %.1f)" % [d_l, DL_TARGET_NORTH])
	assert_almost_eq(
		d_l, DL_TARGET_NORTH, DL_TARGET_NORTH * 0.30,
		"north door probe D_L within 30%% of 2.5 after env build (W-031 / SD-ENV-11)"
	)


func test_north_mean_p_bar_facing_unchanged() -> void:
	# Aggregate north-facing mean stays near the SD-ENV-10 diagnostic (~4.2 D_L).
	var env := _make_env()
	var mean_p := env.mean_p_bar_facing(Conv.NORTH)
	var mean_d_l := mean_p * IvyEnvironment.DL_SCALE
	gut.p("mean north-facing D_L = %f (p_bar %.2f)" % [mean_d_l, mean_p])
	assert_almost_eq(
		mean_d_l, 4.2, 4.2 * 0.30,
		"mean_p_bar_facing(NORTH) aggregate D_L unchanged near 4.2 (SD-ENV-10)"
	)


func test_east_probe_gradient_magnitude_w035() -> void:
	# W-035: |grad| was 57.7 when projection landed in the window void; local wall
	# scale is light_gradient_scale=4, so cap well below 2× that (<< prior saturation).
	var env := _make_env()
	var basis := _surface.tangent_basis_at(EAST_WINDOW_PROBE)
	var grad := env.grad_S_D_L(EAST_WINDOW_PROBE, basis, 0, 0)
	var mag := grad.length()
	gut.p("east window probe |grad_S_D_L| = %f" % mag)
	assert_lt(
		mag, _params.light_gradient_scale * 2.0,
		"east window probe gradient below 2× light_gradient_scale (W-035 / SD-ENV-11)"
	)
