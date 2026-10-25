# Ambient fauna art direction (bees & butterflies)

Visual targets for garden-ring ambient insects. **Not** simulation accuracy — motion garnish scaled against **ivy leaf width**.

## Scale (canonical)

Reference leaf = `IvyParams.leaf_width_base` (**7.5 cm** blade width by default).

| Creature | Rule | Default size |
|----------|------|----------------|
| **Bee** | Body length **⅓ × leaf width** | **~2.5 cm** head–abdomen |
| **Butterfly** | Wingspan **½ × leaf width** | **~3.75 cm** tip to tip |

Code: `FaunaConstants.bee_body_length_m()`, `butterfly_wingspan_m()`.

## Character

- **Insect anatomy**, not mascots — no smiles, dot eyes, or human expressions.
- **Silhouette read**: bee = stripes + wings; butterfly = wing shape + spot pattern.
- **Low poly**, storybook cottage garden (Quaternius backdrop).

## References

| File | Use |
|------|-----|
| `scale_reference_v3.jpg` | **Current** scale + insect tone (small labels) |
| `mood_garden.jpg` | Mood only — ignore scale/smile on older sheets |
| `bee_design_sheet.jpg` | Superseded — ignore smile / oversized scale |
| `butterfly_design_sheet.jpg` | Wing pattern hint only |
| `context_garden_frame.png` | In-engine contrast frame |

## Locked meshes (v1)

Procedural proxies in `FaunaProxyMeshes` — leaf-relative scale, thin wing depth (`bee_wing_half_thickness_m` / `butterfly_wing_half_thickness_m`). Motion in `FaunaMotion`.

## Non-goals

- Photoreal species, swarms, interactable fauna, ladybird in v1 presentation (not spawned).
