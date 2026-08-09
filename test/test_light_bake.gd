extends GutTest

## W-019. Covers the spec section 5 sun model, the SD-ENV-10 regression target, and
## the AR-FIELD-6 coarse visibility products.
##
## The SurfaceQuery here is built with a null physics space, so raycasts never hit and
## the bake measures pure hemisphere geometry. Occlusion by the tower itself is
## exercised in the live scene (see `tools/diag_light_field.gd`), because GUT runs
## headless with no physics world.

const IvyParams = preload("res://src/params/ivy_params.gd")
const Solar = preload("res://src/env/solar.gd")
const LightBake = preload("res://src/env/light_bake.gd")
const TowerSpec = preload("res://src/world/tower_spec.gd")
const TowerSdf = preload("res://src/world/tower_sdf.gd")
const SurfaceQuery = preload("res://src/world/surface_query.gd")
const Physiology = preload("res://src/sim/physiology.gd")

const UNOBSTRUCTED_WALL_SVF := 0.5

var _params: IvyParams
var _solar: Solar
var _bake: LightBake
var _surface: SurfaceQuery


func before_each() -> void:
	_params = IvyParams.new()
	_solar = Solar.new(_params)
	_bake = LightBake.new(_params, _solar)
	_surface = SurfaceQuery.new()
	_surface.setup(null, null, TowerSdf.new(TowerSpec.new()), PackedByteArray(), _params)


func _d_l(p_bar: float) -> float:
	return 0.0864 * p_bar


func test_south_wall_matches_sd_env_10() -> void:
	# SD-ENV-10: south wall D_L about 26, saturated f_L.
	var mask := _bake.visibility_mask(_surface, Vector3(0.0, 1.75, 2.0), Conv.SOUTH)
	var d_l := _d_l(_bake.daily_mean_p_masked(Conv.SOUTH, UNOBSTRUCTED_WALL_SVF, mask))
	gut.p("south wall D_L = %f  f_L = %f" % [d_l, Physiology.f_L(d_l, _params)])
	assert_almost_eq(d_l, 26.0, 26.0 * 0.30, "south wall D_L within 30% of 26")
	assert_almost_eq(Physiology.f_L(d_l, _params), 1.0, 1e-6, "south wall f_L saturated")


func test_north_wall_matches_sd_env_10() -> void:
	# SD-ENV-10: north wall D_L about 2.5, f_L about 0.57.
	var mask := _bake.visibility_mask(_surface, Vector3(0.0, 1.75, -2.0), Conv.NORTH)
	var d_l := _d_l(_bake.daily_mean_p_masked(Conv.NORTH, UNOBSTRUCTED_WALL_SVF, mask))
	gut.p("north wall D_L = %f  f_L = %f" % [d_l, Physiology.f_L(d_l, _params)])
	assert_almost_eq(d_l, 2.5, 2.5 * 0.30, "north wall D_L within 30% of 2.5")
	assert_almost_eq(Physiology.f_L(d_l, _params), 0.57, 0.10, "north wall f_L about 0.57")


func test_south_north_growth_asymmetry() -> void:
	var south := _d_l(_bake.daily_mean_p_masked(Conv.SOUTH, UNOBSTRUCTED_WALL_SVF, 0xFFFFFF))
	var north_mask := _bake.visibility_mask(_surface, Vector3(0.0, 1.75, -2.0), Conv.NORTH)
	var north := _d_l(_bake.daily_mean_p_masked(Conv.NORTH, UNOBSTRUCTED_WALL_SVF, north_mask))
	assert_gt(south / north, 4.0, "south wall carries several times the north wall's light")
	var ratio := Physiology.f_L(south, _params) / Physiology.f_L(north, _params)
	gut.p("f_L ratio south/north = %f" % ratio)
	assert_gt(ratio, 1.4, "growth-rate ratio close to the SD-ENV-10 1.76x figure")


func test_no_light_at_night() -> void:
	for hour in [0, 1, 2, 3, 22, 23]:
		assert_eq(
			_bake.p_at(Conv.SOUTH, 1.0, 1.0, hour), 0.0, "hour %d is fully dark" % hour
		)


func test_direct_term_vanishes_when_sun_is_behind_the_surface() -> void:
	# spec section 5 max(0, n . S); SD-CONV-3 requires n to be the outward normal.
	assert_eq(_bake.p_direct(Conv.NORTH, 1.0, 12), 0.0, "north wall gets no noon sun")
	assert_gt(_bake.p_direct(Conv.SOUTH, 1.0, 12), 0.0, "south wall does")
	assert_eq(_bake.p_direct(Conv.GRAVITY, 1.0, 12), 0.0, "a downward face gets none")


