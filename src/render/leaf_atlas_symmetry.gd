class_name LeafAtlasSymmetry
extends RefCounted

## Mirror-symmetry metrics for a leaf rect in the albedo atlas (alpha channel).
## Used by GUT and headless QA tools.


class SymmetryReport:
	var mirror_mae: float = 0.0
	var mirror_max: float = 0.0
	var centroid_x_offset: float = 0.0 ## Fraction of width; 0 = centered on pixel grid.


static func measure_alpha_patch(img: Image, x0: int, y0: int, rw: int, rh: int) -> SymmetryReport:
	var rep := SymmetryReport.new()
	if rw < 2 or rh < 1:
		return rep
	if img.is_compressed():
		img.decompress()
	var half_w := rw / 2
	var has_mid := rw % 2 == 1
	var sum_diff := 0.0
	var max_diff := 0.0
	var pairs := half_w * rh
	for j in range(rh):
		for i in range(half_w):
			var li := x0 + i
			var ri := x0 + rw - 1 - i
			if has_mid and i == half_w and ri == li:
				continue
			var a_l := img.get_pixel(li, y0 + j).a
			var a_r := img.get_pixel(ri, y0 + j).a
			var d := absf(a_l - a_r)
			sum_diff += d
			max_diff = maxf(max_diff, d)
	rep.mirror_mae = sum_diff / float(pairs)
	rep.mirror_max = max_diff
	var col_sum := PackedFloat32Array()
	col_sum.resize(rw)
	col_sum.fill(0.0)
	var total := 0.0
	for j in range(rh):
		for i in range(rw):
			var a := img.get_pixel(x0 + i, y0 + j).a
			col_sum[i] += a
			total += a
	if total > 0.0001:
		var cx := 0.0
		for i in range(rw):
			cx += float(i) * col_sum[i]
		cx /= total
		rep.centroid_x_offset = (cx - (float(rw) - 1.0) * 0.5) / float(rw)
	return rep


## Column (rect-local) of the brightest long vertical line in the central band: the midrib.
static func detect_midrib_column(
	src: Image, x0: int, y0: int, rw: int, rh: int, band_lo: float = 0.25, band_hi: float = 0.85
) -> int:
	var j_lo := int(rh * band_lo)
	var j_hi := int(rh * band_hi)
	var i_lo := int(rw * 0.3)
	var i_hi := int(rw * 0.7)
	var sums := PackedFloat32Array()
	sums.resize(rw)
	sums.fill(0.0)
	for i in range(i_lo, i_hi):
		var s := 0.0
		for j in range(j_lo, j_hi):
			var c := src.get_pixel(x0 + i, y0 + j)
			s += (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) * c.a
		sums[i] = s
	var best_i := rw / 2
	var best := -1.0
	for i in range(i_lo + 3, i_hi - 3):
		var smooth := 0.0
		for k in range(-3, 4):
			smooth += sums[i + k]
		if smooth > best:
			best = smooth
			best_i = i
	return best_i


