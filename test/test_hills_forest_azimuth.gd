extends GutTest

const HillsParams = preload("res://src/playground/hills_params.gd")
const HillsHeightfield = preload("res://src/playground/hills_heightfield.gd")
const HillsForestPlacement = preload("res://src/playground/hills_forest_placement.gd")
const VillageScatterPositions = preload("res://src/world/village_scatter_positions.gd")

const SECTORS := 6
const R_LO := 110.0   # rework5: matches new NEAR_BAND_R_LO = 110 m
const R_HI := 190.0   # rework5: matches new NEAR_BAND_R_HI = 190 m
const MIN_PER_SECTOR := 10
## Sectors whose phi-midpoint falls within the north wedge (±55°).
## sec 0: phi ∈ [-PI, -2PI/3) → midpoint at -5PI/6 ≈ -150° → diff from north(PI)=30° → inside ✓
## sec 5: phi ∈ [2PI/3, PI)  → midpoint at  5PI/6 ≈ +150° → diff from north(PI)=30° → inside ✓
const NORTH_SECTORS: Array[int] = [0, 5]


static func _sector_counts(xforms: Array, layout: VillageLayout) -> PackedInt32Array:
	var g := layout.hamlet_centre_xz
	var counts := PackedInt32Array()
	counts.resize(SECTORS)
	for t in xforms:
		var tr := t as Transform3D
		var p := Vector2(tr.origin.x, tr.origin.z)
		var rg := p.distance_to(g)
		if rg < R_LO or rg > R_HI:
			continue
		var phi := atan2(p.x - g.x, p.y - g.y)
		var sec := int(floor((phi + PI) / TAU * SECTORS)) % SECTORS
		counts[sec] += 1
	return counts


func test_near_band_forest_floor_per_azimuth_sector() -> void:
	for seed in [1, 7, 12]:
		var layout := VillageLayout.generate(seed)
		VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
		if layout.fallback:
			continue
		var params := HillsParams.production()
		var t_seed := HillsHeightfield.terrain_seed(layout, params)
		var backdrop := VillageScatterPositions.forest_tree_xz(layout)
		var xforms := HillsForestPlacement.hill_forest_transforms(
			layout, params, t_seed, backdrop)
		var counts := _sector_counts(xforms, layout)
		# rework4: hills are north-only; only north sectors (0 and 5) get the floor guarantee.
		for s in NORTH_SECTORS:
			assert_gte(
				counts[s], MIN_PER_SECTOR,
				"seed %d north sector %d count %d" % [seed, s, counts[s]])
