class_name AmbientWind
extends Node

var _phase: float = 0.0
var _direction_xz: Vector2 = Vector2(1.0, 0.3).normalized()


func _process(delta: float) -> void:
	_phase += delta * (TAU / FaunaConstants.WIND_CYCLE_SEC)
	if _phase > TAU:
		_phase = fmod(_phase, TAU)
	_direction_xz = Vector2(cos(_phase * 0.13), sin(_phase * 0.13)).normalized()


func get_phase() -> float:
	return _phase


func get_horizontal_direction() -> Vector2:
	return _direction_xz


func strength_for_species(species: FaunaConstants.Species) -> float:
	match species:
		FaunaConstants.Species.BUTTERFLY:
			return 0.35
		FaunaConstants.Species.BEE:
			return 0.10
		_:
			return 0.0
