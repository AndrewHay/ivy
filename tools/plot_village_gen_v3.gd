## Headless 2D plot: v3 path-first layouts (paths by kind, cottages, junctions, lawn, pond).
## Usage:
##   godot --headless --quit-after 3000 --path <ivy> --script res://tools/plot_village_gen_v3.gd -- --out=res://.tmp/village-gen-v3/shots/plot_seeds.png --seeds=1,2,3,4,5,6,240424020
extends SceneTree

const _DEFAULT_OUT := "res://.tmp/village-gen-v3/shots/plot_seeds.png"
const _DEFAULT_SEEDS := "1,2,3,4,5,6,240424020"
const _CELL_PX := 420
const _VIEW_PAD_M := 3.5
const _Layout := preload("res://src/world/village_layout.gd")

const _C_BG := Color(0.09, 0.10, 0.12, 1.0)
const _C_LAWN := Color(0.25, 0.42, 0.22, 0.35)
const _C_POND := Color(0.2, 0.45, 0.75, 0.55)
const _C_PLAZA := Color(0.45, 0.45, 0.48, 0.85)
const _C_HERO := Color(0.2, 0.85, 0.95, 0.9)
const _C_PRIMARY := Color(0.95, 0.55, 0.15, 0.9)
const _C_SECONDARY := Color(0.95, 0.9, 0.25, 0.88)
const _C_DOOR := Color(1.0, 1.0, 1.0, 0.92)
const _C_JUNCTION := Color(1.0, 0.35, 0.9, 1.0)
const _C_COTTAGE := Color(0.55, 0.7, 0.95, 0.55)


func _initialize() -> void:
	var args := _parse_cmdline()
	var out_path: String = args.get("out", _DEFAULT_OUT)
	var seeds_str: String = args.get("seeds", _DEFAULT_SEEDS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))

	var seeds: Array[int] = []
	for part: String in seeds_str.split(","):
		var t := part.strip_edges()
		if t.is_valid_int():
			seeds.append(int(t))
	if seeds.is_empty():
		seeds = [1, 6]

	var cols: int = mini(3, seeds.size())
	var rows: int = int(ceil(float(seeds.size()) / float(cols)))
	var w: int = cols * _CELL_PX
	var h: int = rows * _CELL_PX
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(_C_BG)

	for i: int in seeds.size():
		var layout: VillageLayout = VillageLayout.generate(seeds[i])
		var col: int = i % cols
		var row: int = i / cols
		_draw_cell(img, col, row, layout, seeds[i])

	var gpath := ProjectSettings.globalize_path(out_path)
	img.save_png(gpath)
	print("wrote ", gpath)
	quit()


func _draw_cell(img: Image, col: int, row: int, layout: VillageLayout, seed: int) -> void:
	var ox: float = float(col * _CELL_PX)
	var oy: float = float(row * _CELL_PX)
	var g: Vector2 = layout.hamlet_centre_xz
	var view: Dictionary = _cell_view(layout, g)
	var scale: float = float(view["scale"])
	## Lawn circle (clipped to this cell so neighbouring villages don't bleed)
	_draw_circle_world(img, ox, oy, g, scale, g, layout.lawn_radius, _C_LAWN)
	## Pond
	if layout.pond_placed:
		_draw_circle_world(img, ox, oy, g, scale, layout.pond_center, 5.5, _C_POND)
	## Paths
	for pi: int in layout.paths.size():
		var raw: Variant = layout.paths[pi]
		var poly := _to_packed(raw)
		var kind: String = str(layout.path_kinds[pi]) if pi < layout.path_kinds.size() else "primary"
		var col_path: Color = _kind_color(kind)
		_draw_poly_world(img, ox, oy, g, scale, poly, col_path, 2.2)
	## Junctions
	for jp: Variant in layout.junction_points:
		var p: Vector2 = jp as Vector2
		var px: Vector2 = _world_to_px(ox, oy, g, scale, p)
		_draw_dot(img, ox, oy, int(px.x), int(px.y), 3, _C_JUNCTION)
	## Cottages
	for spec: Variant in layout.cottages:
		var r: Rect2 = VillageBackdrop.cottage_exterior_rect(spec as Dictionary)
		_draw_rect_world(img, ox, oy, g, scale, r, _C_COTTAGE)
		var door := VillageBackdrop.cottage_door(spec as Dictionary)
		var dp: Vector2 = door[0] as Vector2
		var px2: Vector2 = _world_to_px(ox, oy, g, scale, dp)
		_draw_dot(img, ox, oy, int(px2.x), int(px2.y), 2, Color(0.1, 0.1, 0.1, 1.0))
	## Corner marker: white dot size encodes seed (quick ID in contact sheet)
	_draw_dot(img, ox, oy, int(ox + 12.0), int(oy + 12.0), 2 + mini(seed % 7, 4), Color(0.95, 0.95, 0.9, 1.0))


func _kind_color(kind: String) -> Color:
	match kind:
		"plaza":
			return _C_PLAZA
		"hero":
			return _C_HERO
		"primary":
			return _C_PRIMARY
		"secondary":
			return _C_SECONDARY
		"door":
			return _C_DOOR
		_:
			return Color(0.7, 0.7, 0.7, 0.8)


