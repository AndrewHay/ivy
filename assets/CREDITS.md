# Asset Credits

Every third-party asset committed to this repository is **CC0 1.0 Universal** or
**CC-BY**. For CC0 attribution is not legally required but is recorded anyway, for
provenance; for CC-BY the row below *is* the attribution. NC and ND licenses are
excluded — see the asset constraints in `DESIGN.md` for why ND in particular can
never be made admissible here.

Everything currently listed happens to be CC0.

**Whole libraries** downloaded to audition pieces from are recorded separately in
`ASSET_LIBRARIES.md`, along with where the untracked full copies live. This file
covers only what is committed.

---

## ambientCG (https://ambientcg.com) — CC0 1.0

License: https://docs.ambientcg.com/license

| Asset ID | Used for | Path |
|---|---|---|
| `LeafSet017` | **Primary ivy leaves.** Photographed *Hedera helix*; 6 leaves, muted weathered sage-green. Chosen for the classic palmate silhouette and flat photography that suits leaf cards. | `plants/ivy/LeafSet017/` |
| `LeafSet029` | **Seasonal leaf variation.** Brighter green plus autumn-tinted leaves; also ships a Scattering map for backlit translucency. | `plants/ivy/LeafSet029/` |
| `Bricks094` | **Primary tower material.** Old weathered red brick. Chosen for contrast — green ivy reads clearly against warm red. | `materials/brick/Bricks094/` |
| `Bricks102` | **Alternate tower material.** Warm sandy medieval stonework, Cotswolds/cottagecore feel. Kept for in-engine A/B. | `materials/brick/Bricks102/` |
| `RoofingTiles014B` | **Mesh structure roof cap.** Weathered round roofing tiles (~2.9 m patch); pairs with stone walls on square/tower hero meshes. | `materials/roof/RoofingTiles014B/` |

### Re-downloading

ambientCG download URLs are deterministic:

```
https://ambientcg.com/get?file=<AssetID>_2K-JPG.zip
```

So the five archives above are `LeafSet017_2K-JPG.zip`, `LeafSet029_2K-JPG.zip`,
`Bricks094_2K-JPG.zip`, `Bricks102_2K-JPG.zip`, and `RoofingTiles014B_2K-JPG.zip`. Asset metadata (including the full
map list and available resolutions) can be queried without downloading anything:

```
https://ambientcg.com/api/v2/full_json?id=<AssetID>
```

### Notes on the map set

- **Use `_NormalGL`, not `_NormalDX`.** Godot uses the OpenGL normal convention.
  The DirectX variants were deleted from this repo to prevent them being wired up
  by mistake (they produce inverted lighting).
- `.blend`, `.usdc`, and `.mtlx` files shipped in the archives were removed; Godot
  does not read them.
- Each ambientCG archive also ships a ready-made Godot `.tres` material.

### Derived files

`*_Leaves_RGBA.png` are **generated, not downloaded**. ambientCG ships colour and
opacity as separate JPGs, so they were composited into a single RGBA PNG for use with
Godot's alpha-scissor materials:

```
magick <Set>_2K-JPG_Color.jpg <Set>_2K-JPG_Opacity.jpg \
       -alpha off -compose CopyOpacity -composite <Set>_Leaves_RGBA.png
```

`leaf_atlas.json` records per-leaf UV sub-rects. These were extracted from the alpha
channel by connected-component analysis, so leaf cards can index individual leaves
rather than sampling the whole atlas.

---

## Quaternius — Medieval Village MegaKit (https://quaternius.itch.io/medieval-village-megakit) — CC0 1.0

