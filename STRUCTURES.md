# Structures catalog

Playable mesh buildings, procedural test fixtures, and backdrop kit pieces used in Ivy.
Dimensions are in **metres** unless noted. Kit source: **Quaternius Medieval Village Megakit** (see `assets/CREDITS.md`, `assets/ASSET_LIBRARIES.md`).

---

## Building kit parts (component catalog)

Individual **modules** you can place in Blender (`Hero_*` collections) or in the village generator. Three tiers:

| Tier | On disk | Count (building-related) | Used in game today |
|---|---|---|---|
| **A — Committed copies** | `assets/backdrop/pieces/{Name}.gltf` | 18 medieval modules (+ nature scatter, not listed below) | Village cottages, playable **`ivy`**, garden props in `village_backdrop.tscn` |
| **B — Full megakit** | `assets/_local/medieval_village_megakit/glTF/{Name}.gltf` *(download; see `ASSET_LIBRARIES.md`)* | **176** models (170 vine-free) | **`square`**, **`tower`**, **`surface_wall`** via `tools/build_structures.py`; any piece can be added to a blend |
| **C — Generated (not kit GLBs)** | N/A — built in `tools/build_structures.py` | See [Generated parts](#generated-parts-not-from-kit-glb) | Hero + sim collision / SDF only |

**Module grid:** wall pieces are **2.0 m** wide (one bay), **~0.31 m** thick (native kit depth; sim solidifies to **0.45 m**). Single-storey wall height **~3.12–3.125 m**. Cottage depth is **two bays = 4.0 m** (`VillageBackdrop.COTTAGE_DEPTH`).

**Remeasure AABBs** (after Godot has imported glTFs):  
`godot --headless --path . --script res://tools/measure_structure_kit_pieces.gd`  
Megakit (tier B): `res://tools/measure_cottage_kit.gd` with paths under `_local/…/glTF/`.

### Tier A — Committed medieval modules (`assets/backdrop/pieces/`)

| Piece | Size (W × D × H approx.) | Description | Used in |
|---|---|---|---|
| `Wall_Plaster_Straight` | 2.00 × 0.31 × 3.13 | Plain plaster wall, 1 bay | **`ivy`**, all cottages |
| `Wall_Plaster_Door_Flat` | 2.00 × 0.31 × 3.13 | Plaster wall with flat door opening | **`ivy`**, cottages |
| `Wall_Plaster_Window_Wide_Flat` | 2.00 × 0.31 × 3.13 | Plaster wall, wide flat window | **`ivy`**, cottages |
| `Wall_UnevenBrick_Straight` | 2.00 × 0.31 × 3.13 | Brick accent wall (1 bay) | Cottages (optional `brick` side) |
| `Door_1_Flat` | ~1.0 × 0.05 × 2.5 | Door leaf; kit origin offset **−0.51267 m** on local +X | **`ivy`**, cottages (`Door_1_Flat`) |
| `WindowShutters_Wide_Flat_Closed` | ~1.2 × 0.1 × 2.5 | Closed shutters on wide windows | **`ivy`**, cottages |
| `Roof_RoundTiles_4x6` | ~4.6 × 6.6 × 2.4 | Hip roof, **3-bay** cottage length | **`ivy`**, CB/CC/CE/CF/CG |
| `Roof_RoundTiles_4x8` | ~4.6 × 8.6 × 2.4 | Hip roof, **4-bay** length | CA, CD |
| `Roof_RoundTiles_4x4` | *(similar)* | Larger 4×4 hip *(superseded in cottages; kept in repo)* | Reference only |
| `Roof_2x4_RoundTile` | *(tile module)* | Single round-tile roof module | Not in current cottage recipes |
| `Roof_Front_Brick4` | ~4.0 × 3.1 × 3.1 | Gable-end brick infill at ridge ends | **`ivy`**, all cottages |
| `Prop_Chimney` | ~0.6 × 0.6 × 1.8 | Shorter chimney | Older cottage variant |
| `Prop_Chimney2` | ~0.6 × 0.6 × 2.0 | Taller chimney stack | **`ivy`**, cottages |
| `Prop_WoodenFence_Single` | — | Fence panel | Backdrop detail |
| `Prop_WoodenFence_Extension1` | — | Fence extension | Backdrop detail |
| `Prop_Wagon` | — | Wagon prop | `village_backdrop.tscn` |
| `Prop_Crate` | — | Crate prop | Garden accents |
| `Balcony_Simple_Straight` | — | Balcony module | Garden accents |

Textures for tier A: `assets/backdrop/textures/` (`T_Plaster_*`, `T_UnevenBrick_*`, etc.).

### Tier B — Megakit wall, door, window, roof, floor *(not all copied to `backdrop/`)*

Authoritative **name list** (176 models): `assets/ASSET_LIBRARIES.md` § “Full manifest”. Summary by category (all under `…/glTF/{Name}.gltf`):

| Category | Count | Examples | Used in Ivy structures |
|---|---|---|---|
| **Wall** | 20 | `Wall_UnevenBrick_Straight`, `Wall_UnevenBrick_Door_Round`, `Wall_UnevenBrick_Window_Thin_Round`, `Wall_Plaster_*`, `Wall_Arch`, `Wall_BottomCover` | **`square`**, **`tower`**, **`surface_wall`** (uneven brick ring layouts) |
| **Door** | 8 | `Door_1_Flat`, `Door_1_Round`, `Door_2_Flat`, **`Door_2_Round`**, `Door_4_*`, `Door_8_*` | **`square`/`tower` seals:** `Door_2_Round`; **`ivy`:** `Door_1_Flat` |
| **Window** *(insert meshes)* | 6 | `Window_Thin_Flat1`, `Window_Roof_Thin`, `Window_Roof_Wide`, … | Mostly unused; wall **modules** carry openings (`Wall_*_Window_*`) |
| **Roof** | 39 | `Roof_RoundTiles_*`, `Roof_Front_Brick*`, `Roof_Wooden_2x1*`, `Roof_Dormer_*`, `Roof_Tower_RoundTiles`, … | **`tower`:** `RoofCone` (procedural clay); **`square`:** flat `RoofCap`; **`ivy`:** tier A roofs |
| **Overhang** | 20 | `Overhang_Plaster_*`, `Overhang_UnevenBrick_*`, … | Not in current playable builds *(eave fixture is procedural `OverhangBuilder`, not kit)* |
| **Floor** | 12 | `Floor_Brick`, `Floor_UnevenBrick`, `Floor_WoodDark`, `Floor_WoodLight`, half/overhang variants | **Not placed in any shipped structure** — see [Floors](#floors) |
| **Corner** *(hero trim)* | — | `Corner_ExteriorWide_Brick`, `Corner_Exterior_Brick` | **`square`/`tower` hero** (optional sim columns) |
| **Prop** | 23 | chimneys, fences, **`Prop_Vine1–6,9` (excluded)** | See tier A for committed props |

**Door frames (hero seals, ring layouts):** `DoorFrame_Round_Brick` pairs with `Door_2_Round` on **`square`** / **`tower`**.

### Floors

| Kind | What it is | In game? |
|---|---|---|
| **Kit `Floor_*`** | Textured planes (~**0.02 m** thick); 12 variants in megakit | **No** — not imported into backdrop or structures |
| **Sim `FloorSlab`** | Clay box underfoot, z ∈ **[−0.30, 0.05]**, footprint = building envelope | **Yes** — all mesh structures (`build_structures.py`) |
| **Sim `MidFloorSlab`** | Clay intermediate deck at **z ≈ 3.0 m** (tower storey) | **`tower` only** |
| **Hero interior glimpse** | `HeroInteriorFloor` / `Reveal_*_floor` cubes through open doors | Dev / open-aperture configs only |
| **Playable interior walkable floor** | — | **No** real floor mesh today; SG-8 uses hollow shell + slabs only |

So: **we do not use kit floor tiles**; collision “floor” is a **generated sim slab**, not `Floor_Brick` etc.

### Generated parts (not from kit GLB)

Created in Blender by `tools/build_structures.py` (names appear in `*_hero.glb` / `*_sim.glb`):

| Part pattern | Typical size / role | Hero | Sim |
|---|---|---|---|
| `{name}_sim_FloorSlab` | Envelope × **0.35 m** tall ground slab | — | ✓ |
| `{name}_sim_MidFloorSlab` | Interior span, **tower** mid-storey | ✓ (tower) | ✓ |
| `{name}_sim_RoofCap` | Flat clay cap at wall top (+ **0.30 m**) | ✓ (`square`, **`ivy`**) | ✓ |
| `{name}_hero_RoofCone` | Conical tower roof | ✓ **`tower`** | ✓ (synced from hero) |
| `{name}_sim_CornerColumn_*` | **0.45 m** corner posts, full height | — | ✓ ring layouts |
| `{name}_hero_Corner_*` | `Corner_ExteriorWide_Brick`, `Corner_Exterior_Brick` trim | ✓ ring | — |
| `{name}_hero_CornerBlock_<storey>_<i>` | Kit `Corner_Exterior_Brick` block at `corner_centers[i]`, turned 90·i about the vertical with its corner's wide trim, so every corner matches corner 0 (`ivy-b1e.36`, AR-MESH-20.13) | ✓ **`surface_wall`** | — |
| `{name}_hero_WallEndCap_<yaw>_<p\|n>` | Closed **0.01 m** plate in the end plane of each wall run's open 0.09 m kit overshoot (stub), measured from the run: end plane to 0.01 m inward, **1.5 mm** past each sheet face, from the ground to the top of the open sheet end (3.0 m, under the neighbour's cornice band); kit `MI_UnevenBrick` with the outer sheet's UV density (`ivy-b1e.39`, SD-MESH-19.4.3 item C) | ✓ **`surface_wall`** | — |
| `{name}_hero_Seal_*_glass` | **0.02 m** glass pane (`ivy`: dark opaque `HeroGlassCottage`, sized to the kit hole + 2 cm) | ✓ | — |
| `{name}_hero_Seal_*_door` | `Door_2_Round` or `Door_1_Flat` leaf (`ivy`: kit-textured, centred in its opening) | ✓ | — |
| `{name}_sim_Panel_*` | Aperture seal (**0.45 m** clay): the kit piece's **real hole + 3 cm** tuck (`tools/kit_openings.py`), not the hero size | — | ✓ |
| `ivy_hero_CornerPost_*` | Kit `Corner_Exterior_Wood` at the 4 outer corners (closes the wall-trim gap) | ✓ | via the growth surface |
| `ivy_hero_Window_Wide_Flat1_*`, `ivy_hero_DoorFrame_Flat_WoodDark_*` | Kit window insert (sill, casement, mullions) and timber door frame | ✓ | via the growth surface |
| **`ivy` growth surface** | `tools/build_growth_surface.py` solids from the hero: relief-exact walls, the roof's tile field (rule 11), ridge caps and their supports, `fill` pieces. The Blender sim (wall shells, padded boxes per wooden part) is only its scaffold | — | ✓ cottage layout (`ivy-b1e.7`) |

### Which parts each playable building uses

| Building | Walls | Doors / windows | Roof | Chimney / other |
|---|---|---|---|---|
| **`ivy`** | Tier A plaster + optional brick; `Corner_Exterior_Wood` posts; sim = `tools/build_growth_surface.py` output (walls with their bands and reveals, shutters as envelopes, hero seals as panels, the tile field exact on the tiles) | `Door_1_Flat` in `DoorFrame_Flat_WoodDark`, `Window_Wide_Flat1` frames with closed shutters, hero seals | `Roof_RoundTiles_4x6`, `Roof_Front_Brick4` ×2 | `Prop_Chimney2` |
| **`square`** | `Wall_UnevenBrick_*` ring (3 bays/side); sim = `tools/build_growth_surface.py` output with defaults, no `growth_surface` block (walls extruded from the hero, scaffold `FloorSlab`, `RoofCap` and the four aperture `Panel_`s copied; 42 nodes, 2252 triangles; `ivy-b1e.8`) | `Door_2_Round`, round windows, glass + panels | Flat **`RoofCap`** | Corner trim blocks |
| **`tower`** | `Wall_UnevenBrick_*` (2 bays/side × 2 storeys); sim = `tools/build_growth_surface.py` output on the Blender scaffold with a `growth_surface` block of 8 `fill` boxes (storey-seam and roof-seat rings over the wall thickness, closing the 1–3 mm cracks behind the cornices; 64 nodes, 3022 triangles; `ivy-b1e.8`) | Mixed round door/windows | **`RoofCone`** + hero `WallTopCap` (`ivy-b1e.33`) | Corner trim; **`MidFloorSlab`** |
| **`surface_wall`** | Uneven-brick ring tiled with whole 2 m kit pieces, three per 6 m side at `module_offsets` [-2, 0, 2] with no overlap (`ivy-b1e.41`; it was five per side at 1 m spacing, and the overlapping straights bricked over the openings): south = wide window, closed door, straight; east = straight, **open** door (`surface_wall_ground_door_E_1`, its reveal floor standing on the ground inside the room), straight; north and west = three straights. Sim = `tools/build_growth_surface.py` output on the Blender scaffold with a `growth_surface` block `{"stones": ["Corner"]}` (rule 12: the 208 corner stones as fitted boxes closed under 0.10 m; rule 2a cuts the 8 wall-end lips, the 8 capped stubs kept, the 4 scaffold `CornerColumn_`s replaced; 1,020 nodes, 13,876 triangles; `ivy-b1e.8`, `ivy-b1e.41`) | Same seal policy as ring | **`RoofCap`** | Corner trim + `CornerBlock_` per corner, each turned with its corner (`ivy-b1e.36`); `WallEndCap_` on each of the 8 wall-end stubs (`ivy-b1e.39`) |

---

## Playable mesh buildings (Blender pipeline)

These appear in the building picker (`BuildingCatalog`) or dev tooling. Each has a canonical `.blend`, exported `*_hero.glb` / `*_sim.glb`, baked `*_sim.sdf`, and a `StructureScenario` under `assets/structures/scenarios/`.

| ID | Label | Config | Blend | Scenario | Footprint (approx.) | Height (approx.) | Notes |
|---|---|---|---|---|---|---|---|
| `ivy` | Village cottage | `tools/structure_configs.json` → `ivy` | `assets/structures/ivy.blend` | `assets/structures/scenarios/ivy.tres` | 6 m × 4 m wall exterior (3 bays × 2 bays deep) | ~3.4 m to wall top; ~5.5 m to roof ridge | **Layout `cottage`** — same recipe as backdrop cottage **CC** (`VillageBackdrop.COTTAGES`): plaster walls, flat door, wide windows, `Roof_RoundTiles_4x6`, brick gables, chimney. `scene_offset` `[-7, 0, 0]`. Edit in Blender via `Hero_ivy` / rebuild sim with `tools/rebuild_sim_from_hero.py`. |
| `tower` | Tower | `tower` | `assets/structures/tower.blend` | `assets/structures/scenarios/tower.tres` | 4.37 m envelope | 6.54 m (2 storeys) | Uneven-brick ring layout; M2.6 phase B probe. |
| `square` | *(retired from picker)* | `square` | `assets/structures/square.blend` | `assets/structures/scenarios/square.tres` | 7.17 m envelope | 3.42 m | Single-storey uneven-brick ring; kept for regression tests and SDF fixtures. |
| `surface_wall` | *(dev only)* | `surface_wall` | `assets/structures/surface_wall.blend` | `assets/structures/scenarios/surface_wall.tres` | 10 m × 6 m face | 3.42 m | Long test wall with ground door; not in picker. |

### Pipeline commands (ivy example)

```bash
# Regenerate from JSON + kit (or bootstrap blend)
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_structures.py -- \
  assets/_local/medieval_village_megakit/glTF assets/structures --no-render --emit-blend --force ivy

python3 tools/rebuild_sim_from_hero.py assets/structures/ivy.blend assets/structures ivy
# Growth surface from the hero (AR-MESH-20; see below). The cottage's shipped ivy_sim.glb is this
# tool's output (ivy-b1e.7); the Blender sim GLB is only its scaffold, and the tool is idempotent on
# its own output, so it can be re-run in place. The square's and the tower's sims are also this tool's
# output (ivy-b1e.8, built on the ivy-b1e.19 scaffolds; the tower with its 8-fill growth_surface block),
# and so is surface_wall's (ivy-b1e.8, growth_surface block stones ["Corner"], rule 12).
python3 tools/build_growth_surface.py assets/structures/ivy_hero.glb assets/structures/ivy_sim.glb \
  assets/structures/ivy_sim.glb --structure ivy --report .tmp/gs/ivy_report.json
python3 tools/bake_mesh_sdf.py assets/structures/ivy_sim.glb assets/structures/ivy_sim.sdf
/Applications/Godot.app/Contents/MacOS/Godot --headless res://tools/audit_growth_surface.tscn -- --structures=ivy
python3 tools/measure_structure_gates.py ivy tower
```

`measure_structure_gates.py` on the cottage (`ivy-b1e.20`): gates 1 and 2 probe at half the wall
height (`cottage_layout.WALL_TOP`), not the middle of the bounds, which is in the roof. For a
structure with a `growth_surface` block gate 3 judges only hero vertices standing **proud** of the
growth surface; vertices buried in a solid (interior faces inside wall slabs, parts under a shutter
envelope) are counted and printed but not judged, because the tool has no visibility test: SG-9 (a)
in the audit judges that side; the tower has a block (its fills) and is read this way since
`ivy-b1e.8` installed its growth surface (gate 3 ivy-reachable max 0.0242 m, 224 buried vertices
reported), and so is surface_wall (its `stones` block; gate 3 ivy-reachable max 0.0175 m, 660 buried
vertices reported; `ivy-b1e.8`). The square keeps the two-sided read with the SD-OPEN-27(d) relief exemption: its growth
surface needs no `growth_surface` block (defaults fit), so the gates tool still reads it that way
(gate 3 ivy-reachable max 0.0495 m on the growth surface, `ivy-b1e.8`).

### Growth-surface builder (`tools/build_growth_surface.py`)

Turns every node of the hero GLB into closed solids in world space and writes the sim GLB that the
SDF baker and `StructureBody` read (IMPLEMENTATION.md AR-MESH-20.3, `ivy-b1e.14`). Pure Python,
standard library only; self-test `python3 tools/test_build_growth_surface.py` (86 tests).

```bash
python3 tools/build_growth_surface.py <hero.glb> <scaffold_sim.glb> <out_sim.glb> \
  [--structure <id>] [--report <report.json>] [--config <structure_configs.json>]
```

- The Blender-built `*_sim.glb` is only a **scaffold**: `FloorSlab`, `MidFloorSlab`, `RoofCap`,
  `RoofCone`, `CornerColumn_`, `Interior_` and (unless `seals` is `hero`) the `Panel_` of each
  aperture are copied from it; its wall, roof, gable, chimney and shutter pieces are discarded. The
  `.blend`'s `Sim_{name}` collection therefore no longer matches the shipped sim GLB once a structure
  goes through the tool.
- Per hero island: closed → kept; planar sheet facing out → extruded `wall_t` inward (holes become
  reveals); planar sheet facing in → dropped; open trim → each boundary loop capped (planar) or
  skirted to its backing sheet 2 mm inside the slab (not planar); solids wholly inside a slab →
  dropped. Shutters listed under `envelope` become one box extended back to the wall; hero `_Seal_`
  nodes become the aperture panel when `seals` is `hero`. Solids that meet overlap by at least 1 mm.
  The scaffold `FloorSlab` is pulled 0.10 m inside the wall faces and its top lowered to y = 0 (it
  stood 0.05 m above the ground and buried the hero's wall bases; `ivy-b1e.7`).
- Rule 2a, corner lip (`ivy-b1e.35`, AR-MESH-20.3 / 20.13): before extrusion, an outward sheet that
  runs past a perpendicular outward sheet's plane is cut there (the cut edge 1 mm past the plane, the
  usual rule 8 grow) when the overshoot is over 1 mm and at most `wall_t` **and** every overshooting
  vertex projects inside the other sheet. Geometry-derived, no config. It removes the 9 cm kit
  wall-end lip at each surface_wall corner (8 cuts) and cuts nothing on the cottage (its gables
  overshoot outside the wall sheets), tower, square or relief article. The report lists each cut under
  `corner_cuts` (sheet, other sheet, overshoot) and counts them in `rules.2a_corner_cut`.
- Stub keep (`ivy-b1e.40`, SD-MESH-19.4.3 item C): when a rule-2a cut's overshoot is closed at its end
  by a closed hero solid spanning the sheet and its interior partner sheet (the surface_wall
  `WallEndCap_*` plates, `ivy-b1e.39`), the capped stub is kept as one box between the two sheets,
  from 1 mm inside the neighbouring wall's slab out to the cap; the 0.45 m slab end is still cut.
  Counted in `rules.12_stub_kept`, listed under `stubs_kept` (sheet, cutting sheet, cap, box). An
  uncapped overshoot keeps nothing.
- Rule 10 column exception (`ivy-b1e.35`): a scaffold `CornerColumn_` whose bounds overlap a rule-6
  envelope solid's bounds, or a rule-12 stone's fitted box (`ivy-b1e.40`), by at least 1 mm on every
  axis is not copied: the hero corner trim replaces it. Counted in `rules.10_column_replaced`, listed
  under `columns_replaced`. Columns with nothing over them are copied as before.
- Rule 12, quoin stones (`stones`, `ivy-b1e.40`, AR-MESH-20.3): every island of a listed node must be
  closed and is one stone, turned into the axis-aligned box whose sides sit at the area-weighted mean
  of each side's own faces (normals within about 37°), not at the extreme vertex. A stone whose
  least-area plan rectangle is more than 1° off the axes fails the build (the kit stones read at most
  0.91°). Stones less than 0.20 m apart share a corner zone (their bounds grown 0.10 m); in each zone
  every empty run under 0.10 m along x, y or z between filled cells (stones and the bounds of every
  other solid) is filled until nothing changes, and stones plus fills are merged into boxes named
  `{id}_sim_CornerStones_c<k>_iNN`. Counters `rules.12_stones`, `rules.12_closed_cells`,
  `rules.12_boxes`; per-stone yaw and box under `stones`, per-zone grid and counts under
  `stone_zones`. surface_wall (`{"stones": ["Corner"]}` in its config since `ivy-b1e.8`; first
  measured in scratch by `ivy-b1e.40`): 208 stones in 4 zones, 962 boxes, 8 stubs kept, 4 columns
  replaced, 1,044 nodes, 14,924 triangles, 0 slots.
- Rule 11, tiled roofs (`tile_field`, `ivy-b1e.7`): the islands of a listed node that rule 4 cannot
  close (the tile surface) are split at the ridge; each slope becomes one solid whose top is the tile
  surface itself (troughs included) and whose bottom reaches down along the slope normal to the
  node's own underside (its down-facing islands), or, where nothing lies below (eave and verge
  overhangs), to `TILE_EDGE_DEPTH` (0.05 m) under the lowest tile point within 0.05 m across the
  slope (a plain offset folded through the tile ends and lips, which are not single-valued along the
  slope normal, and left inward-wound slivers; SD-MESH-19.4.1); the tiles are cut along the
  underside's edges so that step is 2 mm wide. Closed islands that straddle the ridge and rise above the tiles (ridge caps) are kept
  exactly, plus a convex filling (buries the hollow and the lap joint under the next cap) and a
  support down into the tiles across the middle 60 % of the cap's width (the pockets under the rims
  stay open); both stop 0.10 m short of a cap end no other cap overlaps, so its hollow stays.
