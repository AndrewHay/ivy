## Tests for SkySun's pure arithmetic helpers (SD-TIME-4 / W-059).
##
## The helpers — lit_for, light_color_for, ambient_energy_for, background_energy_for —
## are static so they can be exercised headlessly without a rendering device.
## Each assertion is chosen so that removing the behaviour under test causes a clear failure:
##   • lit_for tests: wrong smoothstep bounds or wrong edge values fail immediately.
##   • light_color_for tests: a reversed lerp (dawn↔noon swapped) fails the warm/cool checks.
##   • energy tests: swapping night/day floors or wrong lerpf direction fails both inequalities.
##
## NOT tested here: that SkySun actually writes these values onto the DirectionalLight3D and
## Environment — those writes are scene-graph side-effects that require a rendering device.
## Smoke coverage for the write path comes from tools/ui_scripts/qa_sun_track.txt.
extends GutTest


## lit_for — 0 when the sun is below the horizon.
func test_lit_zero_when_sun_at_or_below_horizon() -> void:
	assert_almost_eq(SkySun.lit_for(-1.0), 0.0, 1e-6,
		"sun far below horizon must give lit = 0")
	assert_almost_eq(SkySun.lit_for(0.0), 0.0, 1e-6,
		"sun at exact horizon (s_y = 0) must give lit = 0")


## lit_for — 1 once the sun clears the twilight band.
func test_lit_one_when_sun_fully_above_twilight_band() -> void:
	assert_almost_eq(SkySun.lit_for(SkySun.TWILIGHT_SIN), 1.0, 1e-6,
		"at the TWILIGHT_SIN threshold the smoothstep must reach 1.0")
	assert_almost_eq(SkySun.lit_for(1.0), 1.0, 1e-6,
		"sun at zenith (s_y = 1) must give lit = 1")


## lit_for — monotonically increasing and strictly partial inside the band.
## Catches a constant-return bug or a reversed smoothstep.
func test_lit_partial_and_increasing_inside_twilight_band() -> void:
	var lo := SkySun.lit_for(0.0)
	var mid := SkySun.lit_for(SkySun.TWILIGHT_SIN * 0.5)
	var hi := SkySun.lit_for(SkySun.TWILIGHT_SIN)
	assert_true(lo < mid and mid < hi,
		"lit must be strictly increasing across the twilight band")
	assert_true(mid > 0.0 and mid < 1.0,
		"mid-twilight must be partial, not clamped")


## light_color_for — warm (red >> blue) at low solar elevation.
## Fails when the dawn/noon colour endpoints are swapped or the lerp is reversed.
func test_light_color_warm_at_low_elevation() -> void:
	var c := SkySun.light_color_for(0.01)
	assert_gt(c.r, c.b + 0.25,
		"at a near-horizon sun (s_y ≈ 0.01) the colour must be warm: red >> blue")
	assert_gt(c.r, c.g + 0.05,
		"at a near-horizon sun the colour must be warm: red > green")


## light_color_for — near-white at high solar elevation (noon).
## Fails when the noon colour is too saturated (e.g. still orange at s_y = 0.8).
func test_light_color_near_white_at_high_elevation() -> void:
	var c := SkySun.light_color_for(0.8)
	assert_gt(c.r, 0.95, "red channel near-white at noon")
	assert_gt(c.g, 0.90, "green channel near-white at noon")
	assert_gt(c.b, 0.85, "blue channel near-white at noon")


## light_color_for — cooler at noon than at dawn (higher blue fraction).
## Catches a constant-colour regression.
func test_light_color_cooler_at_noon_than_at_dawn() -> void:
	var dawn := SkySun.light_color_for(0.01)
	var noon := SkySun.light_color_for(0.8)
	assert_gt(noon.b / maxf(noon.r, 0.001), dawn.b / maxf(dawn.r, 0.001),
		"the blue-to-red ratio must increase from dawn to noon (cooler colour temperature)")


## ambient_energy_for — small but nonzero at night.
## The nonzero floor keeps silhouettes readable against a dim sky.
## Catches swapping the night/day arguments or a zero-floor regression.
func test_ambient_energy_low_and_nonzero_at_night() -> void:
	var e := SkySun.ambient_energy_for(0.0)
	assert_lt(e, 0.15, "night ambient must be low (lit = 0)")
	assert_gt(e, 0.0,  "night ambient must be nonzero — silhouette readability floor")


## ambient_energy_for — substantial at noon so shaded surfaces read as shaded, not black.
func test_ambient_energy_substantial_at_noon() -> void:
	var e := SkySun.ambient_energy_for(1.0)
	assert_gt(e, 0.7, "full-day ambient must be substantial")


## ambient_energy_for — strictly increasing from night to day.
func test_ambient_energy_increases_from_night_to_day() -> void:
	assert_gt(SkySun.ambient_energy_for(1.0), SkySun.ambient_energy_for(0.5),
		"ambient must increase toward day")
	assert_gt(SkySun.ambient_energy_for(0.5), SkySun.ambient_energy_for(0.0),
		"ambient must increase away from night")


## background_energy_for — very dim at night so the sky reads dark, not grey.
## Catches the [0, 1] interval being inverted (full brightness at night).
func test_background_energy_very_low_at_night() -> void:
	var e := SkySun.background_energy_for(0.0)
	assert_lt(e, 0.05, "night sky must be very dim (lit = 0)")
	assert_gt(e, 0.0,  "night sky must not be zero (implied moonlight/stars)")


## background_energy_for — full energy during the day.
func test_background_energy_full_at_day() -> void:
	assert_almost_eq(SkySun.background_energy_for(1.0), 1.0, 1e-6,
		"sky background energy must be 1.0 at full daylight")


## background_energy_for — strictly increasing from night to day.
func test_background_energy_increases_from_night_to_day() -> void:
	assert_gt(SkySun.background_energy_for(1.0), SkySun.background_energy_for(0.0),
		"background energy must increase from night to day")
