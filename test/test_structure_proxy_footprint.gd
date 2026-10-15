extends GutTest

## ivy-nzj: every collision piece below the roof must sit inside the visible (hero)
## footprint. A proxy solid the hero does not render is an invisible wall ivy climbs.

const SCENARIO := "res://assets/structures/scenarios/square.tres"
const MARGIN := 0.05
const ROOF_BASE_Y := 3.0


func test_square_collision_below_roof_within_hero_footprint() -> void:
	var scenario := load(SCENARIO) as StructureScenario
	var body := StructureBody.new()
	add_child_autofree(body)
	body.build(scenario.collision_glb, scenario.hero_glb)

	var hero := _hero_footprint(body.get_node("StructureVisual")).grow(MARGIN)
	assert_gt(hero.size.x, 1.0, "hero wall footprint found")

	var checked := 0
	for child in body.get_children():
		if not child is CollisionShape3D:
			continue
		var col := child as CollisionShape3D
		var box: AABB = col.transform * col.shape.get_debug_mesh().get_aabb()
		if box.position.y >= ROOF_BASE_Y:
			continue
		checked += 1
		var lo := Vector2(box.position.x, box.position.z)
		var hi := Vector2(box.end.x, box.end.z)
		assert_true(
			hero.has_point(lo) and hero.has_point(hi),
			"%s xz [%s..%s] pokes outside hero footprint %s" % [col.name, lo, hi, hero]
		)
	assert_gt(checked, 10, "expected wall/slab/seal collision pieces below the roof")


func _hero_footprint(root: Node) -> Rect2:
	var merged := Rect2()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is MeshInstance3D or "roof" in node.name.to_lower():
			continue
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		var rect := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		merged = rect if first else merged.merge(rect)
		first = false
	return merged
