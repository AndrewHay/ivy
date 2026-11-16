## In-camera relief measure for the two canonical gameplay views (ivy-82zn.14.1 village swell).
## Shared by tools/probe_village_relief.gd and test_village_terrain_heightfield.gd so the probe
## and the floor test read the same numbers (architect plan ivy-82zn.14.4, targets T1 / T2).
##
## Ground a camera sees: eye at layout-local `eye`, looking along sign_z * Z, ~106 deg horizontal
## FOV; ground 8-45 m from the eye, inside the lawn disc, outside the hero flat disc; 2 m grid.
##   CamSun   (default gameplay cam at load): eye (0, 10.8), sign_z -1.
##   CamShade (rig child 1, mirror of CamSun): eye (0, -10.8), sign_z +1.
extends RefCounted

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")

const CAMSUN_EYE := Vector2(0.0, 10.8)
const CAMSHADE_EYE := Vector2(0.0, -10.8)
## |h| above this counts as visibly off datum ("coverage").
const VISIBLE_H_M := 0.15


static func camsun(sampler: GDScript, layout: VillageLayout, params: VillageTerrainParams,
		t_seed: int, with_slope: bool = false) -> Dictionary:
	return stats(sampler, layout, params, t_seed, CAMSUN_EYE, -1.0, with_slope)


static func camshade(sampler: GDScript, layout: VillageLayout, params: VillageTerrainParams,
		t_seed: int, with_slope: bool = false) -> Dictionary:
	return stats(sampler, layout, params, t_seed, CAMSHADE_EYE, 1.0, with_slope)


## Returns {span, mean_abs, frac_visible, max_slope, n}. max_slope is 0 unless with_slope.
static func stats(sampler: GDScript, layout: VillageLayout, params: VillageTerrainParams,
		t_seed: int, eye: Vector2, sign_z: float, with_slope: bool = false) -> Dictionary:
	var min_h := INF
	var max_h := -INF
	var sum_abs := 0.0
	var n := 0
	var n_vis := 0
	var max_slope := 0.0
	var x := -60.0
	while x <= 60.0:
		var z := -60.0
		while z <= 60.0:
			var p := Vector2(x, z)
			var dz := (z - eye.y) * sign_z
			var d := p.distance_to(eye)
			if dz > 3.0 and absf(x) < 1.33 * dz and d >= 8.0 and d <= 45.0 \
					and p.distance_to(layout.hamlet_centre_xz) < layout.lawn_radius \
					and p.distance_to(VillageLayout.HERO_DOOR_STOOP) > params.hero_flat_r_m:
				var h: float = sampler.sample_y(p, layout, params, t_seed)
				min_h = minf(min_h, h)
				max_h = maxf(max_h, h)
				sum_abs += absf(h)
				if absf(h) > VISIBLE_H_M:
					n_vis += 1
				n += 1
				if with_slope:
					max_slope = maxf(max_slope, sampler.sample_slope_deg(p, layout, params, t_seed))
			z += 2.0
		x += 2.0
	return {"span": max_h - min_h if n > 0 else 0.0, "mean_abs": sum_abs / maxf(n, 1),
		"frac_visible": float(n_vis) / maxf(n, 1), "max_slope": max_slope, "n": n}
