# Asset Credits

All third-party assets in this project are **CC0 1.0 Universal (public domain)**.
Attribution is not legally required, but is recorded here for provenance.

---

## ambientCG (https://ambientcg.com) — CC0 1.0

License: https://docs.ambientcg.com/license

| Asset ID | Used for | Path |
|---|---|---|
| `LeafSet017` | **Primary ivy leaves.** Photographed *Hedera helix*; 6 leaves, muted weathered sage-green. Chosen for the classic palmate silhouette and flat photography that suits leaf cards. | `plants/ivy/LeafSet017/` |
| `LeafSet029` | **Seasonal leaf variation.** Brighter green plus autumn-tinted leaves; also ships a Scattering map for backlit translucency. | `plants/ivy/LeafSet029/` |
| `Bricks094` | **Primary tower material.** Old weathered red brick. Chosen for contrast — green ivy reads clearly against warm red. | `materials/brick/Bricks094/` |
| `Bricks102` | **Alternate tower material.** Warm sandy medieval stonework, Cotswolds/cottagecore feel. Kept for in-engine A/B. | `materials/brick/Bricks102/` |

### Re-downloading

ambientCG download URLs are deterministic:

```
https://ambientcg.com/get?file=<AssetID>_2K-JPG.zip
```

So the four archives above are `LeafSet017_2K-JPG.zip`, `LeafSet029_2K-JPG.zip`,
`Bricks094_2K-JPG.zip`, and `Bricks102_2K-JPG.zip`. Asset metadata (including the full
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

## Not used

- **HDRI skies** were considered and rejected. The simulator computes true solar
  position (spec §5), so a procedural sky driven by a `DirectionalLight3D` couples the
  visible sun to the growth model. Static HDRIs are frozen times of day and cannot do that.
- **Pre-made ivy 3D models** are fundamentally unusable here: the vine geometry is
  generated at runtime by the simulator, so a pre-grown ivy mesh is the opposite of
  what this project needs.
