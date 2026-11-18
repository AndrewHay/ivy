extends GutTest

## ivy-b1e.38 (IMPLEMENTATION.md SD-MESH-19.4.3 item A): a way out of a proxy solid along the line
## of sight must end PROXY_EXIT_MARGIN clear of the proxy, as the gradient exit does. A sight line
## that only grazes along a face never gets clear and is refused (no_exit_found).
##
## Fixture: a closed box room on a floor slab, like surface_wall and the square. The hero walls are
## 0.20 m thick, the proxy walls 0.45 m, flush outside, so every courtyard face sits 0.25 m behind
## the proxy's inner face and its 0.25 m viewpoint lands on that face. Proxy and hero are roofed;
## the hero has no floor, so a ray that passes through the one-sided proxy floor slab leaves under
## the structure. The proxy's floor slab collides at y = +0.0005 while its SDF reads the slab top at
## y = -0.0001: the sub-millimetre SDF/collision mismatch measured on c4 and the square, where the
## sight exit stopped ON the slab plane (phi +0.0000 .. +0.0002) and 7 of 17 sky rays passed down
## through the floor. Samples at y 0.0000 and 0.0002 were judged (about +0.20); 0.01 m never was.

const Audit = preload("res://tools/growth_surface_audit.gd")
const Fixtures = preload("res://test/test_growth_surface_audit.gd")

const ROOM := 2.90  # outer footprint, x and z
const HERO_WALL := 0.20
const PROXY_WALL := 0.45
const WALL_H := 2.0
const SLAB := 0.20
const COLLISION_FLOOR_TOP := 0.0005
const SDF_FLOOR_TOP := -0.0001

var _nodes: Array[Node] = []


## Four walls of thickness `t` around an ROOM x ROOM footprint at `o`, y `base` .. WALL_H. The
## proxy's walls run down into the floor slab (one solid, as the builder's are), the hero's stand on y 0.
static func _walls(o: Vector3, t: float, base: float = 0.0) -> Array[AABB]:
	var h := WALL_H - base
	var b := Vector3(0.0, base, 0.0)
	return [
		AABB(o + b, Vector3(t, h, ROOM)),
		AABB(o + b + Vector3(ROOM - t, 0.0, 0.0), Vector3(t, h, ROOM)),
		AABB(o + b + Vector3(t, 0.0, 0.0), Vector3(ROOM - 2.0 * t, h, t)),
		AABB(o + b + Vector3(t, 0.0, ROOM - t), Vector3(ROOM - 2.0 * t, h, t)),
	]


static func _roof(o: Vector3) -> AABB:
	return AABB(o + Vector3(0.0, WALL_H, 0.0), Vector3(ROOM, SLAB, ROOM))


static func _floor(o: Vector3, top: float) -> AABB:
	return AABB(Vector3(o.x, top - SLAB, o.z), Vector3(ROOM, SLAB, ROOM))


func _room_audit(o: Vector3):
	var hero_boxes: Array[AABB] = _walls(o, HERO_WALL)
	hero_boxes.append(_roof(o))
	var pieces: Array = []
	for i in hero_boxes.size():
		pieces.append({"name": "t_hero_Wall_room_%d" % i, "faces": Fixtures._box_faces(hero_boxes[i]),
			"transform": Transform3D.IDENTITY})
	var proxy_collision: Array[AABB] = _walls(o, PROXY_WALL, -SLAB)
	proxy_collision.append_array([_roof(o), _floor(o, COLLISION_FLOOR_TOP)])
	var proxy_sdf: Array[AABB] = _walls(o, PROXY_WALL, -SLAB)
	proxy_sdf.append_array([_roof(o), _floor(o, SDF_FLOOR_TOP)])
	var proxy := StaticBody3D.new()
	proxy.collision_layer = Audit.PROXY_MASK
	proxy.collision_mask = 0
	add_child(proxy)
	for box in proxy_collision:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(Fixtures._box_faces(box))
		var col := CollisionShape3D.new()
		col.shape = shape
		proxy.add_child(col)
	var hero_body: StaticBody3D = Audit.make_hero_body(self, pieces)
	_nodes = [proxy, hero_body]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var audit = Audit.new()
	audit.setup(proxy.get_world_3d().direct_space_state, pieces, Fixtures._analytic_sdf(proxy_sdf))
	return audit


