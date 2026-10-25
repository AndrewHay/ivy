# Ambient fauna — design & implementation status

Companion to `DESIGN.md` § Ambient fauna and `IMPLEMENTATION.md` § SD-FAUNA. Art scale and
reference images: `assets/reference/fauna/README.md`.

Tracking: bead **ivy-ckq**.

---

## Player-facing vision

Garden wildlife should feel like the village was already alive before the player arrived — a
**contemplative garnish** on the ivy loop, not a mechanic.

- **Bees** read as busy, purposeful pollinators: small, striped, moving **between flowers** at a
  calm pace.
- **Butterflies** read as lighter, more **haphazard** visitors: irregular flits, flower-to-flower
  drift, occasional **paired chases** when one briefly follows another in a short sprint, then both
  return to blooms.
- **Scale** stays honest relative to ivy leaves (~2.5 cm bee body, ~3.75 cm butterfly wingspan);
  proxies are low-poly placeholders sized from `IvyParams.leaf_width_base`.
- **No UI, scores, or collision** in the main game — spawn density and hours are hidden designer
  signals (diel gates, caps, camera LOD, hero exclusion).
- **One breeze:** insect drift shares `AmbientWind` phase with village foliage sway (ivy-4gn).

**Non-goals (current phase):** ladybird in live spawns, moths/swallows, interactable insects,
sim-linked bloom, photoreal species IDs, swarm behaviour.

---

## Architecture boundary

| Layer | Role |
|-------|------|
| `FaunaController` | Spawn/tick, environment bind, agent lifetime, debug/test hooks |
| `FaunaGating` | Diel activity, caps, hero weights, ring rules, LOD spawn/despawn |
| `FaunaMotion` | Presentation trajectories only (bees, butterfly FSM) |
| `FaunaProxyMeshes` | Leaf-relative proxy rigs (bee mesh; butterfly body + wing rigs) |
| `VillageBackdrop.export_fauna_anchors()` | Flower + clover anchor export from scatter data |

Fauna does **not** read/write growth, `IvyParams` gameplay fields, or collision layers.

---

## Species behaviour (implemented)

### Bee (`FaunaConstants.Species.BEE`)

| Aspect | Behaviour |
|--------|-----------|
| **Scale** | Body length ≈ leaf/3; visual rig × `BEE_VISUAL_SCALE` (1.1). |
| **Movement** | Flower-to-flower **lerp** in XZ at ~0.32–0.52 m/s (`BEE_CRUISE_SPEED_MPS` band); smoothstep along segment; small wing bob; yaw along path. |
| **At flower** | Linger 0.4–1.2 s, then pick another **FLOWER** anchor in garden ring (respects near-pivot debug filter when enabled). |
| **Wind** | Light horizontal nudge from `AmbientWind`. |
| **Wings** | Part of single mesh (no separate flap rig). |

### Butterfly (`FaunaConstants.Species.BUTTERFLY`)

| Aspect | Behaviour |
|--------|-----------|
| **Scale** | Wingspan ≈ leaf/2; left/right wing meshes with **4 Hz** flap, **±20%** scale amplitude. |
| **FSM** | `TO_FLOWER` → `FLIT_AT_FLOWER` → (optional chase) → back to flowers. |
| **To flower** | Slower cruise (~`BUTTERFLY_FLIT_CRUISE_MPS`); path wobble perpendicular to travel; irregular height bob. |
| **Flit at flower** | Haphazard hover: wandering heading, multi-frequency wobble around anchor (or test custom hover XZ). |
| **After linger** | With probability **`BUTTERFLY_CHASE_PROB` (0.25)**, if another idle butterfly exists: follower links to leader. |
| **Race** | **~10 s** (`BUTTERFLY_RACE_DURATION_SEC`): leader sprints ~4× cruise in a random XZ direction with jitter; follower pursues; faster wing flap on leader pass. |
| **After race** | Both unlink; each schedules a **new flower trip** (`TO_FLOWER`). |
| **Wind** | Stronger drift multiplier than bees. |

### Gating & caps (main game)

- Activity from lit + solar hour + timelapse blend; despawn when dark.
- Garden ring: flower anchors XZ radius **5.5–12 m** (backdrop-local); hero weight 0 inside 5 m, fade to 1 by 7 m.
- **Caps:** global 12; bee 8; butterfly 6 (unless controller `uncapped_population` — test scene only).
- **LOD:** despawn beyond **18 m** camera XZ (disabled in test scene via `ignore_lod_despawn`).

---

## Test & QA surfaces

### `scenes/test_fauna/test_fauna.tscn` (“Test fauna”)

Standalone scenario (also on main menu **Choose a scenario**):

- **8 flowers** in a ring on a large dark-green ground patch.
- **Prefill** 4 bees + 4 butterflies; **uncapped** +/- panel; spawn at random XZ in flower box.
- **Camera:** mouse orbit (right-click toggles stick/unstick); scroll zoom.
- Uses `bind_environment`, `prefill_agents`, `spawn_at_hover_local`, `despawn_one`.

### Automated tests

| File | Covers |
|------|--------|
| `test/test_fauna_gating.gd` | Diel, ring, hero weight, LOD distance, scale constants |
| `test/test_fauna_environment.gd` | Village anchor export counts and ring |
| `test/test_fauna_motion.gd` | Bee paths, bee speed, butterfly wing flap, butterfly FSM/chase |
| `test/test_fauna_controller.gd` | Controller spawn/despawn, caps vs uncapped, partner unlink on despawn |

---

## File map

```
src/presentation/fauna/
  fauna_controller.gd      — tick, spawn, test API
  fauna_motion.gd          — bee + butterfly motion FSM
  fauna_agent_state.gd     — per-agent fields (paths, butterfly_mode, partner)
  fauna_gating.gd          — activity, caps, rings
  fauna_constants.gd       — sizes, caps, butterfly chase constants
  fauna_proxy_meshes.gd    — rigs
scenes/test_fauna/         — isolated QA scene
assets/reference/fauna/    — art direction README + reference images
```

---

## Known gaps / next beats

- **Ladybird** anchors exist; not spawned in MVP presentation.
- **Main-game** `debug_spawn_near_pivot_only` TEMP filter for Squat house QA.
- **Final art** may replace proxies; motion contracts should survive mesh swap.
- **Chase roll** is per flower visit, not global clock — tune `BUTTERFLY_CHASE_PROB` / race duration for feel.
- IMPLEMENTATION **SD-FAUNA-9** spawn forbid at 22 m was aligned to despawn at 18 m (see gating tests).
