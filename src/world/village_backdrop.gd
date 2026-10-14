## VillageBackdrop — non-interactive environment dressing around the playable structure.
##
## Repositioned by World._activate_mesh_scenario() to (pivot.x, 0, pivot.z).
## Hidden on the procedural path and in _teardown_active_building().
## All MeshInstance3D descendants render with their native glTF PBR materials.
##
## Shadow policy:
##   - Static .tscn pieces: < 8 m from backdrop origin in XZ → cast_shadow=OFF (near-hero dressing);
##     ≥ 8 m retain native ON so background cottages cast cosy soft shadows.
##   - Generated cottages (Cottage_*, all >= 10 m out): cast_shadow=ON.
##   - MultiMesh scatter near ring (Scatter_*): always cast_shadow=OFF.
##   - MultiMesh far treeline (FarTreeline): cast_shadow=ON.
##   - HillRing: cast_shadow=OFF (ground-level, minimal shadow contribution).
##
## No collision, no layer 1, never referenced by BuildingCatalog or SurfaceQuery.
class_name VillageBackdrop
extends Node3D

## XZ distance threshold for shadow culling.
const _SHADOW_NEAR_M := 8.0

# ── Cottages ──────────────────────────────────────────────────────────────────
#
# Cottages are generated from COTTAGES rather than authored node-by-node: every
# kit piece type renders as one MultiMesh, so 7 two-bay-deep houses cost ~20
# draws instead of ~140 MeshInstance3D surfaces.
#
# House-local frame: ridge along +X, body spans x ∈ [-L/2, L/2] (L = bays × 2 m),
# z ∈ [-2, 2]. Kit walls sit with their origin on the grid line, their 0.31 m
# thickness inside and their exterior face 0.09 m outward, so the 4×N round-tile
# roofs and Roof_Front_Brick4 gables meet the wall tops as the kit intends.
# Wall slots are named "<side>:<bay>"; sides are front (+Z), back (-Z),
# left (-X end) and right (+X end). End walls have bays 0 (-Z) and 1 (+Z).
# yaw_deg must be a multiple of 90.

const COTTAGE_DEPTH := 4.0
const WALL_OUT := 0.09
const WALL_TOP := 3.125

const COTTAGES := [
	{"name": "CA", "centre": Vector2(16.0, -9.5), "bays": 4, "yaw_deg": -90,
		"door": "front:2", "windows": ["front:0", "front:3", "back:1"], "brick": "", "chimney_bay": 0},
	{"name": "CB", "centre": Vector2(-15.0, -8.5), "bays": 3, "yaw_deg": 0,
		"door": "right:1", "windows": ["front:1", "front:2"], "brick": "back", "chimney_bay": 0},
	{"name": "CC", "centre": Vector2(12.0, 11.0), "bays": 3, "yaw_deg": 180,
		"door": "front:1", "windows": ["front:0", "left:0"], "brick": "", "chimney_bay": 2},
	{"name": "CD", "centre": Vector2(-12.0, 11.0), "bays": 4, "yaw_deg": 180,
		"door": "front:2", "windows": ["front:0", "front:3"], "brick": "back", "chimney_bay": 0},
	{"name": "CE", "centre": Vector2(16.5, 1.0), "bays": 3, "yaw_deg": 180,
		"door": "right:0", "windows": ["front:1", "back:1"], "brick": "", "chimney_bay": 1},
	{"name": "CF", "centre": Vector2(-16.0, 1.0), "bays": 3, "yaw_deg": 90,
		"door": "front:1", "windows": ["front:0", "front:2"], "brick": "left", "chimney_bay": 2},
	{"name": "CG", "centre": Vector2(4.0, -17.0), "bays": 3, "yaw_deg": 0,
		"door": "front:1", "windows": ["front:2"], "brick": "", "chimney_bay": 0},
]

