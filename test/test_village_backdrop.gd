## Tests for VillageBackdrop scene and contract invariants.
##
## Acceptance criteria (ivy-3cx slice 1):
##  (a) no StaticBody3D/CollisionObject3D descendants
##  (b) no descendant on collision layer bit 1
##  (c) after _ready all MeshInstance3D have NATIVE materials (no mute override) + distance shadow policy
##  (d) surface/draw estimate <= 160; tri count < 120000 (slices 1-3 merged full-village cap — ivy-3cx.2 §5)
##  (e) no vine piece names present
##  (f) VillageBackdrop is NOT referenced by BuildingCatalog
##  (g) planting-raycast: mask-1 ray at a backdrop mesh returns no hit (unplantable)
##  (h) no house wall face closer than 5.9 m from the pivot column in XZ
##  (i) fog depth begin >= 9.5 m
##  (j) fog sky affect in [0.3, 0.5]
extends GutTest

const VillageBackdropScene = preload("res://src/world/village_backdrop.tscn")
const MuteMaterial = preload("res://assets/backdrop/backdrop_mute.tres")
const BuildingCatalog = preload("res://src/world/building_catalog.gd")

## XZ distance threshold: all slice-1 cottages >= 12 m from pivot, wall shadow=ON; any piece
## < 8 m from pivot gets shadow=OFF. Test verifies the policy is correct for all pieces.
const _SHADOW_NEAR_THRESHOLD := 8.0

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


# ── (c) Native materials + shadow distance policy after _ready ────────────────

func test_all_meshes_have_native_material() -> void:
	## Every MeshInstance3D must:
	##   - resolve a non-null active material on surface 0
	##   - NOT have material_override == backdrop_mute.tres
	## Native glTF materials live on the mesh surfaces, not as overrides.
	var meshes := _find_nodes_of_type(_backdrop, MeshInstance3D)
	assert_gt(meshes.size(), 0, "Backdrop must have at least one MeshInstance3D")
	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		assert_ne(mi.material_override, MuteMaterial,
			"MeshInstance3D '%s' must NOT have backdrop_mute.tres as material_override" % mi.name)
		var mat: Material = null
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.get_active_material(0)
		assert_not_null(mat,
			"MeshInstance3D '%s' must resolve a non-null active material on surface 0" % mi.name)


func test_backdrop_shadow_policy() -> void:
	## Shadow distance policy: pieces < 8 m from backdrop origin in XZ → cast_shadow OFF
	## Pieces >= 8 m → native value unconstrained (ON allowed; all slice-1 cottages are >= 12 m).
	var meshes := _find_nodes_of_type(_backdrop, MeshInstance3D)
	assert_gt(meshes.size(), 0, "Backdrop must have at least one MeshInstance3D")
	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		var pos := (mi as Node3D).global_position
		var xz_dist := Vector2(pos.x, pos.z).length()
		if xz_dist < _SHADOW_NEAR_THRESHOLD:
			assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"MeshInstance3D '%s' at XZ dist %.2f m (<8 m) must have cast_shadow=OFF" % [mi.name, xz_dist])
		# >= 8 m: unconstrained (no assertion — ON is allowed for background cottages)
	## MultiMesh scatter nodes (Scatter_*) must always cast_shadow=OFF (near-ring dressing).
	for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
		var mmi := mmi_node as MultiMeshInstance3D
		if mmi.name.begins_with("Scatter_"):
			assert_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"Scatter MultiMesh '%s' must have cast_shadow=OFF" % mmi.name)


# ── FarTreeline leaf material threshold (ivy-3cx.8) ──────────────────────────

func test_far_treeline_leaf_alpha_threshold_low() -> void:
	## Regression: FarTreeline MultiMesh Leaves_Pine surface (index 1) must have
	## alpha_scissor_threshold <= 0.15.  Without this patch, glTF default 0.2 combined
	## with absent mipmaps causes leaf coverage to drop at r=19-28 m, exposing bare trunks.
	for child in _backdrop.get_children():
		if child.name == "FarTreeline" and child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			assert_not_null(mmi.multimesh, "FarTreeline must have a multimesh")
			if mmi.multimesh == null:
				return
			assert_not_null(mmi.multimesh.mesh, "FarTreeline multimesh must have a mesh")
			if mmi.multimesh.mesh == null:
				return
			var mesh := mmi.multimesh.mesh
			assert_gte(mesh.get_surface_count(), 2,
				"Pine_2 mesh must have >= 2 surfaces (Bark + Leaves)")
			if mesh.get_surface_count() < 2:
				return
			var mat := mesh.surface_get_material(1) as StandardMaterial3D
			assert_not_null(mat,
				"FarTreeline leaf surface (index 1) must be a StandardMaterial3D after _ready")
			if mat != null:
				assert_lte(mat.alpha_scissor_threshold, 0.15,
					"FarTreeline leaf material alpha_scissor_threshold must be <= 0.15 to preserve " + \
					"coverage at distance; got %.3f" % mat.alpha_scissor_threshold)
			return
	fail_test("FarTreeline MultiMeshInstance3D not found in VillageBackdrop")


