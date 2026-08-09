class_name RngStream
extends RefCounted

var _rng := RandomNumberGenerator.new()
var _seed_value: int = 0
var _draw_count: int = 0
var _dev_build: bool = true


func _init(seed_value: int, dev_build: bool = true) -> void:
	_dev_build = dev_build
	_seed_value = seed_value
	_rng.seed = seed_value


static func from_seed(seed_value: int, dev_build: bool = true) -> RngStream:
	return RngStream.new(seed_value, dev_build)


func derive(branch_index: int) -> RngStream:
	return RngStream.new(Hash64.mix(_seed_value, branch_index), _dev_build)


func randf() -> float:
	_advance()
	return _rng.randf()


func randf_range(a: float, b: float) -> float:
	_advance()
	return _rng.randf_range(a, b)


func randi() -> int:
	_advance()
	return _rng.randi()


## `self.` is required on every internal draw. An unqualified `randf()` binds to the
## @GlobalScope built-in of the same name — the process-global RNG, seeded randomly at
## startup — rather than to this class's method, which silently destroys determinism
## (INV-7) while every externally qualified `stream.randf()` call still looks correct.
func rand_unit_vector() -> Vector3:
	var u1 := self.randf()
	var u2 := self.randf()
	var z := 1.0 - 2.0 * u1
	var r := sqrt(max(0.0, 1.0 - z * z))
	var phi := TAU * u2
	return Vector3(cos(phi) * r, sin(phi) * r, z)


func normal_std() -> float:
	var u1: float = max(self.randf(), 1e-8)
	var u2: float = self.randf()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)


func draw_count() -> int:
	return _draw_count


func _advance() -> void:
	if _dev_build:
		_draw_count += 1