const _PIECE_DIR := "res://assets/backdrop/pieces/"
const _P_WALL := "Wall_Plaster_Straight"
const _P_WALL_WINDOW := "Wall_Plaster_Window_Wide_Flat"
const _P_WALL_DOOR := "Wall_Plaster_Door_Flat"
const _P_WALL_BRICK := "Wall_UnevenBrick_Straight"
const _P_DOOR_LEAF := "Door_1_Flat"
const _P_SHUTTER := "WindowShutters_Wide_Flat_Closed"
const _P_GABLE := "Roof_Front_Brick4"
const _P_CHIMNEY := "Prop_Chimney2"
## Roof piece per bay count; native ridge runs along the piece's local Z.
const _P_ROOF := {3: "Roof_RoundTiles_4x6", 4: "Roof_RoundTiles_4x8"}


func _ready() -> void:
	_apply_subtree(self)
	_build_cottages()
	_setup_multimesh_scatter()
	_create_paths()
	_add_hill_ring()


static func cottage_transform(spec: Dictionary) -> Transform3D:
	var c: Vector2 = spec["centre"]
	return Transform3D(
		Basis(Vector3.UP, deg_to_rad(float(spec["yaw_deg"]))), Vector3(c.x, 0.0, c.y))


## World-XZ rectangle covered by the wall exteriors (eaves not included).
static func cottage_exterior_rect(spec: Dictionary) -> Rect2:
	var half := Vector2(int(spec["bays"]) + WALL_OUT, COTTAGE_DEPTH * 0.5 + WALL_OUT)
	if absi(int(spec["yaw_deg"])) % 180 == 90:
		half = Vector2(half.y, half.x)
	var c: Vector2 = spec["centre"]
	return Rect2(c - half, half * 2.0)


## Door as [exterior-face centre (world XZ), outward normal (world XZ)].
static func cottage_door(spec: Dictionary) -> Array[Vector2]:
	var slot := _slot_local(spec, String(spec["door"]))
	var xf := cottage_transform(spec)
	var p := xf * (slot[0] as Vector3 + (slot[1] as Vector3) * WALL_OUT)
	var n := xf.basis * (slot[1] as Vector3)
	return [Vector2(p.x, p.z), Vector2(n.x, n.z).normalized()]


## Wall slot "<side>:<bay>" → [grid-line position, outward normal] in house-local space.
static func _slot_local(spec: Dictionary, slot: String) -> Array[Vector3]:
	var parts := slot.split(":")
	var side := parts[0]
	var bay := int(parts[1])
	var half_len := float(int(spec["bays"]))
	var half_depth := COTTAGE_DEPTH * 0.5
	match side:
		"front":
			return [Vector3(-half_len + 1.0 + 2.0 * bay, 0.0, half_depth), Vector3.BACK]
		"back":
			return [Vector3(-half_len + 1.0 + 2.0 * bay, 0.0, -half_depth), Vector3.FORWARD]
		"left":
			return [Vector3(-half_len, 0.0, -1.0 + 2.0 * bay), Vector3.LEFT]
		_:
			return [Vector3(half_len, 0.0, -1.0 + 2.0 * bay), Vector3.RIGHT]


## Kit pieces face their exterior (timber framing, shutters, door leaf) along
## local +Z; rotate so it points along `normal`.
static func _facing(normal: Vector3, origin: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(normal.x, normal.z)), origin)