# ── (d) Triangle and draw call budget — slices 1-3 merged (ivy-3cx.7) ───────
## Slices 1-3 merged cap: tri < 120000, surface <= 160 (ivy-3cx.2 §5 full-village cap).

func test_triangle_budget_under_120k() -> void:
	## Counts MeshInstance3D tris + MultiMesh tris (mesh counted once, not ×instance_count).
	## GPU instancing: MultiMesh costs 1 draw per surface, not N draws.
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
	## MultiMesh: count mesh once (instancing = 1 draw per surface, not instance_count draws).
	for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
		var mmi := mmi_node as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		for s in range(mmi.multimesh.mesh.get_surface_count()):
			var arrays := mmi.multimesh.mesh.surface_get_arrays(s)
			if arrays != null and arrays[Mesh.ARRAY_INDEX] != null:
				total_tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif arrays != null and arrays[Mesh.ARRAY_VERTEX] != null:
				total_tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	assert_lt(total_tris, 120000,
		"Total tris (MI3D + MultiMesh once) must be < 120k; got %d" % total_tris)


func test_surface_count_under_160() -> void:
	## Counts MeshInstance3D surfaces + MultiMesh surfaces (1 draw per surface regardless of instances).
	var total_surfaces := 0
	for mesh in _find_nodes_of_type(_backdrop, MeshInstance3D):
		var mi := mesh as MeshInstance3D
		if mi.mesh != null:
			total_surfaces += mi.mesh.get_surface_count()
	## MultiMesh: each surface in the mesh costs exactly 1 draw call.
	for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
		var mmi := mmi_node as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			total_surfaces += mmi.multimesh.mesh.get_surface_count()
	assert_lte(total_surfaces, 160,
		"Surface/draw count (MI3D + MultiMesh surfaces) must be <= 160; got %d" % total_surfaces)


# ── Covering-roof invariant ───────────────────────────────────────────────────

func test_each_cottage_has_covering_roof() -> void:
	## Every cottage (CA-CG) must contain at least one roof MeshInstance3D whose
	## local AABB spans > 1.5 m in BOTH X and Z (a covering tile surface, not just
	## a thin gable-end triangle like Roof_Front_Brick4).
	var cottage_prefixes := ["CA_", "CB_", "CC_", "CD_", "CE_", "CF_", "CG_"]
	var meshes := _find_nodes_of_type(_backdrop, MeshInstance3D)
	for prefix in cottage_prefixes:
		var has_covering := false
		for mesh in meshes:
			var mi := mesh as MeshInstance3D
			if mi.mesh == null:
				continue
			var root := _get_direct_child_of_backdrop(mi)
			if root == null:
				continue
			# Only look at nodes whose backdrop-root has a Roof suffix
			if not root.name.begins_with(prefix) or not "Roof" in root.name:
				continue
			var aabb := mi.get_aabb()
			if aabb.size.x > 1.5 and aabb.size.z > 1.5:
				has_covering = true
				break
		assert_true(has_covering,
			"Cottage '%s' must have a covering roof with AABB XZ both > 1.5 m (not just gable-end)" \
			% prefix.rstrip("_"))


# ── (e) No vine piece names ───────────────────────────────────────────────────

func test_no_vine_piece_names() -> void:
	var vine_patterns := ["Vine1", "Vine2", "Vine4", "Vine5", "Vine6", "Vine9", "VineLeaf"]
	_check_no_vine_names(_backdrop, vine_patterns)


# ── (f) Not in BuildingCatalog ───────────────────────────────────────────────

