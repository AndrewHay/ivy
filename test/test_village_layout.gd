## Tests for VillageLayout.authored() equivalence — ivy-80z S1.
##
## INV-15: The classic village render is byte-for-byte unchanged after the S1
## refactor. Evidence:
##   (a) authored().cottages deep-equals COTTAGES
##   (b) authored().paths equals path_polylines() point-for-point
##   (c) stone_seed=9999 / min_stone_spacing=0.0
##   (d) inside_cottages matches inside_any_cottage on a grid of sample points
##   (e) VillageBackdrop built with default authored() layout produces the same
##       MultiMesh node names, instance_counts, and buffer hashes as the
##       pre-refactor baseline (captured 2026-10-29 Godot 4.7.2 macOS).
extends GutTest

const VillageBackdropScene = preload("res://src/world/village_backdrop.tscn")

# ── (a) authored().cottages equals COTTAGES ───────────────────────────────────

func test_authored_cottages_equal_const() -> void:
	var layout := VillageLayout.authored()
	assert_eq(layout.cottages.size(), VillageBackdrop.COTTAGES.size(),
		"authored().cottages must have same count as COTTAGES")
	for i in range(layout.cottages.size()):
		var got: Dictionary = layout.cottages[i]
		var want: Dictionary = VillageBackdrop.COTTAGES[i]
		assert_eq(got.keys(), want.keys(),
			"authored().cottages[%d] must have same keys as COTTAGES[%d]" % [i, i])
		for k in want.keys():
			assert_eq(got[k], want[k],
				"authored().cottages[%d]['%s'] mismatch" % [i, k])


# ── (b) authored().paths equals path_polylines() point-for-point ──────────────

func test_authored_paths_equal_static() -> void:
	var layout := VillageLayout.authored()
	var static_paths := VillageBackdrop.path_polylines()
	assert_eq(layout.paths.size(), static_paths.size(),
		"authored().paths must have same count as path_polylines()")
	for i in range(layout.paths.size()):
		var lp: Array = layout.paths[i]
		var sp: Array = static_paths[i]
		assert_eq(lp.size(), sp.size(), "path[%d] same length" % i)
		for j in range(lp.size()):
			assert_almost_eq((lp[j] as Vector2).x, (sp[j] as Vector2).x, 1e-5,
				"path[%d][%d].x" % [i, j])
			assert_almost_eq((lp[j] as Vector2).y, (sp[j] as Vector2).y, 1e-5,
				"path[%d][%d].y" % [i, j])


# ── (c) stone_seed and min_stone_spacing ─────────────────────────────────────

func test_authored_stone_seed_is_9999() -> void:
	var layout := VillageLayout.authored()
	assert_eq(layout.stone_seed, 9999,
		"authored() must carry stone_seed=9999 (INV-15 classic LCG seed)")
	assert_almost_eq(layout.min_stone_spacing, 0.0, 1e-6,
		"authored() must carry min_stone_spacing=0.0 (dedupe off for classic)")


func test_authored_fallback_is_false() -> void:
	var layout := VillageLayout.authored()
	assert_false(layout.fallback, "authored() must have fallback=false")


# ── (d) inside_cottages matches inside_any_cottage on a sample grid ────────────

func test_inside_cottages_matches_inside_any_cottage() -> void:
	## INV-15: VillageLayout.inside_cottages(COTTAGES, …) == VillageBackdrop.inside_any_cottage(…)
	## on a dense sample grid covering the full village extent.
	for xi in range(-22, 23, 2):
		for zi in range(-22, 23, 2):
			var p := Vector2(float(xi), float(zi))
			for margin in [0.0, 0.2, 0.5]:
				var via_layout := VillageLayout.inside_cottages(VillageBackdrop.COTTAGES, p, margin)
				var via_static := VillageBackdrop.inside_any_cottage(p, margin)
				assert_eq(via_layout, via_static,
					"inside_cottages vs inside_any_cottage at %s margin=%.1f" % [str(p), margin])


