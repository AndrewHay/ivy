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

## Matches `IvyParams.leaf_width_base` default — blade width, not petiole length.
const LEAF_REFERENCE_WIDTH_M := 0.075
## Bee total body length (head–abdomen); butterfly wingspan (tip to tip).
const BEE_LENGTH_FRAC_OF_LEAF := 1.0 / 3.0
const BUTTERFLY_WINGSPAN_FRAC_OF_LEAF := 0.5

static func bee_body_length_m() -> float:
	return LEAF_REFERENCE_WIDTH_M * BEE_LENGTH_FRAC_OF_LEAF


static func butterfly_wingspan_m() -> float:
	return LEAF_REFERENCE_WIDTH_M * BUTTERFLY_WINGSPAN_FRAC_OF_LEAF


## Half-thickness of wing volume (metres) — slight depth so wings are not paper planes.
static func bee_wing_half_thickness_m() -> float:
	return bee_body_length_m() * 0.016


static func butterfly_wing_half_thickness_m() -> float:
	return butterfly_wingspan_m() * 0.012


const BEE_VISUAL_SCALE := 1.1
const BUTTERFLY_WING_FLAP_HZ := 4.0
const BUTTERFLY_WING_FLAP_AMPLITUDE := 0.20
## Bee cruise speed between flower anchors (m/s).
const BEE_CRUISE_SPEED_MPS := 0.45
const BUTTERFLY_FLIT_CRUISE_MPS := 0.32
const BUTTERFLY_CHASE_PROB := 0.25
const BUTTERFLY_RACE_DURATION_SEC := 10.0