## Reflect the cleaner half of a scan leaf about its midrib into the destination rect, re-centred so
## the midrib (and petiole) sits on the rect centre line. Crisp single midrib; drops one-sided damage.
## Midrib line as (x_a, j_a, x_b, j_b) rect-local: the apex (topmost opaque run) and the brightest
## vertical vein in the lower blade. The lowest opaque pixel is often a basal lobe, not the petiole.
## Scan leaves sit a few degrees off vertical.
static func detect_midrib_line(src: Image, x0: int, y0: int, rw: int, rh: int) -> Vector4:
	var apex := _opaque_run_centre(src, x0, y0, rw, rh, 0, 1)
	var low_j := rh * 0.85
	if apex.x < 0.0 or absf(low_j - apex.y) < 1.0:
		var c := float(detect_midrib_column(src, x0, y0, rw, rh))
		return Vector4(c, 0.0, c, float(rh - 1))
	# Truncate/wedge-based leaves end in the petiole at the bottom centre: trust it directly.
	var bottom := _opaque_run_centre(src, x0, y0, rw, rh, rh - 1, -1)
	if bottom.x >= rw * 0.4 and bottom.x <= rw * 0.6:
		return Vector4(apex.x, apex.y, bottom.x, bottom.y)
	# The midrib is the brightest straight line from the apex down through the blade.
	var best_x := float(rw) * 0.5
	var best := -1.0
	var samples := 160
	for xb in range(int(rw * 0.3), int(rw * 0.7)):
		var s := 0.0
		for t_i in range(samples):
			var t := lerpf(0.08, 1.0, float(t_i) / float(samples - 1))
			var px := int(round(lerpf(apex.x, float(xb), t)))
			var py := int(round(lerpf(apex.y, low_j, t)))
			var c := src.get_pixel(x0 + px, y0 + py)
			s += (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) * c.a
		if s > best:
			best = s
			best_x = float(xb)
	return Vector4(apex.x, apex.y, best_x, low_j)


## Mean x of opaque pixels over the first few opaque rows scanning from row j_start in step dj.
static func _opaque_run_centre(src: Image, x0: int, y0: int, rw: int, rh: int, j_start: int, dj: int) -> Vector2:
	var j := j_start
	var found_j := -1
	var sum_x := 0.0
	var count := 0
	var rows := 0
	while j >= 0 and j < rh and rows < 6:
		var row_count := 0
		for i in range(rw):
			if src.get_pixel(x0 + i, y0 + j).a > 0.5:
				sum_x += float(i)
				row_count += 1
		if row_count > 0:
			if found_j < 0:
				found_j = j
			count += row_count
			rows += 1
		j += dj
	if count == 0:
		return Vector2(-1.0, -1.0)
	return Vector2(sum_x / float(count), float(found_j))


static func _axis_at(line: Vector4, j: int) -> float:
	var t := (float(j) - line.y) / (line.w - line.y)
	return lerpf(line.x, line.z, t)


## Picks the half to mirror: a half that would be clipped by the rect edge (wider than the re-centred
## half-width) loses; then the half without damage (brown necrosis / bite edges); then the larger one.
static func reflect_leaf_into(src: Image, dst: Image, x0: int, y0: int, rw: int, rh: int) -> Array:
	if src.is_compressed():
		src.decompress()
	var line := detect_midrib_line(src, x0, y0, rw, rh)
	var axis := int(round((line.x + line.z) * 0.5))
	var limit := rw / 2 - 2
	var clip_l := _half_clipped(src, x0, y0, rw, rh, line, -1, limit)
	var clip_r := _half_clipped(src, x0, y0, rw, rh, line, 1, limit)
	var brown_l := _half_brown(src, x0, y0, rw, rh, axis, -1)
	var brown_r := _half_brown(src, x0, y0, rw, rh, axis, 1)
	var tol := 0.002 * float(rw * rh)
	var dir := 1
	if absf(clip_l - clip_r) > tol:
		dir = 1 if clip_r < clip_l else -1
	elif absf(brown_l - brown_r) > tol:
		dir = 1 if brown_r < brown_l else -1
	else:
		var area_l := _half_opaque(src, x0, y0, rw, rh, axis, -1)
		var area_r := _half_opaque(src, x0, y0, rw, rh, axis, 1)
		dir = 1 if area_r >= area_l else -1
	reflect_with(src, dst, x0, y0, rw, rh, line, dir, false)
	return [line, dir]


## Opaque pixels on side `dir` lying `limit` or more columns from the (tilted) midrib.
static func _half_clipped(
	src: Image, x0: int, y0: int, rw: int, rh: int, line: Vector4, dir: int, limit: int
) -> float:
	var count := 0.0
	for j in range(rh):
		var axis := int(round(_axis_at(line, j)))
		for k in range(limit, rw):
			var i := axis + dir * k
			if i < 0 or i >= rw:
				break
			if src.get_pixel(x0 + i, y0 + j).a > 0.5:
				count += 1.0
	return count