func _build_cottages() -> void:
	var placements := {}
	for spec in COTTAGES:
		var house := cottage_transform(spec)
		var bays := int(spec["bays"])
		var slots: Array[String] = []
		for side in ["front", "back"]:
			for i in range(bays):
				slots.append("%s:%d" % [side, i])
		for side in ["left", "right"]:
			for j in range(2):
				slots.append("%s:%d" % [side, j])
		for slot in slots:
			var local := _slot_local(spec, slot)
			var xf := house * _facing(local[1], local[0])
			var side := slot.split(":")[0]
			if slot == spec["door"]:
				_place(placements, _P_WALL_DOOR, xf)
				_place(placements, _P_DOOR_LEAF, xf)
			elif slot in spec["windows"]:
				_place(placements, _P_WALL_WINDOW, xf)
				_place(placements, _P_SHUTTER, xf)
			elif side == spec["brick"]:
				_place(placements, _P_WALL_BRICK, xf)
			else:
				_place(placements, _P_WALL, xf)
		for normal in [Vector3.LEFT, Vector3.RIGHT]:
			var end := Vector3(normal.x * bays, WALL_TOP, 0.0)
			_place(placements, _P_GABLE, house * _facing(normal, end))
		_place(placements, _P_ROOF[bays],
			house * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, WALL_TOP, 0.0)))
		var chimney_x := -bays + 1.0 + 2.0 * int(spec["chimney_bay"])
		_place(placements, _P_CHIMNEY,
			house * Transform3D(Basis.IDENTITY, Vector3(chimney_x, WALL_TOP + 0.3, -1.1)))
	for piece in placements:
		_create_piece_multimesh(piece, "Cottage_" + piece, placements[piece],
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func _place(placements: Dictionary, piece: String, xf: Transform3D) -> void:
	if not placements.has(piece):
		placements[piece] = [] as Array[Transform3D]
	(placements[piece] as Array[Transform3D]).append(xf)


## One MultiMesh per mesh node in the piece, each instance carrying the node's
## own transform inside the glTF so multi-node pieces assemble correctly.
func _create_piece_multimesh(
		piece: String, node_name: String,
		transforms: Array[Transform3D],
		shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	var ps := load(_PIECE_DIR + piece + ".gltf") as PackedScene
	if ps == null:
		push_error("VillageBackdrop: missing cottage piece '%s'" % piece)
		return
	var inst := ps.instantiate()
	var parts: Array = []
	_collect_mesh_parts(inst, Transform3D.IDENTITY, parts)
	inst.free()
	for k in range(parts.size()):
		var local: Transform3D = parts[k][1]
		var placed: Array[Transform3D] = []
		for xf in transforms:
			placed.append(xf * local)
		var part_name := node_name if parts.size() == 1 else "%s_%d" % [node_name, k]
		_add_multimesh(parts[k][0], part_name, placed, shadow)


func _collect_mesh_parts(node: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append([(node as MeshInstance3D).mesh, xf])
	for child in node.get_children():
		_collect_mesh_parts(child, xf, out)


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
	## Bush_Common: 45 plain-green bushes clustered near cottage walls and path edges.
	_create_scatter(
		"res://assets/backdrop/pieces/Bush_Common.gltf",
		"Scatter_Bush_Common", _bush_common_positions(),
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_patch_bush_green_material()


func _create_scatter(
		path: String, node_name: String,
		transforms: Array[Transform3D],
		shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	var mesh := _extract_first_mesh(path)
	if mesh == null:
		return
	_add_multimesh(mesh, node_name, transforms, shadow)


func _add_multimesh(
		mesh: Mesh, node_name: String,
		transforms: Array[Transform3D],
		shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	# Write transforms. set_instance_transform can silently fail on some meshes
	# in headless mode; use the raw buffer as a reliable fallback.
	# The buffer is row-major (3×4 matrix rows), i.e. the basis *columns* are
	# interleaved — writing basis.x contiguously would transpose every rotation.
	var buf := PackedFloat32Array()
	buf.resize(transforms.size() * 12)
	for i in range(transforms.size()):
		var t := transforms[i]
		var b := i * 12
		buf[b + 0] = t.basis.x.x; buf[b + 1] = t.basis.y.x; buf[b + 2] = t.basis.z.x
		buf[b + 3] = t.origin.x
		buf[b + 4] = t.basis.x.y; buf[b + 5] = t.basis.y.y; buf[b + 6] = t.basis.z.y
		buf[b + 7] = t.origin.y
		buf[b + 8] = t.basis.x.z; buf[b + 9] = t.basis.y.z; buf[b + 10] = t.basis.z.z
		buf[b + 11] = t.origin.z
	mm.buffer = buf
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


## Bush_Common glTF has COLOR_0 (autumn-red) vertex colours that Godot imports
## with vertex_color_use_as_albedo=true. Replace surface 0 with a fresh
## StandardMaterial3D (vertex_color_use_as_albedo defaults to false) so the
## Leaves_NormalTree texture renders as plain green. Load the texture by its
## known path to avoid depending on the glTF material type.
func _patch_bush_green_material() -> void:
	for child in get_children():
		if child.name != "Scatter_Bush_Common" or not child is MultiMeshInstance3D:
			continue
		var mmi := child as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			return
		var orig_mesh: Mesh = mmi.multimesh.mesh
		if orig_mesh.get_surface_count() == 0:
			return
		var green_mat := StandardMaterial3D.new()
		var leaf_tex := load("res://assets/backdrop/textures/Leaves_NormalTree_C.png") as Texture2D
		green_mat.albedo_texture = leaf_tex
		green_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		green_mat.alpha_scissor_threshold = 0.2
		green_mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # double-sided
		green_mat.roughness = 1.0
		green_mat.metallic = 0.0
		# vertex_color_use_as_albedo defaults false — vertex colours ignored.
		var dup_mesh: Mesh = orig_mesh.duplicate() as Mesh
		if dup_mesh == null:
			return
		dup_mesh.surface_set_material(0, green_mat)
		mmi.multimesh.mesh = dup_mesh
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


## True if p lies inside any cottage's wall exterior grown by `margin` metres.
static func inside_any_cottage(p: Vector2, margin: float) -> bool:
	for spec in COTTAGES:
		if cottage_exterior_rect(spec).grow(margin).has_point(p):
			return true
	return false


## ~45 plain-green bushes (Bush_Common: ~1.0 m at scale 0.55-0.80) hugging the
## outside of each cottage's walls, plus loose clumps in the mid ring.
## Seeded LCG, no randf. Clear of doors, wall bodies and the hero footprint (r<5 m).
func _bush_common_positions() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := 1234
	for spec in COTTAGES:
		var rect := cottage_exterior_rect(spec).grow(0.8)
		var door: Vector2 = cottage_door(spec)[0]
		var corners: Array[Vector2] = [
			rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y)]
		var count := 6
		st = _lcg_step(st); count += (st & 1)  # 6 or 7
		for _j in range(count):
			st = _lcg_step(st); var edge: int = int(_lcg_f01(st) * 4.0) % 4
			st = _lcg_step(st); var t: float = _lcg_f01(st)
			var p: Vector2 = corners[edge].lerp(corners[(edge + 1) % 4], t)
			if p.distance_to(door) < 1.6 or p.length() < 5.0:
				continue
			if inside_any_cottage(p, 0.3):
				continue
			var cx: float = p.x
			var cz: float = p.y
			st = _lcg_step(st); var s: float = lerpf(0.55, 0.80, _lcg_f01(st))
			st = _lcg_step(st); var rot: float = _lcg_f01(st) * TAU
			var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
			out.append(Transform3D(basis, Vector3(cx, 0.0, cz)))
	# Additional loose clumps scattered in the mid-ring (r=8-15 m).
	var st2 := 5678
	var placed_extra := 0
	while placed_extra < 10:
		st2 = _lcg_step(st2); var angle: float = _lcg_f01(st2) * TAU
		st2 = _lcg_step(st2); var r: float = lerpf(8.0, 15.0, _lcg_f01(st2))
		var cx: float = cos(angle) * r
		var cz: float = sin(angle) * r
		if Vector2(cx, cz).length() < 5.0 or inside_any_cottage(Vector2(cx, cz), 1.0):
			continue
		st2 = _lcg_step(st2); var s: float = lerpf(0.55, 0.80, _lcg_f01(st2))
		st2 = _lcg_step(st2); var rot: float = _lcg_f01(st2) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(cx, 0.0, cz)))
		placed_extra += 1
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


# ── Village paths ─────────────────────────────────────────────────────────────

## Stepping-stone paths linking each cottage door toward the hero area.
## Uses three RockPath_Round_Small variants as a single MultiMesh each, sharing
## the same seeded LCG layout for deterministic placement.
## Paths stop at r≥5 m from the hero pivot — never on the hero footprint.
func _create_paths() -> void:
	var stone_glb := [
		"res://assets/backdrop/pieces/RockPath_Round_Small_1.gltf",
		"res://assets/backdrop/pieces/RockPath_Round_Small_2.gltf",
		"res://assets/backdrop/pieces/RockPath_Round_Small_3.gltf",
	]
	var all_xf: Array[Transform3D] = []
	var segs := path_polylines()
	var st := 9999
	for seg_raw in segs:
		var seg := seg_raw as Array
		# Sample stones at ~0.9 m spacing along the polyline.
		for i in range(seg.size() - 1):
			var a := seg[i] as Vector2
			var b := seg[i + 1] as Vector2
			var seg_len: float = a.distance_to(b)
			var n_stones := maxi(1, int(seg_len / 0.9))
			for k in range(n_stones):
				var t: float = float(k) / float(n_stones)
				var pos: Vector2 = a.lerp(b, t)
				# Small random perpendicular offset for organic look.
				st = _lcg_step(st); var jx: float = (_lcg_f01(st) - 0.5) * 0.35
				st = _lcg_step(st); var jz: float = (_lcg_f01(st) - 0.5) * 0.35
				var cx: float = pos.x + jx
				var cz: float = pos.y + jz
				if Vector2(cx, cz).length() < 4.5 or inside_any_cottage(Vector2(cx, cz), 0.2):
					continue  # skip stones on the hero base or under a cottage
				st = _lcg_step(st); var rot_y: float = _lcg_f01(st) * TAU
				var basis := Basis.from_euler(Vector3(0.0, rot_y, 0.0))
				all_xf.append(Transform3D(basis, Vector3(cx, 0.0, cz)))
	# Distribute instances across 3 stone-type MultiMesh nodes (round-robin by type).
	var b0: Array[Transform3D] = []
	var b1: Array[Transform3D] = []
	var b2: Array[Transform3D] = []
	for i in range(all_xf.size()):
		match i % 3:
			0: b0.append(all_xf[i])
			1: b1.append(all_xf[i])
			2: b2.append(all_xf[i])
	if not b0.is_empty():
		_create_scatter(stone_glb[0], "Scatter_Path_0", b0,
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if not b1.is_empty():
		_create_scatter(stone_glb[1], "Scatter_Path_1", b1,
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if not b2.is_empty():
		_create_scatter(stone_glb[2], "Scatter_Path_2", b2,
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## One XZ polyline per cottage: straight out of the door for 2 m, then a gentle
## curve toward the hero that ends 6.5 m from the pivot.
static func path_polylines() -> Array:
	var out: Array = []
	var bend := 1.0
	for spec in COTTAGES:
		var door := cottage_door(spec)
		var stoop: Vector2 = door[0] + door[1] * 0.5
		var turn: Vector2 = door[0] + door[1] * 2.0
		var finish: Vector2 = turn.normalized() * 6.5
		var dir := (finish - turn).normalized()
		var mid: Vector2 = (turn + finish) * 0.5 + Vector2(-dir.y, dir.x) * 0.7 * bend
		bend = -bend
		out.append([stoop, turn, mid, finish])
	return out


# ── Horizon hill ring ─────────────────────────────────────────────────────────

## Visual-only raised ground ring at r=20-44 m that lifts the horizon above a flat line.
## Terrain transitions from y=0 (inner) to y=3.0 m (outer), hiding the sky-ground seam.
## Extended to r=44 m (was 34 m) and higher (3.0 m, was 1.5 m) to eliminate grey horizon band.
## No CollisionShape3D, no physics body, no collision layer.
func _add_hill_ring() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner_r := 20.0
	var outer_r := 44.0
	var hill_h := 3.0
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
