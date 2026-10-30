## Top-down 2D plot of VillageLayout placements — ivy-80z S3 visual verification.
##
## Draws a contact sheet of up to 8 seed layouts plus the authored layout.
## Each cell shows: pivot marker, keep-out circle (r=5.9), inner ring bounds
## (r=11.5/13.0), outer ring bounds (r=19.5/21.5), lawn ring (r=30),
## cottage exterior rects (colour by type; inner cottages dimmed), door position +
## outward normal tick, cottage name label, path polylines (colour by edge type:
## hero-edge=cyan, cross-ring=yellow, same-ring=green), and node dots.
##
## Usage (headless — no scene needed):
##   godot --headless --script res://tools/plot_village_layout.gd \
##         -- --seeds=1,2,3,4,5,6 --out=res://.tmp/village_gen/s3_networks.png
##
## Default seeds: 1,2,3,4,5,6 + authored (slot 0).
## Default out: res://.tmp/village_gen/s3_networks.png
extends SceneTree

const _DEFAULT_SEEDS := "1,2,3,4,5,6"
const _DEFAULT_OUT   := "res://.tmp/village_gen/s3_networks.png"

## Pixel size of each individual cell in the contact sheet.
const _CELL_PX := 256
## World metres visible on each side of the origin (square view). 32 m fits the
## 27.18 m outer corners + 30 m lawn ring.
const _WORLD_HALF_M := 32.0
## Layout of cells in the contact sheet (cols × rows). 0=authored + up to 6 seeds.
const _COLS := 3
## Colours (RGBA 32-bit, packed as 0xRRGGBBAA little-endian byte order for Image.set_pixel).
## Image.FORMAT_RGBA8: pixel bytes = [R, G, B, A].
const _C_BG           := Color(0.13, 0.11, 0.08, 1.0)  # dark earth
const _C_GRID         := Color(0.25, 0.23, 0.20, 1.0)  # faint grid
const _C_KEEPOUT      := Color(0.9,  0.2,  0.2,  0.6)  # red keep-out ring
const _C_INNER_RING   := Color(0.4,  0.8,  1.0,  0.6)  # light-blue inner ring bounds
const _C_OUTER_RING   := Color(0.2,  0.5,  0.9,  0.5)  # mid-blue outer ring bounds
const _C_LAWN         := Color(0.3,  0.8,  0.3,  0.3)  # green lawn hint (r=30)
const _C_PIVOT        := Color(1.0,  1.0,  0.0,  1.0)  # yellow pivot
const _C_DOOR         := Color(1.0,  0.6,  0.0,  1.0)  # orange door marker
const _C_DOOR_NORM    := Color(1.0,  0.9,  0.1,  1.0)  # yellow door-normal tick
const _C_LABEL        := Color(1.0,  1.0,  1.0,  0.9)
const _C_INNER_DIM    := Color(0.6,  0.6,  0.6,  0.5)  # dim overlay for inner ring rects
## Path polyline colours (by edge type).
const _C_PATH_HERO   := Color(0.0,  1.0,  1.0,  0.9)  # cyan  — hero-incident edge
const _C_PATH_CROSS  := Color(1.0,  1.0,  0.0,  0.85) # yellow — cross-ring (inner↔outer)
const _C_PATH_SAME   := Color(0.3,  1.0,  0.3,  0.85) # green  — same-ring edge
## Node dot colour.
const _C_NODE        := Color(1.0,  0.4,  0.0,  1.0)  # orange node dot

## Per-type cottage colours (7 authored types CA…CG in order).
const _COTTAGE_COLORS: Array[Color] = [
	Color(0.95, 0.55, 0.55, 0.85),  # CA — red
	Color(0.55, 0.95, 0.55, 0.85),  # CB — green
	Color(0.55, 0.55, 0.95, 0.85),  # CC — blue
	Color(0.95, 0.95, 0.40, 0.85),  # CD — yellow
	Color(0.95, 0.55, 0.95, 0.85),  # CE — magenta
	Color(0.40, 0.95, 0.95, 0.85),  # CF — cyan
	Color(0.95, 0.75, 0.35, 0.85),  # CG — orange
]

var _img: Image
var _cell: int = _CELL_PX


