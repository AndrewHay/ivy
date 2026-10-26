class_name VillageScatterPositions
extends RefCounted

## Deterministic backdrop scatter transforms (Knuth LCG). Shared by VillageBackdrop
## MultiMesh setup and FaunaEnvironment export (SD-FAUNA-2).

const FLOWER_CLUSTER_PIECES: Array[String] = [
	"Flower_3_Group",
	"Flower_3_Single",
	"Flower_4_Group",
	"Flower_4_Single",
]

const PETAL_PIECES: Array[String] = [
	"Petal_1",
	"Petal_2",
	"Petal_3",
	"Petal_4",
	"Petal_5",
]

const PLANT_PIECES: Array[String] = [
	"Plant_7",
	"Plant_7_Big",
]

# SD-GRASS-1 hybrid lawn: ground shader (far) + card MultiMesh (near) + wispy accents.
const GRASS_LCG_SEED := 42007
const GRASS_ACCENT_LCG_SEED := 42042
## Near-ring card geometry (garden band); far ring is procedural ground only.
const GRASS_RING_INNER_M := 5.5
const GRASS_RING_OUTER_M := 12.0
const GRASS_GRID_STEP_M := 0.58
const GRASS_MAX_INSTANCES := 650
const GRASS_ACCENT_COUNT := 28
const GRASS_ACCENT_INNER_M := 6.0
const GRASS_ACCENT_OUTER_M := 11.5
const COTTAGE_MARGIN := 0.35
const PATH_CLEARANCE_M := 0.55
const PLANT_CLEARANCE_M := 0.45

static func lcg_step(state: int) -> int:
	return (state * 1664525 + 1013904223) & 0x7FFFFFFF


static func lcg_f01(state: int) -> float:
	return float(state & 0x7FFFFFFF) / float(0x7FFFFFFF)


## ~45 plain-green bushes (Bush_Common). Same LCG layout as former VillageBackdrop private.
static func bush_common_positions() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := 1234
	for spec in VillageBackdrop.COTTAGES:
		var rect := VillageBackdrop.cottage_exterior_rect(spec).grow(0.8)
		var door: Vector2 = VillageBackdrop.cottage_door(spec)[0]
		var corners: Array[Vector2] = [
			rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y)]
		var count := 6
		st = lcg_step(st); count += (st & 1)  # 6 or 7
		for _j in range(count):
			st = lcg_step(st); var edge: int = int(lcg_f01(st) * 4.0) % 4
			st = lcg_step(st); var t: float = lcg_f01(st)
			var p: Vector2 = corners[edge].lerp(corners[(edge + 1) % 4], t)
			if p.distance_to(door) < 1.6 or p.length() < 5.0:
				continue
			if VillageBackdrop.inside_any_cottage(p, 0.3):
				continue
			var cx: float = p.x
			var cz: float = p.y
			st = lcg_step(st); var s: float = lerpf(0.55, 0.80, lcg_f01(st))
			st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
			var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
			out.append(Transform3D(basis, Vector3(cx, 0.0, cz)))
	var st2 := 5678
	var placed_extra := 0
	while placed_extra < 10:
		st2 = lcg_step(st2); var angle: float = lcg_f01(st2) * TAU
		st2 = lcg_step(st2); var r: float = lerpf(8.0, 15.0, lcg_f01(st2))
		var cx2: float = cos(angle) * r
		var cz2: float = sin(angle) * r
		if Vector2(cx2, cz2).length() < 5.0 or VillageBackdrop.inside_any_cottage(Vector2(cx2, cz2), 1.0):
			continue
		st2 = lcg_step(st2); var s2: float = lerpf(0.55, 0.80, lcg_f01(st2))
		st2 = lcg_step(st2); var rot2: float = lcg_f01(st2) * TAU
		var basis2 := Basis.from_euler(Vector3(0.0, rot2, 0.0)).scaled(Vector3(s2, s2, s2))
		out.append(Transform3D(basis2, Vector3(cx2, 0.0, cz2)))
		placed_extra += 1
	return out


## Near-ring cross-card instances (geometry up close).
static func grass_card_positions(ctx: VillageGrassExclusionContext) -> Array[Transform3D]:
	return _grass_grid_positions(ctx, GRASS_LCG_SEED, GRASS_RING_INNER_M, GRASS_RING_OUTER_M,
		GRASS_GRID_STEP_M, GRASS_MAX_INSTANCES, 0.85, 1.05)


## Sparse Grass_Wispy_Short accents in the garden band (not a full carpet).
static func grass_wispy_accent_positions(ctx: VillageGrassExclusionContext) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var anchors := collect_scatter_anchor_xz(ctx)
	var st := GRASS_ACCENT_LCG_SEED
	var attempts := 0
	while out.size() < GRASS_ACCENT_COUNT and attempts < GRASS_ACCENT_COUNT * 40:
		attempts += 1
		st = lcg_step(st); var angle: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r: float = lerpf(GRASS_ACCENT_INNER_M, GRASS_ACCENT_OUTER_M, lcg_f01(st))
		var p := Vector2(cos(angle) * r, sin(angle) * r)
		if not _grass_cell_accepted(p, ctx, anchors, GRASS_ACCENT_INNER_M, GRASS_ACCENT_OUTER_M):
			continue
		st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
		st = lcg_step(st); var s: float = lerpf(0.18, 0.24, lcg_f01(st))
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))
	return out


