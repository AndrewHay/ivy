# Ivy — Technical Index

Last updated: 2026-08-09

> Update this file whenever files are added, removed, renamed, or change responsibility.
> See `.cursor/rules/technical-index-maintenance.mdc`.

**Status legend:** _(no marker)_ = exists on disk · **[planned]** = specified by the Gameplay
Architect in `IMPLEMENTATION.md` § "Phase 1 Implementation Architecture" (`AR-FILES`), not yet
implemented. Remove the marker as each file lands.

---

## File Index

### Project root and bootstrap

| Path | Summary |
|------|---------|
| `project.godot` | Godot project config; main scene `res://src/main/main.tscn`. Needs the `AR-SCENE-7` render settings (MSAA 4× for alpha-to-coverage, screen-space AA off, 4096 directional shadows). |
| `src/main/main.tscn` | **[being replaced]** Currently the bootstrap `Control` placeholder. Becomes the `Node3D` composition root hosting `World`, `Sim`, `PlantRender`, `UI` (`AR-SCENE-1/2`). Path and UID are preserved so the dev tools keep working. |
| `src/main/main.gd` | **[being replaced]** Placeholder label logic today; becomes the composition root that owns the single `IvyParams` instance and injects it downward (`AR-SCENE-6`). |

### Parameters

| Path | Summary |
|------|---------|
| `src/params/ivy_params.gd` | **[planned]** `IvyParams : Resource` — every spec §30 default plus every `SD-PARAM` row, the single authoritative parameter table (INV-6). Exposes `content_hash()` for the acceptance-harness integrity guard. |
| `src/params/ivy_params_default.tres` | **[planned]** Committed default parameter resource. |

### Core (conventions, determinism, clock)

| Path | Summary |
|------|---------|
| `src/core/conv.gd` | **[planned]** `Conv` — every coordinate convention in `SD-CONV` as constants and static helpers (gravity, up, compass axes, sun vector, tangent basis with the horizontal-surface fallback). No basis may be constructed anywhere else. |
| `src/core/hash64.gd` | **[planned]** `Hash64` — splitmix64 mixing, `unit_float`, and `jitter_vec3` for deterministic field-sample jitter (`SD-ENV-4`, `SD-RNG-4`). |
| `src/core/rng_stream.gd` | **[planned]** `RngStream` — per-tip event-advanced RNG with `derive(branch_index)` substreams and a dev-build draw counter (`SD-RNG-1/2`). |
| `src/core/sim_clock.gd` | **[planned]** `SimClock` — fixed one-game-hour tick at every speed, speed→ticks/s mapping, and `advance_ticks()` for deterministic test/harness/UI-script driving (`SD-TIME-1/2`). |

### World (static geometry, surface queries, lighting, cameras)

| Path | Summary |
|------|---------|
| `src/world/world.tscn` / `world.gd` | **[planned]** `World` — builds the tower at load, owns `SurfaceQuery`, `SeedAnchors`, `SkySun`, and `CameraRig`. |
| `src/world/tower_spec.gd` | **[planned]** `TowerSpec : Resource` — parametric tower description; single source of truth for mesh, collision, SDF, seed anchors, and the coverage-metric opening mask. |
| `src/world/tower_spec_default.tres` | **[planned]** Committed tower defaults (3.5 m tall, 2.0 m radius, north doorway, east window recess, top lip). |
| `src/world/tower_builder.gd` | **[planned]** `TowerBuilder` — generates the `ArrayMesh`, the `ConcavePolygonShape3D` from the *same* triangles, and the per-face material array; runs the `SD-CONV-3` outward-normal assertions including the SDF cross-check. |
| `src/world/tower.gd` | **[planned]** `Tower : StaticBody3D` — hosts the generated mesh and collision on physics layer 1 (SURFACE); applies the brick material with cylindrical UVs. |
| `src/world/tower_sdf.gd` | **[planned]** `TowerSdf` — analytic signed distance and gradient derived from `TowerSpec`; backs nearest-surface adhesion queries and the field's shell projection. |
| `src/world/surface_query.gd` | **[planned]** `SurfaceQuery` — the only interface the simulator has to the world: physics raycast (exact collision), analytic nearest-surface, tangent basis, per-face material lookup, shell projection. |
| `src/world/material_registry.gd` | **[planned]** `MaterialRegistry` / `SurfaceMaterialDef : Resource` — `material_id → {name, A_m, in_coverage_denominator}` (INV-10). |
| `src/world/seed_anchors.gd` | **[planned]** `SeedAnchors` — derives the four compass anchors by raycast at load with the deterministic azimuth search, caches them, marks unavailable ones (`SD-AGENCY-1/2/3`). |
| `src/world/sky_sun.gd` | **[planned]** `SkySun` — `DirectionalLight3D` plus procedural sky driven by `Solar`; applies the time-lapse render blend. The light's forward is `−S` (`SD-CONV-9`). |
| `src/world/camera_rig.gd` | **[planned]** `CameraRig` — four canonical `Camera3D`s with authored transforms that are never written at runtime; `select()` only toggles `current`. |

