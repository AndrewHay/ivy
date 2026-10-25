# Cottagecore leaf art pass — LeafSet017

> **Superseded (2026-10-25)** for leaf shape and colour by [`LEAF_STANDARD.md`](LEAF_STANDARD.md):
> pointed palmate lobes, deep green with pale contrasting veins, visible petiole. The rounded
> procedural painter (`paint_cottage_leaf_atlas`) has been deleted; commands below no longer run.
> Kept for history.

**Status:** Superseded — see above.

**Audience:** Whoever edits `LeafSet017_Leaves_RGBA.png` and the paired normal/roughness maps.

**World pairing:** Village plaster cottages, Bricks102 sandy stone, round tile roofs — ivy should feel like a **storybook garden climber**, not a macro plant scan.

---

## Target look (one sentence)

Soft, warm, slightly **illustrated** English ivy: chunky rounded lobes, gentle veins, dusty sage greens — cozy and readable at game scale.

---

## Shape (atlas paint)

| Do | Don’t |
|----|--------|
| **3-lobe juvenile** silhouettes with **rounded** sinuses between lobes | 5-lobe “starfish” or needle tips from the raw scan |
| Slight asymmetry (hand-cut, not mirrored CG) | Perfect bilateral symmetry on every variant |
| Petiole notch at bottom centre (keep `petiole_uv` anchor) | Move pivot or crop into the blade |
| Blunt apical lobe; tip radius ≈ 8–12% of blade height | Acuminate “dagger” tips |

**Per-variant notes (current ids):**

| id | tier | Retouch priority |
|----|------|------------------|
| `a` | H | Round outer lobes; simplify to 3 lobes if needed |
| `c` | H | **Hero reference** — soften deepest sinus, blunt tip |
| `e` | H | Shorten blade length in rect if still reads spear-like |
| `b`,`d`,`f` | W | Dusty olive, **mottling as watercolor wash** not disease spots |

**Mesh assist (already in engine):** `LeafCupMesh` apical UV taper samples inset from tips until art catches up (`TIP_TAPER_V`, `TIP_WIDTH_MIN` in `leaf_cup_mesh.gd`).

---

## Colour

| Role | Reference | Notes |
|------|-----------|--------|
| Healthy (H) | Moss / sage | Warm yellow-green highlights; shadow olive not blue-black |
| Weathered (W) | Dried herb, tea stain | Lower saturation than H; no grey mould |
| Veins | Watercolour | **One** midrib + two side branches; vein contrast ≤ 15% luminance delta |
| Specular | Chalk matte | No waxy houseplant shine |

**In-engine grade (until atlas is repainted):** `leaf.gdshader` `healthy_tint`, `weathered_tint`, `warm_lift`, reduced `normal_scale`, higher `roughness_floor`, soft alpha edge.

---

## Texture maps

| Map | Cottagecore treatment |
|-----|------------------------|
| **Albedo** | Repaint per table above; export RGBA 2048², same `leaf_atlas.json` rects |
| **Normal** | **Flatten** — blur 2–4 px, reduce Z contrast ~40%; leaves read as cards not emboss |
| **Roughness** | Raise floor (~0.45); gentle variation only; no pore noise |

Do **not** change `rect_uv`, `aspect`, `alpha_fill`, or `petiole_uv` without updating `leaf_atlas.json` and re-running coverage / LG-2 tests.

---

## Acceptance (visual)

1. At **1.5 m** (`capture_leaf_lookdev`), a single leaf reads as **rounded and cozy**, not photoreal sharp.
2. At **wall close-up** (`capture_wall_archetype` mid, day 60), mat reads as **illustrated foliage** against brick/plaster — still clearly ivy.
3. Side-by-side with Bricks102 / village backdrop: **same temperature** (warm stone + warm leaf).

---

## Procedural atlas paint (engine)

```bash
Godot --headless res://tools/paint_cottage_leaf_atlas.tscn
```

Rewrites `LeafSet017_Leaves_RGBA.png`, flat normal + matte roughness JPGs, and remeasures `alpha_fill` in `leaf_atlas.json`. Original scan: `LeafSet017_Leaves_RGBA_scan.png`. Python twin: `tools/paint_cottage_leaf_atlas.py` (needs Pillow + numpy).

---

## Capture commands (QA)

**Leaf only (no vine / wall)** — use this to judge atlas silhouette:

```bash
Godot --headless res://tools/symmetrize_leaf_atlas.tscn   # mirror-average scan rects (then --import)
Godot res://tools/capture_single_leaf_card.tscn -- --id=a
Godot res://tools/capture_single_leaf_card.tscn -- --id=a --view=oblique
Godot res://tools/capture_single_leaf_card.tscn -- --id=all
```

Writes `.tmp/leaf-lookdev/leaf_card_<id>.png` and `leaf_card_all.png`.

**In context:**

```bash
Godot res://tools/capture_leaf_lookdev.tscn -- \
  --out=res://.tmp/leaf-lookdev/leaf_cottage_closeup.png

Godot res://tools/capture_wall_archetype.tscn -- \
  --archetype=mid --day=60 --label=leaf_wall_cottage
```

---

## Non-goals

- Botanical keyed ageing (lifecycle beads).
- New species or second atlas set (stay on LeafSet017 six-pack).
- Photoreal PBR hero close-ups.
