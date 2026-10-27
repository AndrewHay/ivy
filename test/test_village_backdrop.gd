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


func test_grass_wispy_accent_uses_grass_accent_shader() -> void:
	var found := false
	for child in _backdrop.get_children():
		if child.name != "Scatter_Grass_Accent" or not child is MultiMeshInstance3D:
			continue
		found = true
		var mmi := child as MultiMeshInstance3D
		assert_not_null(mmi.material_override, "Grass accent scatter must use material_override")
		var mat := mmi.material_override as ShaderMaterial
		assert_not_null(mat, "Grass accent material must be ShaderMaterial")
		if mat == null:
			return
		var sh: Shader = mat.shader
		assert_not_null(sh, "Grass accent shader must be set")
		if sh != null:
			assert_true(
				sh.resource_path.ends_with("grass_accent.gdshader"),
				"Expected grass_accent.gdshader, got %s" % sh.resource_path)
		assert_gte(mmi.multimesh.instance_count, 1, "Grass accent scatter must have instances")
		return
	assert_true(found, "Scatter_Grass_Accent MultiMeshInstance3D must exist after _ready")


func test_main_tscn_world_ground_is_external_shader() -> void:
	var f := FileAccess.open("res://src/main/main.tscn", FileAccess.READ)
	if f == null:
		pending("Could not open main.tscn")
		return
	var text := f.get_as_text()
	f.close()
	assert_true(
		text.contains("world_ground.gdshader"),
		"main.tscn World/Ground must reference world_ground.gdshader")
	assert_false(
		text.contains("Shader_grass"),
		"main.tscn must not keep inline Shader_grass sub_resource")


# ── (d) Triangle and draw call budget — slices 1-3 merged (ivy-3cx.7) ───────
## Slices 1-3 merged cap: tri < 120000, surface <= 160 (ivy-3cx.2 §5 full-village cap).

func test_triangle_budget_under_120k() -> void:
	## Counts MeshInstance3D tris + MultiMesh tris (mesh counted once per MultiMesh, not ×instance_count).
	## Instanced grass (Scatter_Grass_Blades_*) is budgeted separately in test_grass_instanced_triangle_budget.
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


const GRASS_TRIS_PER_TUFT := 35
const GRASS_INSTANCED_TRI_CAP := VillageScatterPositions.GRASS_MAX_INSTANCES * GRASS_TRIS_PER_TUFT


func test_grass_instanced_triangle_budget() -> void:
	## GPU cost: mesh triangle count × MultiMesh.instance_count for blade lawn chunks.
	var instanced_tris := 0
	for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
		var mmi := mmi_node as MultiMeshInstance3D
		if mmi.name.begins_with("Scatter_Grass_Blades_") == false:
			continue
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		var mesh_tris := 0
		for s in range(mmi.multimesh.mesh.get_surface_count()):
			var arrays := mmi.multimesh.mesh.surface_get_arrays(s)
			if arrays != null and arrays[Mesh.ARRAY_INDEX] != null:
				mesh_tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif arrays != null and arrays[Mesh.ARRAY_VERTEX] != null:
				mesh_tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		instanced_tris += mesh_tris * mmi.multimesh.instance_count
	print("Grass instanced triangle count: %d (cap %d)" % [instanced_tris, GRASS_INSTANCED_TRI_CAP])
	assert_lte(
		instanced_tris, GRASS_INSTANCED_TRI_CAP,
		"Grass instanced tris must be <= GRASS_MAX × 35; got %d" % instanced_tris)


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