func _initialize() -> void:
	var args := _parse_args()
	var seeds_str: String = args.get("seeds", _DEFAULT_SEEDS)
	var out_path: String = args.get("out", _DEFAULT_OUT)
	out_path = ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())

	var seeds: Array[int] = []
	for s_raw in seeds_str.split(","):
		var s := s_raw.strip_edges()
		if s.is_valid_int():
			seeds.append(int(s))

	# Build layouts: authored first, then each seed
	var layouts: Array[VillageLayout] = []
	var labels: Array[String] = []
	layouts.append(VillageLayout.authored())
	labels.append("authored")
	for seed: int in seeds:
		layouts.append(VillageLayout.generate(seed))
		labels.append("seed=%d" % seed)

	# Contact sheet dimensions
	var n := layouts.size()
	var cols := _COLS
	var rows := int(ceil(float(n) / float(cols)))
	var sheet_w := cols * _cell
	var sheet_h := rows * _cell

	_img = Image.create(sheet_w, sheet_h, false, Image.FORMAT_RGBA8)

	for cell_idx: int in n:
		var col := cell_idx % cols
		var row := cell_idx / cols
		var ox := col * _cell
		var oy := row * _cell
		_draw_cell(layouts[cell_idx], labels[cell_idx], ox, oy)

	var err := _img.save_png(out_path)
	if err != OK:
		push_error("plot_village_layout: failed to save '%s' (err=%d)" % [out_path, err])
		quit(1)
		return

	print("[plot_village_layout] saved contact sheet (%d layouts) → %s" % [n, out_path])
	quit(0)


func _draw_cell(layout: VillageLayout, label: String, ox: int, oy: int) -> void:
	# Fill background
	for py in range(_cell):
		for px in range(_cell):
			_img.set_pixel(ox + px, oy + py, _C_BG)

	# Draw circles (keep-out, inner ring, outer ring, lawn) as ring outlines
	_draw_circle_outline(ox, oy,  5.9, _C_KEEPOUT,    1)
	_draw_circle_outline(ox, oy, 11.5, _C_INNER_RING, 1)
	_draw_circle_outline(ox, oy, 13.0, _C_INNER_RING, 1)
	_draw_circle_outline(ox, oy, 19.5, _C_OUTER_RING, 1)
	_draw_circle_outline(ox, oy, 21.5, _C_OUTER_RING, 1)
	_draw_circle_outline(ox, oy, 30.0, _C_LAWN,       1)

	# Draw cottages (dim inner cottages slightly to distinguish from outer)
	for i: int in layout.cottages.size():
		var spec: Dictionary = layout.cottages[i]
		var col: Color = _COTTAGE_COLORS[i % _COTTAGE_COLORS.size()]
		# If ring info is available, dim inner cottages
		var ring_id := -1
		if layout.cottage_rings.size() == layout.cottages.size():
			ring_id = int(layout.cottage_rings[i])
		if ring_id == 0:
			col = col.lerp(_C_INNER_DIM, 0.35)
		_draw_cottage(ox, oy, spec, col)

	# Draw path polylines (S3: drawn before pivot so pivot overlays them)
	_draw_paths(layout, ox, oy)

	# Draw node dots for stoops (0..6) and hero (7)
	_draw_network_nodes(layout, ox, oy)

	# Draw pivot (cross)
	var px0 := _w2px(0.0) + ox
	var py0 := _w2py(0.0) + oy
	for d: int in range(-4, 5):
		_safe_set(px0 + d, py0, _C_PIVOT)
		_safe_set(px0, py0 + d, _C_PIVOT)

	# Draw label (seed number) at top-left
	_draw_label_text(label, ox + 3, oy + 3, _C_LABEL)


func _draw_cottage(ox: int, oy: int, spec: Dictionary, col: Color) -> void:
	# Draw exterior rect outline
	var rect := VillageBackdrop.cottage_exterior_rect(spec)
	var x0 := _w2px(rect.position.x) + ox
	var y0 := _w2py(rect.position.y) + oy
	var x1 := _w2px(rect.end.x) + ox
	var y1 := _w2py(rect.end.y) + oy
	_draw_rect_outline(x0, y0, x1, y1, col)

	# Draw door marker and outward-normal tick
	var door_info := VillageBackdrop.cottage_door(spec)
	var door_pos: Vector2 = door_info[0]
	var door_normal: Vector2 = door_info[1]
	var dpx := _w2px(door_pos.x) + ox
	var dpy := _w2py(door_pos.y) + oy
	# Door: 3×3 square
	for dy2: int in range(-1, 2):
		for dx2: int in range(-1, 2):
			_safe_set(dpx + dx2, dpy + dy2, _C_DOOR)
	# Normal tick: draw 6 px along the door normal direction (in screen space)
	# world +x → +px, world +y → -py (y axis inverted in image)
	var tick_len := 6
	for k: int in range(1, tick_len + 1):
		var tx := int(round(float(dpx) + door_normal.x * float(k)))
		var ty := int(round(float(dpy) - door_normal.y * float(k)))  # y flipped
		_safe_set(tx, ty, _C_DOOR_NORM)

	# Cottage name text
	var centre: Vector2 = spec["centre"]
	var cx := _w2px(centre.x) + ox
	var cy := _w2py(centre.y) + oy
	_draw_label_text(String(spec.get("name", "?")), cx - 4, cy - 4, col)


