class_name FaunaAgentState
extends RefCounted

enum ButterflyMode { TO_FLOWER, FLIT_AT_FLOWER, RACING, FOLLOWING }

var species: FaunaConstants.Species = FaunaConstants.Species.BEE
## Root node in the scene (MeshInstance3D or Node3D rig).
var mesh: Node3D = null
var wing_left: MeshInstance3D = null
var wing_right: MeshInstance3D = null
var anchor_index: int = 0
var lifetime: float = 12.0
var age: float = 0.0
var wing_phase: float = 0.0
var travel_phase: float = 0.0
var heading: float = 0.0
var hover_radius: float = 0.02
var travel_speed: float = 1.0
var wing_beat_hz: float = 12.0
## Bee / butterfly flower trips (world space).
var path_from: Vector3 = Vector3.ZERO
var path_to: Vector3 = Vector3.ZERO
var path_segment_u: float = 1.0
var cruise_speed_mps: float = FaunaConstants.BEE_CRUISE_SPEED_MPS
var bee_linger_sec: float = 0.0
var bee_trip_target_index: int = -1
## Test Fauna scene: orbit / hover centre in backdrop XZ (not flower anchor).
var test_use_custom_hover: bool = false
var test_hover_xz: Vector2 = Vector2.ZERO
## Butterfly presentation FSM (SD-FAUNA test / garden).
var butterfly_mode: int = ButterflyMode.FLIT_AT_FLOWER
var butterfly_linger_sec: float = 0.0
var butterfly_race_sec: float = 0.0
var butterfly_race_dir_xz: Vector2 = Vector2.ZERO
var butterfly_partner = null
var butterfly_is_race_leader: bool = false
var flit_wobble_phase: float = 0.0
var flit_heading: float = 0.0