static func _half_opaque(src: Image, x0: int, y0: int, rw: int, rh: int, axis: int, dir: int) -> float:
	var count := 0.0
	for j in range(rh):
		for k in range(1, rw):
			var i := axis + dir * k
			if i < 0 or i >= rw:
				break
			if src.get_pixel(x0 + i, y0 + j).a > 0.5:
				count += 1.0
	return count


## Brown / necrotic and hole-edge pixels on one side of `axis` (rect-local column).
static func _half_brown(src: Image, x0: int, y0: int, rw: int, rh: int, axis: int, dir: int) -> float:
	var count := 0.0
	for j in range(rh):
		for k in range(1, rw):
			var i := axis + dir * k
			if i < 0 or i >= rw:
				break
			var c := src.get_pixel(x0 + i, y0 + j)
			# Pale veins run r ≈ 0.94·g; necrosis and bite edges are warmer than green.
			if c.a > 0.5 and c.r > c.g * 1.02:
				count += 1.0
	return count


## Reflect `src` row-by-row about the midrib `line` (see detect_midrib_line), taking the half on side
## `dir` (±1), re-centred in the rect. For tangent-space normal maps pass flip_x so the mirrored half's
## X component is negated. A 2 px rect border is cleared so filtering never picks up a seam.
static func reflect_with(
	src: Image, dst: Image, x0: int, y0: int, rw: int, rh: int, line: Vector4, dir: int, flip_x: bool,
	clear: Color = Color(0, 0, 0, 0)
) -> void:
	if src.is_compressed():
		src.decompress()
	var half := rw / 2
	var odd := rw % 2 == 1
	var border := 2
	for j in range(rh):
		var y := y0 + j
		var axis := int(round(_axis_at(line, j)))
		var edge_row := j < border or j >= rh - border
		for k in range(half + (1 if odd else 0)):
			var si := axis + dir * k
			var c := clear
			if si >= 0 and si < rw and not edge_row and k < half - border:
				c = src.get_pixel(x0 + si, y)
			var right_i: int
			var left_i: int
			if odd:
				right_i = half + k
				left_i = half - k
			else:
				right_i = half + k
				left_i = half - 1 - k
			var flipped := Color(1.0 - c.r, c.g, c.b, c.a) if flip_x else c
			if right_i < rw:
				dst.set_pixel(x0 + right_i, y, c if dir > 0 else flipped)
			if left_i >= 0:
				dst.set_pixel(x0 + left_i, y, flipped if dir > 0 else c)


static func mean_alpha_fill(img: Image, x0: int, y0: int, rw: int, rh: int) -> float:
	var sum := 0.0
	var n := rw * rh
	for j in range(rh):
		for i in range(rw):
			sum += img.get_pixel(x0 + i, y0 + j).a
	return sum / float(n)