# ── Instance method delegates to static ──────────────────────────────────────

func test_instance_inside_any_cottage_delegates_to_static() -> void:
	var layout := VillageLayout.authored()
	for xi in range(-20, 21, 5):
		for zi in range(-20, 21, 5):
			var p := Vector2(float(xi), float(zi))
			assert_eq(
				layout.inside_any_cottage(p, 0.0),
				VillageLayout.inside_cottages(layout.cottages, p, 0.0),
				"instance.inside_any_cottage must delegate to inside_cottages at %s" % str(p))


func test_path_polylines_instance_returns_paths() -> void:
	var layout := VillageLayout.authored()
	assert_eq(layout.path_polylines(), layout.paths,
		"path_polylines() must return self.paths")


# ── S2′ cottage_rings field ───────────────────────────────────────────────────

func test_authored_cottage_rings_is_empty() -> void:
	## authored() carries no ring-membership data — cottage_rings is empty (S2′ contract).
	var layout := VillageLayout.authored()
	assert_eq(layout.cottage_rings.size(), 0,
		"authored().cottage_rings must be empty [] (no ring membership for classic layout)")


# ── S1 generate() stub ────────────────────────────────────────────────────────

func test_generate_stub_returns_authored_shape() -> void:
	## S1: generate() is stubbed → same cottage count/layout as authored().
	## S2+: generate() produces a real layout; cottage count is still 7 (INV-13).
	var layout := VillageLayout.generate(42)
	assert_eq(layout.cottages.size(), VillageBackdrop.COTTAGES.size(),
		"generate() must return 7 cottages (authored count)")


# ── Seed normalisation (SD-VILLAGE-GEN-2 / SD-VILLAGE-GEN-8 edge cases) ──────

func test_seed_normalisation_zero() -> void:
	## Seed 0: 0 & 0x7FFFFFFF = 0. Must not fallback.
	var layout := VillageLayout.generate(0)
	assert_false(layout.fallback, "seed=0 must not fall back (SD-VILLAGE-GEN-8)")
	assert_eq(layout.cottages.size(), 7, "seed=0 must produce 7 cottages")


func test_seed_normalisation_negative() -> void:
	## Negative seed normalised by & 0x7FFFFFFF. Must match positive normalised value.
	var layout_neg := VillageLayout.generate(-1)
	# In GDScript, -1 & 0x7FFFFFFF = 2147483647 (two's-complement low 31 bits).
	var layout_pos := VillageLayout.generate(-1 & 0x7FFFFFFF)
	assert_false(layout_neg.fallback, "generate(-1) must not fall back")
	assert_eq(layout_neg.cottages.size(), 7, "generate(-1) must produce 7 cottages")
	# Centres must match
	for i: int in layout_neg.cottages.size():
		var cn: Vector2 = layout_neg.cottages[i]["centre"]
		var cp: Vector2 = layout_pos.cottages[i]["centre"]
		assert_almost_eq(cn.x, cp.x, 1e-4,
			"generate(-1) cottage[%d] centre.x must equal generate(norm)" % i)
		assert_almost_eq(cn.y, cp.y, 1e-4,
			"generate(-1) cottage[%d] centre.y must equal generate(norm)" % i)


func test_seed_normalisation_huge() -> void:
	## Seed > 2^31 masked to 31 bits. Must be deterministic.
	const HUGE: int = 1 << 62
	var layout := VillageLayout.generate(HUGE)
	var layout2 := VillageLayout.generate(HUGE)
	assert_false(layout.fallback, "huge seed must not fall back")
	assert_eq(layout.cottages.size(), 7, "huge seed must produce 7 cottages")
	for i: int in layout.cottages.size():
		var c1: Vector2 = layout.cottages[i]["centre"]
		var c2: Vector2 = layout2.cottages[i]["centre"]
		assert_almost_eq(c1.x, c2.x, 1e-4,
			"huge seed cottage[%d] centre.x must be deterministic" % i)
		assert_almost_eq(c1.y, c2.y, 1e-4,
			"huge seed cottage[%d] centre.y must be deterministic" % i)


