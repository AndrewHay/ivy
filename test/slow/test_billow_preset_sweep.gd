## SD-VILLAGE-TERRAIN-30 (ivy-82zn.14.26): the matched-relief Billow preset has a passing landform
## offset on every seed 1-20, and at most 2 / 20 seeds end on the authored fallback.
## Slow: one full generate per seed (billow mean ~5.4 s, playground only).
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")

const SEEDS := 20
const MAX_AUTHORED := 2


func test_billow_preset_seeds_1_to_20() -> void:
	var p := VillageTerrainParams.production()
	p.apply_preset("Billow")
	var no_pass: Array[int] = []
	var authored: Array[int] = []
	for seed: int in range(1, SEEDS + 1):
		if not bool(VillageLandform.rank_offsets(seed, p)[0]["pass"]):
			no_pass.append(seed)
		if VillageLayout.generate(seed, p.duplicate_params()).fallback:
			authored.append(seed)
	assert_eq(no_pass.size(), 0, "rank 0 passes on every seed (failing: %s)" % str(no_pass))
	assert_lte(authored.size(), MAX_AUTHORED, "authored fallback on <= %d / %d (seeds %s)" % [
		MAX_AUTHORED, SEEDS, str(authored)])
	gut.p("Billow sweep: no-pass %s, authored %s" % [str(no_pass), str(authored)])
