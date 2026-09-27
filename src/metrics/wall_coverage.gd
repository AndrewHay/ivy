class_name WallCoverageMetric
extends RefCounted

## Flat-wall XY-projection coverage metric (ivy-50f / ivy-v4a contract).
##
## A read-only observer. Consumes no RNG draws, reads no environment field,
## and writes nothing to the simulation — two identical calls with the same
## PlantData return identical numbers (INV-7 safe).
##
## Sibling to CoverageMetric (cylinder, src/metrics/coverage.gd); does NOT
## extend or reuse it — cylindrical azimuth bins are incorrect for a flat wall.
##
## Grid: CELL = 0.10 m; nx = ceil(length / CELL), ny = ceil(height / CELL).
## Leaf position: XY projection from leaf_xform origin (z ignored).
## Bucket: bx = floor((x + length/2) / CELL), by = floor(y / CELL).
## Out-of-range leaves and segment midpoints are silently dropped.
##
## Coverage: a bucket is "covered" when accumulated ref_leaf_area ≥ 0.5 × CELL².
## ref_leaf_area is FIXED at REF_LEAF_WIDTH = 0.075 (NOT params.leaf_width_base)
## so wide-leaf presets cannot inflate the metric by widening their leaves.
##
## measure() returns:
##   overall_pct        — % of buckets covered (0.0–100.0)
##   stem_bucket_pct    — % of buckets with any segment midpoint (diagnostic)
##   covered_buckets    — raw count
##   total_buckets      — nx × ny (all eligible; test_wall has no openings)

const CELL: float = 0.10
## Fixed canonical leaf width; deliberately NOT params.leaf_width_base.
const REF_LEAF_WIDTH: float = 0.075
const COVERAGE_THRESHOLD: float = 0.5

const _LeafAtlas = preload("res://src/render/leaf_atlas.gd")

## Lazy cache for ref_leaf_area().  The value is deterministic (pure function of
## REF_LEAF_WIDTH and fixed LeafAtlas constants) so we compute it once and reuse
## it.  -1.0 is the sentinel for "not yet computed".
static var _ref_leaf_area_cache: float = -1.0

## Fixed canonical leaf area in m²:
##   alpha_fill_for('a') × REF_LEAF_WIDTH² / aspect_for('a') ≈ 0.003392 m².
## Exposed as static so unit tests can assert the expected value.
## Result is cached in _ref_leaf_area_cache — this function is called once per
## test/tool run (not per-tick) but there is no reason to allocate a LeafAtlas
## more than once since the value never changes.
static func ref_leaf_area() -> float:
	if _ref_leaf_area_cache >= 0.0:
		return _ref_leaf_area_cache
	var atlas := _LeafAtlas.new()
	_ref_leaf_area_cache = atlas.alpha_fill_for("a") * REF_LEAF_WIDTH * REF_LEAF_WIDTH / atlas.aspect_for("a")
	return _ref_leaf_area_cache


## Measure flat-wall XY-projection coverage.
## plant  — PlantData (read-only)
## spec   — WallSpec  (length, height used; thickness/other fields ignored)
func measure(plant: PlantData, spec: WallSpec) -> Dictionary:
	var nx: int = ceili(spec.length / CELL)
	var ny: int = ceili(spec.height / CELL)
	var total_buckets: int = nx * ny

	# coverage_threshold per bucket: >= 50% of bucket area
	var coverage_threshold: float = COVERAGE_THRESHOLD * CELL * CELL  # 0.005 m²
	var rla: float = ref_leaf_area()
	var half_len: float = spec.length * 0.5

	var leaf_accum := PackedFloat32Array()
	leaf_accum.resize(total_buckets)
	var stem_has := PackedByteArray()
	stem_has.resize(total_buckets)

	# ---- Segments (stem diagnostic) ----
	var n_segs: int = plant.segment_count()
	for i in range(n_segs):
		var a: Vector3 = plant.seg_a[i]
		var b: Vector3 = plant.seg_b[i]
		var mx: float = (a.x + b.x) * 0.5
		var my: float = (a.y + b.y) * 0.5
		# z ignored — pure XY projection
		var bx: int = int(floor((mx + half_len) / CELL))
		var by_: int = int(floor(my / CELL))
		if bx < 0 or bx >= nx or by_ < 0 or by_ >= ny:
			continue
		stem_has[bx * ny + by_] = 1

	# ---- Leaves ----
	# PlantData leaf_xform layout (12 floats per leaf):
	#   [bx.x, bx.y, bx.z, origin.x,
	#    by.x, by.y, by.z, origin.y,
	#    bz.x, bz.y, bz.z, origin.z]
	# => origin.x at base+3, origin.y at base+7, origin.z at base+11
	var n_leaves: int = plant.leaf_count()
	for i in range(n_leaves):
		var base: int = i * 12
		var ox: float = plant.leaf_xform[base + 3]
		var oy: float = plant.leaf_xform[base + 7]
		# oz at base+11 — ignored, pure XY projection
		var bx: int = int(floor((ox + half_len) / CELL))
		var by_: int = int(floor(oy / CELL))
		if bx < 0 or bx >= nx or by_ < 0 or by_ >= ny:
			continue
		leaf_accum[bx * ny + by_] += rla

	# ---- Tally ----
	var covered_buckets: int = 0
	var stem_bucket_count: int = 0
	for idx in range(total_buckets):
		if leaf_accum[idx] >= coverage_threshold:
			covered_buckets += 1
		if stem_has[idx] != 0:
			stem_bucket_count += 1

	var overall_pct: float = 0.0
	var stem_bucket_pct: float = 0.0
	if total_buckets > 0:
		overall_pct = 100.0 * float(covered_buckets) / float(total_buckets)
		stem_bucket_pct = 100.0 * float(stem_bucket_count) / float(total_buckets)

	return {
		"overall_pct":       overall_pct,
		"stem_bucket_pct":   stem_bucket_pct,
		"covered_buckets":   covered_buckets,
		"total_buckets":     total_buckets,
	}