### Environment layer

| Path | Summary |
|------|---------|
| `src/env/cell_grid.gd` | **[planned]** `CellGrid` — cell addressing, 64-bit key packing, cell↔world conversion. |
| `src/env/sparse_field.gd` | **[planned]** `SparseHashField` — sparse allocation plus parallel `PackedFloat32Array` channels; trilinear read and central-difference gradient are the only read primitives (no nearest-cell accessor exists). |
| `src/env/environment.gd` | **[planned]** `IvyEnvironment` — public environment API, per-tick light EWMA, `deposit_crowding` (the sole write path from physiology), and `invalidate(aabb)`. |
| `src/env/solar.gd` | **[planned]** `Solar` — NOAA solar position, sun direction and elevation, irradiance-weighted day-average direction, and the diel growth gate. |
| `src/env/light_bake.gd` | **[planned]** `LightBake` — sky-view factor and 24-bit hourly visibility on a coarse grid, plus the full-resolution `P(cell, hour)` table. |

### Simulation layer

| Path | Summary |
|------|---------|
| `src/sim/sim_root.gd` | **[planned]** `SimRoot : Node` — owns the clock, environment, tips, and plant data; runs the fixed-order tick loop. |
| `src/sim/sim_context.gd` | **[planned]** `SimContext` — injected bundle of params, environment, surface, solar, plant data, tips, anchors. |
| `src/sim/tip.gd` | **[planned]** `Tip` — per-tip state: spec §3 variables plus lifecycle, ring frame, leaf-node accumulators, and cached vigour. |
| `src/sim/tip_manager.gd` | **[planned]** `TipManager` — lifecycle state machine, soft/hard tip cap, branch-probability taper, vigour-based retirement. |
| `src/sim/physiology.gd` | **[planned]** `Physiology` — pure static functions for `f_L`, `f_C`, `f_S`, `H`, all direction weights, growth rate, branch rate, and crowding deposits. The only writer to the crowding field. |
| `src/sim/growth_step.gd` | **[planned]** `GrowthStep` — one segment: the §21 direction sum, collision resolve, floating-length update, persistence update, branch draw, leaf-node draw, in the fixed `SD-RNG-3` order. |
| `src/sim/plant_data.gd` | **[planned]** `PlantData` — append-only structure-of-arrays for segments and leaf instances. Has no removal path, which is how INV-2 is enforced. |
| `src/sim/leaf_placer.gd` | **[planned]** `LeafPlacer` — internode spacing, phyllotaxy, orientation stack, size model, atlas tier selection, colour, and crowding suppression. Emits fully-resolved leaf instances into `PlantData`. |

### Presentation layer

| Path | Summary |
|------|---------|
| `src/render/plant_render.tscn` / `plant_render.gd` | **[planned]** `PlantRender` — hosts the stem chunks and the two leaf `MultiMeshInstance3D`s; syncs from `PlantData` by high-water mark each frame. |
| `src/render/stem_mesh.gd` | **[planned]** `StemMeshBuilder` — chunked incremental tube append; never rebuilds frozen geometry. |
| `src/render/leaf_renderer.gd` | **[planned]** `LeafRenderer` — preallocated static and growing `MultiMesh` buffers with freeze migration. |
| `src/render/leaf_atlas.gd` | **[planned]** `LeafAtlas` — parses `leaf_atlas.json` (rect, aspect, `alpha_fill`, `tier`, petiole anchor). |
| `src/render/shaders/leaf.gdshader` | **[planned]** Per-instance atlas sub-rect, alpha scissor with alpha-to-coverage, culling disabled, backlight transmittance. |
| `src/render/materials/leaf_material.tres` | **[planned]** `ShaderMaterial` wiring the LeafSet017 colour / normal / roughness maps. |
| `src/render/materials/tower_brick.tres` | **[planned]** Project-side copy of the ambientCG brick material with cylinder UV scaling; the asset `.tres` stays untouched. |

### Metrics and UI

