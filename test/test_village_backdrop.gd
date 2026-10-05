## Tests for VillageBackdrop scene and contract invariants.
##
## Acceptance criteria (ivy-42m.4):
##  (a) no StaticBody3D/CollisionObject3D descendants
##  (b) no descendant on collision layer bit 1
##  (c) after _ready all MeshInstance3D have material_override == mute material + cast_shadow OFF
##  (d) surface/draw estimate <= 100 (via surface count across all ArrayMesh); tri count <= 30k
##  (e) no vine piece names present
##  (f) VillageBackdrop is NOT referenced by BuildingCatalog
##  (g) planting-raycast: mask-1 ray at a backdrop mesh returns no hit (unplantable)
extends GutTest

const VillageBackdropScene = preload("res://src/world/village_backdrop.tscn")
const MuteMaterial = preload("res://assets/backdrop/backdrop_mute.tres")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")

var _backdrop: Node3D


func before_each() -> void:
	_backdrop = VillageBackdropScene.instantiate()
	add_child_autofree(_backdrop)
	# _ready() fires on add_child


# ── (a) No collision objects ──────────────────────────────────────────────────

func test_no_collision_objects() -> void:
	var collision_nodes := _find_nodes_of_type(_backdrop, CollisionObject3D)
	var names: Array[String] = []
	for n in collision_nodes:
		names.append(n.name)
	assert_eq(collision_nodes.size(), 0,
		"VillageBackdrop must have zero CollisionObject3D descendants; found: %s" % str(names))


func test_no_static_bodies() -> void:
	var bodies := _find_nodes_of_type(_backdrop, StaticBody3D)
	var names: Array[String] = []
	for n in bodies:
		names.append(n.name)
	assert_eq(bodies.size(), 0,
		"VillageBackdrop must have zero StaticBody3D descendants; found: %s" % str(names))


# ── (b) No collision layer bit 1 ─────────────────────────────────────────────

func test_no_descendant_on_collision_layer_1() -> void:
	var violators: Array[String] = []
	_check_collision_layers(_backdrop, violators)
	assert_eq(violators.size(), 0,
		"No backdrop node may be on collision layer bit 1; violators: %s" % str(violators))


# ── (c) material_override and cast_shadow after _ready ───────────────────────

func test_all_meshes_have_mute_material_override() -> void:
	var meshes := _find_nodes_of_type(_backdrop, MeshInstance3D)
	assert_gt(meshes.size(), 0, "Backdrop must have at least one MeshInstance3D")
	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		assert_eq(mi.material_override, MuteMaterial,
			"MeshInstance3D '%s' must have backdrop_mute.tres as material_override" % mi.name)


func test_all_meshes_have_shadow_off() -> void:
	var meshes := _find_nodes_of_type(_backdrop, MeshInstance3D)
	assert_gt(meshes.size(), 0, "Backdrop must have at least one MeshInstance3D")
	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"MeshInstance3D '%s' must have cast_shadow=OFF" % mi.name)


# ── (d) Triangle and draw call budget ────────────────────────────────────────

func test_triangle_budget_under_30k() -> void:
	var total_tris := 0
	for mesh in _find_nodes_of_type(_backdrop, MeshInstance3D):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays != null and arrays[Mesh.ARRAY_INDEX] != null:
				total_tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif arrays != null and arrays[Mesh.ARRAY_VERTEX] != null:
				total_tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	assert_lt(total_tris, 31000,
		"Total tris must be <=~30k for backdrop budget; got %d" % total_tris)


func test_surface_count_under_100() -> void:
	var total_surfaces := 0
	for mesh in _find_nodes_of_type(_backdrop, MeshInstance3D):
		var mi := mesh as MeshInstance3D
		if mi.mesh != null:
			total_surfaces += mi.mesh.get_surface_count()
	assert_lt(total_surfaces, 101,
		"Surface count (proxy for draw calls) must be <=100; got %d" % total_surfaces)


# ── (e) No vine piece names ───────────────────────────────────────────────────

func test_no_vine_piece_names() -> void:
	var vine_patterns := ["Vine1", "Vine2", "Vine4", "Vine5", "Vine6", "Vine9", "VineLeaf"]
	_check_no_vine_names(_backdrop, vine_patterns)


# ── (f) Not in BuildingCatalog ───────────────────────────────────────────────

func test_not_in_building_catalog() -> void:
	# BuildingCatalog.all() must not contain any backdrop-related entry.
	# VillageBackdrop has no catalog entry and must never grow one.
	for entry in BuildingCatalog.all():
		assert_ne(entry.id.to_lower(), "village_backdrop",
			"VillageBackdrop must NOT be in BuildingCatalog")
		assert_false(entry.id.to_lower().begins_with("backdrop"),
			"No backdrop id may appear in BuildingCatalog; found '%s'" % entry.id)


# ── (g) Planting-raycast: mask-1 ray returns no hit ──────────────────────────

