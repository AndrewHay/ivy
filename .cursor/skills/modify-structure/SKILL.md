---
name: modify-structure
description: >-
  Guides editing ivy mesh structures (square, tower, surface_wall) via Blender
  blend authoring — what the owner does manually vs what the agent runs
  (export, sim rebuild, SDF bake, gate measure). Use when the user wants to
  edit, tweak, move, or regenerate a building structure, or mentions structure
  authoring, build_structures, hero/sim GLB, or blend files.
disable-model-invocation: true
---

# Modify Structure

Epic: **ivy-ari**. Design decisions: **ivy-9uh** (closed 2026-09-03).

## Architecture (ratified)

| Layer | Owns | Does not own |
|---|---|---|
| `tools/structure_configs.json` | Coarse layout — storeys, bay grid, aperture types, `scene_offset` | Fine placement offsets, one-off piece swaps |
| `assets/structures/{name}.blend` | Fine placement — move kit pieces, hero visual tweaks | Runtime behaviour (Godot loads GLBs) |
| Export script | `{name}_{hero,sim}.glb` from blend collections | — |
| Sim-rebuild script | Regenerates `Sim_{name}` from `Hero_{name}` (watertight rules) | Hero edits (owner) |
| Godot runtime | Loads GLBs + baked SDF via `StructureScenario` | Blender |

**Stomp rule:** never overwrite a canonical `.blend` silently. Recipe regen writes `{name}_draft.blend`; the owner merges in Blender.

**Sim rule:** the owner edits **Hero** only. Sim is always rebuilt by script — never hand-edited in parallel.

## Structure map

Resolve the user's name (tower, square, surface wall, etc.) to:

| id | Config key | Blend (target) | Hero GLB | Sim GLB | SDF | Scenario |
|---|---|---|---|---|---|---|
| `square` | `square` | `assets/structures/square.blend` | `assets/structures/square_hero.glb` | `assets/structures/square_sim.glb` | `assets/structures/square_sim.sdf` | `assets/structures/scenarios/square.tres` |
| `tower` | `tower` | `assets/structures/tower.blend` | `assets/structures/tower_hero.glb` | `assets/structures/tower_sim.glb` | `assets/structures/tower_sim.sdf` | `assets/structures/scenarios/tower.tres` |
| `surface_wall` | `surface_wall` | `assets/structures/surface_wall.blend` | `assets/structures/surface_wall_hero.glb` | `assets/structures/surface_wall_sim.glb` | `assets/structures/surface_wall_sim.sdf` | `assets/structures/scenarios/surface_wall.tres` |

Building picker (`BuildingCatalog`) exposes `square` and `tower` only; `surface_wall` is dev/tooling.

Kit glTF dir (untracked): `assets/_local/medieval_village_megakit/glTF` — see `assets/ASSET_LIBRARIES.md`.

Blender: **4.2.1 LTS** at `/Applications/Blender.app`.

## Implementation status

| Capability | Tool | Status |
|---|---|---|
| Bootstrap blend from JSON | `build_structures.py --emit-blend` | **Implemented** |
| Export GLBs from blend | `tools/export_structures.py` | **Implemented** |
| Rebuild sim from hero | `tools/rebuild_sim_from_hero.py` | **Implemented** |
| JSON-only build (legacy) | `tools/build_structures.py` | Exists — stomps GLBs |
| SDF bake | `tools/bake_mesh_sdf.py` | Exists |
| Director gates | `tools/measure_structure_gates.py` | Exists |

Canonical blends live at `assets/structures/{name}.blend` (committed to git).

---

## Session opener (always do this)

When the user says e.g. "I want to edit the tower":

1. Resolve structure id and paths from the table above.
2. Check whether `assets/structures/{name}.blend` exists.
3. Print a **split checklist** (USER vs AGENT) for their intent:
   - **Fine tweak** (move door, nudge wall) → Edit workflow
   - **Recipe change** (new bay, different window type) → Draft-merge workflow
   - **New structure** → Bootstrap workflow
4. Ask which intent if ambiguous — do not guess.

Output template:

```markdown
## Structure edit: {name}

**Canonical blend:** `{blend path}` ({exists|missing})
**Intent:** {fine tweak | recipe change | bootstrap | verify only}

### You (manual in Blender)
- [ ] …

### Agent (automated)
- [ ] …
```

---

## Workflow A — Fine tweak (placement only)

Use when layout in JSON stays valid; only hero placement changes.

### You (manual)

1. Open `assets/structures/{name}.blend` in Blender.
2. Edit objects in collection **`Hero_{name}`** only (move/rotate/scale kit pieces, swap kit mesh within reason).
3. Save the blend.
4. Tell the agent: "rebuild sim and export {name}".

