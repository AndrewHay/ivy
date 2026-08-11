class_name CoverageMetric
extends RefCounted

## Surface-bucket occupancy in tower-cylindrical coordinates (SD-METRIC-1/2/3/5/6).
##
## This is a read-only observer.  It consumes no RNG draws, reads no environment
## field, and writes nothing to the simulation.  Two identical calls with the same
## PlantData return identical numbers (INV-7 is not threatened).
##
## Bucket grid (SD-METRIC-1): 72 azimuth × 35 height = 2,520 wall buckets.
##   azimuth: 5° bins, 0° = north, increasing clockwise (east = 90°, south = 180°).
##   height:  0.10 m bins, covers y = [0, 3.5 m).
##
## A bucket is "covered" when the accumulated weight for it reaches ≥50% of the bucket
## area (SD-METRIC-3 as amended by SD-OPEN-13).  Per-leaf weight = ref_area, attributed
## to the petiole's bucket (AR-AMBIG-6).  There is no orientation term.
##
## ref_area = alpha_fill("a") · leaf_width_base² / aspect("a") — AR-METRIC-1 amendment.
##
## AS-1 asks whether enough ivy is *placed* on a part of the wall, which is the same
## question LG-1 answers by eye, so the gate excludes every presentation term at once:
## size (SD-LEAF-5 s_light), art (SD-LEAF-6 variant and tier), and orientation
## (SD-LEAF-4's phototropic cant, plus jitter and droop).  Each of the first two was
## found moving a ratified acceptance floor while the plant was bit-identical.
##
## The orientation term was withdrawn rather than switched to the wall normal, because on
## a cylinder it cannot discriminate: a leaf's bucket is chosen from its own position, so
## the wall normal and the bucket normal are never more than half a 5° bin apart and the
## dot product never falls below 0.999.  Keeping it would have left a ratified clause with
## no arithmetic effect.  Orientation-weighted figures remain available as the *_nleaf
## diagnostic, which is the basis every AS-1 number before this amendment used.
##
## Rendered leaf_area is unchanged and available for other consumers.
##
## Buckets on door or window openings are excluded from the denominator (SD-METRIC-2).
##
## measure() returns a Dictionary with:
##   overall_pct, sun_half_pct, shade_half_pct, stem_bucket_pct
##   sector_stem_length[12], sector_leaf_count[12]
##   lip_reached
##   sun_stem_length, shade_stem_length, stem_asymmetry_pct   (AS-2)
##   total_eligible_buckets, sun_eligible_buckets, shade_eligible_buckets
##   overall_pct_nleaf, sun_half_pct_nleaf, shade_half_pct_nleaf
##     Diagnostic only: the orientation-weighted basis every AS-1 figure before the SD-OPEN-13
##     amendment was measured on. Gates nothing; reported so a change of basis is legible.

const AZIMUTH_BINS: int = 72       # 5° each — SD-METRIC-1
const HEIGHT_BINS: int = 35        # 0.10 m each — SD-METRIC-1
const HEIGHT_BIN_SIZE: float = 0.10
const SECTOR_COUNT: int = 12       # 30° each — SD-METRIC-6
const COVERAGE_THRESHOLD: float = 0.5  # ≥50% of bucket area — SD-METRIC-3

const _LeafAtlas = preload("res://src/render/leaf_atlas.gd")

var _spec: TowerSpec
var _eligible: PackedByteArray  # AZIMUTH_BINS × HEIGHT_BINS; 1 = eligible, 0 = excluded
var _bucket_area: float         # arc_length × height_bin, m²
## Fixed reference footprint (AR-METRIC-1): alpha_fill("a") · leaf_width_base² / aspect("a").
## Every leaf is attributed this area regardless of variant/tier; computed once in setup().
var _ref_area: float = 0.0