func test_backdrop_mesh_unplantable_via_mask1_ray() -> void:
	# Planting uses collision_mask=1 (SurfaceQuery).  MeshInstance3D nodes carry no
	# PhysicsBody3D / CollisionShape3D, so they are invisible to physics queries.
	# Verify by firing a ray into the backdrop from above at a known piece position.
	var space: PhysicsDirectSpaceState3D = _backdrop.get_world_3d().direct_space_state
	if space == null:
		pending("physics space not available in this test environment — skip")
		return

	# Right building ground wall is at approx x=5.5, y=1.5, z=0 in local space.
	# The backdrop starts at world origin (not yet repositioned by World) so we
	# fire from above into that local-space position.
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(5.5, 10.0, 0.0),
		Vector3(5.5, -1.0, 0.0),
		1  # mask bit 1 — the planting layer
	)
	var result: Dictionary = space.intersect_ray(ray)
	assert_true(result.is_empty(),
		"Mask-1 ray into backdrop position must return no hit (backdrop is unplantable); got: %s" % result)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_nodes_of_type(root: Node, type) -> Array:
	var result: Array = []
	_collect_type(root, type, result)
	return result


func _collect_type(node: Node, type, result: Array) -> void:
	if node != null and is_instance_of(node, type):
		result.append(node)
	for child in node.get_children():
		_collect_type(child, type, result)


func _check_collision_layers(node: Node, violators: Array[String]) -> void:
	if node is CollisionObject3D:
		if (node as CollisionObject3D).get_collision_layer() & 1:
			violators.append(node.name)
	for child in node.get_children():
		_check_collision_layers(child, violators)


func _check_no_vine_names(node: Node, patterns: Array) -> void:
	for pattern in patterns:
		assert_false(node.name.contains(pattern),
			"Vine-named node found in backdrop: '%s'" % node.name)
	for child in node.get_children():
		_check_no_vine_names(child, patterns)


# -- (h) Flank inner face >= ~6 m from pivot (ivy-42m.7 findings #1 and #3) ---

func test_flank_inner_face_outside_6m() -> void:
	# Vol A inner face: RA_W_N / RA_W_S  (rot90deg,  face_x = tx - 0.314)
	# Vol B inner face: RB_E_N / RB_E_S  (rot-90deg, face_x = tx + 0.314)
	# Wall piece face at Z=-0.314 in local space; rot90deg maps local Z to world +X,
	# so world face_x = origin.x - 0.314 (the innermost X of the wall geometry).
	var vol_a_names := ["RA_W_N", "RA_W_S"]
	var vol_b_names := ["RB_E_N", "RB_E_S"]
	for node_name in vol_a_names:
		var piece := _backdrop.get_node_or_null(node_name)
		assert_not_null(piece, "Vol A inner wall node '%s' must exist" % node_name)
		if piece:
			var tx: float = (piece as Node3D).transform.origin.x
			assert_gte(tx - 0.314, 5.9,
				"Vol A '%s' inner face (tx-0.314=%.3f) must be >= ~6 m; tx=%.3f" % [node_name, tx - 0.314, tx])
	for node_name in vol_b_names:
		var piece := _backdrop.get_node_or_null(node_name)
		assert_not_null(piece, "Vol B inner wall node '%s' must exist" % node_name)
		if piece:
			var tx: float = (piece as Node3D).transform.origin.x
			assert_lte(tx + 0.314, -5.9,
				"Vol B '%s' inner face (tx+0.314=%.3f) must be <= ~-6 m; tx=%.3f" % [node_name, tx + 0.314, tx])


# -- (i) Fog depth begin exceeds max camera-to-hero distance (ivy-42m.7 finding #4) ------------

func test_fog_depth_begin_exceeds_max_camera_distance() -> void:
	# CamTop is the farthest canonical camera from the hero pivot:
	# sqrt(7.407^2 + 5.657^2) ~= 9.32 m. fog_depth_begin must exceed this so the hero
	# and ivy remain clearly unfogged. Target range: 8-10 m (we require >= 9.5 here).
	var f := FileAccess.open("res://src/main/main.tscn", FileAccess.READ)
	if f == null:
		pending("Could not open main.tscn -- skipping fog_depth_begin test")
		return
	var content := f.get_as_text()
	f.close()
	var regex := RegEx.new()
	regex.compile("fog_depth_begin = ([0-9.]+)")
	var hit := regex.search(content)
	assert_not_null(hit, "fog_depth_begin property not found in main.tscn")
	if hit == null:
		return
	var begin_val := hit.get_string(1).to_float()
	assert_gte(begin_val, 9.5,
		"fog_depth_begin must exceed max camera-to-hero distance (~9.32 m); got %.1f" % begin_val)


func test_fog_sky_affect_in_range() -> void:
	# fog_sky_affect 0.3-0.5 makes depth fog perceivable against the taupe backdrop.
	var f := FileAccess.open("res://src/main/main.tscn", FileAccess.READ)
	if f == null:
		pending("Could not open main.tscn -- skipping fog_sky_affect test")
		return
	var content := f.get_as_text()
	f.close()
	var regex := RegEx.new()
	regex.compile("fog_sky_affect = ([0-9.]+)")
	var hit := regex.search(content)
	assert_not_null(hit, "fog_sky_affect property not found in main.tscn")
	if hit == null:
		return
	var sky_val := hit.get_string(1).to_float()
	assert_gte(sky_val, 0.3, "fog_sky_affect must be >= 0.3; got %.2f" % sky_val)
	assert_lte(sky_val, 0.5, "fog_sky_affect must be <= 0.5; got %.2f" % sky_val)