| Path | Summary |
|------|---------|
| `src/metrics/coverage.gd` | `CoverageMetric` — surface-bucket occupancy in tower-cylindrical coordinates (SD-METRIC-1/2/3/5/6), opening exclusion, stem-bucket diagnostic, 12-sector asymmetry, sun/shade split by seed azimuth. Reads only `PlantData`. |
| `src/metrics/blacklist.gd` | **[planned]** `BlacklistAssertions` — automatable artifact checks and the numeric auto-screens for banding and coplanar leaves. |
| `src/metrics/run_hash.gd` | **[planned]** `RunHash` — canonical determinism fingerprint used by the AS-4 test and the harness. |
| `src/ui/hud.tscn` / `hud.gd` | **[planned]** `Hud` — four anchor buttons, pause and three speeds, date/time readout, time-lapse indicator. |
| `src/ui/dev_overlay.tscn` / `dev_overlay.gd` | **[planned]** `DevOverlay` — reflection-driven live editing of every `IvyParams` property plus light/crowding field visualization. |

### Tests

| Path | Summary |
|------|---------|
| `test/test_gut_smoke.gd` | GUT smoke tests (infrastructure sanity check). |
| `test/test_conv.gd` | **[planned]** Coordinate conventions: gravity, solar-noon sun vector, tangent basis including the horizontal-surface degenerate case. |
| `test/test_conv_light.gd` | **[planned]** Render/sun coupling — the directional light's forward equals `−S`. |
| `test/test_solar.gd` | **[planned]** Day length, sunrise/sunset azimuths, night elevation for the fixed epoch. |
| `test/test_tower_geometry.gd` | **[planned]** Outward-normal assertions over every triangle; mesh and collision built from identical triangles; doorway and window present in collision. |
| `test/test_surface_query.gd` | **[planned]** SDF sign and raycast agreement, nearest-surface at creases, per-face material lookup, seed-anchor derivation and doorway avoidance. |
| `test/test_params.gd` | **[planned]** Every parameter present with its specified default; `content_hash()` stability. |
| `test/test_params_conformance.gd` | **[planned]** Source scan asserting no §30 literal appears outside `src/params/`. |
| `test/test_rng.gd` | **[planned]** Stream reproducibility, substream independence, jitter bounds, and a source scan for stray random calls. |
| `test/test_field.gd` | **[planned]** Trilinear exactness, gradient recovery, zero gradient on a uniform field, out-of-shell fallback, shell projection. |
| `test/test_physiology.gd` | **[planned]** All response functions and weights against the spec's worked values; bounded growth-budget loop. |
| `test/test_geometry.gd` | **[planned]** Direction sum, degenerate fallbacks, adhesion-range vs contact-distance distinction, ground clamp and dormancy, no-penetration guarantee. |
| `test/test_tip_lifecycle.gd` | **[planned]** State transitions, cap taper, retirement rules and exemptions. |
| `test/test_time.gd` | **[planned]** Speed-change invariance, diel-gate mean preservation, day/night gate magnitudes. |
| `test/test_leaf_placement.gd` | **[planned]** Nodes per metre rather than per tick, tip suppression, shade etiolation, atlas adjacency, offset ladder, size distribution. |
| `test/test_determinism.gd` | **[planned]** Two identical runs produce identical tip count, bit-identical stem length, identical leaf count and run hash. |
| `test/test_metric.gd` | Bucket mapping round-trip, opening exclusion, synthetic 100% coverage, sun/shade split by seed azimuth, AS-1 coupling rule, 12-sector asymmetry, lip-reached, RNG independence. |
| `test/test_blacklist.gd` | **[planned]** Each automatable artifact check fires on a synthetic violation and stays quiet on a clean plant. |

### Dev tooling

| Path | Summary |
|------|---------|
| `tools/take_screenshot.gd` / `.tscn` | Headless screenshot runner for the main scene. Unchanged by the 3D conversion. |
| `tools/run_ui_script.gd` / `.tscn` | UI script runner. **To be extended** with `CAMERA`, `SEED`, `SPEED`, `ADVANCE_DAYS`, `SET_PARAM`, `DUMP_METRICS`, and `ASSERT` verbs (`AR-UI-3`). |
| `tools/ui_scripts/smoke.txt` | Minimal UI script smoke test (wait + screenshot). Must stay green through the 3D conversion. |
| `tools/ui_scripts/m1_growth.txt` | **[planned]** M1 exit gate — grow 30 game-days and capture. |
| `tools/ui_scripts/canonical.txt` | **[planned]** All four canonical camera angles at a fixed game-day. |
| `tools/ui_scripts/as6_silhouette.txt` | **[planned]** Ground-level silhouette-break capture. |
| `tools/ui_scripts/reseed.txt` | **[planned]** Re-seed flow: plant reset, field warm-up, anchor greying. |
| `tools/ui_scripts/time_controls.txt` | **[planned]** Speed and pause UI, time-lapse indicator. |
| `tools/ui_scripts/dev_tuning.txt` | **[planned]** Live parameter change visible without a restart (M3 exit condition). |
| `tools/acceptance_harness.gd` / `.tscn` | **[planned]** Headless acceptance runner for AS-1 through AS-6, recording the parameter content hash. |
| `tools/fetch_assets.sh` | Re-downloads the ambientCG CC0 source archives. |

