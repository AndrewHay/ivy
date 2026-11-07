class_name VillagePondSite
extends RefCounted

## Single source for village pond scale, classic placement, and clearance contracts.

const CLASSIC_CENTER := Vector2(0.5, 12.0)

const SIZE_SCALE := 1.5
const MEAN_WATER_RADIUS_M := 1.75 * SIZE_SCALE
const BANK_OUTER_M := 3.25 * SIZE_SCALE
const BANK_RING_WIDTH_M := BANK_OUTER_M - MEAN_WATER_RADIUS_M

## Bank outer outline is the pond footprint for placement tests.
const COTTAGE_ROOF_GROW_M := 0.75
const COTTAGE_CLEARANCE_M := 1.0

const PATH_SEGMENT_CLEARANCE_M := 0.55
const PATH_POND_EXTRA_GAP_M := 0.5
const PATH_CLEARANCE_M := PATH_SEGMENT_CLEARANCE_M + PATH_POND_EXTRA_GAP_M

const HERO_MIN_BANK_DIST_M := 6.5
const LAWN_BANK_INSET_M := 2.0

## Scatter must stay outside bank + this margin (flowers, plants, bushes).
const SCATTER_CLEARANCE_M := 0.15

## Blade grass may grow on the outer bank where shoreline_along >= this (0 = water edge, 1 = bank lip).
const GRASS_BANK_MIN_ALONG := 0.58
