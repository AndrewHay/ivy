## Profile village grass placement vs MultiMesh chunk build (ivy-k9r0).
extends Node


func _ready() -> void:
	var classic_ctx := _classic_ctx()
	var t0 := Time.get_ticks_usec()
	var classic_grass := VillageScatterPositions.grass_blade_positions(classic_ctx)
	var place_us := Time.get_ticks_usec() - t0
	var gen_ctx := _generated_ctx(1)
	t0 = Time.get_ticks_usec()
	var gen_grass := VillageScatterPositions.grass_blade_positions(gen_ctx)
	var gen_place_us := Time.get_ticks_usec() - t0
	print(
		"[grass-profile] placement classic=%d tufts %.2fms generated=%d tufts %.2fms"
		% [classic_grass.size(), place_us / 1000.0, gen_grass.size(), gen_place_us / 1000.0])
	var chunk_us := _profile_chunk_build(classic_grass)
	var gen_chunk_us := _profile_chunk_build(gen_grass)
	print(
		"[grass-profile] chunk_build classic=%.2fms generated=%.2fms"
		% [chunk_us / 1000.0, gen_chunk_us / 1000.0])
	get_tree().quit(0)


func _profile_chunk_build(all: Array) -> int:
	var mesh := VillageGrassMesh.blade_tuft_mesh()
	var tuft_aabb := mesh.get_aabb()
	var t0 := Time.get_ticks_usec()
	var buckets: Dictionary = {}
	const CHUNK := 6.0
	for t in all:
		var ix := int(floor(t.origin.x / CHUNK))
		var iz := int(floor(t.origin.z / CHUNK))
		var key := Vector2i(ix, iz)
		if not buckets.has(key):
			buckets[key] = [] as Array[Transform3D]
		(buckets[key] as Array[Transform3D]).append(t)
	var chunk_count := 0
	for key in buckets.keys():
		var transforms: Array[Transform3D] = buckets[key]
		VillageBackdrop._grass_chunk_custom_aabb(transforms, tuft_aabb)
		var buf := PackedFloat32Array()
		buf.resize(transforms.size() * 12)
		for i in range(transforms.size()):
			var tr := transforms[i]
			var b := i * 12
			buf[b + 0] = tr.basis.x.x; buf[b + 1] = tr.basis.y.x; buf[b + 2] = tr.basis.z.x
			buf[b + 3] = tr.origin.x
			buf[b + 4] = tr.basis.x.y; buf[b + 5] = tr.basis.y.y; buf[b + 6] = tr.basis.z.y
			buf[b + 7] = tr.origin.y
			buf[b + 8] = tr.basis.x.z; buf[b + 9] = tr.basis.y.z; buf[b + 10] = tr.basis.z.z
			buf[b + 11] = tr.origin.z
		chunk_count += 1
	var elapsed := Time.get_ticks_usec() - t0
	print("[grass-profile]   chunks=%d instances=%d" % [chunk_count, all.size()])
	return elapsed


func _classic_ctx() -> VillageGrassExclusionContext:
	var path_stones := VillageScatterPositions.path_stone_transforms(
		VillageBackdrop.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).length() < 4.5 \
				or VillageBackdrop.inside_any_cottage(Vector2(cx, cz), 0.2))
	var bushes := VillageScatterPositions.bush_common_positions()
	return VillageGrassExclusionContext.for_village(path_stones, bushes)


func _generated_ctx(seed: int) -> VillageGrassExclusionContext:
	var layout := VillageLayout.generate(seed)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var path_stones := VillageScatterPositions.path_stone_transforms(
		layout.path_polylines(),
		func(cx: float, cz: float) -> bool:
			return Vector2(cx, cz).distance_to(VillageLayout.HERO_DOOR_STOOP) < 4.5 \
				or layout.inside_any_cottage(Vector2(cx, cz), 0.2),
		layout.stone_seed, layout.min_stone_spacing)
	var bushes := VillageScatterPositions.bush_common_positions(
		layout.cottages, layout.bush_filler_inner, layout.bush_filler_outer,
		layout.hamlet_centre_xz)
	return VillageGrassExclusionContext.for_layout(
		layout.paths,
		func(p: Vector2) -> bool: return layout.inside_any_cottage(p, 0.35),
		path_stones, bushes, layout.hamlet_centre_xz, VillageLayout.HERO_DOOR_STOOP, true,
		layout.cottages)
