class_name FaunaConstants
extends RefCounted

enum Species { BEE, BUTTERFLY, LADYBIRD }

enum AnchorKind { FLOWER, CLOVER }

const GLOBAL_MAX_AGENTS := 12
const MAX_BEE := 8
const MAX_BUTTERFLY := 6
const MAX_LADYBIRD := 1

const GARDEN_RING_INNER_M := 5.5
const GARDEN_RING_OUTER_M := 12.0
const CLOVER_RING_OUTER_M := 14.0

const HERO_HARD_EXCLUSION_M := 5.0
const HERO_SOFT_FADE_M := 7.0

const LOD_DESPAWN_M := 18.0
const LOD_SPAWN_FORBID_M := 22.0
const HERO_CAMERA_CAP_SCALE_DIST_M := 6.0
const HERO_CAMERA_CAP_SCALE := 0.4

const LIT_SPAWN_CUTOFF := 0.05
const SPAWN_TICK_HZ := 4.0

const WIND_CYCLE_SEC := 10.0
