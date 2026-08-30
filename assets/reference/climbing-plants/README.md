# Climbing-plant art direction (W-024)

Visual inspiration for choosing the game's wall-climber look. **Not botanical simulation.**

## Workflow

**Phase 1** — One species at a time: commit **candidate** JPEGs for three roles under `assets/reference/climbing-plants/<species>/candidates/`, then close that species bead.

**Phase 2** — Bead `ivy-mx5.12`: compare all species side-by-side, pick hero art direction. **Done** — owner picked **English ivy** (`hedera-helix/`).

| Step | Species | Folder | Bead | Status |
|------|---------|--------|------|--------|
| 1 | English ivy | `hedera-helix/` | `ivy-mx5.5` | ✓ **hero species** |
| 2 | Grape vine | `vitis-vinifera/` | `ivy-mx5.6` | ✓ done (root-level finals) |
| 3 | Boston ivy | `parthenocissus/` | `ivy-mx5.7` | ✓ candidates committed |
| 4 | Clematis | `clematis/` | `ivy-mx5.8` | ✓ candidates committed |
| 5 | Climbing rose | `rosa-climbing/` | `ivy-mx5.9` | ✓ candidates committed |
| 6 | Hops | `humulus-lupulus/` | `ivy-mx5.10` | ✓ candidates committed |
| 7 | Wisteria | `wisteria/` | `ivy-mx5.11` | ✓ candidates committed |
| 8 | Compare all | — | `ivy-mx5.12` | ✓ English ivy |

## Hero art direction (2026-08-30)

**Species:** English ivy (*Hedera helix*) — folder `hedera-helix/`.

**Rationale:** Strongest wall-takeover read across all three roles — dense adhesive mat on masonry (`mat_edge`), readable starburst runners at leaf scale (`leaf_detail`), and full-building drape framing architecture (`silhouette`). Other species are flower-forward (clematis, rose, wisteria), airy/industrial (hops, grape), or seasonal spectacle (Boston ivy autumn red). Ivy matches the core ruin-climber fantasy.

**Reference set:** `mat_edge_chosen.jpg`, `leaf_detail_chosen.jpg`, `silhouette_chosen.jpg` (also at root as `mat_edge.jpg`, etc.). Side-by-side compare gallery: `_compare/index.html`.

### Three roles (≥2 candidates each)

| Role | Filename prefix | What to capture |
|------|-----------------|-----------------|
| mat_edge | `mat_edge_01.jpg` … | Thick mat + leading edge on masonry |
| leaf_detail | `leaf_detail_01.jpg` … | Close range, many readable leaves |
| silhouette | `silhouette_01.jpg` … | Foliage vs sky / roofline |

Each species folder needs a `README.md` listing every candidate: local filename, source page URL, one-line note.

---

## Downloading from Wikimedia Commons

**Do not use** `commons.wikimedia.org/wiki/Special:FilePath/…` — it rate-limits aggressively.

Use the direct file on `upload.wikimedia.org` instead. The path is the MD5 of the filename with spaces → underscores:

```
https://upload.wikimedia.org/wikipedia/commons/{md5[0]}/{md5[0:2]}/{filename_with_underscores}
```

Example — resolve URL for `Clematis and ivy.jpg`:

```bash
python3 -c "
import hashlib, urllib.parse
title = 'Clematis and ivy.jpg'
fn = title.replace(' ', '_')
h = hashlib.md5(fn.encode()).hexdigest()
print('https://upload.wikimedia.org/wikipedia/commons/' + h[0] + '/' + h[0:2] + '/' + urllib.parse.quote(fn))
"
```

Then download (wait if you get HTTP 429 — the IP needs to cool down):

```bash
curl -fsSL -A "ivy-art-research/1.0" \
  -o assets/reference/climbing-plants/clematis/candidates/mat_edge_03.jpg \
  'https://upload.wikimedia.org/wikipedia/commons/d/d7/Clematis_and_ivy.jpg'
```

No scripts required — one `curl` per file. **Wait ~61 seconds before each download** if Commons returns HTTP 429.

`CATALOG.md` has extra starting URLs from the old CC0 research pass.
