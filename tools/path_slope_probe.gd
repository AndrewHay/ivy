extends SceneTree

const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")


func _initialize() -> void:
	for seed in [1, 3, 5, 7, 12, 240424020]:
		var layout := VillageLayout.generate(seed)
		if layout.fallback:
			print("seed %d fallback" % seed)
			continue
		var params := VillageTerrainParams.production()
		var t_seed := VillageTerrain.terrain_seed(layout, params)
		var max_s := 0.0
		var max_p := Vector2.ZERO
		for polyline: Variant in layout.path_polylines():
			var pts: Array = polyline as Array
			var total := 0.0
			var lens: Array[float] = []
			for i in range(pts.size() - 1):
				var len := (pts[i] as Vector2).distance_to(pts[i + 1] as Vector2)
				lens.append(len)
				total += len
			var dist := 0.0
			while dist <= total:
				var p := _along(pts, lens, dist)
				var s := VillageTerrain.sample_slope_deg(p, layout, params, t_seed)
				if s > max_s:
					max_s = s
					max_p = p
				dist += 0.5
		var pd := max_p.distance_to(VillageLayout.HERO_DOOR_STOOP)
		print("seed %d max=%.2f° at %s hero_d=%.1f y=%.3f" % [
			seed, max_s, max_p, pd, VillageTerrain.sample_y(max_p, layout, params, t_seed)])
	quit()


static func _along(pts: Array, lens: Array[float], dist: float) -> Vector2:
	var rem := dist
	for i in range(lens.size()):
		if rem <= lens[i]:
			var t := rem / maxf(lens[i], 1e-6)
			return (pts[i] as Vector2).lerp(pts[i + 1] as Vector2, t)
		rem -= lens[i]
	return pts[pts.size() - 1] as Vector2