License: CC0 1.0 Universal (verified in `License_Standard.txt` shipped with the kit).
Author: Quaternius (https://quaternius.com).

Both M2.6 structures are **offline assemblies** of kit glTF pieces (hero mesh
keeps original kit UVs; sim mesh holds bridged closed solids for collision and
SDF baking). Assembly recipe and conditioning notes live in `ASSET_LIBRARIES.md`.
The six kit vine props were excluded — ivy is simulator-generated.

| Asset ID | Used for | Path |
|---|---|---|
| `square_hero` | **Square building — phase A hero render mesh.** One-storey 6 m × 6 m wall-centre footprint, 3.42 m height; original kit materials and UVs. | `structures/square_hero.glb`, `structures/square_hero_T_*.png` |
| `square_sim` | **Square building — phase A collision proxy and SDF source.** Watertight bridged solids (0.45 m wall target); baked to `square_sim.sdf`. | `structures/square_sim.glb`, `structures/square_sim.sdf` |
| `tower_hero` | **Tower — phase B hero render mesh.** Squat two-storey probe (4.37 m footprint, 6.54 m height); original kit materials and UVs. | `structures/tower_hero.glb`, `structures/tower_hero_T_*.png` |
| `tower_sim` | **Tower — phase B collision proxy and SDF source.** Watertight bridged solids (0.45 m wall target); baked to `tower_sim.sdf`. | `structures/tower_sim.glb`, `structures/tower_sim.sdf` |

Shared kit textures (`T_UnevenBrick_*`, `T_Plaster_*`, `T_RockTrim_*`,
`T_WoodTrim_*`, `T_MetalOrnaments_*`) are embedded beside each hero GLB.

### Re-downloading

Free Standard tier: https://quaternius.itch.io/medieval-village-megakit

The committed meshes are not raw kit exports — they are produced by the offline
build script recorded in `ASSET_LIBRARIES.md` (`.tmp/assethunt/build.py` when
present locally). Rebuilding from the kit requires that script and the full
untracked library under `assets/_local/medieval_village_megakit/`.

---

## M4 climbing-plant reference photographs (`assets/reference/climbing-plants/`)

Inspiration-only stock photos for rubric comparison. **CC0 / Public Domain only.**

### `hedera-helix/` (`ivy-mx5.5`)

| File | Source | Author | License | Retrieved |
|------|--------|--------|---------|-----------|
| `mat_edge.jpg` | https://skitterphoto.com/photos/2979/climbing-ivy | Peter Heeling | CC0 1.0 (Skitterphoto) | 2026-08-30 |
| `leaf_detail.jpg` | https://commons.wikimedia.org/wiki/File:Climbing_ivy_on_fence.jpg | Ron Clausen | CC0 1.0 | 2026-08-30 |
| `silhouette.jpg` | Owner-provided (brick facade, ivy mat + window awnings) | Andrew Hay | CC0 1.0 (author dedication) | 2026-08-30 |

### `vitis-vinifera/` (`ivy-mx5.6`)

| File | Source | Author | License | Retrieved |
|------|--------|--------|---------|-----------|
| `mat_edge.jpg` | https://commons.wikimedia.org/wiki/File:Grape_Vine_on_rock_wall.jpg | Almapayokels | CC0 1.0 | 2026-08-30 |
| `leaf_detail.jpg` | https://commons.wikimedia.org/wiki/File:Young_grapevine_leaves_1.jpg | W.carter | CC0 1.0 | 2026-08-30 |
| `silhouette.jpg` | https://commons.wikimedia.org/wiki/File:Small_greenhouse_with_grapevines_escaping.jpg | W.carter | CC0 1.0 | 2026-08-30 |

---

---

## Quaternius Medieval Village MegaKit — committed backdrop tier — CC0 1.0

Source: https://quaternius.itch.io/medieval-village-megakit  
Author: Quaternius (https://quaternius.com)  
License: CC0 1.0 Universal (public domain) — verified in `License_Standard.txt` within archive  
Path: `assets/backdrop/`

### Committed pieces (`assets/backdrop/pieces/`)

18 pieces; cottages are generated from them by `VillageBackdrop.COTTAGES` (ivy-2or)  
(* = ivy-3cx slice 1; ** = ivy-3cx.7 slices-merged):

| Piece | Role |
|---|---|
| `Wall_Plaster_Straight.gltf` + `.bin` | Plain 1-storey plaster wall (2 m × 3.125 m) — side/back faces |
| `Wall_Plaster_Window_Wide_Flat.gltf` + `.bin` | Plaster wall with wide window — hero-facing faces |
| `Roof_Front_Brick4.gltf` + `.bin` | Gable-end infill (4 m span) — both ends of every cottage (ivy-2or) |
| `Roof_2x4_RoundTile.gltf` + `.bin` | Low-profile round-tile roof (2 m × 4 m) — superseded by 4×N roofs in ivy-2or |
| `Prop_Chimney.gltf` + `.bin` | Chimney stack — one per plaster cottage |
| `Wall_Plaster_Door_Flat.gltf` + `.bin` | * Door-frame plaster wall — hero-facing cottage fronts |
| `Door_1_Flat.gltf` + `.bin` | * Door leaf for the door frame — lived-in read |
| `Prop_Chimney2.gltf` + `.bin` | * Taller chimney shaft — brick-accent cottages |
| `Wall_UnevenBrick_Straight.gltf` + `.bin` | * Brick-accent wall — material variety on CB/CF/CD |
| `Roof_RoundTiles_4x4.gltf` + `.bin` | ** Big 4×4 hip roof — superseded; kept for reference |
| `Roof_RoundTiles_4x6.gltf` + `.bin` | ** ivy-2or: 4 m × 6 m round-tile roof — 3-bay cottages (CB, CC, CE, CF, CG) |
| `Roof_RoundTiles_4x8.gltf` + `.bin` | ** ivy-2or: 4 m × 8 m round-tile roof — 4-bay cottages (CA, CD) |
| `Prop_WoodenFence_Single.gltf` + `.bin` | ** Single fence panel — cottage gate details |
| `Prop_WoodenFence_Extension1.gltf` + `.bin` | ** Fence extension panel — prepared for future use |
| `Prop_Wagon.gltf` + `.bin` | ** Wagon prop — committed for future placement |
| `Prop_Crate.gltf` + `.bin` | ** Crates — clutter beside CE |
| `WindowShutters_Wide_Flat_Closed.gltf` + `.bin` | ** Closed shutters — CA window detail |
| `Balcony_Simple_Straight.gltf` + `.bin` | ** Balcony piece — committed for future use |

### Committed textures (`assets/backdrop/textures/`) — medieval kit

18 shared PBR maps; normal maps are the OpenGL-convention variants from the kit's  
`Textures/Normals Godot-Unity/` subfolder (* = added in ivy-3cx slice 1):

`T_WoodTrim_BaseColor.png`, `T_WoodTrim_Normal.png` *(OpenGL)*, `T_WoodTrim_Roughness.png`,  
`T_Plaster_BaseColor.png`, `T_Plaster_Normal.png` *(OpenGL)*, `T_Plaster_ORM.png`,  
`T_Brick_BaseColor.png`, `T_Brick_Normal.png` *(OpenGL)*, `T_Brick_Roughness.png`,  
`T_RoundTiles_BaseColor.png`, `T_RoundTiles_Normal.png` *(OpenGL)*, `T_RoundTiles_Roughness.png`,  
`T_RockTrim_BaseColor.png`, `T_RockTrim_Normal.png` *(OpenGL)*, `T_RockTrim_ORM.png`,  
`T_UnevenBrick_BaseColor.png` *(*)*, `T_UnevenBrick_Normal.png` *(OpenGL, *)*, `T_UnevenBrick_Roughness.png` *(*)*

All textures' image URIs in the committed `.gltf` files have been rewritten from
the kit-relative form (`T_*.png`) to `../textures/T_*.png` so the shared folder
dedups the few textures across many pieces.

Vine piece exclusion (`Prop_Vine1/2/4/5/6/9` and `T_VineLeaf.png`) is documented
in `ASSET_LIBRARIES.md`. No vine piece or texture was copied into this repository.

---

## Quaternius Stylized Nature Megakit — committed backdrop tier — CC0 1.0

Source: https://quaternius.itch.io/stylized-nature-megakit  
Author: Quaternius (https://quaternius.com)  
License: CC0 1.0 Universal (public domain)  
Tier: Standard  
Archive SHA-256: `298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`  
Archive size: 104,088,529 bytes  
Retrieved: 2026-10-05  
Path: `assets/backdrop/`

### Committed pieces (`assets/backdrop/pieces/`) — nature kit

15 pieces used as-built in `village_backdrop.tscn` (ivy-3cx.7 slices-merged):

| Piece | Role |
|---|---|
| `CommonTree_1.gltf` + `.bin` | Broad-leaf common tree — mid-distance right cluster |
| `CommonTree_2.gltf` + `.bin` | Broad-leaf common tree variant — far treeline |
| `CommonTree_3.gltf` + `.bin` | Broad-leaf common tree variant — far treeline |
| `Pine_1.gltf` + `.bin` | Conifer — mid-distance left cluster |
| `Pine_2.gltf` + `.bin` | Conifer variant — far treeline |
| `Pine_3.gltf` + `.bin` | Conifer variant — far treeline |
| `TwistedTree_1.gltf` + `.bin` | Gnarled deciduous — far treeline silhouette interest |
| `Bush_Common.gltf` + `.bin` | ivy-2or: Plain green bush — village scatter (Scatter_Bush_Common MultiMesh) |
| `Bush_Common_Flowers.gltf` + `.bin` | Flowering bush — near garden (Director rule: flowers OK, plain green excluded) |
| `Flower_3_Group.gltf` + `.bin` | Flower cluster — near garden ground cover |
| `Flower_4_Group.gltf` + `.bin` | Flower cluster variant — near garden ground cover |
| `Grass_Wispy_Short.gltf` + `.bin` | Wispy grass tufts — near garden scatter |
| `Clover_1.gltf` + `.bin` | Clover patch — near garden ground cover |
| `Rock_Medium_1.gltf` + `.bin` | Medium rock — accent near garden |
| `RockPath_Round_Wide.gltf` + `.bin` | Round stepping stone (~2 m dia.) — superseded by Small variants |
| `RockPath_Round_Small_1.gltf` + `.bin` | ivy-2or: Small stepping stone — village path MultiMesh (Scatter_Path_0) |
| `RockPath_Round_Small_2.gltf` + `.bin` | ivy-2or: Small stepping stone variant 2 — village path MultiMesh (Scatter_Path_1) |
| `RockPath_Round_Small_3.gltf` + `.bin` | ivy-2or: Small stepping stone variant 3 — village path MultiMesh (Scatter_Path_2) |
| `Pebble_Round_1.gltf` + `.bin` | Small pebble — committed for future use |

### Committed textures (`assets/backdrop/textures/`) — nature kit

12 diffuse/normal maps (normals are the kit's OpenGL-convention files, named `*_Normal.png`):

`Bark_NormalTree.png`, `Bark_NormalTree_Normal.png`,  
`Bark_TwistedTree.png`, `Bark_TwistedTree_Normal.png`,  
`Flowers.png`, `Grass.png`, `Leaf_Pine_C.png`,  
`Leaves.png`, `Leaves_NormalTree_C.png`, `Leaves_TwistedTree_C.png`,  
`PathRocks_Diffuse.png`, `Rocks_Diffuse.png`

Image URIs in committed `.gltf` files have been rewritten from bare filenames  
(`Filename.png`) to `../textures/Filename.png` for the shared folder layout.

Vine exclusion policy (`Prop_Vine*`, `T_VineLeaf`) applies to this kit as well —  
no vine piece or texture was copied. See `ASSET_LIBRARIES.md`.

---

## Not used

- **HDRI skies** were considered and rejected. The simulator computes true solar
  position (spec §5), so a procedural sky driven by a `DirectionalLight3D` couples the
  visible sun to the growth model. Static HDRIs are frozen times of day and cannot do that.
- **Pre-made ivy 3D models** are fundamentally unusable here: the vine geometry is
  generated at runtime by the simulator, so a pre-grown ivy mesh is the opposite of
  what this project needs. This has now bitten twice — the Quaternius kit ships six
  drapeable vine props that must be excluded for the same reason. Assume any
  architectural library bundles foliage, and check.