# ── (e) INV-15: VillageBackdrop MultiMesh fingerprints unchanged after refactor ──

## Reference fingerprints captured 2026-10-29 Godot 4.7.2 macOS,
## from unmodified village_backdrop.gd (pre S1 refactor).
## Format: node_name → [instance_count, buffer_hash]
const _REFERENCE_FINGERPRINTS := {
	"Cottage_Wall_Plaster_Window_Wide_Flat": [14, 4128123923],
	"Cottage_WindowShutters_Wide_Flat_Closed": [14, 4128123923],
	"Cottage_Wall_Plaster_Straight": [44, 1972257807],
	"Cottage_Wall_Plaster_Door_Flat": [7, 4143240826],
	"Cottage_Door_1_Flat": [7, 3179870872],
	"Cottage_Roof_Front_Brick4": [14, 2923429747],
	"Cottage_Roof_RoundTiles_4x8": [2, 2205579321],
	"Cottage_Prop_Chimney2": [7, 2019212655],
	"Cottage_Wall_UnevenBrick_Straight": [9, 3563615590],
	"Cottage_Roof_RoundTiles_4x6": [5, 3153429718],
	"Scatter_Path_0": [18, 1630142961],
	"Scatter_Path_1": [18, 3724659153],
	"Scatter_Path_2": [17, 764894738],
	"Scatter_Grass_Accent": [48, 477387432],
	"Scatter_Flower_Flower_3_Group": [6, 1838170387],
	"Scatter_Flower_Flower_3_Single": [11, 1327737020],
	"Scatter_Flower_Flower_4_Group": [8, 472738313],
	"Scatter_Flower_Flower_4_Single": [6, 2727710284],
	"Scatter_Petal_Petal_1": [2, 1416668245],
	"Scatter_Petal_Petal_2": [4, 74488022],
	"Scatter_Petal_Petal_3": [3, 1037038042],
	"Scatter_Petal_Petal_4": [3, 2303113989],
	"Scatter_Petal_Petal_5": [5, 1267880977],
	"Scatter_Plant_Plant_7": [14, 1898465062],
	"Scatter_Plant_Plant_7_Big": [8, 2122416198],
	"FarTreeline": [22, 3381520378],
	"Scatter_Bush_Common": [50, 1093590483],
}


func test_classic_layout_multimesh_fingerprints_unchanged() -> void:
	## INV-15 byte-for-byte evidence: after the S1 refactor, the VillageBackdrop
	## built with the default authored() layout must produce MultiMesh nodes with
	## identical instance_count and buffer hash as the pre-refactor baseline.
	var backdrop := VillageBackdropScene.instantiate()
	add_child_autofree(backdrop)
	# Check every reference node is present and matches.
	for node_name in _REFERENCE_FINGERPRINTS.keys():
		var ref: Array = _REFERENCE_FINGERPRINTS[node_name]
		var ref_count: int = ref[0]
		var ref_hash: int = ref[1]
		var found := false
		for child in backdrop.get_children():
			if child.name != node_name or not child is MultiMeshInstance3D:
				continue
			found = true
			var mmi := child as MultiMeshInstance3D
			assert_not_null(mmi.multimesh,
				"INV-15: %s must have a multimesh" % node_name)
			if mmi.multimesh == null:
				break
			assert_eq(mmi.multimesh.instance_count, ref_count,
				"INV-15: %s instance_count changed after refactor" % node_name)
			var got_hash := hash(mmi.multimesh.buffer)
			assert_eq(got_hash, ref_hash,
				"INV-15: %s buffer hash changed after refactor (byte regression)" % node_name)
			break
		assert_true(found,
			"INV-15: expected node '%s' not found in VillageBackdrop after refactor" % node_name)
