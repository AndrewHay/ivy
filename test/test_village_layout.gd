## Tests for VillageLayout.authored() equivalence — ivy-80z S1.
##
## INV-15: The classic village render is byte-for-byte unchanged after the S1
## refactor. Evidence:
##   (a) authored().cottages deep-equals COTTAGES
##   (b) authored() paths keep clearance from pond bank (pond before paths)
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


# ── (b) authored paths detour around pond bank ────────────────────────────────

func test_authored_paths_clear_pond_bank() -> void:
	var layout := VillageLayout.authored()
	assert_true(layout.pond_placed, "authored layout must place pond before paths")
	var bank := VillagePondShape.at(layout.pond_center).bank_outer_outline_world_xz()
	var need := VillagePondSite.PATH_CLEARANCE_M
	for poly_raw in layout.paths:
		var poly: Array = poly_raw as Array
		for pt_raw in poly:
			var pt := pt_raw as Vector2
			var min_d := INF
			for bi in range(bank.size()):
				min_d = minf(
					min_d,
					VillagePondPlacement.segment_point_distance(
						pt, bank[bi], bank[(bi + 1) % bank.size()]))
			assert_gte(min_d, need - 1e-4, "path must stay clear of pond bank")


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


func test_authored_pond_clearance_fields_use_site_defaults() -> void:
	## INV-15: authored() must not override generated-only pond clearance fields.
	var layout := VillageLayout.authored()
	assert_almost_eq(
		layout.pond_cottage_clearance_m, VillagePondSite.COTTAGE_CLEARANCE_M, 1e-6,
		"authored pond_cottage_clearance_m must stay at site default")
	assert_almost_eq(
		layout.pond_path_clearance_m, VillagePondSite.PATH_CLEARANCE_M, 1e-6,
		"authored pond_path_clearance_m must stay at site default")


func test_generate_sets_generated_pond_clearance_fields() -> void:
	var layout := VillageLayout.generate(42)
	if layout.fallback:
		pending("seed 42 fell back — skip pond clearance field check")
		return
	assert_almost_eq(layout.pond_cottage_clearance_m, 3.0, 1e-6,
		"generate() must set pond_cottage_clearance_m=3.0")
	assert_almost_eq(layout.pond_path_clearance_m, 2.0, 1e-6,
		"generate() must set pond_path_clearance_m=2.0")


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
	assert_false(layout.is_generated, "authored() must not set is_generated")
	assert_eq(layout.hamlet_centre_xz, Vector2.ZERO, "classic hamlet centre at pivot")
	assert_almost_eq(layout.plaza_side_m, 0.0, 1e-6, "classic plaza_side_m unset")
	assert_true(layout.plaza_rect.size.is_zero_approx(), "classic plaza_rect empty")


func test_plaza_rect_centred_on_g() -> void:
	var g := Vector2(3.0, -18.0)
	var side := 18.0
	var r := VillageLayout.plaza_rect_at(g, side)
	assert_almost_eq(r.get_center().x, g.x, 1e-4)
	assert_almost_eq(r.get_center().y, g.y, 1e-4)
	assert_almost_eq(r.size.x, side, 1e-4)
	assert_almost_eq(r.size.y, side, 1e-4)


func test_generated_plaza_side_in_range() -> void:
	var layout := VillageLayout.generate(42)
	if layout.fallback:
		pending("seed 42 fell back — skip plaza field check")
		return
	assert_gte(layout.plaza_side_m, 16.0)
	assert_lte(layout.plaza_side_m, 20.0)
	var g := layout.hamlet_centre_xz
	assert_almost_eq(
		layout.plaza_rect.size.x, layout.plaza_side_m, 1e-4, "plaza_rect side must match plaza_side_m")
	var keep := VillageLayout.plaza_keep_clear_rect(g, layout.plaza_side_m)
	assert_lt(keep.size.x, layout.plaza_rect.size.x, "keep-clear inset shrinks rect")


# ── S1 generate() stub ────────────────────────────────────────────────────────

func test_generate_stub_returns_authored_shape() -> void:
	## S1: generate() is stubbed → same cottage count/layout as authored().
	## S2+: generate() produces a real layout; cottage count is still 7 (INV-13).
	var layout := VillageLayout.generate(42)
	assert_eq(layout.cottages.size(), VillageLayout.GENERATED_HAMLET_COUNT,
		"generate() must return GENERATED_HAMLET_COUNT cottages")


# ── Seed normalisation (SD-VILLAGE-GEN-2 / SD-VILLAGE-GEN-8 edge cases) ──────

func test_seed_normalisation_zero() -> void:
	## Seed 0: 0 & 0x7FFFFFFF = 0. Must not fallback.
	var layout := VillageLayout.generate(0)
	assert_false(layout.fallback, "seed=0 must not fall back (SD-VILLAGE-GEN-8)")
	assert_eq(layout.cottages.size(), VillageLayout.GENERATED_HAMLET_COUNT,
		"seed=0 must produce GENERATED_HAMLET_COUNT cottages")


func test_seed_normalisation_negative() -> void:
	## Negative seed normalised by & 0x7FFFFFFF. Must match positive normalised value.
	var layout_neg := VillageLayout.generate(-1)
	# In GDScript, -1 & 0x7FFFFFFF = 2147483647 (two's-complement low 31 bits).
	var layout_pos := VillageLayout.generate(-1 & 0x7FFFFFFF)
	assert_false(layout_neg.fallback, "generate(-1) must not fall back")
	assert_eq(layout_neg.cottages.size(), VillageLayout.GENERATED_HAMLET_COUNT,
		"generate(-1) must produce GENERATED_HAMLET_COUNT cottages")
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
	assert_eq(layout.cottages.size(), VillageLayout.GENERATED_HAMLET_COUNT,
		"huge seed must produce GENERATED_HAMLET_COUNT cottages")
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
	"Scatter_Path_0": [56, 881458508],
	"Scatter_Path_1": [56, 2959288073],
	"Scatter_Path_2": [56, 3622295605],
	## Grass scatter slice (ivy-vlr / 48k grass) changed accent buffer layout — not path/layout.
	"Scatter_Grass_Accent": [48, 2211811117],  ## re-baselined with Plant_7_Big, see below
	"Scatter_Flower_Flower_3_Group": [4, 1239188146],
	"Scatter_Flower_Flower_3_Single": [9, 55149561],
	"Scatter_Flower_Flower_4_Group": [8, 1715658938],
	"Scatter_Flower_Flower_4_Single": [5, 897501049],
	"Scatter_Petal_Petal_1": [11, 2329237050],
	"Scatter_Petal_Petal_2": [18, 1286106724],
	"Scatter_Petal_Petal_3": [6, 4056015965],
	"Scatter_Petal_Petal_4": [8, 1663965343],
	"Scatter_Petal_Petal_5": [20, 3210729364],
	"Scatter_Plant_Plant_7": [14, 1898465062],
	## Re-baselined (ivy-oan3.9, user-approved): one big plant stood in the classic pond; plants
	## are now redrawn when they land in water. This also moves Scatter_Grass_Accent (grass
	## avoids plant anchors). Plant_7 (small) bytes are unchanged.
	"Scatter_Plant_Plant_7_Big": [8, 1368777133],
	"FarTreeline": [22, 3381520378],
	"Scatter_Bush_Common": [50, 4061434494],
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
