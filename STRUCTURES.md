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
| `{name}_hero_Seal_*_glass` | **0.02 m** glass pane | ✓ | — |
| `{name}_hero_Seal_*_door` | `Door_2_Round` or `Door_1_Flat` leaf | ✓ | — |
| `{name}_sim_Panel_*` | Aperture seal (**0.45 m** clay), doors/windows | — | ✓ |
| **`ivy` wall shells** | AABB / solidified kit matching hero walls | — | ✓ cottage layout |

### Which parts each playable building uses

| Building | Walls | Doors / windows | Roof | Chimney / other |
|---|---|---|---|---|
| **`ivy`** | Tier A plaster + optional brick; sim = hero-matched shells + solid door/window + solid `Roof_RoundTiles_4x6` | `Door_1_Flat`, shutters, sim panels | `Roof_RoundTiles_4x6`, `Roof_Front_Brick4` ×2 | `Prop_Chimney2` |
| **`square`** | `Wall_UnevenBrick_*` ring (3 bays/side) | `Door_2_Round`, round windows, glass + panels | Flat **`RoofCap`** | Corner trim blocks |
| **`tower`** | `Wall_UnevenBrick_*` (2 bays/side × 2 storeys) | Mixed round door/windows | **`RoofCone`** + cap | Corner trim; **`MidFloorSlab`** |
| **`surface_wall`** | Long uneven-brick run + door | Same seal policy as ring | **`RoofCap`** | — |

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
# Growth surface from the hero (AR-MESH-20; see below). Not yet run on committed structures:
# ivy-b1e.7 (cottage) and ivy-b1e.8 (the rest) switch each one over.
python3 tools/build_growth_surface.py assets/structures/ivy_hero.glb assets/structures/ivy_sim.glb \
  .tmp/gs/ivy_sim.glb --structure ivy --report .tmp/gs/ivy_report.json
python3 tools/bake_mesh_sdf.py assets/structures/ivy_sim.glb assets/structures/ivy_sim.sdf
python3 tools/measure_structure_gates.py ivy tower
```

### Growth-surface builder (`tools/build_growth_surface.py`)

Turns every node of the hero GLB into closed solids in world space and writes the sim GLB that the
SDF baker and `StructureBody` read (IMPLEMENTATION.md AR-MESH-20.3, `ivy-b1e.14`). Pure Python,
standard library only; self-test `python3 tools/test_build_growth_surface.py`.

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
- Settings: optional `growth_surface` block of the structure in `tools/structure_configs.json`,
  validated by `validate_config`: `wall_t` (≥ 0.24, default 0.45), `envelope` and `exempt` (substrings
  of the hero node name after `{id}_hero_`), `seals` (`hero` / `scaffold`, default `scaffold`), `fill`
  (`[{"name", "min", "max"}]` boxes in glTF world coordinates). Absent block → defaults.
- It **fails** (exit 1, nothing written) instead of substituting a box: an island no rule covers, a
  result that is not closed, a boundary loop more than 5 mm out of plane with no backing sheet, a hero
  node that is not exempt and produced no solid, an envelope with no wall behind it, a config entry
  that matches no node, or an ivy-reachable slot narrower than 0.10 m between parallel proxy faces
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
| (c) | The baked SDF against the collision mesh: raw `\|Φ\|` at the face (no search along the normal) and `Φ` 0.10 m inside wherever at least 0.20 m of solid lies behind the face. | face p95 ≤ 0.01 m and max ≤ 0.025 m; every inside probe negative |

These numbers were ratified on 2026-11-13 (`ivy-b1e.4`, owner ruling) and are the constants at the top
of `tools/growth_surface_audit.gd` (`ivy-b1e.12`). `--samples` is the class W count; class R gets half
of it. Two method details: class W samples inside a slot narrower than 0.10 m are skipped (the growth
surface bridges such a slot), and an inside probe for (c) only counts when no other proxy face lies
within 0.05 m of it (a hit beside an edge is not 0.10 m deep). `test/slow/test_sg9_sdf_collision.gd`
asserts gate (c) through the same code.
`test/test_growth_surface_audit.gd` proves the audit is falsifiable: a bounding-box proxy over a ribbed
hero wall fails (a) and (b), and a proxy that carries the ribs passes (a), (b) and (c).

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
