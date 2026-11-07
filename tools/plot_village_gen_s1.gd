## Headless debug plot: village_gen stage-1 paths (curves + pursuit).
extends SceneTree

const PathGrowerScr := preload("res://src/world/village_gen/path_grower.gd")
const OccupancyGridScr := preload("res://src/world/village_gen/occupancy_grid.gd")
const OUT_DIR := "res://.tmp/village-gen-v3/s1"
const OUT_PATH := OUT_DIR + "/s1_preview.png"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var img := Image.create(520, 400, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.96, 0.96, 0.94, 1))
	var margin := 28.0
	var wmin := Vector2(-5.0, -8.0)
	var wmax := Vector2(45.0, 32.0)
	var start := Vector2(0.0, 12.0)
	for si in range(6):
		var p := PathGrowerScr.GrowParams.new()
		p.seed = 400 + si * 97
		var poly: PackedVector2Array = PathGrowerScr.grow_free(start, 0.0, 26.0, p, null, null)
		_draw_poly(img, poly, wmin, wmax, margin, Color(0.1, 0.25, 0.55, 1.0), 1.8)
	var g = OccupancyGridScr.new(Rect2(0, 0, 50, 30), 1.0)
	g.block_rect(Rect2(20, 5, 6, 20), 0.0)
	var guide: PackedVector2Array = g.astar(Vector2(5, 15), Vector2(45, 15))
	_draw_poly(img, guide, wmin, wmax, margin, Color(0.55, 0.55, 0.55, 1.0), 1.2)
	var pp := PathGrowerScr.GrowParams.new()
	pp.seed = 240424020
	var purs: PackedVector2Array = PathGrowerScr.grow_pursuit(Vector2(5, 15), guide, pp, g)
	_draw_poly(img, purs, wmin, wmax, margin, Color(0.85, 0.2, 0.15, 1.0), 2.2)
	var err := img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	if err != OK:
		push_error("save failed %d" % err)
	print("wrote ", OUT_PATH)
	quit()


func _world_to_px(p: Vector2, wmin: Vector2, wmax: Vector2, margin: float, iw: int, ih: int) -> Vector2i:
	var nx := (p.x - wmin.x) / maxf(wmax.x - wmin.x, 1e-6)
	var ny := (p.y - wmin.y) / maxf(wmax.y - wmin.y, 1e-6)
	var px := int(margin + nx * (float(iw) - 2.0 * margin))
	var py := int(float(ih) - margin - ny * (float(ih) - 2.0 * margin))
	return Vector2i(px, py)


func _draw_poly(
	img: Image, poly: PackedVector2Array, wmin: Vector2, wmax: Vector2, margin: float, col: Color, rad: float
) -> void:
	var iw := img.get_width()
	var ih := img.get_height()
	for i in range(poly.size() - 1):
		var a := _world_to_px(poly[i], wmin, wmax, margin, iw, ih)
		var b := _world_to_px(poly[i + 1], wmin, wmax, margin, iw, ih)
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y)) + 1
		for s in range(steps + 1):
			var t := float(s) / float(steps)
			var px := int(lerpf(float(a.x), float(b.x), t))
			var py := int(lerpf(float(a.y), float(b.y), t))
			_fill_disk(img, px, py, rad, col)


func _fill_disk(img: Image, cx: int, cy: int, r: float, col: Color) -> void:
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy <= r * r:
				var x := cx + dx
				var y := cy + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixelv(Vector2i(x, y), col)