- Settings: optional `growth_surface` block of the structure in `tools/structure_configs.json`,
  validated by `validate_config`: `wall_t` (≥ 0.24, default 0.45), `envelope` (shutters), `stones`
  (rule 12; surface_wall uses `["Corner"]` since its install, `ivy-b1e.8`), `exempt` and
  `tile_field` (substrings of the hero node name after `{id}_hero_`), `seals` (`hero` / `scaffold`,
  default `scaffold`), `fill` (`[{"name", "min", "max"}]` boxes in glTF world coordinates, or
  `{"name", "points"}`: the convex hull of at least 4 points, for a fill that hugs a rotated piece).
  Absent block → defaults. The cottage's 24 fills (sill gaps, shutters on the sill, the groove under
  each sill, window head to corner post only while that gap is under 0.10 m (on the merged hero it is
  0.19 m, so none; ivy-b1e.28), the gable purlins' barge-board notches, the gap above the
  middle purlins, and the barge boards' ends against the eave lip at the four eave corners) are
  computed by `python3 tools/cottage_growth_fills.py` from the hero (the eave corners from the
  builder's own slot report, via `build(..., fail_on_slots=False)`); paste its output into the block
  when the hero or rule 11 changes (`--check` exits 1 while the committed list is stale, and so does
  `tools/test_build_growth_surface.py`).
- It **fails** (exit 1, nothing written) instead of substituting a box: an island no rule covers, a
  result that is not closed (a scaffold copy included, tested once welded, `ivy-b1e.27`), a boundary
  loop more than 5 mm out of plane with no backing sheet, a hero
  node that is not exempt and produced no solid, an envelope with no wall behind it, a config entry
  that matches no node, a stone island that is not closed or is more than 1° off the axes, a node
  matching both `stones` and `envelope`, or an ivy-reachable slot narrower than 0.10 m between parallel proxy faces
  (`--report` lists each slot's position, width, extent and the two nodes; close it with a `fill` box
  or an `envelope`). Exit 2: usage or input error.
- Output: one node per solid, named `{id}_sim_{hero tail}_iNN` (scaffold copies keep their name plus
  `_i00`), no node transforms. Running it on its own output as the scaffold gives a byte-identical GLB.
- Audit a candidate under `.tmp/` without touching a scenario with the explicit-path form of the audit
  below (`--collision`, `--hero`, `--sdf`, `--id`).

### Relief test article (SG-9(d), `ivy-b1e.6`)

A synthetic ribbed wall with a niche, a minimum recess, a narrow slot and a plaque (IMPLEMENTATION.md
SD-MESH-19.5), the growth-surface pipeline's first customer. Rebuild, then bake each `*_sim.glb`:

```bash
python3 tools/build_relief_article.py hero assets/structures
python3 tools/build_growth_surface.py assets/structures/relief_article_hero.glb assets/structures/relief_article_hero.glb \
  assets/structures/relief_article_sim.glb --structure relief_article --config tools/relief_article_config.json
python3 tools/build_relief_article.py fillets assets/structures/relief_article_sim.glb assets/structures
python3 tools/bake_mesh_sdf.py assets/structures/relief_article_sim.glb assets/structures/relief_article_sim.sdf
```

(and the same bake for `relief_article_{r025,r050,bbox}_sim`). Catalog ids `relief_article`,
`relief_article_r025`, `relief_article_r050`, `relief_article_bbox` (not in the picker); open one with
`Godot res://tools/open_building.tscn -- --building=<id>`. Probe: `test/slow/test_relief_article_probe.gd`.

### Blender build notes

- **Worktrees:** the kit lives only in the main checkout (`assets/_local/` is gitignored). In a worktree, pass
  the main checkout's kit path: the absolute `…/ivy/assets/_local/medieval_village_megakit/glTF` as the
  build's first argument, and `--kit <that path>` to `rebuild_sim_from_hero.py`.
- **`rebuild_sim_from_hero.py`** rebuilds only the sim from the saved blend (hero untouched). It is
  cottage-aware (ivy-b1e.18). On multi-storey ring structures (`tower`) each hero wall's storey comes
  from the object's own height, and Blender's `.001` duplicate names are accepted, so the rebuild
  reproduces the full build's wall set (ivy-b1e.22: node bounds identical to the full-build
  tower sim, which since ivy-b1e.8 is only the growth-surface scaffold, not the shipped `tower_sim.glb`). A hero wall whose name cannot be parsed, or whose kit piece does not match the
  config at that storey, yaw and bay, stops the rebuild instead of being skipped.