### Assets

| Path | Summary |
|------|---------|
| `assets/CREDITS.md` | Provenance and licensing for all third-party (CC0) assets, plus notes on derived files. |
| `assets/materials/brick/Bricks094/` | Primary tower brick PBR set (colour, `_NormalGL`, roughness, AO, displacement) with a ready-made Godot material. |
| `assets/materials/brick/Bricks102/` | Alternate tower material, kept for in-engine A/B. |
| `assets/plants/ivy/LeafSet017/` | Primary ivy leaf atlas: composited `_Leaves_RGBA.png`, PBR maps, and `leaf_atlas.json`. |
| `assets/plants/ivy/LeafSet017/leaf_atlas.json` | Per-leaf UV sub-rects, aspect, petiole anchor, `alpha_fill` (coverage metric) and `tier` (health tier selection). Consumed read-only. |
| `assets/plants/ivy/LeafSet029/` | Seasonal leaf variation. **Not used in Phase 1**; retained for Phase 2 and as the transmittance reference. |
| `addons/gut/` | GUT test framework (local install, gitignored). |

---

## Cross-Reference

| System | Primary files |
|--------|----------------|
| Composition root | `src/main/main.tscn`, `src/main/main.gd` |
| Coordinate conventions | `src/core/conv.gd`, `test/test_conv.gd`, `test/test_conv_light.gd` |
| Determinism | `src/core/hash64.gd`, `src/core/rng_stream.gd`, `src/metrics/run_hash.gd`, `test/test_rng.gd`, `test/test_determinism.gd` |
| Time model | `src/core/sim_clock.gd`, `src/env/solar.gd`, `src/world/sky_sun.gd`, `test/test_time.gd` |
| Parameters | `src/params/ivy_params.gd`, `src/params/ivy_params_default.tres`, `src/ui/dev_overlay.gd` |
| Tower and surface queries | `src/world/tower_spec.gd`, `tower_builder.gd`, `tower_sdf.gd`, `tower.gd`, `surface_query.gd`, `material_registry.gd` |
| Environment field | `src/env/cell_grid.gd`, `sparse_field.gd`, `environment.gd`, `light_bake.gd` |
| Plant physiology | `src/sim/physiology.gd` |
| Growth geometry | `src/sim/growth_step.gd`, `src/sim/tip.gd`, `src/sim/tip_manager.gd`, `src/sim/plant_data.gd` |
| Leaf model | `src/sim/leaf_placer.gd`, `src/render/leaf_renderer.gd`, `src/render/leaf_atlas.gd`, `src/render/shaders/leaf.gdshader` |
| Stem rendering | `src/render/stem_mesh.gd` |
| Player agency | `src/world/seed_anchors.gd`, `src/ui/hud.gd` |
| Acceptance and metrics | `src/metrics/coverage.gd`, `src/metrics/blacklist.gd`, `tools/acceptance_harness.gd` |
| Cameras and screenshots | `src/world/camera_rig.gd`, `tools/take_screenshot.*`, `tools/run_ui_script.*`, `tools/ui_scripts/` |
| Testing | `test/`, `addons/gut/` |

---

## Signal Flow Summary

Phase 1 deliberately uses **very few signals**. The layer boundaries in `AR-OVER-1` are enforced by
dependency direction and by the absence of reverse APIs, not by an event bus. There is no autoload
and no service locator (`AR-OVER-3`).

**Per-tick data flow (no signals):**

```
SimClock ──ticks──► SimRoot._tick()
                      │
                      ├─► IvyEnvironment.tick()         reads LightBake table, updates light EWMA
                      ├─► Solar.diel_gate()             scalar growth-magnitude gate
                      ├─► TipManager.refresh_vigour()
                      ├─► Physiology / GrowthStep       reads Environment + SurfaceQuery,
                      │        │                        appends to PlantData
                      │        └─► IvyEnvironment.deposit_crowding()   ← the ONLY write back (INV-1)
                      └─► TipManager.apply_lifecycle()
```

**Per-frame presentation flow (pull, not push):** `PlantRender.sync(plant)` compares its
high-water marks against `PlantData`'s append counters and copies only new segments and leaves.
Per-segment and per-leaf signals were deliberately rejected — at Grow speed there are roughly 640
segment and 480 leaf events per second, and signal dispatch at that rate costs more than the copy.

**UI signals (M3):** `Hud` emits `speed_changed(speed)` and `anchor_selected(compass)`, consumed by
`SimRoot`. `DevOverlay` writes directly to the injected `IvyParams` instance; subsystems read
parameter values every tick, so no change notification is needed.