func test_each_cottage_roof_fits_its_body() -> void:
	## The roof piece chosen for each cottage must overhang the wall exteriors by
	## the kit's eave (~0.7 m, allowed 0.3-0.8 m) on every side — no giant roofs
	## on thin bodies.
	for spec in VillageBackdrop.COTTAGES:
		var bays := int(spec["bays"])
		assert_true(VillageBackdrop._P_ROOF.has(bays),
			"Cottage '%s' has no roof piece for %d bays" % [spec["name"], bays])
		if not VillageBackdrop._P_ROOF.has(bays):
			continue
		var roof := _piece_aabb(VillageBackdrop._P_ROOF[bays])
		# Native roof ridge runs along local Z; the house ridge runs along local X.
		var half_len := float(bays) + VillageBackdrop.WALL_OUT
		var half_depth := VillageBackdrop.COTTAGE_DEPTH * 0.5 + VillageBackdrop.WALL_OUT
		var eaves := [
			-roof.position.x - half_depth, roof.end.x - half_depth,
			-roof.position.z - half_len, roof.end.z - half_len]
		for eave in eaves:
			assert_between(float(eave), 0.3, 0.8,
				"Cottage '%s' roof %s eave %.2f m must be 0.3-0.8 m" \
				% [spec["name"], VillageBackdrop._P_ROOF[bays], eave])
		assert_lte(roof.position.y, 0.0,
			"Cottage '%s' roof eaves must not float above the wall top" % spec["name"])


func test_each_cottage_piece_type_renders() -> void:
	var expected := ["Wall_Plaster_Straight", "Wall_Plaster_Door_Flat", "Door_1_Flat",
		"Wall_Plaster_Window_Wide_Flat", "WindowShutters_Wide_Flat_Closed",
		"Roof_Front_Brick4", "Roof_RoundTiles_4x6", "Roof_RoundTiles_4x8", "Prop_Chimney2"]
	for piece in expected:
		var found := false
		for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
			var mmi := mmi_node as MultiMeshInstance3D
			if mmi.name.begins_with("Cottage_" + piece) and mmi.multimesh.instance_count > 0:
				found = true
				break
		assert_true(found, "Expected a Cottage_%s MultiMesh with instances" % piece)


# ── Cottage aspect ratio (ivy-2or) ───────────────────────────────────────────

func test_cottages_are_two_bays_deep_and_long() -> void:
	## Owner: "the houses are very narrow". Two bays deep (4 m grid) and at least
	## 3 bays long, so no cottage reads as a thin shed from its gable end.
	assert_eq(VillageBackdrop.COTTAGE_DEPTH, 4.0, "Cottages must be two 2 m bays deep")
	for spec in VillageBackdrop.COTTAGES:
		var rect := VillageBackdrop.cottage_exterior_rect(spec)
		var length: float = maxf(rect.size.x, rect.size.y)
		var depth: float = minf(rect.size.x, rect.size.y)
		assert_gte(int(spec["bays"]), 3, "Cottage '%s' must be >= 3 bays long" % spec["name"])
		assert_gte(length / depth, 1.4,
			"Cottage '%s' footprint %.1f x %.1f m must be clearly longer than deep" \
			% [spec["name"], length, depth])


func test_cottages_do_not_overlap() -> void:
	## Footprints grown by the ~0.7 m eave must stay apart.
	var specs: Array = VillageBackdrop.COTTAGES
	for i in range(specs.size()):
		for j in range(i + 1, specs.size()):
			var a := VillageBackdrop.cottage_exterior_rect(specs[i]).grow(0.8)
			var b := VillageBackdrop.cottage_exterior_rect(specs[j]).grow(0.8)
			assert_false(a.intersects(b),
				"Cottages '%s' and '%s' overlap (incl. eaves)" % [specs[i]["name"], specs[j]["name"]])


func test_each_door_faces_hero_and_has_path() -> void:
	var paths := VillageBackdrop.path_polylines()
	assert_eq(paths.size(), VillageBackdrop.COTTAGES.size(), "One path per cottage door")
	for i in range(VillageBackdrop.COTTAGES.size()):
		var spec: Dictionary = VillageBackdrop.COTTAGES[i]
		var door := VillageBackdrop.cottage_door(spec)
		var to_hero: Vector2 = (-door[0]).normalized()
		assert_gt(door[1].dot(to_hero), 0.5,
			"Cottage '%s' door must face the hero area" % spec["name"])
		var start: Vector2 = (paths[i] as Array)[0]
		assert_lt(start.distance_to(door[0]), 1.0,
			"Cottage '%s' path must start at its door" % spec["name"])