- **Aperture checks** in the build log: every door/window prints `SEALED` (centre ray hits its panel) and
  `edges COVERED 9/9` (9 probes just inside the kit piece's real hole all hit sim solid; ivy-b1e.19).
  Apertures in `open_apertures` print `edges skipped (open by design)`. The closing
  `FALSIFIABILITY` section removes one panel and must report `LEAK FAIL`.
- **Cottage style variants** (ivy-b1e.17): production is `window=frame`, `door=frame` (kit window insert
  with shutters on it; kit door frame). For design A/Bs, override per build with a build argument
  after `--`, e.g. `--cottage-style window=flush,door=stretch,sill=shallow`, and write to a scratch
  output dir. Keys and choices: `window` frame|flush, `door` frame|stretch, `sill` native|shallow,
  `window_wall` flat|flat2, `plinth` none|all_l|all_lr|all_base (stone base under every plain bay on
  all four sides), `header` native|trim (window lintel cut to the sill nose width so it clears the
  corner post; ivy-b1e.25), `shutter_back` open|backed (recessed wood board behind the closed
  shutter's planks so the plank gaps don't show the dark glass; ivy-b1e.25). Defaults live in
  `COTTAGE_STYLE_DEFAULT` (`tools/cottage_layout.py`). (The older `IVY_COTTAGE_STYLE` env var still
  works as a fallback, but commands should start with the executable path.)
- `.blend` files are tracked in **Git LFS** (ivy-c848); Blender's `*.blend1` backups are gitignored.

### Growth-surface audit (SG-9 a–c)

Judges each structure's growth surface (collision proxy + baked SDF) against the hero mesh the player
sees (SD-OPEN-28, `ivy-b1e.2`). It measures and reports; it fixes nothing. Run it after any change to a
`*_sim.glb`, `*_hero.glb` or `*_sim.sdf`:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless res://tools/audit_growth_surface.tscn -- \
  --structures=ivy,tower,square,surface_wall --json-dir=res://.tmp/audit
```

All arguments are optional: `--structures` (default: all four), `--samples` (default 2000 class W hero
samples per structure, plus 1000 class R), `--seed` (default 1), `--json-dir` (writes one JSON report per structure). Exit code 0
when every structure passes, 1 when any fails SG-9 (a)–(c), 2 on a usage or missing-asset error.

A candidate that no scenario points at (for example a `tools/build_growth_surface.py` output) is audited
with explicit paths instead of `--structures`; the three paths go together and `--id` names the report:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless res://tools/audit_growth_surface.tscn -- \
  --id=ivy_candidate --collision=res://.tmp/gs/ivy_sim.glb --hero=res://assets/structures/ivy_hero.glb \
  --sdf=res://.tmp/gs/ivy_sim.sdf --json-dir=res://.tmp/audit
```

| Gate | What it measures | Ratified pass (DESIGN.md SG-9, IMPLEMENTATION.md SD-MESH-19) |
|---|---|---|
| (a) W | Signed gap `g` between hero and proxy on area-uniform samples of the hero's ivy-reachable exterior, walls and every other non-tile surface (≥ 2,000 samples). `g > 0`: hero recessed behind the proxy, ivy floats. `g < 0`: hero proud, ivy clips. Reported overall, per node category and for the worst nodes. | p95 `\|g\|` ≤ 0.01 m, p99 ≤ 0.03 m, max ≤ 0.05 m; median `\|g\|` ≤ 0.01 m in every category with ≥ 30 samples; no sample without proxy in reach |
| (a) R | The same gap on tiled roof fields (category `roof`, ≥ 1,000 samples where present), reported separately. | tiles proud by more than 0.01 m on ≤ 5 % of samples; float p95 ≤ 0.05 m, max `\|g\|` ≤ 0.10 m (float side provisional); no sample without proxy in reach |
| (b) | Hero recesses and proud features ≥ 0.05 m deep, ≥ 0.15 m wide both ways and ≥ 0.0225 m² in opening area (up to 1 m across), found on depth maps ray-cast from each side and from above, with the proxy's depth at the same place. Relief under 0.03 m and slots narrower than 0.10 m are never listed. | every listed feature within 0.03 m of the hero's depth |
| (c) | The baked SDF against the collision mesh: raw `\|Φ\|` at the face (no search along the normal) and `Φ` 0.10 m inside wherever no front face lies within 0.20 m behind the face, on a proxy that passes closure; at mid-thickness for a closed solid 0.10–0.20 m thick; no inside probe in a solid under 0.10 m (SD-MESH-19.4.1). | face p95 ≤ 0.01 m and max ≤ 0.025 m; every inside probe negative |
| (c) closure | Each of the 4,000 gate (c) rays, cast again against a two-sided copy of the proxy: is its one-sided hit the first face it crosses? | 0 rays with a crossing more than 0.002 m before the one-sided hit |

These numbers were ratified on 2026-11-13 (`ivy-b1e.4`, owner ruling) and are the constants at the top
of `tools/growth_surface_audit.gd` (`ivy-b1e.12`). `--samples` is the class W count; class R gets half
of it. Three method details: a hero sample reached from open air only through an opening narrower
than 0.10 m, of any shape (a slot, a crack between two hero pieces, a notch, the gaps between closed
shutter boards), is not judged, on the terms of IMPLEMENTATION.md SD-MESH-19.4.2 (`ivy-8mqi`,
`ivy-b1e.29`, `ivy-b1e.30`, amended `ivy-b1e.31`). The opening width at a point on a path is the
least hero chord through it (the hit distances either way, each cast at most 0.10 m, a miss reading
wide), over 8 directions 22.5° apart perpendicular to the path and along the surface normal of every
hero face those 16 casts hit (normals within 1° merged). The normal chord catches a path that crosses
a thin sheet at an angle, where the perpendicular casts slide past the short sides of the gap (the
closed-shutter case); a chord between two hero faces never reads less than the gap between them. A
coarse hero proximity query every 0.05 m finds where hero lies near the path and only there is it
stepped every 0.9 mm, so every opening up to 0.098 m wide (its own width, the least distance between
its faces) and 1 mm long along the path is found and none 0.10 m or wider is; a slit of width w in a
sheet of thickness T crossed at any angle that still lets a straight path through it is found when
w is at most 0.098 m and at most 2T (clause 2a). Three paths are tested: the class W viewpoint segment (0.015 to 0.25 m
off the face), every way out of a proxy solid the audit tries (classes W and R), and the escape rays
below. Such a narrow-opening candidate is judged after all when any of 34 escape rays from 0.015 m
off the face (the 17 level or rising world directions and the 17 sky-probe directions about the face
normal) meets no hero skin and threads no narrow opening until it leaves the hero bounds grown by
0.10 m (`judged_by_escape`), or when the audit has no narrowest width and position to show for it.
Every exemption is listed (node, position, side, would-be `g`, the path that threaded the opening,
its narrowest width and where, clear escapes 0) and summarised under each (a) verdict: how many, how
many with would-be `|g|` over 0.03 m, and the worst. A sample whose 0.25 m viewpoint lands inside a
growth-surface solid is judged
from the nearest point just outside that solid, or, when that way out is below the ground, behind hero
skin, through a narrow opening or not open to the sky, from the point where its line of sight leaves the
solid (within 1 m), and not at all only when both ways out fail (`ivy-8mqi`, `ivy-b1e.27`: a proxy over
the relief beside a recessed wall swallows the viewpoint, and its nearest way out runs through that
relief). Either way out ends 0.02 m (`PROXY_EXIT_MARGIN`) clear of the proxy, not on its face: a line of
sight that only grazes a face, as one along a floor slab's top at the ground line does, never gets clear
and is refused (`no_exit_found`), rather than probing the sky from a one-sided face that downward rays
pass through (`ivy-b1e.38`, SD-MESH-19.4.3 item A). Every other draw (a) does not judge is counted by reason in the report, and those turned down for
want of a way out of a proxy solid are listed with position, would-be `g` and how many of 17 level or
rising rays from the viewpoint leave the hero (0: sealed inside it); and an inside probe for (c) only counts when no other proxy face lies
within 0.05 m of it (a hit beside an edge is not 0.10 m deep). The "0.20 m of solid behind the face"
test is a one-sided cast, so it means "no front face within 0.20 m", which is solid only on a proxy
that passes closure; the local thickness `τ` (first two-sided crossing along −n, counted only if it is
an exit face) decides the mid-thickness probe and the no-probe case, and a not-negative probe is
labelled `inverted` (its ray fails closure), `open` (the first crossing behind it is met from the
front) or `sdf` (the field is wrong) in the report (SD-MESH-19.4.1, `ivy-b1e.23`). Callers hand the
audit a two-sided copy of the proxy (`make_two_sided_proxy`, `set_two_sided_proxy`); without one,
closure reads NOT MEASURED and (c) fails. `test/slow/test_sg9_sdf_collision.gd` asserts gate (c),
closure included, through the same code; all four structures pass it (the tower's former `open`
probe at its cone rim went with its growth surface, `ivy-b1e.8`; surface_wall passes on its growth
surface too, face p95 0.0000 max 0.0158, 3643 inside probes, worst -0.0405, `ivy-b1e.8`).
`test/test_growth_surface_audit.gd` proves the audit is falsifiable: a bounding-box proxy over a ribbed
hero wall fails (a) and (b), and a proxy that carries the ribs passes (a), (b) and (c).
`test/test_growth_surface_audit_closure.gd` does the same for gate (c) (SD-MESH-19.4.1 F1–F6): an
unsigned field fails (`sdf`), a 0.05 m slab is not probed, an unsigned 0.15 m slab fails at
mid-thickness, a reversed face fails closure and an open sheet fails as `open`.

## Procedural picker fixtures (no Blender asset)

| ID | Label | Implementation | Purpose |
|---|---|---|---|
| `cylinder` | Test cylinder | Analytic `TowerSpec` / `TowerBuilder` | Baseline growth, metrics |
| `test_wall` | Test wall | `WallBuilder` | Flat brick wall acceptance |
| `overhang` | Eave wall | `OverhangBuilder` | Eave traversal (flag on) |
| `overhang_spread` | Eave wall (stop-spread) | Same geometry, traversal off | Regression |

## Village backdrop cottages (non-playable)

Generated at runtime by `src/world/village_backdrop.gd` from `COTTAGES` (MultiMesh, no collision). Same kit pieces as `assets/backdrop/pieces/`.

| Name | Centre (XZ) | Bays | Yaw° | Door | Distinctive |
|---|---|---|---|---|---|
| CA | (16, -9.5) | 4 | -90 | front:2 | 4-bay roof |
| CB | (-15, -8.5) | 3 | 0 | right:1 | brick back |
| CC | (12, 11) | 3 | 180 | front:1 | **Source layout for playable `ivy`** |
| CD | (-12, 11) | 4 | 180 | front:2 | brick back |
| CE | (16.5, 1) | 3 | 180 | right:0 | |
| CF | (-16, 1) | 3 | 90 | front:1 | brick left |
| CG | (4, -17) | 3 | 0 | front:1 | |

Shared constants: `COTTAGE_DEPTH` 4 m (two 2 m bays), `WALL_TOP` 3.125 m, `WALL_OUT` 0.09 m.

*(Per-piece tables live in [Building kit parts](#building-kit-parts-component-catalog) above.)*

## Procedural picker fixtures (no Blender asset)