func test_not_in_building_catalog() -> void:
	# BuildingCatalog.all() must not contain any backdrop-related entry.
	for entry in BuildingCatalog.all():
		assert_ne(entry.id.to_lower(), "village_backdrop",
			"VillageBackdrop must NOT be in BuildingCatalog")
		assert_false(entry.id.to_lower().begins_with("backdrop"),
			"No backdrop id may appear in BuildingCatalog; found '%s'" % entry.id)


# ── (g) Planting-raycast: mask-1 ray returns no hit ──────────────────────────

func test_backdrop_mesh_unplantable_via_mask1_ray() -> void:
	# Planting uses collision_mask=1 (SurfaceQuery).  MeshInstance3D nodes carry no
	# PhysicsBody3D / CollisionShape3D, so they are invisible to physics queries.
	# Verify by firing a ray into the backdrop from above at a known cottage position.
	# Cottage A is centered at approx (9, 0, -9) in local space.
	var space: PhysicsDirectSpaceState3D = _backdrop.get_world_3d().direct_space_state
	if space == null:
		pending("physics space not available in this test environment — skip")
		return

	# Cottage CA is centered at approx (14, 0, -8) in local space.
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(14.0, 10.0, -8.0),
		Vector3(14.0, -1.0, -8.0),
		1  # mask bit 1 — the planting layer
	)
	var result: Dictionary = space.intersect_ray(ray)
	assert_true(result.is_empty(),
		"Mask-1 ray into backdrop cottage position must return no hit (backdrop is unplantable); got: %s" % result)


# ── (h) No cottage face inside 5.9 m from pivot ──────────────────────────────

func test_no_house_face_inside_6m() -> void:
	## All cottages are centred at >= 12 m radius; their wall/roof AABB nearest
	## face must be >= 5.9 m from the backdrop pivot in XZ.
	## Garden scatter (flowers, clover, path stones, bushes, rocks) is intentionally
	## placed in the near zone and is exempt from this check.
	## Only instances whose direct parent under VillageBackdrop has a cottage prefix
	## (CA_, CB_, CC_, CD_, CE_, CF_, CG_) are checked.
	var cottage_prefixes := ["CA_", "CB_", "CC_", "CD_", "CE_", "CF_", "CG_"]
	var meshes := _find_nodes_of_type(_backdrop, MeshInstance3D)
	assert_gt(meshes.size(), 0, "Backdrop must have at least one MeshInstance3D")
	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		var instance_root := _get_direct_child_of_backdrop(mi)
		if instance_root == null:
			continue
		var is_cottage := false
		for prefix in cottage_prefixes:
			if instance_root.name.begins_with(prefix):
				is_cottage = true
				break
		if not is_cottage:
			continue
		var aabb := mi.get_aabb()
		var global_aabb := mi.global_transform * aabb
		var min_xz_dist := _nearest_xz_dist_from_origin(global_aabb)
		assert_gte(min_xz_dist, 5.9,
			"Cottage piece in '%s' nearest XZ face (%.3f m) must be >= 5.9 m from pivot" % [instance_root.name, min_xz_dist])


# ── (i) Fog depth begin >= 9.5 ───────────────────────────────────────────────

func test_fog_depth_begin_exceeds_max_camera_distance() -> void:
	# CamTop is the farthest canonical camera from the hero pivot:
	# sqrt(7.407^2 + 5.657^2) ~= 9.32 m. fog_depth_begin must exceed this.
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


# ── (j) Fog sky affect in [0.3, 0.5] ─────────────────────────────────────────

func test_fog_sky_affect_in_range() -> void:
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


# ── Helpers ───────────────────────────────────────────────────────────────────

## Walk up from node until we reach a direct child of _backdrop, then return that child.
func _get_direct_child_of_backdrop(node: Node) -> Node:
	var current: Node = node
	while current != null and current.get_parent() != _backdrop:
		current = current.get_parent()
	return current


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


func _nearest_xz_dist_from_origin(aabb: AABB) -> float:
	## Returns the shortest XZ distance from the world origin to the AABB rectangle.
	var min_x := aabb.position.x
	var max_x := aabb.position.x + aabb.size.x
	var min_z := aabb.position.z
	var max_z := aabb.position.z + aabb.size.z
	# Nearest point on rectangle to origin in XZ
	var nx := clampf(0.0, min_x, max_x)
	var nz := clampf(0.0, min_z, max_z)
	return sqrt(nx * nx + nz * nz)