Do **not** edit **`Sim_{name}`** — sim is derived.

### Agent (automated)

Run from project root using `working_directory: /Users/andrewhay/github/ivy` and `required_permissions: ["all"]`. Use **inline paths** — do not assign shell variables.

```bash
# 1. Rebuild sim from hero
python3 tools/rebuild_sim_from_hero.py assets/structures/{name}.blend assets/structures {name}

# 2. Export GLBs (rebuild already exports; run again if hero changed without rebuild)
python3 tools/export_structures.py assets/structures/{name}.blend assets/structures {name}

# 3. SDF bake
python3 tools/bake_mesh_sdf.py assets/structures/{name}_sim.glb assets/structures/{name}_sim.sdf

# 4. Director gates
python3 tools/measure_structure_gates.py {name}
```

Bootstrap a canonical blend (one structure per invocation):

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_structures.py -- assets/_local/medieval_village_megakit/glTF assets/structures --no-render --emit-blend {name}
```

5. If gates fail, report which gate and stop — do not commit broken assets.
6. Run slow GUT suite if sim/SDF changed — see `.cursor/skills/run-tests/SKILL.md`.
7. Optionally capture structure review — `tools/capture_structure_review.gd`.

**Agent must not:** rerun `build_structures.py` against committed GLBs for a blend-owned structure unless the user explicitly requests a draft regen (Workflow B).

---

## Workflow B — Recipe change (draft merge)

Use when `structure_configs.json` changes (storeys, bays, aperture layout).

### You (manual)

1. Review the agent's JSON diff (if any) — coarse layout only.
2. After agent produces `{name}_draft.blend`, open **both** canonical and draft in Blender.
3. Merge desired changes into `assets/structures/{name}.blend` (manual — no silent overwrite).
4. Save canonical blend.
5. Optionally adjust hero placement in `Hero_{name}`.
6. Tell agent to rebuild sim, export, bake, measure (Workflow A agent steps).

### Agent (automated)

1. Edit `tools/structure_configs.json` for the structure block (layout keys only — not fine offsets).
2. Regenerate **draft only**:

```bash
blender --background --python tools/build_structures.py -- \
  assets/_local/medieval_village_megakit/glTF \
  assets/structures/_draft \
  --emit-blend --no-render {name}
# Target output: assets/structures/_draft/{name}.blend
# NEVER write directly to assets/structures/{name}.blend
```

3. Summarize what changed in the draft vs JSON (storey count, aperture list, footprint).
4. Stop and hand off merge to the owner.
5. After owner confirms merge + save, run Workflow A agent steps.

**Stretch (ivy-ari.4, end of epic only):** attempt reverse-sync — diff canonical vs draft, emit sidecar override or JSON patch **proposal** for owner review. Never auto-apply.

---

## Workflow C — Bootstrap (first blend for a structure)

Use when `{name}.blend` does not exist yet.

### Agent

1. Confirm `{name}` exists in `structure_configs.json`.
2. Emit canonical blend (target):

```bash
blender --background --python tools/build_structures.py -- \
  assets/_local/medieval_village_megakit/glTF \
  assets/structures \
  --emit-blend --no-render {name}
```

3. Export + SDF + gates (Workflow A agent steps).
4. Verify GLBs match or improve on committed baselines.

### You

1. Open the new blend, verify hero looks correct.
2. Fine-tune placement if needed → Workflow A.

---

## Workflow D — Verify only (no edits)

Agent runs gates + optional `capture_structure_review.gd` and reports. No blend/GLB writes.

---

## Legacy fallback (until ivy-ari.3 lands)

When blend/export/rebuild tools are missing:

```bash
blender --background --python tools/build_structures.py -- \
  assets/_local/medieval_village_megakit/glTF assets/structures --no-render {name}
python3 tools/bake_mesh_sdf.py assets/structures/{name}_sim.glb assets/structures/{name}_sim.sdf
python3 tools/measure_structure_gates.py {name}
```

Warn the owner: this path **stomps GLBs from JSON** and ignores hand-edited blends. Use only for JSON-only iteration or emergency rebuild.

---

## Agent retrieval

Before editing, call `search_project_memory` (`project="ivy"`) for: structure blend authoring, `build_structures.py`, SD-MESH gates, hero/sim alignment.

Read only cited files. Do not open `IMPLEMENTATION.md` whole.

---

## Non-goals

- Editing structures inside Godot scenes (runtime loads GLBs, not blends).
- Hand-editing sim meshes in Blender.
- Silent regen of canonical blends or committed GLBs.
- Retiring procedural test-cylinder (`BuildingCatalog` id `cylinder`) in this epic.
- Implementing reverse-sync (ivy-ari.4) before core pipeline (ivy-ari.3) is done.