func setup(spec: TowerSpec, params: IvyParams) -> void:
	_spec = spec
	# Arc length of one 5° bin at the outer radius
	_bucket_area = 2.0 * PI * spec.radius_outer / float(AZIMUTH_BINS) * HEIGHT_BIN_SIZE
	_eligible = _build_opening_mask(spec)
	# AR-METRIC-1 amendment: fixed leaf-"a" reference footprint, independent of variant/tier/s_light.
	var atlas := _LeafAtlas.new()
	_ref_area = atlas.alpha_fill_for("a") * params.leaf_width_base * params.leaf_width_base \
		/ atlas.aspect_for("a")


## Compute all coverage numbers from PlantData.
##
## seed_azimuth_deg: the azimuth of the seed anchor in the same convention used
##   for bucket azimuth (0° = north, 180° = south).  The sun-facing 180° is
##   centred on this angle; so for a south seed pass 180.0.
func measure(plant: PlantData, seed_azimuth_deg: float) -> Dictionary:
	var n_buckets := AZIMUTH_BINS * HEIGHT_BINS
	# Main accumulator: ref_area per leaf, no orientation term (SD-METRIC-3 as amended by the
	# SD-OPEN-13 amendment). AS-1 measures placement occupancy — how much leaf is attributed to
	# a bucket — so every presentation term is excluded at once: size (s_light), art (variant and
	# tier) and orientation (cant, jitter, droop).
	var leaf_accum := PackedFloat32Array()
	leaf_accum.resize(n_buckets)
	# Diagnostic accumulator: ref_area · |dot(n_leaf, n_bucket)|, the orientation-weighted basis
	# every historical AS-1 figure was measured on. Reported so a change of basis stays visible
	# rather than looking like a coverage regression; it gates nothing.
	var leaf_accum_nleaf := PackedFloat32Array()
	leaf_accum_nleaf.resize(n_buckets)
	# Stem-occupancy: 1 if any segment midpoint maps to this bucket
	var stem_has := PackedByteArray()
	stem_has.resize(n_buckets)
	# SD-METRIC-6 sector accumulators (30° bins)
	var sector_stem := PackedFloat32Array()
	sector_stem.resize(SECTOR_COUNT)
	var sector_leaves := PackedInt32Array()
	sector_leaves.resize(SECTOR_COUNT)

	var lip_reached := false

	# ---- Segments ----
	var n_segs := plant.segment_count()
	for i in range(n_segs):
		var a: Vector3 = plant.seg_a[i]
		var b: Vector3 = plant.seg_b[i]
		var mx: float = (a.x + b.x) * 0.5
		var my: float = (a.y + b.y) * 0.5
		var mz: float = (a.z + b.z) * 0.5
		var az := _azimuth_bin_of(mx, mz)
		var h := _height_bin_of(my)
		var sec := _sector_of(mx, mz)
		if sec >= 0:
			sector_stem[sec] += a.distance_to(b)
		if az >= 0 and h >= 0:
			stem_has[az * HEIGHT_BINS + h] = 1
		if a.y >= _spec.height or b.y >= _spec.height:
			lip_reached = true

	# ---- Leaves ----
	var coverage_threshold := _bucket_area * COVERAGE_THRESHOLD
	var n_leaves := plant.leaf_count()
	for i in range(n_leaves):
		var base := i * 12
		# PlantData stores: [bx.x, bx.y, bx.z, origin.x,
		#                    by.x, by.y, by.z, origin.y,
		#                    bz.x, bz.y, bz.z, origin.z]
		var ox: float = plant.leaf_xform[base + 3]
		var oy: float = plant.leaf_xform[base + 7]
		var oz: float = plant.leaf_xform[base + 11]
		# basis.z is the leaf face normal (perpendicular to the leaf card plane)
		var nlx: float = plant.leaf_xform[base + 8]
		var nly: float = plant.leaf_xform[base + 9]
		var nlz: float = plant.leaf_xform[base + 10]

		var az := _azimuth_bin_of(ox, oz)
		var h := _height_bin_of(oy)
		var sec := _sector_of(ox, oz)

		if sec >= 0:
			sector_leaves[sec] += 1

		if az < 0 or h < 0:
			continue

		var idx := az * HEIGHT_BINS + h
		# Every leaf contributes the same fixed leaf-"a" footprint: no size term, no art term,
		# no orientation term. The projection that used to be here was withdrawn from the
		# ratified contract rather than left inert, because on a cylinder it could not do
		# anything: a leaf's bucket is chosen from its own position, so the wall normal and the
		# bucket normal are never more than half a 5° bin apart and |dot| never fell below 0.999.
		leaf_accum[idx] += _ref_area

		# Diagnostic only: the orientation-weighted basis, kept so a basis change is legible.
		# Outward wall normal at this bucket's azimuth bin centre (AR-AMBIG-6); nby = 0 for a
		# vertical cylinder wall, so the vertical component of n_leaf is irrelevant here.
		var az_rad := deg_to_rad(float(az) * 5.0 + 2.5)
		var nbx: float = sin(az_rad)
		var nbz: float = -cos(az_rad)
		leaf_accum_nleaf[idx] += _ref_area * absf(nlx * nbx + nlz * nbz)

	# ---- Tally coverage ----
	var total_elig := 0
	var total_cov := 0
	var sun_elig := 0
	var sun_cov := 0
	var shade_elig := 0
	var shade_cov := 0
	var stem_cov := 0
	# Diagnostic orientation-weighted tallies, parallel to the gating ones above
	var total_cov_nleaf := 0
	var sun_cov_nleaf := 0
	var shade_cov_nleaf := 0

	for az in range(AZIMUTH_BINS):
		for h in range(HEIGHT_BINS):
			var idx := az * HEIGHT_BINS + h
			if _eligible[idx] == 0:
				continue
			total_elig += 1
			var az_center := float(az) * 5.0 + 2.5
			var in_sun := _in_sun_half(az_center, seed_azimuth_deg)
			var covered := leaf_accum[idx] >= coverage_threshold
			var covered_nleaf := leaf_accum_nleaf[idx] >= coverage_threshold
			if covered:
				total_cov += 1
			if covered_nleaf:
				total_cov_nleaf += 1
			if stem_has[idx] != 0:
				stem_cov += 1
			if in_sun:
				sun_elig += 1
				if covered:
					sun_cov += 1
				if covered_nleaf:
					sun_cov_nleaf += 1
			else:
				shade_elig += 1
				if covered:
					shade_cov += 1
				if covered_nleaf:
					shade_cov_nleaf += 1

	# ---- AS-2: stem length per hemisphere ----
	var sun_stem := 0.0
	var shade_stem := 0.0
	for sec in range(SECTOR_COUNT):
		var sec_center := float(sec) * 30.0 + 15.0
		if _in_sun_half(sec_center, seed_azimuth_deg):
			sun_stem += sector_stem[sec]
		else:
			shade_stem += sector_stem[sec]
	var stem_asym := 0.0
	var total_stem := sun_stem + shade_stem
	if total_stem > 1e-6:
		stem_asym = (sun_stem - shade_stem) / total_stem * 100.0

	var denom_elig := float(max(total_elig, 1))
	return {
		"overall_pct":             100.0 * float(total_cov)  / denom_elig,
		"sun_half_pct":            100.0 * float(sun_cov)    / float(max(sun_elig, 1)),
		"shade_half_pct":          100.0 * float(shade_cov)  / float(max(shade_elig, 1)),
		"stem_bucket_pct":         100.0 * float(stem_cov)   / denom_elig,
		"sector_stem_length":      sector_stem,
		"sector_leaf_count":       sector_leaves,
		"lip_reached":             lip_reached,
		"sun_stem_length":         sun_stem,
		"shade_stem_length":       shade_stem,
		"stem_asymmetry_pct":      stem_asym,
		"total_eligible_buckets":  total_elig,
		"sun_eligible_buckets":    sun_elig,
		"shade_eligible_buckets":  shade_elig,
		# Diagnostic: orientation-weighted (ref_area · |dot(n_leaf, n_bucket)|), gates nothing.
		# Reports coverage as if every leaf lay flush on the wall (no phototropic cant).
		# Difference from the main numbers isolates the cant's contribution via SD-METRIC-3.
		"overall_pct_nleaf":       100.0 * float(total_cov_nleaf) / denom_elig,
		"sun_half_pct_nleaf":      100.0 * float(sun_cov_nleaf)   / float(max(sun_elig, 1)),
		"shade_half_pct_nleaf":    100.0 * float(shade_cov_nleaf) / float(max(shade_elig, 1)),
	}