func test_diffuse_term_scales_with_svf() -> void:
	var full := _bake.p_diffuse(1.0, 12)
	assert_almost_eq(_bake.p_diffuse(0.5, 12), full * 0.5, 1e-4)
	assert_eq(_bake.p_diffuse(0.0, 12), 0.0)


func test_diffuse_baseline_is_the_out_of_shell_fallback() -> void:
	# SD-EDGE-15: an unallocated read returns diffuse-only light at SVF = 1.
	var baseline := _bake.diffuse_baseline_p_bar()
	assert_gt(baseline, 0.0)
	assert_almost_eq(baseline, _bake.daily_mean_p(Conv.UP, 1.0, 0.0), 1e-4)
	assert_lt(
		_d_l(baseline),
		_d_l(_bake.daily_mean_p_masked(Conv.SOUTH, UNOBSTRUCTED_WALL_SVF, 0xFFFFFF)),
		"the baseline is dimmer than a sunlit wall"
	)


func test_svf_hemisphere_geometry() -> void:
	# SD-CONV-4: hemisphere about +Y, restricted to the hemisphere about n.
	var wall := _bake.sky_view_factor(_surface, Vector3(0.0, 1.75, 2.0), Conv.SOUTH)
	assert_almost_eq(wall, 0.5, 0.02, "an unobstructed vertical wall sees half the sky")
	var top := _bake.sky_view_factor(_surface, Vector3(0.0, 3.65, 1.0), Conv.UP)
	assert_almost_eq(top, 1.0, 0.02, "an unobstructed upward face sees all of it")
	var under := _bake.sky_view_factor(_surface, Vector3(0.0, -0.5, 1.0), Conv.GRAVITY)
	assert_almost_eq(under, 0.0, 0.02, "a downward face sees none of it")


func test_visibility_mask_only_sets_hours_the_sun_can_reach() -> void:
	var south := _bake.visibility_mask(_surface, Vector3(0.0, 1.75, 2.0), Conv.SOUTH)
	assert_true(_bake.mask_has_hour(south, 12), "south wall is lit at noon")
	assert_false(_bake.mask_has_hour(south, 0), "nothing is lit at midnight")
	var north := _bake.visibility_mask(_surface, Vector3(0.0, 1.75, -2.0), Conv.NORTH)
	assert_false(_bake.mask_has_hour(north, 12), "north wall is not lit at noon")
	assert_true(
		_bake.mask_has_hour(north, 6) or _bake.mask_has_hour(north, 18),
		"north wall catches the low early or late sun"
	)
	var down := _bake.visibility_mask(_surface, Vector3(0.0, -0.5, 1.0), Conv.GRAVITY)
	assert_eq(down, 0, "a downward face is never directly lit")


func test_bake_is_deterministic() -> void:
	# INV-7: the hemisphere sample set is a fixed quasirandom sequence, never an RNG.
	var other := LightBake.new(IvyParams.new(), Solar.new(IvyParams.new()))
	var p := Vector3(1.2, 1.4, 1.6)
	for n in [Conv.SOUTH, Conv.NORTH, Conv.EAST, Conv.UP]:
		assert_eq(
			_bake.sky_view_factor(_surface, p, n), other.sky_view_factor(_surface, p, n)
		)
		assert_eq(
			_bake.visibility_mask(_surface, p, n), other.visibility_mask(_surface, p, n)
		)
	assert_eq(_bake.sky_view_factor(_surface, p, Conv.SOUTH), _bake.sky_view_factor(_surface, p, Conv.SOUTH))


func test_coarse_grid_trilerps_up_to_fine_samples() -> void:
	# AR-FIELD-6: SVF and visibility bake coarse and interpolate up.
	var bounds := AABB(Vector3(-2.4, -0.2, -2.4), Vector3(4.8, 4.2, 4.8))
	_bake.bake(_surface, bounds)
	assert_gt(_bake.coarse_count(), 0, "coarse cells were allocated")
	var south := _bake.svf_at(Vector3(0.0, 1.75, 2.0))
	assert_almost_eq(south, 0.5, 0.08, "trilerped south wall SVF")
	assert_between(_bake.visibility_at(Vector3(0.0, 1.75, 2.0), 12), 0.5, 1.0)
	assert_almost_eq(_bake.visibility_at(Vector3(0.0, 1.75, 2.0), 0), 0.0, 1e-6)
