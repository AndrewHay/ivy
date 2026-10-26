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

static func lcg_step(state: int) -> int:
	return (state * 1664525 + 1013904223) & 0x7FFFFFFF


static func lcg_f01(state: int) -> float:
	return float(state & 0x7FFFFFFF) / float(0x7FFFFFFF)


static func grass_positions() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := 42
	for _i in range(30):
		st = lcg_step(st); var angle: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r: float = lerpf(6.5, 15.0, lcg_f01(st))
		st = lcg_step(st); var s: float = lerpf(0.18, 0.24, lcg_f01(st))
		st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(cos(angle) * r, 0.0, sin(angle) * r)))
	return out


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