## True if az_deg is within 90° of seed_az_deg (sun-facing half).
## AR-METRIC: the sun half is centred on the seed anchor azimuth, not a compass constant.
static func _in_sun_half(az_deg: float, seed_az_deg: float) -> bool:
	var diff := fposmod(az_deg - seed_az_deg, 360.0)
	if diff > 180.0:
		diff = 360.0 - diff
	return diff <= 90.0


## azimuth bin in [0, AZIMUTH_BINS) from world-space xz position.
## Convention: azimuth 0° = north = (0,0,−1), increasing clockwise.
## Uses atan2(x, −z) so: north=0°, east=90°, south=180°, west=270°.
static func _azimuth_bin_of(x: float, z: float) -> int:
	var az := atan2(x, -z)
	if az < 0.0:
		az += 2.0 * PI
	var bin := int(az / (2.0 * PI) * float(AZIMUTH_BINS))
	return clampi(bin, 0, AZIMUTH_BINS - 1)


## height bin in [0, HEIGHT_BINS) or −1 if y is outside the wall range.
static func _height_bin_of(y: float) -> int:
	var bin := int(floor(y / HEIGHT_BIN_SIZE))
	if bin < 0 or bin >= HEIGHT_BINS:
		return -1
	return bin


## sector index in [0, SECTOR_COUNT) — 30° sectors, sector 0 starts at north.
static func _sector_of(x: float, z: float) -> int:
	var az := atan2(x, -z)
	if az < 0.0:
		az += 2.0 * PI
	return int(az / (2.0 * PI) * float(SECTOR_COUNT))