func test_door_leaves_face_out_of_their_doors() -> void:
	## Regression: MultiMesh buffers are row-major. Writing basis vectors
	## contiguously transposed every instance rotation, turning ±90° walls inside
	## out. Decode each door leaf's +Z (kit exterior) axis from the buffer.
	var leaves: MultiMeshInstance3D = null
	for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
		if (mmi_node as Node).name.begins_with("Cottage_Door_1_Flat"):
			leaves = mmi_node
			break
	assert_not_null(leaves, "Cottage_Door_1_Flat MultiMesh must exist")
	if leaves == null:
		return
	var buf := leaves.multimesh.buffer
	var normals: Array[Vector2] = []
	for i in range(leaves.multimesh.instance_count):
		normals.append(Vector2(buf[i * 12 + 2], buf[i * 12 + 10]).normalized())
	for spec in VillageBackdrop.COTTAGES:
		var door := VillageBackdrop.cottage_door(spec)
		var matched := false
		for n in normals:
			if n.dot(door[1]) > 0.99:
				matched = true
				break
		assert_true(matched,
			"Cottage '%s' door leaf must face outward along %s" % [spec["name"], door[1]])


func test_no_path_or_bush_inside_a_cottage() -> void:
	for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
		var mmi := mmi_node as MultiMeshInstance3D
		if not (mmi.name.begins_with("Scatter_Path_") or mmi.name.begins_with("Scatter_Bush_")):
			continue
		var buf := mmi.multimesh.buffer
		for i in range(mmi.multimesh.instance_count):
			var p := Vector2(buf[i * 12 + 3], buf[i * 12 + 11])
			assert_false(VillageBackdrop.inside_any_cottage(p, 0.0),
				"%s[%d] at (%.2f, %.2f) is inside a cottage" % [mmi.name, i, p.x, p.y])


# ── Path stone count (ivy-2or) ────────────────────────────────────────────────

func test_path_stone_count_gte_30() -> void:
	## Scatter_Path_* MultiMesh nodes must have >= 30 total instances.
	var total_stones := 0
	for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
		var mmi := mmi_node as MultiMeshInstance3D
		if mmi.name.begins_with("Scatter_Path_") and mmi.multimesh != null:
			total_stones += mmi.multimesh.instance_count
	assert_gte(total_stones, 30,
		"Village paths must have >= 30 path-stone instances; got %d" % total_stones)


# ── Bush count (ivy-2or) ──────────────────────────────────────────────────────

func test_bush_count_gte_40() -> void:
	## Scatter_Bush_Common MultiMesh must have >= 40 instances (many more bushes).
	## Together with static Garden_Bush1/2 and the Scatter_Flower ring,
	## this ensures plentiful bush coverage visible in orbit shots.
	var total_bush := 0
	for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
		var mmi := mmi_node as MultiMeshInstance3D
		if mmi.name == "Scatter_Bush_Common" and mmi.multimesh != null:
			total_bush += mmi.multimesh.instance_count
	assert_gte(total_bush, 40,
		"Scatter_Bush_Common must have >= 40 instances; got %d" % total_bush)


# ── No path or bush on hero footprint (ivy-2or) ───────────────────────────────