func _cell_view(layout: VillageLayout, g: Vector2) -> Dictionary:
	## Lambdas capture locals by value in GDScript, so collect points and fold them here.
	var pts: Array[Vector2] = [g, _Layout.HERO_DOOR_STOOP]
	if layout.pond_placed:
		pts.append(layout.pond_center + Vector2(-5.5, -5.5))
		pts.append(layout.pond_center + Vector2(5.5, 5.5))
	for k: int in 8:
		var ang: float = TAU * float(k) / 8.0
		pts.append(g + Vector2(cos(ang), sin(ang)) * layout.lawn_radius)
	for pi: int in layout.paths.size():
		for q: Vector2 in _to_packed(layout.paths[pi]):
			pts.append(q)
	for jp: Variant in layout.junction_points:
		pts.append(jp as Vector2)
	for spec: Variant in layout.cottages:
		pts.append_array(_rect_corners(VillageBackdrop.cottage_exterior_rect(spec as Dictionary)))
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p: Vector2 in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	mn -= Vector2(_VIEW_PAD_M, _VIEW_PAD_M)
	mx += Vector2(_VIEW_PAD_M, _VIEW_PAD_M)
	var half_x: float = maxf(absf(mn.x - g.x), absf(mx.x - g.x))
	var half_y: float = maxf(absf(mn.y - g.y), absf(mx.y - g.y))
	half_x = maxf(half_x, 8.0)
	half_y = maxf(half_y, 8.0)
	var sx: float = float(_CELL_PX) / (2.0 * half_x)
	var sy: float = float(_CELL_PX) / (2.0 * half_y)
	return {"g": g, "scale": minf(sx, sy)}


func _rect_corners(r: Rect2) -> Array[Vector2]:
	return [
		r.position,
		r.position + Vector2(r.size.x, 0.0),
		r.position + r.size,
		r.position + Vector2(0.0, r.size.y),
	] as Array[Vector2]


func _world_to_px(ox: float, oy: float, g: Vector2, scale: float, p: Vector2) -> Vector2:
	var cx: float = float(_CELL_PX) * 0.5
	var cy: float = float(_CELL_PX) * 0.5
	return Vector2(ox + cx + (p.x - g.x) * scale, oy + cy + (p.y - g.y) * scale)


func _draw_poly_world(img: Image, ox: float, oy: float, g: Vector2, scale: float, poly: PackedVector2Array, col: Color, wpx: float) -> void:
	for i: int in maxi(0, poly.size() - 1):
		var a := _world_to_px(ox, oy, g, scale, poly[i])
		var b := _world_to_px(ox, oy, g, scale, poly[i + 1])
		_draw_line(img, ox, oy, a, b, col, int(wpx))


func _draw_line(img: Image, ox: float, oy: float, a: Vector2, b: Vector2, col: Color, thick: int) -> void:
	var steps: int = int(a.distance_to(b)) + 2
	for s: int in steps:
		var t: float = float(s) / float(maxi(1, steps - 1))
		var p: Vector2 = a.lerp(b, t)
		for tx: int in range(-thick / 2, thick / 2 + 1):
			for ty: int in range(-thick / 2, thick / 2 + 1):
				_set_pixel_cell(img, ox, oy, int(p.x) + tx, int(p.y) + ty, col)


func _draw_rect_world(img: Image, ox: float, oy: float, g: Vector2, scale: float, r: Rect2, col: Color) -> void:
	var p0 := _world_to_px(ox, oy, g, scale, r.position)
	var p1 := _world_to_px(ox, oy, g, scale, r.position + Vector2(r.size.x, 0))
	var p2 := _world_to_px(ox, oy, g, scale, r.position + r.size)
	var p3 := _world_to_px(ox, oy, g, scale, r.position + Vector2(0, r.size.y))
	_draw_line(img, ox, oy, p0, p1, col, 1)
	_draw_line(img, ox, oy, p1, p2, col, 1)
	_draw_line(img, ox, oy, p2, p3, col, 1)
	_draw_line(img, ox, oy, p3, p0, col, 1)


func _draw_circle_world(img: Image, ox: float, oy: float, g: Vector2, scale: float, c: Vector2, radius: float, col: Color) -> void:
	var steps: int = int(radius * 3.14159 * 2.0) + 8
	for i: int in steps:
		var ang: float = TAU * float(i) / float(steps)
		var p: Vector2 = c + Vector2(cos(ang), sin(ang)) * radius
		var px := _world_to_px(ox, oy, g, scale, p)
		_draw_dot(img, ox, oy, int(px.x), int(px.y), 1, col)


func _set_pixel_cell(img: Image, ox: float, oy: float, x: int, y: int, col: Color) -> void:
	var x0 := int(ox)
	var y0 := int(oy)
	if x < x0 or x >= x0 + _CELL_PX or y < y0 or y >= y0 + _CELL_PX:
		return
	if x < 0 or x >= img.get_width() or y < 0 or y >= img.get_height():
		return
	img.set_pixel(x, y, col)


func _draw_dot(img: Image, ox: float, oy: float, x: int, y: int, r: int, col: Color) -> void:
	for dx: int in range(-r, r + 1):
		for dy: int in range(-r, r + 1):
			if dx * dx + dy * dy > r * r + 1:
				continue
			_set_pixel_cell(img, ox, oy, x + dx, y + dy, col)


func _to_packed(raw: Variant) -> PackedVector2Array:
	if raw is PackedVector2Array:
		return raw as PackedVector2Array
	var arr: Array = raw as Array
	var out := PackedVector2Array()
	for v: Variant in arr:
		out.append(v as Vector2)
	return out


func _parse_cmdline() -> Dictionary:
	var out: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
			else:
				out[kv[0]] = "true"
	return out
