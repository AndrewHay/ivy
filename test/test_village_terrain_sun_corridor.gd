## ivy-82zn.14.14 (WP1) — AC-LT-SUN: soft sunrise / sunset horizon from the hero eye
## (SD-VILLAGE-TERRAIN-17 §4, -23; AR-LF-D8). Replaces the E/W FLAT_EPS asserts.
extends GutTest

const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")

const _SEEDS: Array[int] = [1, 7, 12]


func test_sun_azimuths_come_from_solar() -> void:
	var az: Vector2 = VillageTerrain.sun_corridor_azimuths()
	var s := Solar.new(IvyParams.new())
	assert_almost_eq(az.x, s.azimuth_deg(s.sunrise_hour()), 1.0, "A_rise from Solar")
	assert_almost_eq(az.y, s.azimuth_deg(s.sunset_hour()), 1.0, "A_set from Solar")
	assert_almost_eq(az.x, 74.7, 1.0, "production sunrise azimuth")
	assert_almost_eq(az.y, 285.4, 1.0, "production sunset azimuth")


func test_old_east_west_constants_retired() -> void:
	var consts := (load("res://src/playground/village_terrain.gd") as GDScript).get_script_constant_map()
	assert_false(consts.has("_SUN_EAST_AZ_DEG"), "_SUN_EAST_AZ_DEG gone")
	assert_false(consts.has("_SUN_WEST_AZ_DEG"), "_SUN_WEST_AZ_DEG gone")


func test_ac_lt_sun_elevation_inside_corridors() -> void:
	var p := VillageTerrainParams.production()
	var az: Vector2 = VillageTerrain.sun_corridor_azimuths()
	var h0 := VillageLayout.HERO_DOOR_STOOP
	var limit := p.sun_clear_deg + 0.5
	for seed in _SEEDS:
		var layout := VillageLayout.generate(seed)
		var f = VillageTerrain.field(layout, p)
		var eye_y: float = float(f.y_hero) + p.sun_eye_height_m
		var worst := -INF
		var worst_at := ""
		for a_c in [az.x, az.y]:
			var k := -int(p.sun_corridor_half_deg)
			while k <= int(p.sun_corridor_half_deg):
				var a := deg_to_rad(float(a_c) + float(k))
				var dir := Vector2(sin(a), -cos(a))  # compass: 0 = north (−Z), 90 = east (+X)
				var d := 20.0
				while d <= 310.0:
					var y: float = f.sample_y(h0 + dir * d)
					var el := rad_to_deg(atan((y - eye_y) / d))
					if el > worst:
						worst = el
						worst_at = "az %.0f d %.0f" % [float(a_c) + float(k), d]
					d += 2.0
				k += 1
		assert_lte(worst, limit, "seed %d max elevation %.2f° at %s" % [seed, worst, worst_at])