func test_no_path_or_bush_on_hero_footprint() -> void:
	## No Scatter_Path_* or Scatter_Bush_* instance may lie within 4.5 m of the
	## backdrop pivot (hero base). Paths end at r ≥ 5 m; bushes are seeded > 5 m.
	const EXCLUSION_R := 4.5
	for mmi_node in _find_nodes_of_type(_backdrop, MultiMeshInstance3D):
		var mmi := mmi_node as MultiMeshInstance3D
		if not (mmi.name.begins_with("Scatter_Path_") or mmi.name.begins_with("Scatter_Bush_")):
			continue
		if mmi.multimesh == null:
			continue
		# NOTE: MultiMesh.get_instance_transform() reads from RenderingServer GPU-side
		# buffer and returns identity in --headless mode. Read directly from the
		# CPU-side buffer (set via mm.buffer = buf in _create_scatter): each
		# TRANSFORM_3D instance is 12 floats, origin at offsets [3], [7], [11].
		var buf := mmi.multimesh.buffer
		if buf.size() == 0:
			continue
		var stride := 12  # TRANSFORM_3D, no use_colors, no use_custom_data
		for i in range(mmi.multimesh.instance_count):
			var base := i * stride
			var ox: float = buf[base + 3]
			var oz: float = buf[base + 11]
			var xz_dist := Vector2(ox, oz).length()
			assert_gt(xz_dist, EXCLUSION_R,
				"%s[%d] at XZ(%.2f,%.2f) dist %.2f is inside hero exclusion %.1f m" \
				% [mmi.name, i, ox, oz, xz_dist, EXCLUSION_R])


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

	# (14, -8) lies inside cottage CA's footprint.
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
	## Every cottage, including its ~0.7 m eave, must stay >= 5.9 m from the
	## pivot in XZ. Garden scatter (flowers, clover, path stones, bushes, rocks)
	## is intentionally placed in the near zone and is exempt.
	for spec in VillageBackdrop.COTTAGES:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(0.8)
		var aabb := AABB(Vector3(rect.position.x, 0.0, rect.position.y),
			Vector3(rect.size.x, 1.0, rect.size.y))
		var min_xz_dist := _nearest_xz_dist_from_origin(aabb)
		assert_gte(min_xz_dist, 5.9,
			"Cottage '%s' nearest XZ face (%.3f m) must be >= 5.9 m from pivot" % [spec["name"], min_xz_dist])


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


# ── (k) glTF pieces have valid texture URI paths (Defect F) ──────────────────

func test_gltf_pieces_have_valid_texture_uris() -> void:
	## Every .gltf under assets/backdrop/pieces/ must reference textures via
	## "../textures/<filename>" and every referenced texture file must exist.
	var pieces_dir_path := "res://assets/backdrop/pieces"
	var textures_dir_path := "res://assets/backdrop/textures"
	var d := DirAccess.open(pieces_dir_path)
	if d == null:
		pending("Could not open res://assets/backdrop/pieces — skipping URI test")
		return
	var gltf_files: Array[String] = []
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname.ends_with(".gltf"):
			gltf_files.append(pieces_dir_path + "/" + fname)
		fname = d.get_next()
	d.list_dir_end()

	assert_true(gltf_files.size() > 0, "No .gltf files found under assets/backdrop/pieces/")

	for gltf_path in gltf_files:
		var f := FileAccess.open(gltf_path, FileAccess.READ)
		if f == null:
			assert_true(false, "Could not open %s" % gltf_path)
			continue
		var json_text := f.get_as_text()
		f.close()
		var json := JSON.new()
		var err := json.parse(json_text)
		if err != OK:
			assert_true(false, "Failed to parse JSON in %s" % gltf_path)
			continue
		var data: Variant = json.get_data()
		if not (data is Dictionary and data.has("images")):
			continue  # no images section — fine
		var images: Array = data["images"]
		for img_entry in images:
			if not (img_entry is Dictionary and img_entry.has("uri")):
				continue
			var uri: String = img_entry["uri"]
			assert_true(uri.begins_with("../textures/"),
				"glTF image URI '%s' in %s must start with '../textures/'" % [uri, gltf_path.get_file()])
			# Verify the referenced texture file exists.
			var tex_filename := uri.get_file()
			var tex_path := textures_dir_path + "/" + tex_filename
			var tex_f := FileAccess.open(tex_path, FileAccess.READ)
			assert_not_null(tex_f,
				"Texture '%s' referenced in %s does not exist at %s" % [tex_filename, gltf_path.get_file(), tex_path])
			if tex_f != null:
				tex_f.close()


# ── Helpers ───────────────────────────────────────────────────────────────────

## Piece-space AABB of a backdrop kit piece, with glTF node transforms applied.
func _piece_aabb(piece: String) -> AABB:
	var ps := load("res://assets/backdrop/pieces/%s.gltf" % piece) as PackedScene
	var inst := ps.instantiate()
	var parts: Array = []
	_backdrop._collect_mesh_parts(inst, Transform3D.IDENTITY, parts)
	inst.free()
	var out: AABB = (parts[0][1] as Transform3D) * (parts[0][0] as Mesh).get_aabb()
	for k in range(1, parts.size()):
		out = out.merge((parts[k][1] as Transform3D) * (parts[k][0] as Mesh).get_aabb())
	return out


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
