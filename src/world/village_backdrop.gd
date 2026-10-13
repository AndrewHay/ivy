## VillageBackdrop — non-interactive environment dressing around the playable structure.
##
## Repositioned by World._activate_mesh_scenario() to (pivot.x, 0, pivot.z).
## Hidden on the procedural path and in _teardown_active_building().
## All MeshInstance3D descendants render with their native glTF PBR materials.
##
## Shadow policy:
##   - Static .tscn pieces: < 8 m from backdrop origin in XZ → cast_shadow=OFF (near-hero dressing);
##     ≥ 8 m retain native ON so background cottages cast cosy soft shadows.
##   - MultiMesh scatter near ring (Scatter_*): always cast_shadow=OFF.
##   - MultiMesh far treeline (FarTreeline): cast_shadow=ON.
##   - HillRing: cast_shadow=OFF (ground-level, minimal shadow contribution).
##
## No collision, no layer 1, never referenced by BuildingCatalog or SurfaceQuery.
class_name VillageBackdrop
extends Node3D

## XZ distance threshold for shadow culling.
const _SHADOW_NEAR_M := 8.0


func _ready() -> void:
	_apply_subtree(self)
	_setup_multimesh_scatter()
	_add_hill_ring()


func _apply_subtree(node: Node) -> void:
	if node is CollisionObject3D:
		push_error("VillageBackdrop: unexpected collision node '%s' — backdrop must be collision-free" % node.name)
		if (node as CollisionObject3D).get_collision_layer() & 1:
			push_error("VillageBackdrop: node '%s' is on collision layer bit 1" % node.name)
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		# Apply distance-based shadow policy:
		# pieces < 8 m from pivot get shadow OFF; farther pieces cast shadows.
		var pos := mesh_node.global_position
		var xz_dist := Vector2(pos.x, pos.z).length()
		if xz_dist < _SHADOW_NEAR_M:
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# >= _SHADOW_NEAR_M: leave native setting (ON) so cottages cast cosy shadows.
	for child in node.get_children():
		_apply_subtree(child)


# ── MultiMesh scatter setup ───────────────────────────────────────────────────

## Procedural scatter: grass tufts, flower clusters, clover patches (near ring),
## and a dense far pine treeline (horizon fill).
## Each MultiMesh draws all its instances in ONE draw call per mesh surface.
func _setup_multimesh_scatter() -> void:
	_create_scatter(
		"res://assets/backdrop/pieces/Grass_Wispy_Short.gltf",
		"Scatter_Grass", _grass_positions(),
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_create_scatter(
		"res://assets/backdrop/pieces/Flower_3_Group.gltf",
		"Scatter_Flower", _flower_positions(),
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_create_scatter(
		"res://assets/backdrop/pieces/Clover_1.gltf",
		"Scatter_Clover", _clover_positions(),
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_create_scatter(
		"res://assets/backdrop/pieces/Pine_2.gltf",
		"FarTreeline", _pine_positions(),
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_patch_far_treeline_leaf_threshold()


func _create_scatter(
		path: String, node_name: String,
		transforms: Array[Transform3D],
		shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	var mesh := _extract_first_mesh(path)
	if mesh == null or transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = shadow
	add_child(mmi)


func _extract_first_mesh(path: String) -> Mesh:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var meshes: Array = []
	_collect_mesh_nodes(inst, meshes)
	var result: Mesh = null
	if not meshes.is_empty():
		result = (meshes[0] as MeshInstance3D).mesh
	inst.queue_free()
	return result


func _collect_mesh_nodes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_nodes(child, out)


## Lower the Leaves_Pine alpha-scissor threshold on FarTreeline from the glTF
## default (0.2) to 0.1 so leaf card coverage is preserved at r=19-28 m.
## The mesh resource is duplicated before modification to avoid mutating the
## shared glTF import resource.
func _patch_far_treeline_leaf_threshold() -> void:
	for child in get_children():
		if child.name != "FarTreeline" or not child is MultiMeshInstance3D:
			continue
		var mmi := child as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			return
		var orig_mesh: Mesh = mmi.multimesh.mesh
		# Surface 0 = Bark_NormalTree, surface 1 = Leaves_Pine (glTF primitive order for Pine_2).
		if orig_mesh.get_surface_count() < 2:
			return
		var leaf_mat := orig_mesh.surface_get_material(1)
		if leaf_mat == null:
			return
		var new_mat := leaf_mat.duplicate() as StandardMaterial3D
		if new_mat == null:
			return
		new_mat.alpha_scissor_threshold = 0.1
		# Duplicate the mesh so the original glTF resource is not mutated.
		var new_mesh: Mesh = orig_mesh.duplicate() as Mesh
		if new_mesh == null:
			return
		new_mesh.surface_set_material(1, new_mat)
		mmi.multimesh.mesh = new_mesh
		return


# ── Deterministic scatter positions (seeded LCG) ─────────────────────────────
#
# LCG: state = (state * 1664525 + 1013904223) & 0x7FFFFFFF  (Knuth §3.6)
# Seeds are unique per scatter type; layout is identical every run.
# _lcg_step() advances the state; _lcg_f01() converts to [0, 1) float.

func _lcg_step(state: int) -> int:
	return (state * 1664525 + 1013904223) & 0x7FFFFFFF


func _lcg_f01(state: int) -> float:
	return float(state & 0x7FFFFFFF) / float(0x7FFFFFFF)


## 30 grass tufts scattered in the near-mid ring (r=6.5-15 m).
## Grass_Wispy_Short: 1.07 m at scale=1.0 → scale 0.18-0.24 → ~0.19-0.26 m height.
func _grass_positions() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := 42
	for _i in range(30):
		st = _lcg_step(st); var angle: float = _lcg_f01(st) * TAU
		st = _lcg_step(st); var r: float = lerpf(6.5, 15.0, _lcg_f01(st))
		st = _lcg_step(st); var s: float = lerpf(0.18, 0.24, _lcg_f01(st))
		st = _lcg_step(st); var rot: float = _lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(cos(angle) * r, 0.0, sin(angle) * r)))
	return out


## 16 flower clusters in the near garden ring (r=5.5-12 m).
## Flower_3_Group: 2.05 m at scale=1.0 → scale 0.18-0.22 → ~0.37-0.45 m height (knee-high).
func _flower_positions() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := 137
	for _i in range(16):
		st = _lcg_step(st); var angle: float = _lcg_f01(st) * TAU
		st = _lcg_step(st); var r: float = lerpf(5.5, 12.0, _lcg_f01(st))
		st = _lcg_step(st); var s: float = lerpf(0.18, 0.22, _lcg_f01(st))
		st = _lcg_step(st); var rot: float = _lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(cos(angle) * r, 0.0, sin(angle) * r)))
	return out


## 20 clover patches in the near-mid ring (r=5.0-14 m).
## Clover_1: 1.14 m at scale=1.0 → scale 0.12-0.16 → ~0.14-0.18 m height (ground cover).
func _clover_positions() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := 99
	for _i in range(20):
		st = _lcg_step(st); var angle: float = _lcg_f01(st) * TAU
		st = _lcg_step(st); var r: float = lerpf(5.0, 14.0, _lcg_f01(st))
		st = _lcg_step(st); var s: float = lerpf(0.12, 0.16, _lcg_f01(st))
		st = _lcg_step(st); var rot: float = _lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(cos(angle) * r, 0.0, sin(angle) * r)))
	return out