## Build the opening-exclusion mask (SD-METRIC-2).
## Buckets inside any door or window opening get flag 0; eligible buckets get 1.
func _build_opening_mask(spec: TowerSpec) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(AZIMUTH_BINS * HEIGHT_BINS)
	mask.fill(1)
	_mask_out_opening(mask, spec.door_azimuth, spec.door_width,
		0.0, spec.door_height, spec.radius_outer)
	_mask_out_opening(mask, spec.window_azimuth, spec.window_size,
		spec.window_sill, spec.window_sill + spec.window_size, spec.radius_outer)
	return mask


## Exclude all buckets within the angular footprint and height band of one opening.
## center_deg: opening centre in degrees (same azimuth convention as bucket bins).
## width_m: physical opening width in metres at the outer wall surface.
## y_lo / y_hi: bottom and top of the opening in world-space metres.
## radius: outer wall radius used to convert linear width to angular half-width.
func _mask_out_opening(mask: PackedByteArray, center_deg: float, width_m: float,
		y_lo: float, y_hi: float, radius: float) -> void:
	var half_deg := rad_to_deg(atan(width_m * 0.5 / maxf(radius, 1e-3)))
	var h_lo := maxi(0, int(floor(y_lo / HEIGHT_BIN_SIZE)))
	var h_hi := mini(HEIGHT_BINS - 1, int(ceil(y_hi / HEIGHT_BIN_SIZE)) - 1)
	for az in range(AZIMUTH_BINS):
		var az_center := float(az) * 5.0 + 2.5
		var diff := fposmod(az_center - center_deg, 360.0)
		if diff > 180.0:
			diff = 360.0 - diff
		if diff <= half_deg:
			for h in range(h_lo, h_hi + 1):
				mask[az * HEIGHT_BINS + h] = 0
