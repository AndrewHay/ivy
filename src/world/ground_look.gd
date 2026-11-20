## GroundLook (ivy-82zn.17.1): the lawn's grass textures and the under-tree texture.
## One implementation for the game and the terrain playground (G7): VillageTerrain.apply_ground_material
## calls apply() on the lawn and far-hills materials, and the backdrop / playground bake one tree-cover
## mask per layout and hand it to apply_tree_mask(). Uniforms live in ground_look.gdshaderinc.
## Textures: ambientCG Grass005 (open lawn) and Grass004 (under trees), CC0, 1K (assets/CREDITS.md).
class_name GroundLook
extends RefCounted

const OPEN_ALBEDO := "res://assets/materials/ground/Grass005/Grass005_1K_Color.jpg"
const OPEN_NORMAL := "res://assets/materials/ground/Grass005/Grass005_1K_NormalGL.jpg"
const SHADE_ALBEDO := "res://assets/materials/ground/Grass004/Grass004_1K_Color.jpg"
const SHADE_NORMAL := "res://assets/materials/ground/Grass004/Grass004_1K_NormalGL.jpg"

## Canopy radius of a FarTreeline Pine_2 at instance scale 1 (m); scaled by the instance basis.
const PINE_CANOPY_R_M := 2.4
## The baked closeness falls from 1 at the trunk to 0 at this many canopy radii.
const MASK_REACH_CANOPIES := 2.0
## Mask covers the lawn and the lit meadow ring (lawn_radius + 50 m) with a margin.
const MASK_MARGIN_M := 60.0
const MASK_PX := 512


static func apply(mat: ShaderMaterial, p: VillageTerrainParams) -> void:
	mat.set_shader_parameter("u_ground_tex_on", p.ground_tex_on)
	mat.set_shader_parameter("u_ground_tex_scale_m", p.ground_tex_scale_m)
	mat.set_shader_parameter("u_ground_tex_strength", p.ground_tex_strength)
	mat.set_shader_parameter("u_ground_tex_brightness", p.ground_tex_brightness)
	mat.set_shader_parameter("u_ground_macro", p.ground_macro)
	mat.set_shader_parameter("u_ground_saturation", p.ground_saturation)
	mat.set_shader_parameter("u_ground_normal_strength", p.ground_normal_strength)
	mat.set_shader_parameter("u_shade_tex_strength", p.ground_shade_strength)
	mat.set_shader_parameter("u_shade_edge_lo", p.ground_shade_edge_lo)
	mat.set_shader_parameter("u_shade_edge_hi", p.ground_shade_edge_hi)
	mat.set_shader_parameter("u_blade_ground_tint", p.ground_blade_tint)  # grass_blade.gdshader only
	if p.ground_tex_on:
		mat.set_shader_parameter("u_grass_open_albedo", load(OPEN_ALBEDO))
		mat.set_shader_parameter("u_grass_open_normal", load(OPEN_NORMAL))
		mat.set_shader_parameter("u_grass_shade_albedo", load(SHADE_ALBEDO))
		mat.set_shader_parameter("u_grass_shade_normal", load(SHADE_NORMAL))


## Tree canopies near the lawn as Vector3(x, z, radius_m), layout frame: the FarTreeline pines.
## (The far HillForest starts at 110 m, past the textured ring.)
static func tree_canopies(layout: VillageLayout) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for t: Transform3D in VillageScatterPositions.forest_tree_positions(layout):
		var s := t.basis.get_scale().x
		out.append(Vector3(t.origin.x, t.origin.z, PINE_CANOPY_R_M * s))
	return out


## Layout-frame rect the mask covers (centred on the hamlet centre).
static func mask_rect(layout: VillageLayout) -> Rect2:
	var c := layout.hamlet_centre_xz if layout.is_generated else Vector2.ZERO
	var half := layout.lawn_radius + MASK_MARGIN_M
	return Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)


## Closeness to the nearest canopy, 1 at a trunk falling to 0 at MASK_REACH_CANOPIES radii (R8).
static func tree_mask(canopies: Array[Vector3], rect: Rect2, px: int = MASK_PX) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(px * px)
	data.fill(0)
	var cell := rect.size.x / float(px)
	for c: Vector3 in canopies:
		var reach := maxf(c.z * MASK_REACH_CANOPIES, cell)
		var lo_x := clampi(int(floor((c.x - reach - rect.position.x) / cell)), 0, px - 1)
		var hi_x := clampi(int(ceil((c.x + reach - rect.position.x) / cell)), 0, px - 1)
		var lo_y := clampi(int(floor((c.y - reach - rect.position.y) / cell)), 0, px - 1)
		var hi_y := clampi(int(ceil((c.y + reach - rect.position.y) / cell)), 0, px - 1)
		for iy in range(lo_y, hi_y + 1):
			var wz := rect.position.y + (float(iy) + 0.5) * cell
			for ix in range(lo_x, hi_x + 1):
				var wx := rect.position.x + (float(ix) + 0.5) * cell
				var d := Vector2(wx - c.x, wz - c.y).length()
				var v := int(round(clampf(1.0 - d / reach, 0.0, 1.0) * 255.0))
				var k := iy * px + ix
				if v > data[k]:
					data[k] = v
	var img := Image.create_from_data(px, px, false, Image.FORMAT_R8, data)
	return ImageTexture.create_from_image(img)


## Hands the mask to a ground material. world_offset = the layout frame's world origin (backdrop node
## position, or the playground stage offset), so the shader can sample with world xz.
static func apply_tree_mask(mat: ShaderMaterial, tex: Texture2D, rect: Rect2, world_offset: Vector2) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("u_tree_mask", tex)
	mat.set_shader_parameter("u_tree_mask_rect",
		Vector4(rect.position.x + world_offset.x, rect.position.y + world_offset.y, rect.size.x, rect.size.y))
