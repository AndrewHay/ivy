class_name CellGrid
extends RefCounted

var cell_size: float


func _init(size: float) -> void:
	cell_size = size


func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(p.x / cell_size)),
		int(floor(p.y / cell_size)),
		int(floor(p.z / cell_size))
	)


## World position a cell's value is defined at. The lattice is corner-based rather
## than centre-based so that `cell_of()`, allocation, and trilinear interpolation all
## agree: a cell's value sits at one lattice point and the eight surrounding cells
## bracket any sample. A centre-based convention would put a half-cell shift between
## the write and the read.
func cell_point(cell: Vector3i) -> Vector3:
	return Vector3(cell) * cell_size


static func pack_key(c: Vector3i) -> int:
	return (c.x + 2048) | ((c.y + 2048) << 12) | ((c.z + 2048) << 24)


static func unpack_key(key: int) -> Vector3i:
	return Vector3i(
		(key & 0xFFF) - 2048,
		((key >> 12) & 0xFFF) - 2048,
		((key >> 24) & 0xFFF) - 2048
	)
