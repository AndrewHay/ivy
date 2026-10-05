## VillageBackdrop — non-interactive environment dressing around the playable structure.
##
## Repositioned by World._activate_mesh_scenario() to (pivot.x, 0, pivot.z).
## Hidden on the procedural path and in _teardown_active_building().
## All MeshInstance3D descendants get the shared mute material + shadow OFF in _ready().
## No collision, no layer 1, never referenced by BuildingCatalog or SurfaceQuery.
class_name VillageBackdrop
extends Node3D

const _MUTE_MATERIAL := preload("res://assets/backdrop/backdrop_mute.tres")


func _ready() -> void:
	_apply_subtree(self)


func _apply_subtree(node: Node) -> void:
	if node is CollisionObject3D:
		push_error("VillageBackdrop: unexpected collision node '%s' — backdrop must be collision-free" % node.name)
		if (node as CollisionObject3D).get_collision_layer() & 1:
			push_error("VillageBackdrop: node '%s' is on collision layer bit 1" % node.name)
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		mesh_node.material_override = _MUTE_MATERIAL
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_subtree(child)