func after_each() -> void:
	for node in _nodes:
		remove_child(node)
		node.free()
	_nodes = []


func test_courtyard_face_at_the_ground_line_is_not_judged() -> void:
	var o := Vector3(300.0, 0.0, 0.0)
	var audit = await _room_audit(o)
	# The west wall's courtyard face, facing +x, mid-span.
	var face_x := o.x + HERO_WALL
	var inward := Vector3.RIGHT
	for y in [0.0, 0.0002, 0.01]:
		var p := Vector3(face_x, y, o.z + ROOM * 0.5)
		var eye: Vector3 = p + inward * Audit.VISIBLE_CLEARANCE
		assert_lt(float(audit._sdf.signed_distance(eye)), 0.0,
			"y %.4f: the viewpoint lands on the proxy's inner face, just inside it" % y)
		var side: Dictionary = audit._exterior_side(p, inward)
		var g: Array = audit._gap_at(p, inward)
		var sight: Array = audit._sight_exit(eye, inward)
		gut.p("y %.4f: dir %s reason %s sight %s | sight exit %s %s | would-be g %+.4f" % [
			y, side["dir"], side["reason"], side["sight_reason"], sight[0], sight[1], float(g[0])])
		assert_between(float(g[0]), 0.15, 0.30,
			"y %.4f: were it judged, the face would read a courtyard gap like c4's (+0.20 there, " % y
			+ "+0.25 here), far over the 0.05 m max")
		assert_eq(side["dir"], Vector3.ZERO,
			"y %.4f: a sealed courtyard face is not judged (would-be g %+.4f, sight exit %s)" % [
				y, float(g[0]), sight[0]])
		assert_true(String(side["sight_reason"]) in Audit.PROXY_EXIT_REJECTS
				or side["sight_reason"] == Audit.REJECT_NO_SKY,
			"y %.4f: the line of sight was tried and refused: %s" % [y, side["sight_reason"]])


## The grazing sight line along the floor never gets PROXY_EXIT_MARGIN clear, so it is refused
## within SIGHT_EXIT_REACH rather than ending on the slab plane.
func test_sight_exit_that_only_grazes_the_floor_is_refused() -> void:
	var o := Vector3(320.0, 0.0, 0.0)
	var audit = await _room_audit(o)
	var eye := Vector3(o.x + PROXY_WALL, 0.0001, o.z + ROOM * 0.5)
	var sight: Array = audit._sight_exit(eye, Vector3.RIGHT)
	assert_eq(sight[0], Vector3.INF, "no way out: the march runs along the slab plane")
	assert_eq(sight[1], Audit.REJECT_EXIT_NONE)


## A sight line that does get clear still ends PROXY_EXIT_MARGIN outside the proxy (mid-wall height,
## leaving the proxy's inner face into the courtyard air).
func test_sight_exit_ends_at_least_the_margin_clear_of_the_proxy() -> void:
	var o := Vector3(340.0, 0.0, 0.0)
	var audit = await _room_audit(o)
	var eye := Vector3(o.x + PROXY_WALL - 0.01, 1.0, o.z + ROOM * 0.5)
	var sight: Array = audit._sight_exit(eye, Vector3.RIGHT)
	assert_ne(sight[0], Vector3.INF, "mid-wall, the line of sight leaves the proxy: %s" % [sight[1]])
	if sight[0] != Vector3.INF:
		assert_gte(float(audit._sdf.signed_distance(sight[0])), Audit.PROXY_EXIT_MARGIN - 1e-5)
		assert_lte((sight[0] as Vector3).x - eye.x, Audit.PROXY_EXIT_MARGIN + 0.01 + 0.002,
			"and not much further than that")
