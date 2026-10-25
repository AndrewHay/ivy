class_name VillageScatterPositions
extends RefCounted

## Deterministic backdrop scatter transforms (Knuth LCG). Shared by VillageBackdrop
## MultiMesh setup and FaunaEnvironment export (SD-FAUNA-2).

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


static func flower_positions() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := 137
	for _i in range(16):
		st = lcg_step(st); var angle: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r: float = lerpf(5.5, 12.0, lcg_f01(st))
		st = lcg_step(st); var s: float = lerpf(0.18, 0.22, lcg_f01(st))
		st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(cos(angle) * r, 0.0, sin(angle) * r)))
	return out


static func clover_positions() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var st := 99
	for _i in range(20):
		st = lcg_step(st); var angle: float = lcg_f01(st) * TAU
		st = lcg_step(st); var r: float = lerpf(5.0, 14.0, lcg_f01(st))
		st = lcg_step(st); var s: float = lerpf(0.12, 0.16, lcg_f01(st))
		st = lcg_step(st); var rot: float = lcg_f01(st) * TAU
		var basis := Basis.from_euler(Vector3(0.0, rot, 0.0)).scaled(Vector3(s, s, s))
		out.append(Transform3D(basis, Vector3(cos(angle) * r, 0.0, sin(angle) * r)))
	return out