## Luminance / mask symmetry for a captured leaf-card PNG (crops to foreground bbox).
static func measure_luma_patch(img: Image, bg: Color, fg_threshold: float = 0.04) -> SymmetryReport:
	var w := img.get_width()
	var h := img.get_height()
	var bg_l := bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114
	var min_i := w
	var min_j := h
	var max_i := -1
	var max_j := -1
	var lumas := PackedFloat32Array()
	lumas.resize(w * h)
	var mask := PackedFloat32Array()
	mask.resize(w * h)
	for j in range(h):
		for i in range(w):
			var c := img.get_pixel(i, j)
			var luma := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			lumas[j * w + i] = luma
			var fg := c.a >= 0.5 if c.a < 0.98 else maxf(absf(luma - bg_l), absf(c.a - bg.a)) >= fg_threshold
			var m := 1.0 if fg else 0.0
			mask[j * w + i] = m
			if fg:
				min_i = mini(min_i, i)
				max_i = maxi(max_i, i)
				min_j = mini(min_j, j)
				max_j = maxi(max_j, j)
	var rep := SymmetryReport.new()
	if max_i < min_i:
		return rep
	var bw := max_i - min_i + 1
	var bh := max_j - min_j + 1
	var half_w := bw / 2
	var sum_diff := 0.0
	var max_diff := 0.0
	var pair_count := 0
	var total_mass := 0.0
	var col_sum := PackedFloat32Array()
	col_sum.resize(bw)
	col_sum.fill(0.0)
	for j in range(min_j, max_j + 1):
		for i in range(min_i, max_i + 1):
			var bi := i - min_i
			if mask[j * w + i] < 0.5:
				continue
			total_mass += 1.0
			col_sum[bi] += 1.0
	for j in range(min_j, max_j + 1):
		for bi in range(half_w):
			var i_l := min_i + bi
			var i_r := max_i - bi
			if mask[j * w + i_l] < 0.5 or mask[j * w + i_r] < 0.5:
				continue
			pair_count += 1
			var d := absf(lumas[j * w + i_l] - lumas[j * w + i_r])
			sum_diff += d
			max_diff = maxf(max_diff, d)
	if pair_count > 0:
		rep.mirror_mae = sum_diff / float(pair_count)
	rep.mirror_max = max_diff
	if total_mass > 0.0:
		var cx := 0.0
		for bi in range(bw):
			cx += float(bi) * col_sum[bi]
		cx /= total_mass
		rep.centroid_x_offset = (cx - (float(bw) - 1.0) * 0.5) / float(bw)
	return rep


## Foreground mask mirror symmetry (silhouette only) on a capture PNG.
static func measure_mask_patch(img: Image, bg: Color, fg_threshold: float = 0.04) -> SymmetryReport:
	var w := img.get_width()
	var h := img.get_height()
	var bg_l := bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114
	var min_i := w
	var max_i := -1
	var min_j := h
	var max_j := -1
	var mask := PackedFloat32Array()
	mask.resize(w * h)
	for j in range(h):
		for i in range(w):
			var c := img.get_pixel(i, j)
			var luma := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			var fg := c.a >= 0.5 if c.a < 0.98 else maxf(absf(luma - bg_l), absf(c.a - bg.a)) >= fg_threshold
			var m := 1.0 if fg else 0.0
			mask[j * w + i] = m
			if fg:
				min_i = mini(min_i, i)
				max_i = maxi(max_i, i)
				min_j = mini(min_j, j)
				max_j = maxi(max_j, j)
	var rep := SymmetryReport.new()
	if max_i < min_i:
		return rep
	var bw := max_i - min_i + 1
	var half_w := bw / 2
	var sum_diff := 0.0
	var max_diff := 0.0
	var pair_count := 0
	var col_sum := PackedFloat32Array()
	col_sum.resize(bw)
	col_sum.fill(0.0)
	var total_mass := 0.0
	for j in range(min_j, max_j + 1):
		for bi in range(half_w):
			var i_l := min_i + bi
			var i_r := max_i - bi
			var ml := mask[j * w + i_l]
			var mr := mask[j * w + i_r]
			if ml < 0.5 and mr < 0.5:
				continue
			pair_count += 1
			var d := absf(ml - mr)
			sum_diff += d
			max_diff = maxf(max_diff, d)
		for i in range(min_i, max_i + 1):
			if mask[j * w + i] > 0.5:
				total_mass += 1.0
				col_sum[i - min_i] += 1.0
	if pair_count > 0:
		rep.mirror_mae = sum_diff / float(pair_count)
	rep.mirror_max = max_diff
	if total_mass > 0.0:
		var cx := 0.0
		for bi in range(bw):
			cx += float(bi) * col_sum[bi]
		cx /= total_mass
		rep.centroid_x_offset = (cx - (float(bw) - 1.0) * 0.5) / float(bw)
	return rep