## 22 pines evenly spaced around the horizon ring (r=19-28 m), with per-tree jitter.
## Pine_2: 7.14 m at scale=1.0 → scale 1.0-1.5 → ~7.1-10.7 m height.
## Crown starts at y=1.12 m (scale=1.0), so foliage covers most of the visible trunk.
func _pine_positions() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var n := 22
	var st := 7
	for i in range(n):
		st = _lcg_step(st); var angle_jitter: float = (_lcg_f01(st) - 0.5) * 0.5
		var angle: float = (float(i) / n) * TAU + angle_jitter
		st = _lcg_step(st); var r: float = lerpf(19.0, 28.0, _lcg_f01(st))
		st = _lcg_step(st); var s: float = lerpf(1.0, 1.5, _lcg_f01(st))
		st = _lcg_step(st); var rot: float = _lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(cos(angle) * r, 0.0, sin(angle) * r)))
	return out


# ── Horizon hill ring ─────────────────────────────────────────────────────────

## Visual-only raised ground ring at r=22-34 m that lifts the horizon above a flat line.
## Terrain transitions from y=0 (inner) to y=1.5 m (outer), hiding the sky-ground seam.
## No CollisionShape3D, no physics body, no collision layer.
func _add_hill_ring() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner_r := 22.0
	var outer_r := 34.0
	var hill_h := 1.5
	var segs := 48
	for i in range(segs):
		var a0 := (float(i) / segs) * TAU
		var a1 := (float(i + 1) / segs) * TAU
		var v0 := Vector3(cos(a0) * inner_r, 0.0, sin(a0) * inner_r)
		var v1 := Vector3(cos(a1) * inner_r, 0.0, sin(a1) * inner_r)
		var v2 := Vector3(cos(a0) * outer_r, hill_h, sin(a0) * outer_r)
		var v3 := Vector3(cos(a1) * outer_r, hill_h, sin(a1) * outer_r)
		st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v1)
		st.add_vertex(v1); st.add_vertex(v2); st.add_vertex(v3)
	st.generate_normals()
	var mesh := st.commit()
	# Sage-green ground colour to match the lawn; roughness=1.0 avoids any specular glint.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.50, 0.33)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "HillRing"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
