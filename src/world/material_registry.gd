class_name MaterialRegistry
extends RefCounted

const BRICK_WALL := 0
const BRICK_LIP := 1
const OPENING_REVEAL := 2
const INTERIOR := 3
const GROUND := 4


static func adhesion(material_id: int) -> float:
	match material_id:
		GROUND:
			return 0.0
		_:
			return 1.0


static func in_coverage_denominator(material_id: int) -> bool:
	match material_id:
		BRICK_LIP, OPENING_REVEAL, INTERIOR, GROUND:
			return false
		_:
			return true
