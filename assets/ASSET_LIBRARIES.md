# Third-Party Asset Libraries

Some third-party sources ship as whole libraries — hundreds of models, of which we
want a handful. This file records those libraries, where the full copy lives, and
which pieces have actually entered the game.

`CREDITS.md` remains the per-asset provenance record for everything committed.
This file is the layer above it: what we hold locally, and why most of it is not
in the repository.

## Storage policy

Three tiers, deliberately separated:

| Tier | Path | In git? | Contents |
|---|---|---|---|
| Archive | `assets/_zips/` | **No** | The original downloaded `.zip`, untouched |
| Full library | `assets/_local/` | **No** | The whole extracted library, for auditioning pieces |
| In-game | `assets/structures/`, `assets/materials/`, … | **Yes** | Only the pieces the game actually loads |

Both untracked tiers are covered by `.gitignore`. The rule is that **a file enters
the repository at the moment the game references it, and not before.** A 161 MB
kit of which we use a dozen pieces has no business in version control, but the
dozen pieces do — otherwise a fresh clone cannot build the scene.

This means a clone is playable without any manual download. It also means anyone
wanting to audition *different* pieces must re-fetch the library from the URL
recorded below. That trade is intentional.

---

## Medieval Village MegaKit — Quaternius

| | |
|---|---|
| Source | https://quaternius.itch.io/medieval-village-megakit |
| Author | Quaternius (https://quaternius.com) |
| License | **CC0 1.0 Universal** (public domain) — verified in `License_Standard.txt` |
| Tier obtained | `Medieval Village MegaKit[Standard].zip`, the free tier — 161,003,471 bytes |
| Retrieved | 2026-08-18 |
| Archive | `assets/_zips/Medieval Village MegaKit[Standard].zip` *(untracked)* |
| Full library | `assets/_local/medieval_village_megakit/` *(untracked)* |
| Formats | glTF (+`.bin`), FBX, OBJ (+`.mtl`) — 176 models in each, plus 26 shared PBR textures |

Paid Pro and Source tiers exist with more models; we have neither and do not need
them. The Source tier ships a ready-made Godot project, which would be worth
revisiting only if hand-wiring materials becomes the bottleneck.

### It is a kit, not a set of buildings

There is no complete house in this library. All 176 entries are modular pieces on
a **2.00 m grid** with a **3.12 m storey height**, intended to be assembled. The
preview render on the itch.io page shows finished houses built this way, so
assembly is the designed workflow rather than a workaround.

Consequences for M2.6, all measured rather than assumed:

- **Walls are two disconnected sheets, not solids.** Each wall piece places an
  exterior sheet at local y = 0.00 (stone bulge to y = −0.09) and an interior
  sheet at local y = +0.20, with **no** side, top, bottom or reveal faces
  joining them. The real air gap is 0.20 m; the 0.41 m bounding-box thickness is
  misleading. A decorative wooden-beam shell floats between the sheets near the
  top. Conditioning for the SDF bake bridges each exterior boundary loop to its
  nearest interior loop and thickens to a **0.45 m** target (owner ruling), which
  clears SG-4's 0.30 m admissibility floor with margin.
- **Scale is real metres.** The 2.00 m module and 3.12 m storey are consistent
  with the ~2 m door openings, so no rescaling is needed.
- **Individual kit pieces are open shells** where they should be: a straight wall
  carries 38 boundary edges, a window wall 90. Classified by location: about
  10–20 per butt end — normal for modular pieces — plus aperture-reveal rims and
  a little base detail. Corner trims are fully closed (`Corner_Exterior_Brick`:
  3102 triangles, zero boundary edges), though note they are **decorative trim,
  not structural blocks**; a building's corners are two perpendicular wall runs
  overlapping, closed with corner-column solids at each exterior corner.
- **Conditioning for an SDF bake** uses a **hero / simulation split**, not a single
  merged mesh. The **hero** mesh keeps original kit pieces (correct UVs and
  materials) plus corner columns, trim, and a roof cap for visual review. The
  **simulation** mesh holds bridged closed solids — one per wall piece, plus
  corner columns and floor/roof slabs — kept **separate**; the downstream SDF
  composes them as the pointwise **min of per-piece signed distances** (same
  union model as the analytic tower SDF). A boolean union of the pieces was tried
  and rejected: it produced hundreds of non-manifold edges and corrupted UVs.
  Sim-piece UVs are meaningless after bridging; review renders use flat clay.
- **Floors are effectively zero-thickness.** `Floor_Brick` is a 4-triangle plane
  0.02 m deep. Anything needing a real floor for SG-8's interior enclosure will
  need it thickened or substituted.
- **Style is stylised-painterly, not realism-leaning.** This is the known risk
  against SG-7. The geometry is excellent for proving the mesh-SDF backend, which
  is what phase A is for; it is not the structure that wins the art-direction read.

### Excluded: the six vine props

The kit ships its own ivy as drapeable props, and **we must not use them.** Our
ivy is generated at runtime by the simulator, so pre-grown vine geometry both
double-counts visually and corrupts the SG-7 read and any coverage judgement.

Exactly **6 of the 176 models** reference the vine material, and they are exactly
the ones named for it. Verified by parsing every `.gltf` for materials and image
URIs rather than trusting filenames:

```
Prop_Vine1  Prop_Vine2  Prop_Vine4  Prop_Vine5  Prop_Vine6  Prop_Vine9
```

All six use material `MI_Vine` and texture `T_VineLeaf_png.png`; no other model
in the library references either. **The remaining 170 models are provably
vine-free**, so the exclusion rule is a simple denylist of those six names plus
the `T_VineLeaf` texture, and it needs no per-piece inspection.

The same reasoning as `CREDITS.md`'s "pre-made ivy 3D models are fundamentally
unusable here" applies, and this is the second time it has come up — treat any
future library's bundled foliage the same way.

### Full manifest — 176 models

Present in `glTF/`, `FBX/` and `OBJ/` alike. **Bold** entries are excluded above.

**Roof (39)** — `Roof_2x4_RoundTile`, `Roof_Dormer_RoundTile`, `Roof_FrontSupports`,
`Roof_Front_Brick2`, `Roof_Front_Brick4`, `Roof_Front_Brick4_Half_L`,
`Roof_Front_Brick4_Half_R`, `Roof_Front_Brick6`, `Roof_Front_Brick6_Half_L`,
`Roof_Front_Brick6_Half_R`, `Roof_Front_Brick8`, `Roof_Front_Brick8_Half_L`,
`Roof_Front_Brick8_Half_R`, `Roof_Log`, `Roof_Modular_RoundTiles`,
`Roof_RoundTile_2x1`, `Roof_RoundTile_2x1_Long`, `Roof_RoundTiles_4x4`,
`Roof_RoundTiles_4x6`, `Roof_RoundTiles_4x8`, `Roof_RoundTiles_6x10`,
`Roof_RoundTiles_6x12`, `Roof_RoundTiles_6x14`, `Roof_RoundTiles_6x4`,
`Roof_RoundTiles_6x6`, `Roof_RoundTiles_6x8`, `Roof_RoundTiles_8x10`,
`Roof_RoundTiles_8x12`, `Roof_RoundTiles_8x14`, `Roof_RoundTiles_8x8`,
`Roof_Support2`, `Roof_Tower_RoundTiles`, `Roof_Wooden_2x1`,
`Roof_Wooden_2x1_Center`, `Roof_Wooden_2x1_Center_Mirror`,
`Roof_Wooden_2x1_Corner`, `Roof_Wooden_2x1_L`, `Roof_Wooden_2x1_Middle`,
`Roof_Wooden_2x1_R`

**Prop (23)** — `Prop_Brick1`, `Prop_Brick2`, `Prop_Brick3`, `Prop_Brick4`,
`Prop_Chimney`, `Prop_Chimney2`, `Prop_Crate`, `Prop_ExteriorBorder_Corner`,
`Prop_ExteriorBorder_Straight1`, `Prop_ExteriorBorder_Straight2`,
`Prop_MetalFence_Ornament`, `Prop_MetalFence_Simple`, `Prop_Support`,
**`Prop_Vine1`**, **`Prop_Vine2`**, **`Prop_Vine4`**, **`Prop_Vine5`**,
**`Prop_Vine6`**, **`Prop_Vine9`**, `Prop_Wagon`,
`Prop_WoodenFence_Extension1`, `Prop_WoodenFence_Extension2`,
`Prop_WoodenFence_Single`

**Wall (20)** — `Wall_Arch`, `Wall_BottomCover`, `Wall_Plaster_Door_Flat`,
`Wall_Plaster_Door_Round`, `Wall_Plaster_Door_RoundInset`,
`Wall_Plaster_Straight`, `Wall_Plaster_Straight_Base`, `Wall_Plaster_Straight_L`,
`Wall_Plaster_Straight_R`, `Wall_Plaster_Window_Thin_Round`,
`Wall_Plaster_Window_Wide_Flat`, `Wall_Plaster_Window_Wide_Flat2`,
`Wall_Plaster_Window_Wide_Round`, `Wall_Plaster_WoodGrid`,
`Wall_UnevenBrick_Door_Flat`, `Wall_UnevenBrick_Door_Round`,
`Wall_UnevenBrick_Straight`, `Wall_UnevenBrick_Window_Thin_Round`,
`Wall_UnevenBrick_Window_Wide_Flat`, `Wall_UnevenBrick_Window_Wide_Round`

**Overhang (20)** — `Overhang_Plaster_Corner`, `Overhang_Plaster_Corner_Front`,
`Overhang_Plaster_Long`, `Overhang_Plaster_Short`,
`Overhang_RoofIncline_Plaster`, `Overhang_RoofIncline_UnevenBricks`,
`Overhang_Roof_Plaster`, `Overhang_Roof_UnevenBricks`,
`Overhang_Side_Plaster_Long_L`, `Overhang_Side_Plaster_Long_R`,
`Overhang_Side_Plaster_Short_L`, `Overhang_Side_Plaster_Short_R`,
`Overhang_Side_UnevenBrick_Long_L`, `Overhang_Side_UnevenBrick_Long_R`,
`Overhang_Side_UnevenBrick_Short_L`, `Overhang_Side_UnevenBrick_Short_R`,
`Overhang_UnevenBrick_Corner`, `Overhang_UnevenBrick_Corner_Front`,
`Overhang_UnevenBrick_Long`, `Overhang_UnevenBrick_Short`

**Stairs, exterior (15)** — `Stairs_Exterior_NoFirstStep`,
`Stairs_Exterior_Platform`, `Stairs_Exterior_Platform45`,
`Stairs_Exterior_Platform45Clean`, `Stairs_Exterior_PlatformU`,
`Stairs_Exterior_SidePlatform`, `Stairs_Exterior_Sides`,
`Stairs_Exterior_Sides45`, `Stairs_Exterior_SidesU`,
`Stairs_Exterior_SingleSide`, `Stairs_Exterior_SingleSideThick`,
`Stairs_Exterior_Straight`, `Stairs_Exterior_Straight_Center`,
`Stairs_Exterior_Straight_L`, `Stairs_Exterior_Straight_R`

**Floor (12)** — `Floor_Brick`, `Floor_RedBrick`, `Floor_UnevenBrick`,
`Floor_WoodDark`, `Floor_WoodDark_Half1`, `Floor_WoodDark_Half2`,
`Floor_WoodDark_Half3`, `Floor_WoodDark_OverhangCorner`,
`Floor_WoodDark_OverhangCorner2`, `Floor_WoodLight`,
`Floor_WoodLight_OverhangCorner`, `Floor_WoodLight_OverhangCorner2`

**Corner (8)** — `Corner_ExteriorWide_Brick`, `Corner_ExteriorWide_Wood`,
`Corner_Exterior_Brick`, `Corner_Exterior_TopDown`, `Corner_Exterior_TopOnly`,
`Corner_Exterior_Wood`, `Corner_Interior_Big`, `Corner_Interior_Small`

**Door (8)** — `Door_1_Flat`, `Door_1_Round`, `Door_2_Flat`, `Door_2_Round`,
`Door_4_Flat`, `Door_4_Round`, `Door_8_Flat`, `Door_8_Round`

**Window shutters (8)** — `WindowShutters_Thin_Flat_Closed`,
`WindowShutters_Thin_Flat_Open`, `WindowShutters_Thin_Round_Closed`,
`WindowShutters_Thin_Round_Open`, `WindowShutters_Wide_Flat_Closed`,
`WindowShutters_Wide_Flat_Open`, `WindowShutters_Wide_Round_Closed`,
`WindowShutters_Wide_Round_Open`

**Window (6)** — `Window_Roof_Thin`, `Window_Roof_Wide`, `Window_Thin_Flat1`,
`Window_Thin_Round1`, `Window_Wide_Flat1`, `Window_Wide_Round1`

**Hole cover (5)** — `HoleCover_90Angle`, `HoleCover_90Half`,
`HoleCover_90Stairs`, `HoleCover_Straight`, `HoleCover_StraightHalf`

**Balcony (4)** — `Balcony_Cross_Corner`, `Balcony_Cross_Straight`,
`Balcony_Simple_Corner`, `Balcony_Simple_Straight`

**Door frame (4)** — `DoorFrame_Flat_Brick`, `DoorFrame_Flat_WoodDark`,
`DoorFrame_Round_Brick`, `DoorFrame_Round_WoodDark`

**Stairs, interior (4)** — `Stair_Interior_Rails`, `Stair_Interior_Simple`,
`Stair_Interior_Solid`, `Stair_Interior_SolidExtended`

### Textures — 26 shared PBR maps

`T_Brick_*`, `T_UnevenBrick_*`, `T_RedBrick_BaseColor`, `T_Plaster_*`,
`T_RockTrim_*`, `T_WoodTrim_*`, `T_RoundTiles_*` (roof tiles), plus the utility
maps `T_BottomWear`, `T_TopWear`, `T_BrushedNoise`, `T_Noise_Terrain`,
`T_WindowGradient`, and the excluded `T_VineLeaf`. A `Normals Godot-Unity/`
subfolder holds normal maps in the OpenGL convention, which is the one Godot
wants — the same trap documented for ambientCG in `CREDITS.md`.

### Relevance beyond M2.6

The wall set is close to purpose-built for **M2.7** (ivy across differing
surfaces). It carries brick and plaster in the same module, wall variants with
door and window openings already cut, and shutters in both open and closed
states — which is exactly the open-versus-closed aperture the interior-growth
ruling (SD-OPEN-17) needs a subject for. Worth remembering when M2.7's test wall
gets designed, whatever happens to this kit's role in M2.6.

### M2.6 audition structures

Two buildings are assembled offline in `.tmp/assethunt/build.py` from kit glTF
pieces. Each is exported as a **hero** mesh (original kit UVs and materials) and
a **sim** mesh (bridged closed solids for SDF baking). Nothing below has entered
the repository yet.

#### Square building *(M2.6 first subject)*

One storey, three 2 m bays per side (6 m × 6 m wall centre square, 7.17 m
envelope footprint, 3.42 m total height). Wall thickness 0.45 m after
solidification. See `.tmp/assethunt/square_hero.glb` /
`square_sim.glb`.

#### Tower *(M2.6 second subject)*

| | |
|---|---|
| Role | Squat two-storey probe structure beside the square building — narrower footprint, two bays per side, mixed apertures on both storeys for SDF and interior-growth tests |
| Footprint | **4.37 m** envelope square (`envelope_half` 2.185 m); interior cavity **≈2.12 m** square (inner wall faces at ±1.06 m from centre) |
| Height | **6.54 m** total (2 × 3.12 m storeys + 0.30 m roof cap) |
| Storeys | **2** |
| Wall thickness | **0.45 m** (sim solidification target; measured thinnest span 0.450 m on both storeys) |
| Bays | **2** per side at **±1.0 m** from centre (2 m module; **x = 0 is the bay seam**, not an aperture centre) |
| Build script | `.tmp/assethunt/build.py` (`TOWER_CFG`) |
| Exports *(untracked)* | `.tmp/assethunt/tower_hero.glb`, `.tmp/assethunt/tower_sim.glb` |
| Review renders | `.tmp/assethunt/renders9/` |

**Ground-floor south door placement (Director ruling 2026-08-23, ivy-2p0.2):**
The tower's south door sits in the **+1.0 m bay** (corner-adjacent), not centred
on the wall face the way the square building's three-bay layout allows. This is
**intentional and acceptable**: the tower has only **two 2 m bays per side**
(4.37 m envelope) versus the square's three (7.17 m envelope), so a
plain–door–plain symmetric layout would require widening the footprint by ~65%
and re-baking every M2.6 gate. Real small keeps and gate towers often place the
entry off-centre for defensive or circulation reasons; the screenshots read as a
plausible narrow tower, not as a mis-assembled kit piece. **Do not re-flag as a
defect** unless the tower footprint is deliberately enlarged.

**Sealing policy (SD-OPEN-26, 2026-08-19):** Both structures are **sealed for
M2.6** — no interior growth. Every doorway gets a closed door leaf; every window
gets a glazed pane. The exterior shell is the only surface ivy meets. Structures
stay **hollow**: apertures remain modelled in the wall pieces and are closed by
inserted panels, not by filling the interior to a solid massif (so reopening an
aperture later is a panel removal, not an asset rebuild).

**Hero seal pieces:**

| Aperture | Hero | Sim |
|---|---|---|
| Door | `Door_2_Round` + `DoorFrame_Round_Brick` | closed box panel (`Panel_*`) |
| Window (thin / wide) | generated glass pane (0.02 m, `HeroGlass`) | closed box panel (`Panel_*`) |

Sim panels are separate closed solids in the min-composite SDF — no boolean union.
Panel probes assert **SEALED** by ray-crossing the panel object only (≥ 2 hits);
omitting a panel must read **UNSEALED** (verified on `square_ground_door_S`).

**Kit pieces used** (wall instances + hero trim + seal pieces):

| Piece | Count / placement |
|---|---|
| `Wall_UnevenBrick_Straight` | 12 segments (solid walls and fillers) |
| `Wall_UnevenBrick_Door_Round` | 1 — ground south, bay +1.0 m |
| `Wall_UnevenBrick_Window_Thin_Round` | 2 — ground east bay +1.0 m; upper north bay +1.0 m |
| `Wall_UnevenBrick_Window_Wide_Round` | 1 — upper east bay −1.0 m |
| `Corner_ExteriorWide_Brick` | 8 — hero decorative corner trim (4 corners × 2 storeys) |
| `Corner_Exterior_Brick` | 8 — hero scaled corner blocks (4 corners × 2 storeys) |
| `Door_2_Round` | 2 — hero door leaf (square south + tower ground south) |
| `DoorFrame_Round_Brick` | 2 — matching round brick frames |

**Generated geometry** (not from the kit):

| Part | Hero | Sim | Notes |
|---|---|---|---|
| Aperture seal panel | glass pane | yes | one `Panel_*` closed box per door/window; clay on sim |
| Roof cap | yes | yes | Flat cube, **1.51 m** half-width (flush with wall exterior — no square-building overhang) |
| Ground floor slab | — | yes | Clay cube underfoot |
| Intermediate floor slab | yes | yes | Cube sized to **interior cavity** (`interior_half` ≈ 1.06 m), z ≈ 3.12 m — not visible from outside |
| Corner columns | — | yes | 4 vertical cubes filling exterior corners, full height |

Sim wall pieces are the **same kit names** after the standard bridged solidification
recipe (0.45 m target thickness). They are kept as **separate closed solids** for
the min-composite SDF bake — not boolean-unioned.

**Hero / sim exterior alignment:** Hero and sim walls are both placed **without**
straight-piece end overlap (`hero_end_overlap: False`, sim `end_overlap=False`).
Corner volume on the sim is filled by dedicated **`CornerColumn` cubes**
(`corner_size` = 0.90 m), which made the 0.45 m straight-wall extension redundant
and was causing up to 0.45 m of sim-only exterior bulge at corners when overlap
was enabled. Ivy growth attaches to the sim surface, so that bulge would have read
as floating foliage.

Measured hero-vs-sim exterior deviation (`build8.log`, unfalsifiable pairing: first
hit per ray, 3D separation, no proximity filter; samples span ±`envelope_half`):

| | Square | Tower |
|---|---|---|
| Paired samples | 100 | 216 |
| Median | 0.000 m | 0.000 m |
| p90 | 0.090 m | 0.490 m |
| Max | 0.250 m | 3.310 m |
| > 50 mm | 25 | 60 |
| Near-corner max | *(no samples at ±3.585 sweep)* | **0.000 m** (48 samples) |

Tower near-corner samples confirm corners are flush after dropping overlap. The
tower overall max (3.31 m at sample x = +1.31, z = 0.80) is a wall-junction artefact:
on that ray the hero and sim first hits land on different perpendicular faces, not
a residual corner bulge. Mid-wall p90 is 0.49 m (sim exterior sheet vs hero sheet
thickness offset on straight runs).

**Per-aperture hero/sim panel separation** (`build9.log`, ray-paired exterior
faces, 9 samples across each opening width):

| Aperture | Median (m) | Max (m) | Notes |
|---|---|---|---|
| Square ground door S | 0.0775 | 0.0925 | door leaf sits ~93 mm proud of sim panel exterior |
| Square ground win E | 0.0000 | 0.0000 | |
| Square ground win N | 0.0000 | 0.0000 | |
| Square ground win W | 0.0000 | 0.1123 | worst sample at thin-window edge |
| Tower ground door S | 0.0775 | 0.0925 | same door-kit offset as square |
| Tower ground win E | 0.0000 | 0.0000 | |
| Tower upper win E | 0.0000 | 0.2654 | one sample hits frame edge vs panel centreline |
| Tower upper win N | 0.0000 | 0.0000 | |

Doors do not yet coincide with their sim panels to ivy tolerance — the
`Door_2_Round` / `DoorFrame_Round_Brick` kit geometry protrudes beyond the flat
sim panel exterior. Windows are flush except at opening-edge samples.

**Verification snapshot** (2026-08-19, `build9.log`): all sim pieces CLOSED
(square 22/22, tower 27/27; 0 boundary, 0 non-manifold per piece); corner
diagonal probes FILLED; wall spans **0.450 m** on every storey; aperture panel
probes **SEALED** (panel-only rays); falsifiability confirmed — omitting
`square_ground_door_S` panel reads **UNSEALED n=0**; tower intermediate floor
SEPARATES. Review renders: hero `renders9/01–03`, plan (roof hidden)
`renders9/04–05`.

### Committed in-game assets (`assets/structures/`)

| Path | Role |
|---|---|
| `square_sim.glb` / `square_sim.sdf` | Square building collision proxy and baked SDF |
| `square_hero.glb` | Square building hero render mesh |
| `tower_sim.glb` / `tower_sim.sdf` | Two-storey tower collision proxy and baked SDF |
| `tower_hero.glb` | Tower hero render mesh |
| `scenarios/square.tres` | Default square scenario (seed index 0) |
| `scenarios/square_seed1.tres` | Square scenario pinned to seed index 1 (SG-5) |
| `scenarios/tower.tres` | Default tower scenario (seed index 0) |
| `scenarios/tower_seed1.tres` | Tower scenario pinned to seed index 1 (SG-5) |

Provenance on each `.sdf` is `sha256(collision_glb_bytes + cell + band + baker_version)`
and is verified at load (SD-MESH-9). See `CREDITS.md` for licensing.