static func grass_positions(ctx: VillageGrassExclusionContext) -> Array[Transform3D]:
	return grass_card_positions(ctx)


static func _grass_grid_positions(
		ctx: VillageGrassExclusionContext,
		seed: int,
		inner_m: float,
		outer_m: float,
		step: float,
		max_count: int,
		scale_lo: float,
		scale_hi: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var anchors := collect_scatter_anchor_xz(ctx)
	var half := outer_m + step
	var n_cells := int(ceil((2.0 * half) / step))
	var st := seed
	for iy in range(n_cells):
		for ix in range(n_cells):
			if out.size() >= max_count:
				return out
			var cx := -half + (float(ix) + 0.5) * step
			var cz := -half + (float(iy) + 0.5) * step
			var center := Vector2(cx, cz)
			var r_center := center.length()
			if r_center < inner_m or r_center > outer_m:
				continue
			st = lcg_step(st)
			var jx: float = (lcg_f01(st) - 0.5) * step
			st = lcg_step(st)
			var jz: float = (lcg_f01(st) - 0.5) * step
			var p := center + Vector2(jx, jz)
			if not _grass_cell_accepted(p, ctx, anchors, inner_m, outer_m):
				continue
			st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
			st = lcg_step(st); var s: float = lerpf(scale_lo, scale_hi, lcg_f01(st))
			var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
			out.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))
	return out


static func min_xz_dist_to_path_segments(p: Vector2, segments: Array) -> float:
	var best := INF
	for seg_raw in segments:
		var seg := seg_raw as Array
		for i in range(seg.size() - 1):
			var a := seg[i] as Vector2
			var b := seg[i + 1] as Vector2
			best = minf(best, _dist_point_to_segment(p, a, b))
	return best


static func collect_scatter_anchor_xz(ctx: VillageGrassExclusionContext) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var clusters := flower_cluster_layers()
	for piece in FLOWER_CLUSTER_PIECES:
		for t in clusters[piece] as Array[Transform3D]:
			out.append(Vector2(t.origin.x, t.origin.z))
	var petals := petal_layers(ctx.path_stones)
	for piece in PETAL_PIECES:
		for t in petals[piece] as Array[Transform3D]:
			out.append(Vector2(t.origin.x, t.origin.z))
	var plants := plant_layers()
	for piece in PLANT_PIECES:
		for t in plants[piece] as Array[Transform3D]:
			out.append(Vector2(t.origin.x, t.origin.z))
	for t in ctx.path_stones:
		out.append(Vector2(t.origin.x, t.origin.z))
	for t in ctx.bush_transforms:
		out.append(Vector2(t.origin.x, t.origin.z))
	return out


static func _grass_cell_accepted(
		p: Vector2,
		ctx: VillageGrassExclusionContext,
		anchors: Array[Vector2],
		inner_m: float = GRASS_RING_INNER_M,
		outer_m: float = GRASS_RING_OUTER_M) -> bool:
	var r := p.length()
	if r < inner_m or r > outer_m:
		return false
	if ctx.is_inside_cottage.is_valid() and ctx.is_inside_cottage.call(p):
		return false
	if min_xz_dist_to_path_segments(p, ctx.path_segments) < PATH_CLEARANCE_M:
		return false
	for a in anchors:
		if p.distance_to(a) < PLANT_CLEARANCE_M:
			return false
	return true


static func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	var t := 0.0
	if ab_len_sq > 0.0:
		t = clampf(p.dot(ab) / ab_len_sq, 0.0, 1.0)
	return p.distance_to(a.lerp(b, t))


## Path stepping stones (~0.9 m). [param reject_xz] returns true to skip a candidate stone.
static func path_stone_transforms(
		path_segments: Array,
		reject_xz: Callable) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := 9999
	for seg_raw in path_segments:
		var seg := seg_raw as Array
		for i in range(seg.size() - 1):
			var a := seg[i] as Vector2
			var b := seg[i + 1] as Vector2
			var seg_len: float = a.distance_to(b)
			var n_stones := maxi(1, int(seg_len / 0.9))
			for k in range(n_stones):
				var t: float = float(k) / float(n_stones)
				var pos: Vector2 = a.lerp(b, t)
				st = lcg_step(st); var jx: float = (lcg_f01(st) - 0.5) * 0.35
				st = lcg_step(st); var jz: float = (lcg_f01(st) - 0.5) * 0.35
				var cx: float = pos.x + jx
				var cz: float = pos.y + jz
				if reject_xz.call(cx, cz):
					continue
				st = lcg_step(st); var rot_y: float = lcg_f01(st) * TAU
				var basis := Basis.from_euler(Vector3(0.0, rot_y, 0.0))
				out.append(Transform3D(basis, Vector3(cx, 0.0, cz)))
	return out


