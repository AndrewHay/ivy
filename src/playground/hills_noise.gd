class_name HillsNoise
extends RefCounted

## Seeded 2D fBm + gentle domain warp for rolling-hill heightfields (deterministic).
## _noise2d caches FastNoiseLite objects by seed so terrain rebuilds create O(unique-seeds)
## allocations instead of O(vertices × octaves) allocations (~2.85M per rebuild).
static var _noise_cache: Dictionary = {}


static func fbm_height_01(
		world_xz: Vector2, seed: int, base_feature_m: float, octaves: int,
		persistence: float, warp_strength: float) -> float:
	var wp := domain_warp(world_xz, seed, base_feature_m, warp_strength)
	var amp := 1.0
	var freq := 1.0 / maxf(base_feature_m, 1.0)
	var sum := 0.0
	var norm := 0.0
	for i in range(octaves):
		sum += amp * _noise2d(wp * freq, seed + i * 7919)
		norm += amp
		amp *= persistence
		freq *= 2.0
	if norm < 1e-6:
		return 0.5
	var n := sum / norm
	return clampf(n * 0.5 + 0.5, 0.0, 1.0)


static func domain_warp(
		p: Vector2, seed: int, base_feature_m: float, warp_strength: float) -> Vector2:
	var wf := 0.4 / maxf(base_feature_m, 1.0)
	var amp := warp_strength * base_feature_m
	var q := p * wf + Vector2(0.0, float(seed % 97) * 0.013)
	var off := Vector2(
		_noise2d(q, seed + 17),
		_noise2d(q + Vector2(19.1, 7.3), seed + 23),
	)
	return p + off * amp


static func copse_density_01(world_xz: Vector2, seed: int, copse_scale_m: float) -> float:
	var freq := 1.0 / maxf(copse_scale_m, 1.0)
	var n := _noise2d(world_xz * freq, seed + 4409)
	return clampf(n * 0.5 + 0.5, 0.0, 1.0)


static func _noise2d(p: Vector2, seed: int) -> float:
	var n: FastNoiseLite
	if _noise_cache.has(seed):
		n = _noise_cache[seed]
	else:
		n = FastNoiseLite.new()
		n.seed = seed
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 1.0
		_noise_cache[seed] = n
	return n.get_noise_2d(p.x, p.y)