func _draw_rect_outline(x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	# Ensure x0 ≤ x1 and y0 ≤ y1 (image y increases downward)
	var ax := mini(x0, x1)
	var bx := maxi(x0, x1)
	var ay := mini(y0, y1)
	var by := maxi(y0, y1)
	for x: int in range(ax, bx + 1):
		_safe_set(x, ay, col)
		_safe_set(x, by, col)
	for y: int in range(ay, by + 1):
		_safe_set(ax, y, col)
		_safe_set(bx, y, col)


func _draw_paths(layout: VillageLayout, ox: int, oy: int) -> void:
	## Draw all path polylines from layout.paths, coloured by edge type.
	if layout.paths.is_empty():
		return
	var n_cottages := layout.cottages.size()
	for pi: int in layout.paths.size():
		var poly := layout.paths[pi] as Array
		if poly.size() < 2:
			continue
		# Determine edge type from layout.edges[pi]
		var col := _C_PATH_SAME  # default: same-ring
		if pi < layout.edges.size():
			var e: Vector2i = layout.edges[pi]
			var ai := e.x
			var bi := e.y
			if ai == VillageLayout.HERO_NODE or bi == VillageLayout.HERO_NODE:
				col = _C_PATH_HERO
			elif layout.cottage_rings.size() == n_cottages and ai < n_cottages and bi < n_cottages:
				# Cross-ring if one is inner and the other is outer
				if int(layout.cottage_rings[ai]) != int(layout.cottage_rings[bi]):
					col = _C_PATH_CROSS
		# Draw polyline segments
		for i: int in range(poly.size() - 1):
			var pa := poly[i] as Vector2
			var pb := poly[i + 1] as Vector2
			_draw_world_line(ox, oy, pa, pb, col)


func _draw_world_line(ox: int, oy: int, a: Vector2, b: Vector2, col: Color) -> void:
	## Bresenham-style line between two world-space points.
	var ax := _w2px(a.x) + ox
	var ay := _w2py(a.y) + oy
	var bx := _w2px(b.x) + ox
	var by := _w2py(b.y) + oy
	var dx: int = absi(bx - ax)
	var dy: int = absi(by - ay)
	var steps := maxi(1, maxi(dx, dy))
	for k: int in range(steps + 1):
		var t := float(k) / float(steps)
		var px := int(round(lerpf(float(ax), float(bx), t)))
		var py := int(round(lerpf(float(ay), float(by), t)))
		_safe_set(px, py, col)


func _draw_network_nodes(layout: VillageLayout, ox: int, oy: int) -> void:
	## Draw 3×3 dot at each door stoop and hero position.
	if layout.edges.is_empty():
		return
	# Door stoops (nodes 0..6)
	for i: int in layout.cottages.size():
		var spec: Dictionary = layout.cottages[i]
		var door_info := VillageBackdrop.cottage_door(spec)
		var door_pos: Vector2 = door_info[0]
		var door_normal: Vector2 = door_info[1]
		var stoop := door_pos + door_normal * 0.5
		var spx := _w2px(stoop.x) + ox
		var spy := _w2py(stoop.y) + oy
		for dy2: int in range(-1, 2):
			for dx2: int in range(-1, 2):
				_safe_set(spx + dx2, spy + dy2, _C_NODE)
	# Hero node (bright white dot at origin)
	var hpx := _w2px(0.0) + ox
	var hpy := _w2py(0.0) + oy
	for dy2: int in range(-2, 3):
		for dx2: int in range(-2, 3):
			_safe_set(hpx + dx2, hpy + dy2, _C_PIVOT)


func _draw_circle_outline(ox: int, oy: int, radius_m: float, col: Color, thickness: int) -> void:
	var r_px := radius_m * float(_cell) / (2.0 * _WORLD_HALF_M)
	var cx := _w2px(0.0) + ox
	var cy := _w2py(0.0) + oy
	var steps := maxi(64, int(r_px * TAU))
	for i: int in steps:
		var angle := float(i) / float(steps) * TAU
		var px := int(round(float(cx) + cos(angle) * r_px))
		var py := int(round(float(cy) - sin(angle) * r_px))  # y flipped
		for t: int in range(-thickness, thickness + 1):
			_safe_set(px + t, py, col)
			_safe_set(px, py + t, col)


## Convert world metres (XZ) → pixel X in cell (X right, origin centre).
func _w2px(world_x: float) -> int:
	return int(round((world_x + _WORLD_HALF_M) / (2.0 * _WORLD_HALF_M) * float(_cell - 1)))


## Convert world metres (XZ) → pixel Y in cell (Z up = pixel Y down, origin centre).
func _w2py(world_z: float) -> int:
	return int(round((_WORLD_HALF_M - world_z) / (2.0 * _WORLD_HALF_M) * float(_cell - 1)))


func _safe_set(px: int, py: int, col: Color) -> void:
	if px >= 0 and px < _img.get_width() and py >= 0 and py < _img.get_height():
		_img.set_pixel(px, py, col)


## Minimal 3×5 pixel font for single-line ASCII labels (digits + letters A-Z).
## Draws left-to-right starting at (tx, ty). Each glyph is 4 wide (3 + 1 gap).
func _draw_label_text(text: String, tx: int, ty: int, col: Color) -> void:
	var x := tx
	for ch in text:
		var glyph: Array = _FONT.get(ch.to_upper(), _FONT.get("?", []))
		for row_idx: int in glyph.size():
			var row_bits: int = glyph[row_idx]
			for bit: int in range(3):
				if row_bits & (1 << (2 - bit)):
					_safe_set(x + bit, ty + row_idx, col)
		x += 4  # advance 4 pixels per glyph


## 3×5 pixel font: each glyph is Array[int] of 5 row-bitmasks (bits 2..0 = columns L→R).
const _FONT := {
	"0": [0b111, 0b101, 0b101, 0b101, 0b111],
	"1": [0b010, 0b110, 0b010, 0b010, 0b111],
	"2": [0b111, 0b001, 0b111, 0b100, 0b111],
	"3": [0b111, 0b001, 0b111, 0b001, 0b111],
	"4": [0b101, 0b101, 0b111, 0b001, 0b001],
	"5": [0b111, 0b100, 0b111, 0b001, 0b111],
	"6": [0b111, 0b100, 0b111, 0b101, 0b111],
	"7": [0b111, 0b001, 0b001, 0b001, 0b001],
	"8": [0b111, 0b101, 0b111, 0b101, 0b111],
	"9": [0b111, 0b101, 0b111, 0b001, 0b111],
	"A": [0b111, 0b101, 0b111, 0b101, 0b101],
	"B": [0b110, 0b101, 0b110, 0b101, 0b110],
	"C": [0b111, 0b100, 0b100, 0b100, 0b111],
	"D": [0b110, 0b101, 0b101, 0b101, 0b110],
	"E": [0b111, 0b100, 0b111, 0b100, 0b111],
	"F": [0b111, 0b100, 0b111, 0b100, 0b100],
	"G": [0b111, 0b100, 0b101, 0b101, 0b111],
	"H": [0b101, 0b101, 0b111, 0b101, 0b101],
	"I": [0b111, 0b010, 0b010, 0b010, 0b111],
	"J": [0b001, 0b001, 0b001, 0b101, 0b111],
	"K": [0b101, 0b101, 0b110, 0b101, 0b101],
	"L": [0b100, 0b100, 0b100, 0b100, 0b111],
	"M": [0b101, 0b111, 0b111, 0b101, 0b101],
	"N": [0b101, 0b111, 0b111, 0b111, 0b101],
	"O": [0b111, 0b101, 0b101, 0b101, 0b111],
	"P": [0b111, 0b101, 0b111, 0b100, 0b100],
	"Q": [0b111, 0b101, 0b101, 0b111, 0b011],
	"R": [0b111, 0b101, 0b111, 0b110, 0b101],
	"S": [0b111, 0b100, 0b111, 0b001, 0b111],
	"T": [0b111, 0b010, 0b010, 0b010, 0b010],
	"U": [0b101, 0b101, 0b101, 0b101, 0b111],
	"V": [0b101, 0b101, 0b101, 0b111, 0b010],
	"W": [0b101, 0b101, 0b111, 0b111, 0b101],
	"X": [0b101, 0b101, 0b010, 0b101, 0b101],
	"Y": [0b101, 0b101, 0b111, 0b010, 0b010],
	"Z": [0b111, 0b001, 0b010, 0b100, 0b111],
	"=": [0b000, 0b111, 0b000, 0b111, 0b000],
	"-": [0b000, 0b000, 0b111, 0b000, 0b000],
	".": [0b000, 0b000, 0b000, 0b000, 0b010],
	" ": [0b000, 0b000, 0b000, 0b000, 0b000],
	"?": [0b111, 0b001, 0b011, 0b000, 0b010],
}


func _parse_args() -> Dictionary:
	var result: Dictionary = {}
	var args := OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				result[kv[0]] = kv[1]
			else:
				result[kv[0]] = "true"
	return result