## Groups of 3–4 mixed flower meshes in the garden ring (FLORA_DESIGN).
static func flower_cluster_layers() -> Dictionary:
	var layers: Dictionary = {}
	for piece in FLOWER_CLUSTER_PIECES:
		layers[piece] = [] as Array[Transform3D]

	var st := 137
	const CLUSTER_COUNT := 10
	for _c in range(CLUSTER_COUNT):
		st = lcg_step(st); var angle: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r: float = lerpf(5.5, 11.4, lcg_f01(st))
		var center := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		st = lcg_step(st)
		var member_count := 3 if lcg_f01(st) < 0.45 else 4
		for _m in range(member_count):
			st = lcg_step(st); var piece_idx: int = int(lcg_f01(st) * 4.0) % 4
			st = lcg_step(st); var off_a: float = lcg_f01(st) * TAU
			st = lcg_step(st); var off_r: float = lerpf(0.06, 0.32, lcg_f01(st))
			st = lcg_step(st); var s: float = lerpf(0.17, 0.23, lcg_f01(st))
			st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
			var pos := center + Vector3(cos(off_a) * off_r, 0.0, sin(off_a) * off_r)
			var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
			var piece: String = FLOWER_CLUSTER_PIECES[piece_idx]
			(layers[piece] as Array[Transform3D]).append(Transform3D(basis, pos))

	return layers


## Tiny petals beside path stones, not on the stones (FLORA_DESIGN).
static func petal_layers(path_stones: Array[Transform3D]) -> Dictionary:
	var layers: Dictionary = {}
	for piece in PETAL_PIECES:
		layers[piece] = [] as Array[Transform3D]

	var st := 8801
	for i in range(path_stones.size()):
		if i % 2 != 0:
			continue
		var stone := path_stones[i]
		var p := Vector2(stone.origin.x, stone.origin.z)
		st = lcg_step(st)
		var outward := p
		if outward.length_squared() < 0.04:
			continue
		outward = outward.normalized()
		var tangent := Vector2(-outward.y, outward.x)
		st = lcg_step(st)
		var side: float = 1.0 if lcg_f01(st) > 0.5 else -1.0
		st = lcg_step(st)
		var offset: float = lerpf(0.48, 0.72, lcg_f01(st))
		var xz := p + tangent * side * offset
		var r := xz.length()
		if r < FaunaConstants.GARDEN_RING_INNER_M or r > FaunaConstants.GARDEN_RING_OUTER_M:
			continue
		st = lcg_step(st); var piece_idx: int = int(lcg_f01(st) * 5.0) % 5
		st = lcg_step(st); var s: float = lerpf(0.14, 0.19, lcg_f01(st))
		st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		var piece: String = PETAL_PIECES[piece_idx]
		(layers[piece] as Array[Transform3D]).append(Transform3D(basis, Vector3(xz.x, 0.0, xz.y)))

	return layers


static func plant_layers() -> Dictionary:
	var layers: Dictionary = {
		"Plant_7": [] as Array[Transform3D],
		"Plant_7_Big": [] as Array[Transform3D],
	}
	var st := 5503
	for _i in range(14):
		st = lcg_step(st); var angle: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r: float = lerpf(6.0, 14.5, lcg_f01(st))
		st = lcg_step(st); var s: float = lerpf(0.16, 0.22, lcg_f01(st))
		st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		(layers["Plant_7"] as Array[Transform3D]).append(
			Transform3D(basis, Vector3(cos(angle) * r, 0.0, sin(angle) * r)))
	for _i in range(8):
		st = lcg_step(st); var angle2: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r2: float = lerpf(7.0, 13.0, lcg_f01(st))
		st = lcg_step(st); var s2: float = lerpf(0.14, 0.18, lcg_f01(st))
		st = lcg_step(st); var rot2: float = lcg_f01(st) * TAU
		var basis2 := Basis.from_euler(Vector3(0.0, rot2, 0.0)).scaled(Vector3(s2, s2, s2))
		(layers["Plant_7_Big"] as Array[Transform3D]).append(
			Transform3D(basis2, Vector3(cos(angle2) * r2, 0.0, sin(angle2) * r2)))
	return layers


## Bee/butterfly flower anchors: cluster blooms + path-side petals only (FLORA_DESIGN).
static func fauna_flower_anchor_transforms_with_paths(
		path_stones: Array[Transform3D]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var clusters := flower_cluster_layers()
	for piece in FLOWER_CLUSTER_PIECES:
		for t in clusters[piece] as Array[Transform3D]:
			out.append(t)
	var petals := petal_layers(path_stones)
	for piece in PETAL_PIECES:
		for t in petals[piece] as Array[Transform3D]:
			out.append(t)
	return out
