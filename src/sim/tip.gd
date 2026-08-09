class_name Tip
extends RefCounted

enum State { SEEDED, GROWING, FLOATING, DORMANT, DEAD }

var id: int = 0
var state: State = State.SEEDED
var position: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.UP
var random_dir: Vector3 = Vector3.RIGHT
var growth_budget: float = 0.0
var floating_length: float = 0.0
var shoot_length: float = 0.0
var branch_order: int = 0
var segment_count: int = 0
var node_count: int = 0
var distance_since_node: float = 0.0
var last_contact_normal: Vector3 = Vector3.UP
var ground_strikes: int = 0
var stream: RngStream
var branch_index: int = 0
var pending_branch: bool = false
var leaf_side_sign: float = 1.0
var vigour: float = 1.0


func is_live() -> bool:
	return state == State.GROWING or state == State.FLOATING or state == State.SEEDED


func is_growing() -> bool:
	return state == State.GROWING or state == State.FLOATING
