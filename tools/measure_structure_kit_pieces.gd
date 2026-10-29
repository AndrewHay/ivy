## Merged instance AABBs for committed building kit under assets/backdrop/pieces/.
## Usage: godot --headless --path . --script res://tools/measure_structure_kit_pieces.gd
extends SceneTree

const DIR := "res://assets/backdrop/pieces/"
const PIECES := [
	"Balcony_Simple_Straight",
	"Door_1_Flat",
	"Prop_Chimney",
	"Prop_Chimney2",
	"Prop_Crate",
	"Prop_Wagon",
	"Prop_WoodenFence_Extension1",
	"Prop_WoodenFence_Single",
	"Roof_2x4_RoundTile",
	"Roof_Front_Brick4",
	"Roof_RoundTiles_4x4",
	"Roof_RoundTiles_4x6",
	"Roof_RoundTiles_4x8",
	"Wall_Plaster_Door_Flat",
	"Wall_Plaster_Straight",
	"Wall_Plaster_Window_Wide_Flat",
	"Wall_UnevenBrick_Straight",
	"WindowShutters_Wide_Flat_Closed",
]


func _init() -> void:
	for piece in PIECES:
		var path: String = DIR + piece + ".gltf"
		var ps := load(path) as PackedScene
		if ps == null:
			print(piece, ": LOAD FAILED (", path, ")")
			continue
		var inst := ps.instantiate() as Node3D
		var box := _merged_aabb(inst, Transform3D.IDENTITY)
		print(
			"%-40s size=(%5.2f, %5.2f, %5.2f)"
			% [piece, box.size.x, box.size.y, box.size.z]
		)
		inst.free()
	quit()


func _merged_aabb(node: Node, parent_xf: Transform3D) -> AABB:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	var out := AABB()
	var have := false
	if node is MeshInstance3D:
		out = xf * (node as MeshInstance3D).get_aabb()
		have = true
	for child in node.get_children():
		var c := _merged_aabb(child, xf)
		if c.size == Vector3.ZERO:
			continue
		out = c if not have else out.merge(c)
		have = true
	return out
