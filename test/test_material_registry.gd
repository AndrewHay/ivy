extends GutTest

const MaterialRegistry = preload("res://src/world/material_registry.gd")


func test_adhesion_values_committed() -> void:
	assert_eq(MaterialRegistry.adhesion(MaterialRegistry.BRICK_WALL), 1.0)
	assert_eq(MaterialRegistry.adhesion(MaterialRegistry.WOOD), 0.45)
	assert_eq(MaterialRegistry.adhesion(MaterialRegistry.GLASS), 0.05)
	assert_eq(MaterialRegistry.adhesion(MaterialRegistry.INTERIOR), 1.0)
	assert_eq(MaterialRegistry.adhesion(MaterialRegistry.GROUND), 0.0)


func test_eligible_materials_differ_enough_for_rg1() -> void:
	var eligible: Array[float] = [
		MaterialRegistry.adhesion(MaterialRegistry.BRICK_WALL),
		MaterialRegistry.adhesion(MaterialRegistry.WOOD),
		MaterialRegistry.adhesion(MaterialRegistry.GLASS),
	]
	var hi: float = eligible[0]
	var lo: float = eligible[0]
	for v in eligible:
		hi = maxf(hi, v)
		lo = minf(lo, v)
	assert_gte((hi - lo) / hi, 0.15,
		"RG-1 adhesion spread: (max-min)/max should be ≥15%%; got %.1f%%"
		% ((hi - lo) / hi * 100.0))
