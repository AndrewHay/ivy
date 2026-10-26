# Village flora — design & audition decisions

Companion to `FAUNA_DESIGN.md` (bees/butterflies), `assets/CREDITS.md` (provenance), and
`assets/ASSET_LIBRARIES.md` (Quaternius nature kit policy).

Tracking: informal until wired into beads for a flora scatter epic.

---

## Source

Ground-cover and accent plants come from **Quaternius — Stylized Nature Megakit** (CC0 1.0):

- https://quaternius.itch.io/stylized-nature-megakit
- Committed under `assets/backdrop/pieces/` + shared textures in `assets/backdrop/textures/`
- Full kit for audition: `assets/_local/stylized_nature_megakit/` (untracked)

Import helper (URI rewrite to `../textures/`):

```bash
python3 tools/import_nature_backdrop_pieces.py --all-flora
```

**Audition scene:** `tools/nature_flora_lineup.tscn` — numbered row (1–24), same **DebugCamera**
as the main game. Building picker entry: **Nature flora lineup**. Manifest order matches
`tools/import_nature_backdrop_pieces.py` `ALL_FLORA` and `.tmp/nature_flora/lineup_manifest.txt`
when captured with `--out=`.

---

## Lineup index (reference)

| # | Piece | Notes |
|---|--------|--------|
| 1 | `Bush_Common` | Already in village scatter (plain green bushes) |
| 2 | `Bush_Common_Flowers` | Already placed as garden bushes in `village_backdrop.tscn` |
| 3 | `Clover_1` | **Keep — pond ring (deferred)** |
| 4 | `Clover_2` | **Keep — pond ring (deferred)** |
| 5 | `Fern_1` | Not selected in audition |
| 6 | `Flower_3_Group` | **Use — scatter in groups of 3–4** |
| 7 | `Flower_3_Single` | **Use — scatter in groups of 3–4** |
| 8 | `Flower_4_Group` | **Use — scatter in groups of 3–4** |
| 9 | `Flower_4_Single` | **Use — scatter in groups of 3–4** |
| 10 | `Grass_Common_Short` | **Keep as tall-grass tier — do not place yet** |
| 11 | `Grass_Common_Tall` | **Keep as tall-grass tier — do not place yet** |
| 12 | `Grass_Wispy_Short` | Already used for near-garden grass scatter |
| 13 | `Grass_Wispy_Tall` | Not selected in audition |
| 14 | `Mushroom_Common` | **Keep — do not place yet** |
| 15 | `Mushroom_Laetiporus` | **Keep — do not place yet** |
| 16–20 | `Petal_1` … `Petal_5` | **Use — tiny flowers; scatter beside paths, not on path stones** |
| 21 | `Plant_1` | Not selected in audition |
| 22 | `Plant_1_Big` | Not selected in audition |
| 23 | `Plant_7` | **Use — scatter around garden/village ground** |
| 24 | `Plant_7_Big` | **Use — scatter around garden/village ground** |

---

## Director decisions (2026-10-26)

### In scope for gameplay scatter (when implemented)

- **Flower clusters (6–9):** `Flower_3_Group`, `Flower_3_Single`, `Flower_4_Group`,
  `Flower_4_Single` — place as **groups of 3–4** instances (mixed group/single meshes per cluster),
  scattered in the garden ring / near village, not one mesh type only.
- **Tiny petals (16–20):** `Petal_1`–`Petal_5` — **small accent** scatter **adjacent to path
  edges**, explicitly **not** on stepping-stone MultiMesh paths.
- **Plants (23–24):** `Plant_7`, `Plant_7_Big` — general **scatter around** the village/garden
  ground cover layer.

### Committed assets, placement deferred

- **Pond clover (3–4):** `Clover_1`, `Clover_2` — design intent is **around a future pond**;
  **do not add to the main scene** until pond geography exists.
- **Tall grass tier (10–11):** `Grass_Common_Short`, `Grass_Common_Tall` — approved look, **no
  scatter in main scene yet** (distinct from existing wispy grass `Grass_Wispy_Short`).
- **Mushrooms (14–15):** `Mushroom_Common`, `Mushroom_Laetiporus` — approved, **no placement yet**.

### Fauna coupling

- **Bees and butterflies** visit **flower** scatter only — the pieces in the “use” flower rows
  above (6–9, 16–20, and flower-bearing groups as implemented).
- **Do not** register fauna flower anchors on **mushrooms (14–15)** or **tall grass (10–11)** when
  those eventually ship; clover anchors may remain for pond-adjacent wildlife once clover is placed.

### Current main-scene baseline (implemented 2026-10-26)

- **Grass:** `Grass_Wispy_Short` (unchanged).
- **Flower clusters:** `Flower_3_Group`, `Flower_3_Single`, `Flower_4_Group`, `Flower_4_Single` —
  10 clusters × 3–4 members (`VillageScatterPositions.flower_cluster_layers()`).
- **Path petals:** `Petal_1`–`Petal_5` beside path stones (`petal_layers()`).
- **Plants:** `Plant_7`, `Plant_7_Big` scattered in the near ring (`plant_layers()`).
- **Clover:** removed from live scatter (pond deferred); no fauna clover anchors.
- **Fauna:** flower anchors only on cluster blooms + petals (`export_fauna_anchors()`).
- **Not placed:** tall grass 10–11, mushrooms 14–15, pond clover 3–4.

---

## Implementation notes (for next programmer)

- Scatter transforms should stay **deterministic** (LCG pattern in `VillageScatterPositions`) unless
  a design pass explicitly wants hand-placed pond clover.
- Group-of-3–4 flower clusters need a small layout helper (local offsets + shared yaw) per cluster
  center, then MultiMesh or few instanced roots — match existing `_create_scatter` shadow policy
  (OFF for ground cover).
- Petal scatter needs **distance from path transforms** exported by path MultiMesh setup (reject
  samples inside path corridor).
- When clover moves to pond ring, **move or duplicate** fauna clover anchors out of the current
  garden ring band (`FaunaConstants` garden ring tests may need updating).
- Update `assets/CREDITS.md` piece table when new pieces enter the live scene graph (repo policy:
  committed when referenced).

---

## Non-goals

- Trees, rocks, pebbles from the same kit in this flora pass (separate backdrop decisions).
- Replacing runtime ivy with kit vine props (excluded project-wide).
- Interactive flora or pickable plants.
