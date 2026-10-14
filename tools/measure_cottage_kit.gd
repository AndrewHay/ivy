## Instance-space AABBs (mesh transforms applied) for cottage kit pieces.
## Usage: Godot --headless --path . --script res://tools/measure_cottage_kit.gd
extends SceneTree

const KIT := "res://assets/_local/medieval_village_megakit/glTF/%s.gltf"
const PIECES := [
	"Wall_Plaster_Straight",
	"Wall_Plaster_Door_Flat",
	"Wall_Plaster_Window_Wide_Flat",
	"Wall_UnevenBrick_Straight",
	"Roof_2x4_RoundTile",
	"Roof_RoundTiles_4x4",
	"Roof_RoundTiles_4x6",
	"Roof_RoundTiles_4x8",
	"Roof_RoundTiles_6x4",
	"Roof_RoundTiles_6x6",
	"Roof_RoundTiles_6x8",
	"Roof_Front_Brick4",
	"Roof_Front_Brick6",
	"Corner_Exterior_Wood",
	"Corner_Exterior_Brick",
	"Prop_Chimney2",
]


func _init() -> void:
	for piece in PIECES:
		var ps := load(KIT % piece) as PackedScene
		if ps == null:
			print(piece, ": LOAD FAILED")
			continue
		var inst := ps.instantiate() as Node3D
		var box := _merged_aabb(inst, Transform3D.IDENTITY)
		print("%-32s min=(%6.2f,%6.2f,%6.2f) max=(%6.2f,%6.2f,%6.2f) size=(%5.2f,%5.2f,%5.2f)" % [
			piece, box.position.x, box.position.y, box.position.z,
			box.end.x, box.end.y, box.end.z, box.size.x, box.size.y, box.size.z])
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
