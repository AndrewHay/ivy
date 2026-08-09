# Ivy — Implementation Notes

System contracts, API signatures, and cross-system invariants live here as features are designed.

## Bootstrap state

- Godot 4.4 project with GUT 9.4.0 (local install under `addons/gut/`, gitignored)
- Main scene: `res://src/main/main.tscn`
- Tests: `res://test/`
- Dev tools: `res://tools/take_screenshot.tscn`

Add sections per system as the Gameplay Architect defines them.

---

# Phase 1 System Contracts

**Stage:** Systems Designer · **Date:** 2026-08-08 · **Next stage:** Gameplay Architect

**Inputs used:** `DESIGN.md` (Game Director Phase 1 output — vision, G1–G6, INV-1–INV-10, AS-1–AS-6,
artifact blacklist, six-criterion rubric, M1–M4, non-goals, R-1–R-6, open decisions D-1–D-5) ·
`ivy_simulator_v0.1.md` §1–§35 (authoritative equations and the §30 parameter table) ·
`assets/CREDITS.md` · `assets/plants/ivy/LeafSet017/leaf_atlas.json` ·
`.cursor/rules/game-design-philosophy.mdc` · `work-items/WORK_ITEMS.md`.

**Authority order.** `DESIGN.md` invariants override everything. `ivy_simulator_v0.1.md` is
authoritative for equations. This document is authoritative where the spec is silent (leaves,
time model, tip cap, coordinate frame, lifecycle, metrics) and records every place it deviates
from the spec, with rationale. Rules are given stable IDs (`SD-*`) so downstream stages can cite
them.

---

## SD-CONV — Coordinate, unit, and frame conventions

The spec was written in a Z-up frame. Godot is **Y-up, right-handed, −Z forward**. Every place a
convention is implied is listed below. Silently getting any of these wrong produces vines growing
sideways out of the tower or a sun that lights the render but not the plant.

| ID | Spec site | Implied convention | Godot Phase 1 rule |
|---|---|---|---|
| SD-CONV-1 | §20 gravity `G = (0,0,-1)` | Z-up | **`G = (0, -1, 0)`.** This is the only world axis that enters the §21 direction sum. |
| SD-CONV-2 | §5 solar position | geographic azimuth/elevation | **World frame: +Y up, north = −Z, east = +X, azimuth `Az` clockwise from north.** Sun direction `S = (cos α · sin Az, sin α, −cos α · cos Az)`. At solar noon in the northern hemisphere `Az = 180°` ⇒ `S = (0, sin α, cos α)`, i.e. the sun is toward +Z (south). Unit-test this exact case. |
| SD-CONV-3 | §5 `max(0, n·S)` | outward surface normal | `n` is the **outward** world normal from the collision query. The tower mesh must have no inverted faces — an inverted normal makes the tower's interior "sunlit" and silently breaks AS-2. Assert `dot(n, x − axis_point) > 0` for all wall samples at bake time. |
| SD-CONV-4 | §5 `SVF(x)` | upper hemisphere | Hemisphere about **+Y**, further restricted to the hemisphere about `n`. |
| SD-CONV-5 | §16 `∇_S`, surface tangent basis | unstated | `u = normalize(cross(n, (0,1,0)))`, `v = cross(n, u)`. **Degenerate when `n ∥ ±Y`** — which is exactly the tower's top lip, where AS-6 lives. Fallback when `‖cross(n, (0,1,0))‖ < 0.05`: `u = normalize(cross(n, (0,0,1)))`. Must be unit-tested on a horizontal surface. |
| SD-CONV-6 | §1 Luft "upward bias ≈ phototropism" | Z-up | Not used — replaced by the light field (§15/§16). Any residual `up` literal is `(0,1,0)`. |
| SD-CONV-7 | §21, §23 | handedness | Cross-product argument order fixes whether leaf cards and branch offsets flip. Fix the order once in the tangent-basis helper (SD-CONV-5) and never construct a basis inline. |
| SD-CONV-8 | throughout | units | **1 Godot unit = 1 metre.** Tower axis is **+Y**. All spec lengths are metres, all rates are per **game-day**. |
| SD-CONV-9 | §5 render coupling | — | The `DirectionalLight3D`'s forward (its local −Z axis) equals `−S`. Assert `dot(light.global_basis.z, S) > 0.999` in a unit test. One sun, one source of truth. |

---

## SD-TIME — Time model  *(resolves D-1)*

**The conflict (R-5).** At `r_max = 0.12 m/game-day` a lead tip needs ~30 game-days to reach the top
lip and ~150 to cover the tower. A day/night cycle slow enough to enjoy makes coverage take half an
hour; a cycle fast enough for coverage makes the sun strobe and collapses `τ_L = 3 days` into
seconds.

**Resolution: separate the simulation clock from the presentation clock. Only the presentation
clock changes with speed.**

| ID | Rule |
|---|---|
| SD-TIME-1 | **The simulation tick is fixed at `dt_sim = 1/24 game-day` (one game-hour), at every speed.** Speed changes only how many ticks are executed per real second. Nothing about the plant depends on wall-clock time or frame rate. This is the mechanism by which INV-4 and INV-7 hold; it is not an optimization and may not be traded away. |
| SD-TIME-2 | Speeds: **Pause** (0) · **Watch ×1** = 60 s wall-clock per game-day (0.4 ticks/s) · **Fast ×10** = 6 s/day (4 ticks/s) · **Grow ×50** = 1.2 s/day (20 ticks/s). Grow speed reaches 150 game-days in 180 s, satisfying AS-5's 3-minute budget by construction. |
| SD-TIME-3 | Changing speed mid-run, or pausing, **must not change the result**. Directly testable: a run held at Watch for 20 days then Grow to day 60 must produce byte-identical tip count and total stem length to a run held at Grow throughout. This is a required test, not a nice-to-have. |
| SD-TIME-4 | **Render-sun blending.** At Grow speed the sun would traverse the sky in 1.2 s, which strobes. The *rendered* `DirectionalLight3D` and sky are driven by `S_render = slerp(S_dayavg, S(t), b)` where `b = smoothstep(10 s, 30 s, T_day_wallclock)` and `S_dayavg` is the irradiance-weighted mean sun direction for the fixed date. `b = 1` at Watch (instantaneous, real day/night), `b = 0` at Fast and Grow (steady daily-average lighting). Sky exposure and ambient blend the same way. **The light field is never blended — it always uses `S(t)` at tick resolution.** The plant's inputs are untouched; only the picture changes. |
| SD-TIME-5 | When `b < 1`, the time-control UI shows a "time-lapse — average daylight" indicator, so the player is never misled into thinking day/night stopped. |
| SD-TIME-6 | Fixed epoch: **latitude 51.5° N, longitude 0°, timezone UTC, day-of-year 105 (15 April)**. Chosen because at this declination sunrise/sunset sit close to due east/west, which maximizes the cleanliness of the north/south asymmetry AS-2 depends on, and day length (~13.5 h) is generous enough for growth. Runs start at **06:00 local**, so the first thing the player sees is dawn. |
| SD-TIME-7 | **Light-field warm-up.** Every run (and every re-seed) advances the environment alone for `light_warmup_days = 12` game-days (4·τ_L) with no tips, so `D_L` is converged before growth begins. Without this, the sun-side and shade-side comparison runs of AS-2 start from different field states and the comparison is not fair. Warm-up costs nothing — it is a field-only loop. |

### SD-TIME-8 — The diel growth gate (night is real)

**A conflict between `DESIGN.md` and the spec.** The Director requires that "below the horizon,
light contribution goes to zero and growth effectively stops. Night is real" and AS-3 tests it. But
spec §24 gives `r = r_max · f_L · f_M · f_C · f_S`, and `f_L` is a function of the *accumulated*
light `D_L`, which barely moves overnight at `τ_L = 3 days`. **As specified, the plant grows at
essentially full rate all night.** AS-3 cannot pass without a change.

Resolution — a **mean-preserving diel gate** on growth *magnitude only*:

```
g(t)   = γ_night + (1 − γ_night) · [max(0, sin α(t))] ^ 0.35      γ_night = 0.05
g_ref  = mean of g over the previous simulated game-day           (≈ 0.45 for SD-TIME-6)
ĝ(t)   = clamp(g(t) / g_ref, 0, 3)
r      = r_max · f_L · f_M · f_C · f_S · ĝ(t)
```

| ID | Rule |
|---|---|
| SD-TIME-8a | The gate uses solar **elevation only** — a scalar. It scales growth *rate*. It may **never** appear in any directional term (`P`, `R`, `A`, `L`, `C`, `G`). INV-3 protects the plant from chasing the instantaneous sun *direction*; that protection is fully intact. Record this as **INV-3a: the instantaneous sun may modulate growth magnitude, never growth direction.** |
| SD-TIME-8b | Dividing by `g_ref` makes the gate **mean-preserving over a game-day**. Total daily elongation, and therefore `r_max`'s calibration and AS-1's 150-day budget, are unchanged. Only the *within-day distribution* changes. Without this normalization total growth roughly halves and AS-1 fails. |
| SD-TIME-8c | Resulting behaviour: `ĝ ≈ 2.1` at solar noon, `ĝ ≈ 0.11` at night. Growth at night is ~5% of the noon rate — "near zero" for AS-3, without a discontinuity and without ever fully stopping (a hard zero makes the debug rate readout look broken rather than nocturnal). |
| SD-TIME-8d | Branching is per **metre grown** (§26) and so is leaf node placement (SD-LEAF-2), so neither is affected by the gate. INV-4 holds. |
| SD-TIME-8e | **Requires Director ratification** — it is a change to a spec equation in service of a `DESIGN.md` requirement. Documented fallback if rejected: drop the gate, and reword AS-3 to test that *instantaneous light `P` and the render* go to zero at night while growth continues. That fallback is materially worse for the target experience ("Oh, it's actually growing" is much stronger when growth visibly pulses with the sun), which is why the gate is the recommendation. |

---

## SD-ENV — Environment layer

Storage is the world-space sparse hash field (Director's decision, not relitigated). In Phase 1
only cells intersecting the tower collider are ever allocated, so it behaves as a surface field with
a world-space address.

| ID | Rule |
|---|---|
| SD-ENV-1 | **Cell size `field_cell = 0.06 m`** — exactly 2× `segment_length`, so a tip crosses a cell every ~2 segments. Coarser aliases the growth path to the grid; finer wastes memory and makes gradients noisy. ~12,200 allocated cells for a 2 m × 3.5 m tower. |
| SD-ENV-2 | Per cell: `P̄_L` (EWMA mean light), `C` (crowding), `A_m` (material adhesion suitability, looked up per material — INV-10), `SVF` (static), `V_hours` (static 24-bit direct-sun visibility mask), `f_M` (present, pinned 1.0 — INV-9). `D_L = 0.0864 · P̄_L`. |
| SD-ENV-3 | **All field reads are trilinearly interpolated. Nearest-cell sampling is forbidden.** This is the primary mitigation for R-3 (grid banding, artifact-blacklist item 3). |
| SD-ENV-4 | **Deterministic sample jitter.** Before interpolating, offset the sample point by a vector hashed from `(tip_id, segment_index, channel)` with magnitude ≤ `0.35 · field_cell`. Converts residual grid structure into noise. Deterministic, so INV-7 is safe. |
| SD-ENV-5 | **Gradients by central differences at `ε = 1.5 · field_cell` (0.09 m)**, not at `ε = field_cell` — sampling at exactly the cell pitch aliases the gradient onto the cell axes, which is precisely the banding failure. Project the result onto the tangent plane (SD-CONV-5) before use. Four samples per gradient per §16. |
| SD-ENV-6 | **Static-geometry precomputation.** In Phase 1 nothing moves, weather is pinned to 1.0, and the date is fixed, so the sun path repeats exactly every game-day and `P(cell, hour)` is a **pure function** of `(cell, hour)`. Bake it once into a 12,200 × 24 `PackedFloat32Array` (≈1.2 MB). The per-tick environment update then reduces to one table lookup and the EWMA. `SVF` bakes once by cosine-weighted hemisphere raycast (64 rays/cell); `V_hours` bakes once as 24 raycasts/cell. This is what makes 20 ticks/s at Grow speed nearly free. |
| SD-ENV-7 | The bake is a **cache, not an architecture**. It sits behind `environment.invalidate(aabb)`, which Phase 2 (awnings, moving geometry) will call. Do not let the cache leak into the physiology layer's API. |
| SD-ENV-8 | Light memory per §7 with `τ_L = 3 game-days`, applied once per tick with `a = exp(−dt_sim/τ_L)`. Changing `light_memory` at runtime recomputes `a` on the next tick only; it never rewrites stored history. |
| SD-ENV-9 | `W(t)` and `W_sky(t)` exist in the equations and are pinned to 1.0 (INV-9). Do not delete, do not implement. |
| SD-ENV-10 | Expected field values for SD-TIME-6, to be used as the regression target for W-009: **south wall `D_L ≈ 26`, `f_L = 1.00` (saturated); north wall `D_L ≈ 2.5`, `f_L ≈ 0.57` (diffuse only)**. Growth-rate ratio ≈ 1.76×, branch-rate ratio ≈ 1.94×; these compound, so AS-2's ≥40% stem-length asymmetry should be met comfortably. If measured values differ by more than ~30%, the sun model is wrong, not the tuning. |

---

## SD-PHYS — Physiology layer

Spec §10–§15, §18, §24, §25, verbatim. No deviations except SD-TIME-8.

| ID | Rule |
|---|---|
| SD-PHYS-1 | `f_L`, `f_M` (=1), `f_C = e^{−0.8C}`, `f_S = 1 − 0.5(F/F_max)²`, `H = f_L · f_M`, and the weights `w_P`, `w_R`, `w_L`, `w_C` exactly as specified. |
| SD-PHYS-2 | Growth budget per §25: `B += r · dt_sim`; while `B ≥ h` emit one segment and `B −= h`. The `while` loop must be bounded (`max_segments_per_tick = 8`) to survive a pathological parameter edit in the dev overlay; hitting the bound logs a warning. |
| SD-PHYS-3 | **Physiology is the only layer permitted to write to the environment, and only to the crowding channel** (INV-1). In particular, the crowding deposited by a leaf node is computed **in physiology** from `f_L` and branch order (SD-LEAF-8); the geometry layer consumes that number to size the card but never writes it back. Geometry never writes to physiology at all. |
| SD-PHYS-4 | Every §30 parameter is read from one authoritative resource (INV-6). No literal from §30 may appear at a call site. Parameter edits take effect on the next tick and affect **future growth only** — changing `segment_length` mid-run must not re-segment existing stems (INV-2). |

---

## SD-GEO — Growth geometry layer

Spec §14, §16–§23, with `G = (0,−1,0)` (SD-CONV-1).

| ID | Rule |
|---|---|
| SD-GEO-1 | **Two distinct surface thresholds.** The spec conflates them. `d_A = 0.15 m` is the *adhesion range* (the §17 attraction falloff). `d_contact = 0.02 m` is **attachment**: `F` resets to 0 only when `d ≤ d_contact`. Resetting `F` at `d_A` would zero the float counter while the vine is still visibly airborne, which destroys the sag behaviour AS-6 depends on. |
| SD-GEO-2 | If `‖U‖ < 1e−4` (all terms cancel), fall back to `d = P`. If nearest-surface `d < 1e−5`, skip the adhesion term rather than dividing by it. |
| SD-GEO-3 | **No ivy–ivy collision.** Real ivy grows over itself, and self-collision is expensive and produces jitter. Crowding handles density. Stated explicitly so the Architect does not build it. |
| SD-GEO-4 | The ground plane is on a **separate physics layer that the simulator never queries**, and its material has `A_m = 0`. Additionally clamp `x_new.y ≥ 0.02 m`; if the clamp fires on 5 consecutive segments the tip goes DORMANT. Together these make artifact-blacklist item 6 ("ivy growing on the ground plane") unreachable by construction rather than by tuning. |
| SD-GEO-5 | The doorway/window recess interiors **are** simulated surfaces with brick `A_m = 1.0`. They are excluded from the coverage *denominator* (SD-METRIC-2) but never from the simulation — ivy travelling into a recess is rubric criterion 3. |
| SD-GEO-6 | Branch creation: initial direction is the parent's `d_actual` rotated **45°–75°** (uniform draw) about the local wall normal, sign alternating per branch index; position offset `0.005 m` along that direction so parent and child do not emit a doubled stem. Child inherits `o+1`, `F` from parent, `s = 0`, `B = 0`, fresh `R`, and a **new RNG substream** `hash(parent_seed, branch_index)`. |
| SD-GEO-7 | Segments are appended to the stem mesh incrementally. Full rebuilds are forbidden — at 15,000 segments a rebuild per tick is an instant AS-5 failure. |

---

## SD-TIP — Tip lifecycle and the tip cap  *(resolves D-3)*

### States

`SEEDED → GROWING ⇄ FLOATING`, and `GROWING|FLOATING → DORMANT | DEAD`. No resurrection in Phase 1.

| Transition | Condition |
|---|---|
| SEEDED → GROWING | first tick |
| GROWING → FLOATING | nearest-surface `d > d_contact`; `F` begins accumulating; `w_G = r_F^{0.7}` engages |
| FLOATING → GROWING | `d ≤ d_contact`; `F ← 0` |
| FLOATING → DEAD | `F > max_float` (0.40 m) |
| GROWING → DORMANT | retired at the tip cap (below), or stalled: daily elongation `< 0.01 m/day` for 3 consecutive game-days, or ground-clamped 5× (SD-GEO-4) |

**DORMANT and DEAD tips keep all their geometry** (INV-2). A dormant tip simply stops. Nothing ever
disappears from screen.

### The cap  *(resolves D-3, mitigates R-6)*

| ID | Rule |
|---|---|
| SD-TIP-1 | **`tip_cap_soft = 96`, `tip_cap_hard = 160`.** The hard cap is the documented, never-exceeded number AS-5 requires. |
| SD-TIP-2 | Below the soft cap: branching per §26, unmodified. |
| SD-TIP-3 | Between soft and hard, and at and above the hard cap, branch probability is scaled by a single continuous ramp that lands on a **positive floor** `branch_scale_floor` (not zero) rather than tapering to zero: `q = branch_scale_floor + (1 − branch_scale_floor) · clamp((N_hard − N)/(N_hard − N_soft), 0, 1)`. Hence `q = 1.0` for `N ≤ N_soft`, `q` falls linearly to `q = branch_scale_floor` at `N = N_hard`, and `q = branch_scale_floor` for all `N ≥ N_hard`. The function is continuous everywhere — the largest step between adjacent tip counts is `(1 − branch_scale_floor)/(N_hard − N_soft) ≈ 0.0153`, so there is **no pop when the cap is approached** (W-045). The floor is deliberately positive: a zero floor makes SD-TIP-4's swap structurally unreachable (that was the W-037 defect), and it is deliberately small so that churn at saturation stays a slow trickle. |
| SD-TIP-4 | At and above the hard cap, `q` is held at `branch_scale_floor` (SD-TIP-3), so the per-segment branch draw still fires — at that reduced rate. When it fires, a new branch is created only by **retiring** (→ DORMANT) the least-vigorous live non-floating tip, where `vigour = f_L · f_C · f_S` sampled at that tip, and only if the branching parent's vigour exceeds the retiree's by a factor of `retire_margin` (1.25), which prevents thrash. **Intended steady state at saturation is a slow churn** — at most one retirement per *successful* branch, and successful branches are throttled to `branch_scale_floor` of the unthrottled rate — **not** the full-rate one-in-one-out churn that a floor of 1.0 would produce. Because SD-TIP-4 retires the least-vigorous (hence most-shaded) tip, keeping the floor low is what bounds shaded-tip retirement; `retire_margin` remains the designated lever for the AS-1 shaded-floor tension (see `DESIGN.md`), and `branch_scale_floor` is orthogonal to it (it sets *how often* a swap is attempted, not *which* tip is chosen). |
| SD-TIP-5 | **Never retire a FLOATING tip.** Freezing a vine in mid-air reads as a broken floating stem and trips artifact-blacklist item 2. Floating tips are exempt until they reattach or die naturally at `max_float`. |
| SD-TIP-6 | **Never retire a tip above `0.8 · H_tower` if fewer than 3 such tips exist.** This protects the silhouette-break behaviour AS-6 tests. |

**Why this behaviour and not the alternatives.** Retiring the *oldest* tips kills the lead tips —
exactly the growth front that rubric criterion 5 and AS-6 need, so it is rejected. A global growth
slowdown is invisible as a cause, feels like the game breaking, and mushes the sun/shade contrast
that G2 depends on, so it is rejected. Vigour-based retirement does something better than merely
being harmless: **the shaded side's weak tips go dormant first while the sunny side keeps
branching, so the cap itself amplifies the light asymmetry.** The mechanism that exists to protect
performance ends up strengthening the project's load-bearing property.

---

## SD-LEAF — Leaf presentation model

**Why this section exists.** R-2: the spec is entirely about stems and says nothing about leaves,
yet leaves are what decide whether Phase 1 succeeds. This is the design of that missing model. It is
written against what actually exists in the repo: `LeafSet017_Leaves_RGBA.png`, six photographed
*Hedera helix* leaves with per-leaf UV sub-rects and a petiole anchor at `[0.5, 1.0]` of each rect.

Observed atlas content, which the rules below depend on:

| Tier | Leaf ids | Character |
|---|---|---|
| **H — healthy** | `a`, `c`, `e` | larger, more saturated, cleaner, classic palmate silhouette |
| **W — weathered** | `b`, `d`, `f` | smaller, paler and greyer, mottled, damaged edges |

### SD-LEAF-1 — The card

A leaf is a **3×3 vertex patch (9 verts, 8 tris)**, not a flat quad, cupped 8–12° along its long
axis. A flat quad reads as a decal and never catches a highlight; the cup is the single cheapest and
strongest anti-decal measure and it also guarantees no two leaves are ever exactly coplanar.
Material: single atlas texture, `cull_mode = disabled`, **alpha scissor at 0.5 with alpha-to-coverage**
— not alpha blend, which sorts badly across thousands of MultiMesh instances and is a direct route
to artifact-blacklist item 4. Roughness from the atlas roughness map (ivy is glossy; the specular
is a large part of "reads as real"). Transmittance/backlight tint `(0.30, 0.45, 0.18)` so leaves lit
from behind glow — this matters specifically in the ground-level silhouette camera that AS-6 uses.

### SD-LEAF-2 — Node spacing (spawn rate)

Leaves attach at **nodes**, placed per metre of stem grown, never per tick (INV-4).

```
internode = internode_base · (1 + 0.9 · (1 − f_L)) · (1 + 0.25 · (2u − 1))
internode_base = 0.040 m
```

- One leaf per node — *Hedera helix* is **alternate**, one leaf per node. ~25 leaves/m in full light.
- Internodes **lengthen in shade** (etiolation — real, and legible). At `f_L = 0.57` the internode
  is 0.057 m, so shaded stems are visibly leggier and sparser. **This is a second legibility channel
  for G2 that costs one multiply.**
- Segment length (0.03 m) and internode (~0.04 m) deliberately do not align. Each tip carries
  `distance_since_node`; when it exceeds the drawn internode, a node is placed at the interpolated
  point along the current segment.
- **Tip suppression:** no nodes in the last `0.06 m` of a live tip. Leading tips are bare, then
  leaves scale in behind them (SD-LEAF-5). This is what makes the growth front read as a front.

### SD-LEAF-3 — Phyllotaxy

Accumulate a divergence angle of **137.5°** (golden angle) per node about the stem axis, then blend
the resulting azimuth toward the nearest "flat" azimuth — perpendicular to the wall normal, i.e.
left/right along the wall — with weight `w_flat = 0.65`.

Rationale, and this matters: a pure 137.5° pinwheel reads as a **bottle brush**; a pure 180°
alternation reads as a **fern** and is instantly recognizable as procedural. Real climbing ivy
flattens its phyllotaxy against the wall while staying irregular. The 65% flattening gives the
left/right splay; the remaining 35% of the golden-angle signal supplies the irregularity that
defeats rubric criterion 6.

### SD-LEAF-4 — Orientation

Constructed in world space, Godot Y-up (SD-CONV):

1. `n_wall` — the wall normal stored on the node's segment. If the node is unsupported, use the last
   known contact normal; if none, `+Y`.
2. `t` — segment direction at the node.
3. Petiole direction `p = normalize(rotate(t, about n_wall, by ψ) + 0.35 · n_wall)`, where `ψ` is the
   SD-LEAF-3 azimuth. The `+0.35 · n_wall` pushes the leaf off the wall so the mat has thickness.
4. The leaf's local up (blade tip, opposite the petiole) points along `p`; its face normal starts at
   `n_wall`.
5. **Phototropic cant:** `n_leaf = normalize(n_wall + 0.45 · L̂)` where `L̂` is the §16 bounded light
   direction. Leaves on the sunny side visibly turn toward the mean light. Third free legibility
   channel for G2.
6. **Droop:** rotate about the petiole axis toward world down by `12° + 18° · (1 − f_L)`. Every leaf
   droops a little — that is what stops the mat looking like roof shingles — and shaded leaves hang
   more.
7. **Jitter**, all from the deterministic per-tip stream: ±22° tilt about the petiole axis, ±15° roll
   about the blade's long axis, ±8° yaw.
8. **Normal-offset ladder (anti-z-fight):** offset the card along `n_leaf` by
   `0.004 m + 0.0015 m · (node_index mod 5)`. Sequential leaves therefore sit on five distinct
   shells and no two nearby leaves can be coplanar within 0.002 m. Together with the SD-LEAF-1 cup
   this makes artifact-blacklist item 4 structurally unreachable.

### SD-LEAF-5 — Size

```
w = w_0 · s_order · s_age · s_light · s_var          w_0 = 0.075 m (blade width)
blade height = w / atlas_aspect[leaf_id]             (never stretch the photograph)
```

| Factor | Rule | Effect |
|---|---|---|
| `s_order = 1 / (1 + 0.18·o)` | branch order `o` | 1.00 / 0.85 / 0.74 / 0.65 at orders 0–3. Main runners carry big leaves, high-order twigs carry small ones. This is what produces rubric criterion 2's "thick mats and sparse skirmishers". |
| `s_age = smoothstep(0, 1, min(1, a / 0.12 m))` | `a` = **metres of stem grown past this node**, not elapsed time | Leaves within 12 cm of a live tip are visibly smaller and still expanding. The growth front reads as a front (rubric 5) for free. |
| `s_light = 0.80 + 0.30 · f_L` | sampled at node creation, frozen | 1.10 in full sun, 0.97 in shade. |
| `s_var = clamp(exp(0.16·z), 0.75, 1.35)` | `z` deterministic standard normal | CV ≈ 0.16, comfortably inside the ≤0.35 bound the blacklist auto-check enforces. |

`s_age` means a leaf's scale animates after creation. **This does not violate INV-2** — INV-2 forbids
*environmental* changes from rewriting existing geometry; a leaf finishing its own expansion is
intrinsic growth. Practically: only leaves within 0.12 m of a live tip are in the mutable buffer;
past that they freeze and migrate to the static MultiMesh.

**Botanical tension, stated deliberately.** Real *Hedera helix* shade leaves are *larger* and darker
than sun leaves. `s_light` inverts that. This is a knowing trade in favour of G2 legibility per the
Director's ruling that a readable effect beats an accurate one, and it is kept small (±10%) so it
never looks wrong. The dominant legibility signal is density and count, not size.

### SD-LEAF-6 — Atlas selection

```
P(healthy tier) = 0.25 + 0.65 · f_L      → 0.90 in full sun, 0.62 in deep shade
```
Then pick uniformly among the three ids in the chosen tier. **The sunny side is not just denser —
it is greener and cleaner, and the shaded side is visibly weathered.** This turns the atlas's own
photographic variation into the primary causation signal, at zero cost.

**Adjacency rule:** a node may not reuse the atlas id of either of the two preceding nodes on the
same stem; redraw once if violated. This is the preventative guard against artifact-blacklist item 7
(visible repetition).

**`LeafSet029` is not used in Phase 1.** Its autumn-tinted leaves are an explicit Phase 1 non-goal
and must not be smuggled in as "variation". It stays in the repo for Phase 2; its Scattering map is
the reference for the transmittance term.

### SD-LEAF-7 — Colour

Per-instance colour multiplied over the atlas albedo (MultiMesh instance colour):

- **Light tint:** `lerp(shade_tint, sun_tint, f_L)` with `shade_tint = (0.78, 0.86, 0.74)` (cooler,
  darker) and `sun_tint = (1.06, 1.04, 0.86)` (brighter, warmer/olive). Deliberately modest — strong
  enough that the two elevation screenshots read differently, weak enough that it never looks like
  two species.
- **Per-leaf value jitter:** `× (1 + 0.07·z)`, deterministic.
- **Age lightening:** `× lerp((1.10, 1.08, 0.92), (1,1,1), s_age)`. Real ivy tips are visibly paler;
  another free front-reading cue.

### SD-LEAF-8 — Leaf density and the crowding field

> **W-040 landed 2026-08-09. W-048's crowding tuning was applied, measured, and reverted the same
> day.** Live defaults are back to `leaf_crowd_k = 0.5`, `leaf_crowd_suppress = 0.55`,
> `leaf_crowd_floor = 0.35`. The reason is recorded as **W-050 and is a correction to this section's
> earlier reasoning, not a tuning preference** — read it before touching these values.

- **`C` is confined to `[0, 1]` by the implementation.** `Environment.deposit_crowding()` writes
  through `SparseHashField.add_slot(..., lo = 0.0, hi = 1.0)`, which is a hard `clampf`. An earlier
  revision of this section asserted the opposite — that the ceiling of 1 "was a tuning guideline, not
  an invariant" — and W-048 was decided on that basis. It is an invariant. Two consequences follow.
  `f_C = e^{−0.8C}` cannot fall below `e^{−0.8} ≈ 0.45`, so crowding cannot distinguish one leaf
  layer from three; and `lambda_b`'s `pow(1 − C, branch_crowd_exponent)` is safe only because of the
  clamp, so raising the ceiling requires changing that term in the same edit or branch probability
  goes NaN.
- **Leaves write crowding.** A node deposits `C += k_leaf · predicted_leaf_area / cell_area`
  (`k_leaf = leaf_crowd_k = 0.5`). Stems deposit a smaller amount. Crowding should mean "how much ivy
  is here", and leaves are most of the ivy. Per SD-PHYS-3 the predicted area is computed **in
  physiology** so INV-1 is not violated by geometry writing back.
- **`leaf_crowd_k` is a saturation-*rate* knob, not a suppression-*depth* knob.** Given the clamp,
  raising it changes nothing in cells already at `C = 1` and only makes below-saturation cells reach
  the ceiling sooner. On this tower the below-saturation cells are the shaded half. Measured: raising
  it to 0.85 moved sun-facing coverage by 1.2 points (93.67 → 92.47, already clamped) while shaded
  coverage fell 23 points (53.99 → 30.76), and bought only 4% of the volume overshoot. It is the
  wrong lever for the AR-BUDGET problem and an actively dangerous one for AS-1's shaded floor.
- **Crowding suppresses leaves.** `P(place leaf at node) = clamp(1 − leaf_crowd_suppress·C,
  leaf_crowd_floor, 1)`, live at 0.55 / 0.35. At `C = 1` interior placement falls to 0.45. The
  interior of a dense mat does not stack hidden layers of leaves. These two are genuinely
  density-gated in the way this section originally claimed for all three — they act through `C`
  rather than on it, so at low `C` they are near-inert and the sparse shaded half is spared. They
  were not the cause of the W-048 regression and remain available as levers.

> **W-048 re-decision, 2026-08-09 (Systems Designer, informed by W-050). Landed 2026-08-09 (Gameplay
> Fixer).** The rubric-2 "green mat" is a *sun-side leaf-density* problem (sunny 180° at 93.67% with
> ~1.5 redundant leaf layers; ≈60 m² of leaf area on 43 m² of wall), and the correct lever is the
> density-gated pair here, **not** `leaf_crowd_k` (held at 0.5) and **not** any volume brake
> (`branch_rate`/caps — see AR-BUDGET for why the SD-TIP-3 taper's homeostat makes those collapse the
> shaded floor first). **Applied values:** `leaf_crowd_suppress` **0.55 → 0.70**,
> `leaf_crowd_floor` **0.35 → 0.30**. Effect: at `C = 1`, `P = clamp(1 − 0.70·C, 0.30, 1)`
> falls 0.45 → 0.30 (thins the redundant sunny layers); at `C ≈ 0.1` (shaded), `P ≈ 0.93`, essentially
> unchanged. Measured (2026-08-09, two back-to-back runs, digit-for-digit): day-150 AS-1 = 74.58 / 96.23
> / 50.62 — all floors pass. ⚠️ **Shaded floor 50.62% is 0.62 points above the 50% floor.**
> Segment count increased to 43,743 (from 40,952) as predicted — thinner leaf deposit eases `f_C` and
> `λ_b`. AS-2 asymmetry 51.53% — essentially unchanged. INV-7 intact. **The `C ∈ [0,1]` clamp stays**
> (removing it requires a coordinated edit to `f_C` and `λ_b`'s `(1 − C)` term); crowding is a
> saturation-rate lever only — recorded here so it is not re-tried as a suppression-depth lever.

### SD-LEAF-9 — Budgets

Expected 7,000–12,000 leaves at full coverage (≈0.0035 m² each; the arithmetic behind AS-1 is in
SD-METRIC). `leaf_cap = 20,000`; beyond it, placement probability is globally scaled down — acceptable
for a cosmetic even though global scaling was rejected for growth rate. Rendering: two
`MultiMeshInstance3D`s sharing one material — `leaves_static` (frozen) and `leaves_growing`
(≤600 instances, updated per tick). Two draw calls total.

---

## SD-STEM — Stem presentation

- Radius `r_stem = 0.006 m · 1/(1 + 0.25·o) · clamp(s_from_tip / 0.15, 0.35, 1)` — tapering with
  branch order and toward the tip.
- 5-sided tube. At 6 mm radius more sides buy nothing.
- **Path smoothing (R-4):** render the segment polyline through a Catmull-Rom with 2 subdivisions per
  segment. R-4's faceting risk is in the *path*, not the tube — a vine running horizontally around a
  2 m radius at 3 cm segments will stair-step visibly without this.
- No aerial rootlet geometry in Phase 1.

---

## SD-AGENCY — Seed anchors and player controls  *(resolves D-4)*

**Anchors are derived from geometry at runtime, not authored transforms.**

| ID | Rule |
|---|---|
| SD-AGENCY-1 | `TowerSurface.get_seed_anchors()` computes four anchors at load. For each of the four compass azimuths (N = −Z, E = +X, S = +Z, W = −X per SD-CONV-2), cast a ray inward from `centre + outward·(R + 0.5)` at `y = 0.05 m`; take the hit, offset `0.01 m` along the hit normal. |
| SD-AGENCY-2 | If the ray misses or hits a collider tagged `opening`, search azimuth offsets in the fixed deterministic order `0, +5°, −5°, +10°, −10°, … , ±25°` until a valid wall hit is found. If none, that anchor is marked unavailable and greyed out in the UI. |
| SD-AGENCY-3 | The anchor set is computed **once at scene load and cached**. Recomputation mid-run is forbidden. |
| SD-AGENCY-4 | Seed tip initial state: `x = anchor + 0.01·n`, `P = normalize(up + 0.15·n)` (a slight outward lean so adhesion immediately pulls it back and the first segments hug the wall), `R` = random unit tangent, `B = 0`, `F = 0`, `s = 0`, `o = 0`. |

**Rationale for derivation over authoring.** The tower radius is an explicitly tunable range
(1.5–2.5 m); authored anchor transforms would silently desync the moment it changes or the tower is
re-modelled. Derived anchors land exactly on the collision surface the simulator queries, which
authored transforms would only approximate. And the raycast form keeps working unchanged in Phase 2
on a non-cylindrical building, where a cylinder formula would not.

**Re-seeding semantics.** Choosing a different anchor resets the plant and the crowding field, then
re-runs the SD-TIME-7 warm-up. The **light field is not reset** — it is environmental state and its
memory is the point — but the warm-up guarantees it is at the same converged values, so the
sun-side and shade-side runs AS-2 compares are genuinely comparable.

**Controls, complete list:** four anchor buttons, pause, three speeds, a small date/time readout, and
the time-lapse indicator (SD-TIME-5). Nothing else. The dev overlay (W-013) is a separate build flag.

---

## SD-METRIC — Coverage and acceptance measurement  *(resolves D-2 and D-5)*

### D-2 — How coverage is measured

| ID | Rule |
|---|---|
| SD-METRIC-1 | **Surface-bucket occupancy on a fixed measurement grid in tower-cylindrical coordinates, independent of the simulation's hash field.** 72 azimuth bins (5°, ≈0.17 m arc at R = 2 m) × 35 height bins (0.10 m) = 2,520 wall buckets. |
| SD-METRIC-2 | Buckets falling on a doorway or window opening are excluded from the denominator. The top surface and the ground are not counted. |
| SD-METRIC-3 | A bucket is **covered** when the projected leaf area attributed to it reaches **≥50% of the bucket area** (0.0085 m²). Leaf area per instance is `alpha_fill[id] · w · h`, where `alpha_fill` is the atlas alpha coverage fraction per leaf id — **add `alpha_fill` to `leaf_atlas.json`** (offline, from the alpha channel; a small work item). Coverage % = covered buckets / eligible buckets. |
| SD-METRIC-4 | **Why not the crowding field:** crowding is simulation state the plant writes back to, so measuring coverage from it couples the acceptance metric to a tunable and lets tuning game the metric. **Why not rendered coverage:** camera, AA, and lighting dependent, and screenshot comparison is already doing a different job in AS-4. The metric must measure leaves, because leaves are what the player sees. |
| SD-METRIC-5 | **Stem-bucket occupancy** (bucket contains ≥1 segment) is reported alongside as a diagnostic, and is the M1/M2 stand-in before leaf quality exists. |
| SD-METRIC-6 | Secondary metric for AS-2: total stem length and leaf count per 30° azimuth sector (12 sectors). |

### Proposed refinement to AS-1 and AS-2 — ~~requires Director ratification~~ SUPERSEDED

> **SUPERSEDED 2026-08-09. Do not implement the numbers in this subsection.** The Director ratified
> the split but **corrected the figures to 70% overall / 90% sun-facing / 50% shaded**. The 85/35
> pair proposed below is not self-consistent: the two halves average to 60, so a plant could clear
> both half floors and still fail the 70% overall floor, making the three checks contradict rather
> than reinforce each other. The ratified numbers, the coupling rule, and the revised AS-2 day-150
> figure (relaxed to ≥30%) live in `DESIGN.md`, which is the **only** authoritative home for
> acceptance numbers. Retained below solely as the record of what was proposed.

The current AS-1 ("≥70% of the outer wall") can be satisfied by *uniform* mediocre coverage, which is
precisely the wallpaper failure mode rubric criterion 2 exists to prevent. It should be split:

> **AS-1′** — From a single sun-facing seed at 150 game-days, default parameters, unattended:
> **≥70% overall**, **≥85% on the sun-facing 180°**, and **≥35% on the shaded 180°**, by the
> SD-METRIC-3 metric, with the top lip reached.

> **AS-2′** — Adds a *legibility latency* target so the experience, not only the end state, is
> testable: the sun/shade stem-length asymmetry reaches **≥20% by game-day 30** (≈36 s at Grow speed)
> and **≥40% by game-day 60**. The payoff moment has to arrive quickly or the causal belief the
> Director is trying to install never forms.

These are recorded here as proposals; per `DESIGN.md` the numbers live in `DESIGN.md` and should be
revised there by the Director once M2 provides real measurements.

### D-5 — Automatable vs screenshot-only blacklist items

| # | Blacklist item | Verdict | Check |
|---|---|---|---|
| 1 | Stems through or inside the wall | **Automatable** | Signed distance from every segment endpoint to the tower collider; fail if `< −0.005 m`. Dev-build assertion plus a harness pass. |
| 2 | Stems floating beyond `max_float` | **Automatable** | Assert `F ≤ max_float` every tick, and that no endpoint exceeds `max_float + d_A` from any surface. |
| 3 | Axis-aligned / rectilinear banding | **Auto-screened, human-confirmed** | (a) Bin `d_actual`'s tangent-plane angle into 36 bins over the whole plant; fail if the 4-fold Fourier coefficient exceeds 0.15 of DC. (b) 2-D FFT of the leaf-density map in (θ, z); fail on a peak at the `field_cell` frequency. Both catch the cause; the final judgement stays visual. |
| 4 | Z-fighting / coplanar leaf sheets | **Auto-screened, human-confirmed** | Spatial-hash leaf pairs within 0.03 m; flag if `\|dot(n₁,n₂)\| > 0.98` and plane offset `< 0.002 m`. SD-LEAF-4 rule 8 and SD-LEAF-1 make this structurally impossible, so the check is a regression guard. |
| 5 | Leaves detached from stems, inconsistent scale | **Automatable** | Petiole anchor within 0.005 m of the stem surface (guaranteed by construction in SD-LEAF-4, asserted anyway); every width within `[0.4, 1.6] · w_0`; width distribution CV ≤ 0.35. |
| 6 | Ivy on the ground plane or in mid-air | **Automatable** | No segment with `y < 0.02 m` beyond 0.10 m from the seed anchor; no endpoint further than `max_float` from any surface. Made unreachable by SD-GEO-4. |
| 7 | Visible repetition of leaf clusters | **Human only** | Perception cannot be proxied honestly. Preventative guards instead: SD-LEAF-6 adjacency rule, plus an assertion that no two adjacent leaves share `(atlas_id, rotation rounded to 15°)`. |

**Harness integrity guard.** The acceptance harness always runs against the committed default
parameter resource and records its content hash in the output. A run whose hash differs from the
committed defaults is marked non-conforming. This is the guard against the only real exploit vector
Phase 1 has: tuning the simulator to pass its own metrics.

---

## SD-RNG — Determinism contract

| ID | Rule |
|---|---|
| SD-RNG-1 | Each tip owns an RNG stream. Streams are advanced **only by events** — segment creation, node creation, branch draw, leaf attribute draws — and never by frames or ticks. Any per-frame random call anywhere in the simulation is a defect. This is the actual mechanism behind INV-4 and INV-7. |
| SD-RNG-2 | A branch's stream is `hash(parent_seed, branch_index)`, so a variable tip count cannot perturb sibling streams. |
| SD-RNG-3 | Draw order within a segment is fixed and documented: correlated-random update → adhesion → gradients → collision → branch draw → node/leaf draws. Reordering changes results. |
| SD-RNG-4 | Field sample jitter (SD-ENV-4) is hashed, not drawn from a stream, so it cannot desync anything. |
| SD-RNG-5 | AS-4 determinism is verified as: identical tip count, identical total stem length to the bit, and identical leaf count — plus identical canonical screenshots. SD-TIME-3 extends this across speed changes. |

---

## SD-EDGE — Edge cases and guardrails

| ID | Case | Behaviour |
|---|---|---|
| SD-EDGE-1 | Seed azimuth lands in the doorway | SD-AGENCY-2 deterministic azimuth search; anchor greyed out if no wall found. |
| SD-EDGE-2 | Tip reaches the top lip, `n ∥ +Y` | Tangent basis degenerates. SD-CONV-5 fallback. This is the AS-6 code path — it must be unit-tested on a horizontal surface, not discovered on screen. |
| SD-EDGE-3 | Tip crawls onto the flat top, then off the outer edge | Loses contact, `F` accumulates, `w_G = r_F^{0.7}` ramps, the runner sags. Either it reattaches to the outer wall or it dies at `F > 0.40 m`. **Both outcomes are desirable** — a ≤40 cm hanging runner is exactly the silhouette break AS-6 wants on a 3.5 m tower. Do not "fix" the death case. |
| SD-EDGE-4 | Tip enters a recess | Simulated normally (SD-GEO-5). Rubric criterion 3 depends on this happening. |
| SD-EDGE-5 | Tip heads for the ground | SD-GEO-4: ground unqueried, `A_m = 0`, `y ≥ 0.02 m` clamp, dormant after 5 clamps. |
| SD-EDGE-6 | Tip grows into existing ivy | Permitted. No self-collision (SD-GEO-3); crowding handles density. |
| SD-EDGE-7 | All tips dead or dormant before coverage | The run continues; coverage plateaus; the debug readout shows `live tips = 0`. AS-1 fails loudly rather than silently. |
| SD-EDGE-8 | Branch spawns coincident with parent | SD-GEO-6 angular separation and 0.005 m offset. |
| SD-EDGE-9 | Speed changed or paused mid-run | No effect on results (SD-TIME-1, SD-TIME-3). |
| SD-EDGE-10 | §30 parameter edited mid-run (G6) | Takes effect next tick, future growth only (SD-PHYS-4, INV-2). `segment_length` must not re-segment existing stems; `light_memory` recomputes `a` only. |
| SD-EDGE-11 | Re-seed to a different anchor | Plant and crowding reset; light field kept but re-warmed 12 game-days (SD-AGENCY, SD-TIME-7). |
| SD-EDGE-12 | Uniform field ⇒ zero gradient | `L` and `C` are bounded forms with `+g_L` and `+2` in the denominator; they return the zero vector. No divide-by-zero. |
| SD-EDGE-13 | All direction terms cancel | SD-GEO-2 fallback to `P`. |
| SD-EDGE-14 | Nearest surface at distance ≈ 0 | SD-GEO-2 guard on the adhesion divide. |
| SD-EDGE-15 | Tip leaves the built region of the sparse field | Cells allocate on demand, capped at 200,000; out-of-cap reads return the diffuse-only baseline `D_L`. |
| SD-EDGE-16 | Pathological `r` from a bad dev-overlay edit | `max_segments_per_tick = 8` bound with a warning (SD-PHYS-2). |
| SD-EDGE-17 | Night at Watch speed is ~30 s of near-stillness | Accepted for Phase 1: growth is 11% of daily mean rather than zero, so there is still motion, and the player can change speed at any time. Flagged as a Phase 2 pacing watch item, not solved here. |

---

## SD-M1 — Minimum viable version of each system for M1

Per the Director's non-negotiable sequencing: no tuning, no field precision, no leaf polish before
M1 is on screen. This is the split the Architect needs to sequence the build.

| System | **M1 minimum** | **Full Phase 1** |
|---|---|---|
| Tower | Cylinder + doorway + top lip, brick material, one camera | Four canonical cameras fixed forever, window/recess, ground, sky |
| Environment | Constant `D_L = 12` everywhere (`f_L = 1`), `C = 0`, `f_M = 1`, no sun | Solar model, hourly `P` bake, `SVF`, `V_hours`, EWMA, crowding, trilinear + jitter + gradients |
| Time | Pause + one speed, fixed 1-game-hour tick | Three speeds, render-sun blend, diel gate, 12-day warm-up |
| Physiology | `f_L`, `f_C`, `f_S`, `H`, all weights, `r`, budget `B` — **all present from M1** | unchanged; parameters hot-tunable |
| Geometry | Full §21 sum with `G = (0,−1,0)`, raycast adhesion, collision correction, `F` and gravity | unchanged + path smoothing |
| Stem mesh | Fixed-radius 5-sided tube, no taper, no smoothing | Taper by order and tip distance, Catmull-Rom smoothing |
| Leaves | **Flat quad, atlas leaf `a` only, fixed 0.075 m, strict ±90° alternation, 0.04 m internode, no jitter, no colour variation — but the normal-offset ladder is ON from day one** (it costs nothing and without it M1 is a z-fighting mess that teaches nothing) | All of SD-LEAF |
| Tips | Hard cap 64, stop branching at the cap | Soft 96 / hard 160, vigour retirement, full lifecycle |
| Agency | One hardcoded anchor | Four derived anchors, greying, re-seed |
| Metrics | None | SD-METRIC in full, harness, blacklist assertions |

**M1's exit condition is unchanged: recognizably ivy-shaped growth on the tower in a screenshot.
Ugly is fine.** M1's purpose is to discover which of these rules is wrong before any of them is
polished.

---

## SD-PARAM — Parameters added to the spec §30 table

All of these live in the same authoritative resource as the §30 defaults (INV-6) and are hot-tunable.

| Parameter | Default | Introduced by |
|---|---:|---|
| `sim_tick` | 1/24 game-day | SD-TIME-1 |
| `speed_watch` / `speed_fast` / `speed_grow` | 60 / 6 / 1.2 s per game-day | SD-TIME-2 |
| `render_sun_blend_lo` / `_hi` | 10 / 30 s per game-day | SD-TIME-4 |
| `latitude` / `longitude` / `day_of_year` / `start_hour` | 51.5 / 0.0 / 105 / 6.0 | SD-TIME-6 |
| `light_warmup_days` | 12 | SD-TIME-7 |
| `diel_night_floor` / `diel_exponent` | 0.05 / 0.35 | SD-TIME-8 |
| `field_cell` | 0.06 m | SD-ENV-1 |
| `field_sample_jitter` | 0.35 × cell | SD-ENV-4 |
| `gradient_epsilon` | 1.5 × cell | SD-ENV-5 |
| `contact_distance` | 0.02 m | SD-GEO-1 |
| `max_segments_per_tick` | 8 | SD-PHYS-2 |
| `branch_angle_min` / `_max` / `branch_offset` | 45° / 75° / 0.005 m | SD-GEO-6 |
| `tip_cap_soft` / `tip_cap_hard` / `retire_margin` | 96 / 160 / 1.25 | SD-TIP |
| `branch_scale_floor` | 0.02 | SD-TIP-3 (W-045) |
| `stall_rate` / `stall_days` | 0.01 m/day / 3 | SD-TIP |
| `internode_base` / `internode_shade_gain` / `internode_jitter` | 0.040 m / 0.9 / 0.25 | SD-LEAF-2 |
| `leaf_tip_suppress` | 0.06 m | SD-LEAF-2 |
| `phyllotaxy_divergence` / `phyllotaxy_flatten` | 137.5° / 0.65 | SD-LEAF-3 |
| `leaf_out_of_plane` / `leaf_photo_cant` | 0.35 / 0.45 | SD-LEAF-4 |
| `droop_base` / `droop_shade_gain` | 12° / 18° | SD-LEAF-4 |
| `leaf_jitter_tilt` / `_roll` / `_yaw` | 22° / 15° / 8° | SD-LEAF-4 |
| `leaf_offset_base` / `_step` / `_ladder` | 0.004 m / 0.0015 m / 5 | SD-LEAF-4 |
| `leaf_width_base` | 0.075 m | SD-LEAF-5 |
| `leaf_order_falloff` | 0.18 | SD-LEAF-5 |
| `leaf_expand_distance` | 0.12 m | SD-LEAF-5 |
| `leaf_light_scale_base` / `_gain` | 0.80 / 0.30 | SD-LEAF-5 |
| `leaf_size_sigma` | 0.16 | SD-LEAF-5 |
| `leaf_healthy_base` / `_gain` | 0.25 / 0.65 | SD-LEAF-6 |
| `leaf_crowd_k` | 0.5 | SD-LEAF-8 (W-036). Raised to 0.85 by W-048 and reverted — `C` is clamped to `[0, 1]`, so this is a saturation-rate knob that thins the sparse shaded half rather than the dense sunny one. See W-050 before changing. |
| `leaf_crowd_suppress` / `_floor` | 0.70 / 0.30 | SD-LEAF-8. Thins hidden interior leaf layers; genuinely density-gated, so the sparse shaded half is spared. Changed 0.55→0.70 / 0.35→0.30 per SD-OPEN-6 Director ruling (2026-08-09); landed Gameplay Fixer 2026-08-09. |
| `leaf_cap` | 20000 | SD-LEAF-9 |
| `stem_radius_base` / `stem_order_falloff` / `stem_tip_taper` | 0.006 m / 0.25 / 0.15 m | SD-STEM |
| `ground_y_min` | 0.02 m | SD-GEO-4 |

---

## SD-SCEN — Example scenarios (expected behaviour, for the Architect and QA)

**Scenario A — south anchor, Watch then Grow.** Player seeds at the south anchor at 06:00 and leaves
it on Watch. First segment appears within ~6 game-hours (~15 s wall-clock). Over the first two
minutes the tip climbs ~24 cm, places ~6 leaves, and growth visibly slows through the evening and
nearly stops overnight. The player switches to Grow. By game-day 30 (~36 s) the south face carries a
visibly denser, greener mat than the flanks; by day 60 the asymmetry is unmistakable; by day 150
(~3 min) tips have crossed the top lip and are hanging over it. Expected: AS-1′, AS-2′, AS-6.

**Scenario B — north anchor.** Same run, north anchor. `f_L ≈ 0.57`: growth is ~1.8× slower, internodes
are ~40% longer, leaves are smaller and drawn more often from the weathered atlas tier, branching is
~1.9× rarer, and phototropism `w_L` rises from 0.03 to ~0.12 so tips visibly wander around the
tower's flanks toward the light instead of climbing straight. At 150 game-days total stem length is
well under the south run. Expected: AS-2's "≥20% less total stem length" clause, and the "what if I
put it on the other side?" impulse.

**Scenario C — the lip.** A lead tip crests the top lip, crawls across the top on `n = +Y` (exercising
the SD-CONV-5 degenerate tangent basis), reaches the outer edge, loses contact, and sags under
`w_G = r_F^{0.7}`. It either catches the outer wall within 40 cm and resumes climbing down, or dies
and remains as a hanging stem with leaves. Both are correct and both break the silhouette against
the sky. Expected: AS-6, rubric criterion 1.

---

## SD-OPEN — Items escalated out of this stage

| ID | Item | Owner | Blocking? |
|---|---|---|---|
| SD-OPEN-1 | Ratify the diel growth gate (SD-TIME-8) as **INV-3a**, or accept the documented fallback and reword AS-3. | Game Director | **RESOLVED 2026-08-09 — ratified as INV-3a.** AS-3 reworded, and a mean-preservation clause added: total elongation over any whole game-day must be within ±5% of the same run with the gate disabled. The gate-disabled path must therefore ship. |
| SD-OPEN-2 | Ratify AS-1′ and AS-2′ wording into `DESIGN.md`. | Game Director | **RESOLVED 2026-08-09 — ratified with corrected figures (70/90/50).** See the superseded notice above. |
| SD-OPEN-3 | Confirm the three real-ivy-on-brick reference photographs before M4 rubric scoring begins. | Game Director | **RESOLVED 2026-08-09 — specified as W-024.** Three purpose-chosen slots in `assets/reference/ivy/`, **Public Domain or CC0 only** (CC-BY, CC-BY-SA, Unsplash and Pexels all excluded). Still gates M4 exit until filled. |
| SD-OPEN-4 | Add `alpha_fill` per leaf id to `leaf_atlas.json` (offline alpha-coverage measurement). | Architect | **RESOLVED 2026-08-09.** Measured from the alpha channel and committed, along with a `tier` field (H/W) per SD-LEAF-6. Values 0.607–0.675. |
| SD-OPEN-5 | Whether `LeafSet029`'s Scattering map warrants a custom leaf shader in M4, or the constant transmittance tint is sufficient. Deferred: cannot be judged before leaves are on screen. | Architect at M4 | No |
| SD-OPEN-6 | **The AR-BUDGET segment/stem/leaf-area envelope conflicts with AS-1's 50% shaded floor at measured placement efficiency.** The shaded 180° is sparse and volume-limited; it needs ≈60 m² of leaf area (2× the 20–35 m² budget) merely to reach 53.99% (+3.99). Every uniform volume brake (`branch_rate`, the caps, the stall rule) halves the shaded coverage before it reaches the envelope — `branch_rate` is additionally inert until ≈1.0 because the SD-TIP-3 taper is a homeostat, then it collapses the shaded half first (see AR-BUDGET). AR-BUDGET is labelled "sanity targets, not requirements," but its 20–35 m² / 360–600 m / 12–20k-segment lines were back-derived from AR-RISK-4's assumption that ~27 m² *reasonably distributed* meets 70/90/50, and the real distribution is far more uneven. **Two options for the Director, neither decidable at this stage:** (a) re-derive the AR-BUDGET leaf-area/stem/segment lines upward to whatever is actually compatible with holding 70/90/50 (an architectural number — the AS-1 floors themselves are **not** to be touched); or (b) hold the budget and require the shaded floor to be met by *better placement* (M4 leaf-quality / distribution work — e.g. crowding-gradient steering off the saturated sunny mat, W-015), not by more volume. The rubric-2 green-mat half of W-048 is already handled separately by the density-gated SD-LEAF-8 leaf levers and does **not** need this decision. | Game Director | **RESOLVED 2026-08-09 — split ruling.** (a) AR-BUDGET re-derived upward to bracket the measured day-150 pass state; see § AR-BUDGET. (b) Placement-efficiency improvement deferred to M4 via W-015/W-030. AS-1 floors unchanged. M2 gate: envelope no longer blocks; green mat fixed by pending SD-LEAF-8 levers before M2 close. See `DESIGN.md` ratification log. |

---

## SD-NONGOAL — Non-goals of this stage's design

Beyond `DESIGN.md`'s Phase 1 non-goals, this design explicitly does **not** cover, and the Architect
should not build: leaf wind or any per-leaf animation beyond growth expansion · leaf fall or
senescence · autumn colour or `LeafSet029` usage · separate petiole geometry · aerial rootlet
geometry · ivy–ivy collision · per-leaf shadow casting beyond the standard shadow map · LOD or
impostors · GPU-side simulation · multithreading · moisture · a second building or material beyond
the brick A/B · save/load · any player tool other than anchor selection and time control.

---
---

# Phase 1 Implementation Architecture

**Stage:** Gameplay Architect · **Date:** 2026-08-09 · **Next stage:** Gameplay Programmer

**Inputs used:** `IMPLEMENTATION.md` § "Phase 1 System Contracts" (all `SD-*` rules — primary input) ·
`DESIGN.md` (INV-1–INV-10 **and INV-3a**, G1–G6, the **ratified** AS-1–AS-6, artifact blacklist,
rubric, the reference set, M1–M4, non-goals, R-1–R-6, and the 2026-08-09 ratification log) ·
`ivy_simulator_v0.1.md` §1–§35 (equations, §30 parameter table) · `TECHNICAL_INDEX.md` (bootstrap
state) · `assets/CREDITS.md` · `assets/plants/ivy/LeafSet017/leaf_atlas.json` (with the
`alpha_fill`/`tier` columns from SD-OPEN-4) · `assets/materials/brick/Bricks094/Bricks094_2K-JPG.tres` ·
`project.godot`, `src/main/*`, `tools/*`, `test/*` · `.cursor/skills/{run-tests,run-ui-script,take-screenshot}` ·
`.cursor/rules/technical-index-maintenance.mdc` · `work-items/WORK_ITEMS.md`.

**Authority order (unchanged).** `DESIGN.md` invariants → `ivy_simulator_v0.1.md` equations →
`SD-*` contracts → this section. This section is authoritative only for *how* things are built:
scene tree, files, classes, signatures, data layout, sequencing, test surface. Where an `SD-*` rule
is ambiguous or not implementable as written, it is **not silently reinterpreted** — it is listed in
`AR-AMBIG` with a proposed resolution and a stable `AR-*` ID that the Programmer cites.

Rules here are given stable IDs (`AR-*`).

**Reconciliation with the Director's 2026-08-09 ratifications**, which landed while this section was
being written. `SD-OPEN-1` and `SD-OPEN-2` are **closed**, so this plan is written against the
ratified outcome, not the escrowed one:

- **INV-3a is now an invariant**, not a proposal. The diel gate ships. `IvyParams.diel_gate_enabled`
  survives — but as the **AS-3 clause (b) comparison path**, not as an escrow flag (`AR-PARAM-5`).
- **AS-1 is 70% overall / 90% sun-facing 180° / 50% shaded 180°**, not the `SD-METRIC` proposal's
  70/85/35. `CoverageMetric` must therefore report the two halves separately, not just an overall
  figure (`AR-METRIC`). `IMPLEMENTATION.md`'s AS-1′/AS-2′ wording is superseded; `DESIGN.md` is the
  only home for acceptance numbers.
- **AS-2 is ≥20% by day 30, ≥40% by day 60, ≥30% at day 150.** The day-150 relaxation matters
  architecturally: the harness must sample asymmetry at three points during a run, not only at the
  end, so `SimRoot` exposes a metrics snapshot hook rather than a terminal report.
- **AS-3 gains clause (b)**, which requires running the same seed twice with the gate on and off and
  comparing daily elongation to ±5%. That is why the gate-disabled path must remain reachable.
- The Director's flagged tension — that `SD-TIP-4`'s vigour retirement suppresses shaded coverage and
  could drive the shaded half below AS-1's 50% floor — is a **tuning** finding for M2, not an
  architecture change. `retire_margin` is already an `IvyParams` field, which is the correct lever.

---

## AR-OVER — Architecture overview

### AR-OVER-1 — Four layers, one direction

INV-1's causality chain becomes four compile-time-separable layers. The dependency arrows below are
the *only* permitted directions; a reverse reference is a defect, not a style issue.

```
   World (static)          Environment            Physiology + Geometry        Presentation
   ──────────────          ───────────            ─────────────────────        ────────────
   TowerSpec               CellGrid                    Physiology              StemMeshBuilder
   TowerBuilder            SparseHashField             GrowthStep              LeafRenderer
   TowerSdf        ──►     IvyEnvironment    ──►       TipManager       ──►    SkySun
   SurfaceQuery            Solar                       LeafPlacer              CameraRig
   MaterialRegistry        LightBake                   PlantData (append-only)
   SeedAnchors                  ▲
                                └──── deposit_crowding() only ────┘   (INV-1, SD-PHYS-3)
```

- **World** never reads Environment, Physiology, or Presentation.
- **Environment** reads World. Its only mutating entry point from above is
  `IvyEnvironment.deposit_crowding()`, called from `Physiology`, never from geometry or rendering.
- **Physiology/Geometry** read World and Environment and append to `PlantData`. They never touch a
  `Node3D`, a mesh, or a material. This is what makes every simulation rule headlessly unit-testable
  and is the structural enforcement of INV-1.
- **Presentation** reads `PlantData` and writes nothing. It **pulls by high-water mark** each frame
  (`_last_synced_segment`, `_last_synced_leaf`) rather than subscribing to per-segment signals: at
  ~640 segment events/s and ~480 leaf events/s at Grow speed, signal dispatch is measurable overhead
  and buys nothing.

### AR-OVER-2 — Leaf transforms are simulation output, not render output

Every leaf attribute in SD-LEAF (position, basis, size, atlas id, colour) is produced by draws from
the per-tip RNG stream (SD-RNG-1 explicitly lists "leaf attribute draws"). Therefore **`LeafPlacer`
lives in the simulation layer and emits fully-resolved leaf instances into `PlantData`**;
`LeafRenderer` only copies them into a `MultiMesh` buffer.

Two consequences that matter: leaf placement is unit-testable with no rendering device (so it runs
under `--headless` in GUT), and `CoverageMetric` (SD-METRIC-3) can compute projected leaf area from
simulation data without a camera.

### AR-OVER-3 — Dependency injection, no autoloads

`IvyParams`, `SurfaceQuery`, `IvyEnvironment`, and `RngStream` are constructor-injected through a
single `SimContext` value object. **No autoload singletons.** Autoloads would make the GUT suite
depend on scene-tree bootstrap order and would hide exactly the dependencies INV-1 exists to
constrain. `SimRoot` is the composition root for simulation; `Main` is the composition root for the
scene.

---

## AR-SCENE — Scene tree, node types, and project settings

### AR-SCENE-1 — `main.tscn` is replaced, not supplemented

The bootstrap `Control` scene is **replaced**. `res://src/main/main.tscn` keeps its path and UID so
that `tools/take_screenshot.gd`, `tools/run_ui_script.gd`, and `project.godot`'s
`run/main_scene` need no change, but its root type becomes `Node3D` and `main.gd` becomes the
composition root. `src/main/main.gd`'s placeholder label logic is deleted.

Keeping a second "3D scene" alongside the bootstrap `Control` was considered and rejected: it
would fork the screenshot and UI-script tooling into two entry points, and the canonical-screenshot
requirement (AS-4, AS-6) depends on there being exactly one scene whose cameras never move.

### AR-SCENE-2 — The tree

```
Main                        (Node3D, src/main/main.gd)                   composition root
├── World                   (Node3D, src/world/world.gd)
│   ├── Tower               (StaticBody3D, src/world/tower.gd)           layer 1 = SURFACE
│   │   ├── TowerMesh       (MeshInstance3D)      generated ArrayMesh, Bricks094 material
│   │   └── TowerCollision  (CollisionShape3D)    ConcavePolygonShape3D from the same triangles
│   ├── Ground              (StaticBody3D, layer 2 = GROUND)             SD-GEO-4: never queried
│   │   ├── GroundMesh      (MeshInstance3D)      24 m PlaneMesh, neutral matte
│   │   └── GroundCollision (CollisionShape3D)    WorldBoundaryShape3D
│   ├── SkySun              (Node3D, src/world/sky_sun.gd)
│   │   ├── Sun             (DirectionalLight3D)  forward == −S  (SD-CONV-9)
│   │   └── WorldEnvironment (Environment + ProceduralSkyMaterial, ambient source = Sky)
│   └── CameraRig           (Node3D, src/world/camera_rig.gd)
│       ├── CamSun          (Camera3D)  sun-facing elevation,   +Z side, y≈1.8, looking −Z
│       ├── CamShade        (Camera3D)  shade-facing elevation, −Z side, y≈1.8, looking +Z
│       ├── CamAerial       (Camera3D)  45° from above, azimuth 135°
│       └── CamSilhouette   (Camera3D)  ground level y≈0.35, looking up at the lip against sky
├── Sim                     (Node, src/sim/sim_root.gd)                  no transform, no 3D
├── PlantRender             (Node3D, src/render/plant_render.gd)
│   ├── StemChunks          (Node3D)   N frozen MeshInstance3D chunks, appended
│   ├── LeavesStatic        (MultiMeshInstance3D)  preallocated leaf_cap, visible_instance_count
│   └── LeavesGrowing       (MultiMeshInstance3D)  preallocated 600
└── UI                      (CanvasLayer)
    ├── Hud                 (Control, src/ui/hud.gd)         M3
    └── DevOverlay          (Control, src/ui/dev_overlay.gd) M3, hidden unless --dev
```

| ID | Rule |
|---|---|
| AR-SCENE-3 | **Cameras are authored transforms in `world.tscn` and are never written at runtime.** `CameraRig.select(index)` only toggles `current`. AS-4 requires pixel-comparable canonical screenshots across runs; a camera whose transform is computed from `TowerSpec` would move the instant the tower is retuned and silently invalidate every prior screenshot. The four transforms are frozen at M2 and treated as committed test fixtures. |
| AR-SCENE-4 | Physics layers: **1 = SURFACE** (tower only), **2 = GROUND**. `SurfaceQuery` masks layer 1 exclusively. This is SD-GEO-4's "separate physics layer the simulator never queries" made structural — the ground is not merely `A_m = 0`, it is unreachable by any simulator query. |
| AR-SCENE-5 | `Sim` is a plain `Node`, deliberately not a `Node3D`. The simulation has no transform and must never acquire one; all simulation coordinates are world-space (SD-CONV-8). |
| AR-SCENE-6 | `Main` owns the single `IvyParams` instance and passes it to `World`, `Sim`, `PlantRender`, and `UI`. Nothing else may `load()` the parameter resource (INV-6). |

### AR-SCENE-7 — Required `project.godot` changes

| Setting | Value | Why |
|---|---|---|
| `rendering/anti_aliasing/quality/msaa_3d` | `2` (4×) | **SD-LEAF-1 mandates alpha-to-coverage, which is a silent no-op without MSAA.** Without this the leaf mat will look exactly like the alpha-blend failure the rule exists to prevent, and the cause will be invisible. |
| `rendering/anti_aliasing/quality/screen_space_aa` | `0` (disabled) | FXAA over alpha-to-coverage smears leaf edges and destroys the AS-4 screenshot comparison. |
| `rendering/lights_and_shadows/directional_shadow/size` | `4096` | Rubric criterion 4 ("leaves self-shadow") needs shadow resolution at leaf scale on a 5 m subject. |
| `physics/3d/physics_engine` | default (Godot Physics) | Jolt's trimesh raycast `face_index` semantics differ; AR-TOWER-6 depends on `face_index`. If Jolt is adopted later, AR-TOWER-6 needs re-verification. |
| `display/window/stretch/mode` | leave `canvas_items` | Affects CanvasItems only; harmless for 3D and keeps the HUD resolution-independent. |

`--headless` note for the Programmer: `--headless` has no rendering device, so
`get_viewport().get_texture()` returns null. The existing skills already reflect this — GUT runs
headless, screenshots do not. Tests that need `DirectionalLight3D.global_basis` (SD-CONV-9) work
fine headless because that is scene-graph state, not render state.

---

## AR-FILES — File and class layout

Every path below is **planned** (none exist yet). `class_name` is given because the GUT tests
reference these types directly.

### World

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/world/world.gd` | `World` | Builds the tower at `_ready`, exposes `SurfaceQuery` and `SeedAnchors`, owns `SkySun` and `CameraRig`. |
| `src/world/tower_spec.gd` | `TowerSpec : Resource` | Parametric tower description (AR-TOWER-1). Single source of truth for mesh, collision, SDF, anchors, and the SD-METRIC-2 opening mask. |
| `src/world/tower_spec_default.tres` | — | Committed defaults: H 3.5 m, R 2.0 m. |
| `src/world/tower_builder.gd` | `TowerBuilder` | Generates `ArrayMesh` + `ConcavePolygonShape3D` + `face_material: PackedByteArray` from a `TowerSpec`; runs the SD-CONV-3 outward-normal assertion. |
| `src/world/tower.gd` | `Tower : StaticBody3D` | Hosts the generated mesh/shape, applies `Bricks094_2K-JPG.tres` with cylindrical UVs. |
| `src/world/tower_sdf.gd` | `TowerSdf` | Analytic signed distance Φ and ∇Φ from the same `TowerSpec` (AR-TOWER-4). |
| `src/world/surface_query.gd` | `SurfaceQuery` | The **only** interface the simulator has to the world: raycast, nearest-surface, signed distance, material lookup. |
| `src/world/material_registry.gd` | `MaterialRegistry`, `SurfaceMaterialDef : Resource` | `material_id → {name, A_m, in_coverage_denominator}` (INV-10). |
| `src/world/seed_anchors.gd` | `SeedAnchors` | SD-AGENCY-1/2/3 derivation and cache. |
| `src/world/sky_sun.gd` | `SkySun` | Drives `DirectionalLight3D` + procedural sky from `Solar`, applies the SD-TIME-4 render blend. |
| `src/world/camera_rig.gd` | `CameraRig` | `select(index_or_name)`; never writes transforms. |

### Core

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/core/conv.gd` | `Conv` | **Every** coordinate convention in SD-CONV, as constants and static helpers. No basis may be constructed inline anywhere else (SD-CONV-7). |
| `src/core/hash64.gd` | `Hash64` | splitmix64 mixing, `unit_float`, `jitter_vec3` (SD-ENV-4, SD-RNG-4). |
| `src/core/rng_stream.gd` | `RngStream : RefCounted` | Per-tip event-advanced stream with `derive(branch_index)` (SD-RNG-1/2). |
| `src/core/sim_clock.gd` | `SimClock : RefCounted` | Fixed `dt_sim`, speed → ticks/s, deterministic manual driver (SD-TIME-1/2). |

### Parameters

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/params/ivy_params.gd` | `IvyParams : Resource` | All §30 defaults **plus** every SD-PARAM row (INV-6). |
| `src/params/ivy_params_default.tres` | — | The committed default resource. Its `content_hash()` is what the SD-METRIC harness-integrity guard records. |

### Environment

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/env/cell_grid.gd` | `CellGrid` | Cell addressing, 64-bit key packing, cell↔world conversion. |
| `src/env/sparse_field.gd` | `SparseHashField` | `Dictionary[int → slot]` + parallel `PackedFloat32Array` channels; allocation, trilinear read, central-difference gradient. |
| `src/env/environment.gd` | `IvyEnvironment` | Public environment API, EWMA tick, `deposit_crowding`, `invalidate(aabb)` (SD-ENV-7). |
| `src/env/solar.gd` | `Solar` | NOAA solar position, `S(t)`, elevation, day-average direction, diel gate `ĝ` (SD-CONV-2, SD-TIME-4/6/8). |
| `src/env/light_bake.gd` | `LightBake` | `SVF`, `V_hours`, and the `P(cell, hour)` table (SD-ENV-6, W-019). |

### Simulation

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/sim/sim_root.gd` | `SimRoot : Node` | Owns clock, env, tips, plant data. The tick loop and its fixed ordering. |
| `src/sim/sim_context.gd` | `SimContext : RefCounted` | Injected bundle: params, env, surface, solar, plant, tips, anchors. |
| `src/sim/tip.gd` | `Tip : RefCounted` | Per-tip state (§3 + SD-TIP + SD-LEAF-2 accumulators). |
| `src/sim/tip_manager.gd` | `TipManager` | Lifecycle state machine, soft/hard cap, vigour retirement (SD-TIP). |
| `src/sim/physiology.gd` | `Physiology` | Pure static functions: `f_L`, `f_C`, `f_S`, `H`, `w_*`, `r`, `λ_b`, `p_b`, crowding deposit (SD-PHYS). |
| `src/sim/growth_step.gd` | `GrowthStep` | One segment: §21 sum, collision, `F` update, persistence update, branch draw, node draw — in SD-RNG-3 order. |
| `src/sim/plant_data.gd` | `PlantData` | **Append-only** struct-of-arrays for segments and leaves (INV-2). |
| `src/sim/leaf_placer.gd` | `LeafPlacer` | SD-LEAF-2..8: internode, phyllotaxy, orientation, size, atlas, colour, crowding suppression. |

### Presentation

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/render/plant_render.gd` | `PlantRender : Node3D` | Per-frame `sync(plant)` fan-out to stem and leaf renderers. |
| `src/render/stem_mesh.gd` | `StemMeshBuilder` | Chunked incremental tube append (AR-RENDER-1, SD-GEO-7). |
| `src/render/leaf_renderer.gd` | `LeafRenderer` | Static/growing `MultiMesh` buffers, freeze migration (SD-LEAF-9). |
| `src/render/leaf_atlas.gd` | `LeafAtlas` | Parses `leaf_atlas.json`; exposes rect/aspect/`alpha_fill`/`tier` per id. |
| `src/render/shaders/leaf.gdshader` | — | Atlas-rect-from-`INSTANCE_CUSTOM`, alpha scissor + alpha-to-coverage, backlight (SD-LEAF-1). |
| `src/render/materials/leaf_material.tres` | — | `ShaderMaterial` wiring the LeafSet017 colour/normal/roughness maps. |
| `src/render/materials/tower_brick.tres` | — | Duplicate of `Bricks094_2K-JPG.tres` with `uv1_scale` set for the cylinder; the asset `.tres` stays untouched. |

### Metrics and UI

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/metrics/coverage.gd` | `CoverageMetric` | SD-METRIC-1/2/3/5/6 buckets and sectors. |
| `src/metrics/blacklist.gd` | `BlacklistAssertions` | D-5 automatable checks and auto-screens. |
| `src/metrics/run_hash.gd` | `RunHash` | AS-4 / SD-RNG-5 canonical run fingerprint. |
| `src/ui/hud.gd` / `hud.tscn` | `Hud` | Four anchor buttons, pause + 3 speeds, date/time readout, time-lapse indicator (SD-AGENCY controls, SD-TIME-5). |
| `src/ui/dev_overlay.gd` / `.tscn` | `DevOverlay` | Live `IvyParams` editing + field visualization (W-013, G6). |

### Tools and tests

| Path | Responsibility |
|---|---|
| `tools/run_ui_script.gd` | **Extended** with the AR-UI-3 verbs. |
| `tools/ui_scripts/m1_growth.txt` | M1 exit-gate capture. |
| `tools/ui_scripts/canonical.txt` | All four canonical cameras at a fixed game-day. |
| `tools/ui_scripts/as6_silhouette.txt` | AS-6 ground-level silhouette. |
| `tools/ui_scripts/reseed.txt` | SD-EDGE-11 re-seed flow. |
| `tools/acceptance_harness.gd` / `.tscn` | W-014 headless AS-1…AS-6 runner. |
| `test/*.gd` | See AR-TEST. |

---

## AR-TOWER — Tower geometry, collision, and the surface query

This is the highest-risk single component: the simulator raycasts against it thousands of times per
second, SD-CONV-3 requires provably outward normals, and a cylinder primitive's collision contains
neither the doorway nor the lip.

### AR-TOWER-1 — Parametric, not authored

`TowerSpec` is the single source of truth. Both the visual mesh *and* the analytic SDF are derived
from it, so they cannot drift.

| Field | Default | Note |
|---|---:|---|
| `height` | 3.50 m | DESIGN.md range 3–4 m |
| `radius_outer` | 2.00 m | DESIGN.md range 1.5–2.5 m |
| `wall_thickness` | 0.35 m | inner radius 1.65 m |
| `lip_overhang` / `lip_thickness` | 0.18 m / 0.15 m | outer lip radius 2.18 m; AS-6 fixture |
| `door_azimuth` / `_width` / `_height` | 180° (**north, −Z**) / 0.90 m / 2.00 m | |
| `window_azimuth` / `_size` / `_depth` / `_sill` | 90° (**east, +X**) / 0.60 m / 0.12 m / 1.60 m | recess, not a hole |
| `ring_segments` | 96 | 13 cm facets at R = 2 m; below this R-4 faceting is visible |
| `brick_uv_metres` | 1.00 m | tile size; circumference tiling is rounded to an integer to kill the seam |

**The doorway is deliberately placed on the north face.** It is not decoration: it makes the N seed
anchor exercise SD-AGENCY-2's deterministic azimuth search and SD-EDGE-1 on every single run, and it
leaves the sun-facing south wall unobstructed so AS-1 and AS-2 measure light asymmetry rather than
geometry occlusion. It also keeps the doorway out of AS-1's 90% sun-facing half, where excluded
opening buckets would make that already-demanding floor harder to reach for a reason unrelated to
light.

### AR-TOWER-2 — Generated at `_ready()`, not baked to disk

`TowerBuilder.build(spec) -> TowerBuildResult { mesh: ArrayMesh, shape: ConcavePolygonShape3D,
face_material: PackedByteArray, triangle_count: int }`. Roughly 5–6 k triangles; GDScript generation
costs ~100–200 ms at load, which is acceptable and removes any possibility of a stale committed
artifact desyncing from `TowerSpec`. If load time later becomes a problem, add a `--bake-tower` tool
path — do **not** pre-bake speculatively.

**The collision shape is built from the same triangle array as the visual mesh.** This is the
structural guarantee behind blacklist item 1: what you see is exactly what the simulator collides
with. A convex decomposition or a primitive approximation would reintroduce the divergence.

### AR-TOWER-3 — The SD-CONV-3 outward-normal assertion

Run inside `TowerBuilder.build()` in dev builds and unconditionally in `test_tower_geometry.gd`:

1. For each triangle, `n_geo = normalize(cross(b−a, c−a))`; assert `dot(n_geo, n_vertex) > 0.9`
   (winding matches authored normals).
2. For wall triangles, assert `dot(n_geo, centroid − axis_point) > 0` where
   `axis_point = Vector3(0, centroid.y, 0)` — verbatim SD-CONV-3.
3. For lip-top triangles, assert `dot(n_geo, Conv.UP) > 0.9`.
4. **Cross-check against the SDF:** assert `TowerSdf.signed_distance(centroid + 0.01·n_geo) > 0` and
   `< 0` for `centroid − 0.01·n_geo`, for every triangle. This is the check that actually catches an
   inverted face, because it is independent of the winding logic that produced the face.

Failing any of these aborts the build with the offending triangle index. An inverted face makes the
tower's interior "sunlit" and silently breaks AS-2; it must not be discoverable only by screenshot.

### AR-TOWER-4 — Nearest-surface via an analytic SDF, collision via physics raycast

The simulator needs two different things and they get two different mechanisms.

| Query | Mechanism | Why |
|---|---|---|
| §22 collision (`x → x_trial` sweep, hit point, hit normal) | **Godot physics `intersect_ray`** against the trimesh, mask = SURFACE | Exact. Blacklist item 1 is a correctness requirement, and the exact hit normal is needed for the reflect correction and for the segment's stored wall normal. |
| §17 nearest-surface (`q`, `d`) and the `d_contact` test | **Analytic Φ from `TowerSpec`**: `q = x − Φ(x)·∇̂Φ(x)`, `d = Φ(x)` | Godot exposes no nearest-point query for concave shapes. Φ is a closed form for a union/difference of surfaces of revolution and boxes, so it is exact, zero-memory, needs no bake, and updates the instant `TowerSpec` changes. |

Φ composition: `Φ = max( min(Φ_shell, Φ_lip), −Φ_door_box, −Φ_window_box )`, with `Φ_shell` and
`Φ_lip` closed-form annulus/cylinder distances about +Y and the openings as rotated boxes.

**Known limitation, stated rather than hidden:** a max/min composition of primitive SDFs is exact
away from creases and *conservative* (under-estimating) near the doorway and lip edges, by at most a
few millimetres at these dimensions. This is acceptable because (a) physics raycast, not Φ, is
authoritative for collision, and (b) a slightly rounded adhesion field at a sharp edge is
behaviourally *better* — real ivy does not hug a razor edge.

`∇Φ` by central differences at 1 mm. `Conv.tangent_basis(∇̂Φ)` then gives the SD-CONV-5 basis
everywhere, including on the flat top where it degenerates (SD-EDGE-2, AS-6).

### AR-TOWER-5 — `SurfaceQuery` API

```gdscript
class_name SurfaceQuery extends RefCounted

class Hit extends RefCounted:
    var hit: bool
    var position: Vector3
    var normal: Vector3          # outward, SD-CONV-3
    var distance: float
    var material_id: int

func raycast(from: Vector3, to: Vector3) -> Hit          # physics, SURFACE layer only
func signed_distance(p: Vector3) -> float                # analytic Φ
func surface_normal(p: Vector3) -> Vector3               # ∇̂Φ
func nearest(p: Vector3) -> Hit                          # q = p − Φ·∇̂Φ ; SD-GEO-2 guards inside
func tangent_basis_at(p: Vector3) -> Basis               # Conv.tangent_basis(∇̂Φ)
func material_at_face(face_index: int) -> int
func adhesion_suitability(material_id: int) -> float     # A_m via MaterialRegistry (INV-10)
func project_to_shell(p: Vector3, offset: float) -> Vector3
```

### AR-TOWER-6 — Per-face material, and what "tagged `opening`" means

SD-AGENCY-2 says "hits a collider tagged `opening`", but the tower is a single trimesh collider with
no sub-colliders to tag. Resolution (**AR-AMBIG-5**): `TowerBuilder` emits a parallel
`face_material: PackedByteArray`, and `intersect_ray` on a `ConcavePolygonShape3D` returns
`face_index`, so `material_at_face()` is an exact O(1) lookup. Material ids:

| id | Name | `A_m` | In coverage denominator |
|---:|---|---:|---|
| 0 | `brick_wall` | 1.00 | yes |
| 1 | `brick_lip` | 1.00 | no (top surface, SD-METRIC-2) |
| 2 | `opening_reveal` | 1.00 | no (SD-GEO-5: simulated, excluded from the denominator) |
| 3 | `interior` | 1.00 | no |
| 4 | `ground` | 0.00 | no — and unreachable anyway (AR-SCENE-4) |

`A_m` is read from `MaterialRegistry` at the call site, never stored resolved (INV-10, and see
AR-AMBIG-3).

### AR-TOWER-7 — Seed anchors

```gdscript
class_name SeedAnchors extends RefCounted
class Anchor extends RefCounted:
    var compass: int          # 0=N 1=E 2=S 3=W
    var available: bool
    var position: Vector3
    var normal: Vector3
func build(surface: SurfaceQuery, spec: TowerSpec) -> void   # once, at load (SD-AGENCY-3)
func get_anchors() -> Array                                  # cached; recomputation is an assert
```

Implements SD-AGENCY-1/2 verbatim, with the azimuth search rejecting hits whose
`material_at_face()` is `opening_reveal` or `interior`.

---

## AR-FIELD — The sparse hash field

### AR-FIELD-1 — Addressing

`CellGrid(cell_size)` with `cell_of(p) = floor(p / cell)`; key packing
`(x + 2048) | (y + 2048) << 12 | (z + 2048) << 24`, valid to ±122 m at `field_cell = 0.06`, well
inside GDScript's 64-bit int. Keys are stable across runs, which matters because iteration order over
the allocation dictionary must never influence simulation results (it does not — nothing iterates
cells during a tick except the EWMA, which is order-independent).

### AR-FIELD-2 — Storage: structure-of-arrays, not per-cell objects

```gdscript
class_name SparseHashField extends RefCounted
var _slot_of: Dictionary          # int key → int slot
var _cells: PackedInt64Array      # slot → key (for the bake and invalidate)
var _ch: Array                    # channel → PackedFloat32Array, all length == slot_count
var _v_hours: PackedInt32Array    # 24-bit direct-sun mask, one per slot
var _p_hour: PackedFloat32Array   # slot*24 + hour → baked P (SD-ENV-6)
```

Channels: `P_BAR_L`, `CROWDING`, `SVF`, `MATERIAL_ID`, `F_M` (pinned 1.0, INV-9). `D_L` is derived
(`0.0864 · P̄_L`), never stored — storing it would create two places for the same number.

### AR-FIELD-3 — Shell allocation and the projection rule

**This resolves a real gap in SD-ENV (see AR-AMBIG-1 and AR-AMBIG-2).** Cells are allocated where
`|Φ(centre)| ≤ field_shell_halfwidth = 0.09 m` — three cell layers, not one, because trilinear
interpolation of a single-layer shell is undefined.

Sample points outside the shell (a floating tip is up to `max_float = 0.40 m` out) are **projected
onto the shell before lookup**:

```
p_eff = p − clamp(Φ(p), −0.03, +0.03) applied along ∇̂Φ   →  p_eff = p − (Φ(p) − 0.0)·∇̂Φ(p)
```

i.e. the sample is moved to the surface, then read. This makes the world-space hash field behave as
the surface field SD-ENV already describes it as ("in Phase 1 only cells intersecting the tower
collider are ever allocated, so it behaves as a surface field with a world-space address"), and it
removes the fabricated radial gradient that an unprojected read at the shell boundary would produce
— a gradient that would have pulled every floating tip straight back at the wall and quietly
destroyed the AS-6 sag behaviour.

Reads for cells with no allocation still fall back per SD-EDGE-15 (`D_L` → diffuse baseline,
`C` → 0, `SVF` → 1).

### AR-FIELD-4 — Read path

Every read is `jitter → project → trilinear`, in that order:

```gdscript
func sample(channel: int, p: Vector3, tip_id: int, seg: int) -> float:
    var j := Hash64.jitter_vec3(tip_id, seg, channel) * params.field_sample_jitter * params.field_cell
    var pe := surface.project_to_shell(p + j, 0.0)
    return _field.read_trilinear(channel, pe, _fallback(channel))
```

- Jitter before projection, so the jitter perturbs the surface *position*, not the surface distance
  (SD-ENV-4; magnitude ≤ 0.35 · cell, deterministic, hashed not drawn → SD-RNG-4).
- **`read_trilinear` is the only read primitive. There is no nearest-cell accessor on the public
  API** — SD-ENV-3 is enforced by absence, not by discipline.

### AR-FIELD-5 — Gradients

`grad_S(channel, p, basis, tip_id, seg)` — four samples at `p ± ε·u` and `p ± ε·v` with
`ε = gradient_epsilon = 1.5 · field_cell = 0.09 m`, assembled in the tangent basis and returned as a
world vector already in the tangent plane (SD-ENV-5, §16). The tangent basis is always
`Conv.tangent_basis()` output — never constructed inline (SD-CONV-7).

Note that the four gradient samples use `seg` and distinct `channel+direction` jitter salts, so the
jitter does not cancel out of the central difference. That is intentional: it is what converts
residual grid structure into noise rather than into a biased gradient.

### AR-FIELD-6 — The bake (SD-ENV-6, W-019)

Split into two resolutions, because the naive reading of SD-ENV-6 is a multi-second load stall
(AR-AMBIG-4):

| Product | Grid | Cost |
|---|---|---|
| `SVF` | coarse `vis_cell = 0.12 m` (~5 k cells), 64 cosine-weighted rays, trilerped up | ~320 k raycasts |
| `V_hours` (24-bit) | same coarse grid, 24 rays | ~120 k raycasts |
| `P(cell, hour)` | **full** `field_cell` grid, pure arithmetic from `SVF`, `V_hours`, cell normal `∇̂Φ`, and `S(hour)` | no raycasts |

Cell normal comes from `∇̂Φ` — analytic and free, no extra queries.

`IvyEnvironment.tick()` then reduces to, per allocated cell, one table lookup plus the EWMA — which
is what makes 20 ticks/s at Grow speed nearly free, exactly as SD-ENV-6 intends. Memory:
~40 k cells × 24 × 4 B ≈ **3.8 MB** (SD-ENV-6 estimated 1.2 MB for a single-layer shell; see
AR-AMBIG-1).

`invalidate(aabb: AABB)` clears and re-bakes only the intersecting coarse cells and their dependent
fine cells. Nothing in the physiology or geometry layer may call it or know it exists (SD-ENV-7).

### AR-FIELD-7 — `IvyEnvironment` API

```gdscript
class_name IvyEnvironment extends RefCounted

func build(surface: SurfaceQuery, solar: Solar, params: IvyParams) -> void
func invalidate(aabb: AABB) -> void                                          # SD-ENV-7
func warm_up(days: float) -> void                                            # SD-TIME-7
func tick(dt_sim: float, game_day: float) -> void                            # EWMA, SD-ENV-8

func sample_D_L(p, tip_id, seg) -> float
func sample_crowding(p, tip_id, seg) -> float
func sample_f_M(p) -> float                                                  # pinned 1.0, INV-9
func sample_material_id(p) -> int
func grad_S_D_L(p, basis, tip_id, seg) -> Vector3
func grad_S_crowding(p, basis, tip_id, seg) -> Vector3

func deposit_crowding(p: Vector3, amount: float) -> void                     # INV-1: physiology only
```

`deposit_crowding` asserts in dev builds that its caller is `Physiology` (via a one-shot
`_writer_guard` token handed to `Physiology` at construction). Cheap, and it makes INV-1 a runtime
failure rather than a code-review question.

---

## AR-SIM — The tick loop and simulation API

### AR-SIM-1 — Tick ordering (fixed, documented, load-bearing)

`SimRoot._process(delta)`:

```
1. n = clock.advance_real(delta)                # 0 at Pause; capped at max_ticks_per_frame
2. repeat n times:  _tick()
3. sky_sun.update(clock.game_day)               # presentation only, SD-TIME-4 blend
4. plant_render.sync(plant)                     # pull by high-water mark
```

`_tick()`:

```
a. env.tick(dt_sim, game_day)                   # EWMA from the P(cell,hour) table
b. g_hat = solar.diel_gate(game_day)            # scalar; 1.0 if the flag is off  (SD-TIME-8)
c. tips.refresh_vigour(ctx)                     # one field read per tip; SD-TIP-4 needs it O(1) later
d. for tip in tips.live_in_id_order():          # ID order, never dictionary order
       physiology.accumulate_budget(tip, g_hat, ctx)
       emitted = 0
       while tip.B >= params.segment_length and emitted < params.max_segments_per_tick:
           growth_step.step_tip(tip, ctx)       # SD-RNG-3 draw order lives here
           emitted += 1
       if emitted == params.max_segments_per_tick: push_warning(...)   # SD-PHYS-2
e. tips.apply_pending_branches()                # created during (d), activated after, so a branch
                                                # never grows in the tick it was born
f. tips.apply_lifecycle(ctx)                    # stall, ground-strike, max_float, cap retirement
g. clock.tick_index += 1
```

| ID | Rule |
|---|---|
| AR-SIM-2 | **Iteration is over a stable id-ordered array, never a `Dictionary`.** Godot dictionary order is insertion order and *is* stable, but relying on it makes any future refactor a determinism bug. INV-7 and AS-4 depend on this line. |
| AR-SIM-3 | Branches created during step (d) are queued and activated in step (e). Growing a branch in its birth tick would make the plant's statistics depend on where in the tip array the parent happened to sit. |
| AR-SIM-4 | `clock.advance_real` caps at `max_ticks_per_frame = 8`. On a frame spike the simulation runs slower in wall-clock but produces **identical** results — INV-4 is preserved by construction, because nothing downstream of the clock sees real time. |
| AR-SIM-5 | `SimClock.advance_ticks(n)` is the deterministic driver used by GUT tests, the UI-script `ADVANCE_DAYS` verb, and the acceptance harness. It bypasses wall-clock entirely, which is what makes headless screenshots reproducible and fast. |

### AR-SIM-6 — `GrowthStep.step_tip`, in SD-RNG-3 order

```
1. correlated-random update   R ← normalize(0.75·R + 0.25·ξ)        [1 stream draw: ξ]
2. adhesion                   q,d = surface.nearest(x); A per §17 with SD-GEO-2 guards
3. gradients                  L = bounded ∇_S D_L ; C = bounded ∇_S C     [hashed jitter, no draws]
4. direction + collision      U per §21 with G = (0,−1,0); x_trial; raycast; reflect correction
                              ground clamp y ≥ 0.02 (SD-GEO-4); F update against d_contact
                              P ← normalize(0.5·P + 0.5·d_actual)
                              plant.append_segment(...)
                              physiology.deposit_stem_crowding(...)
5. branch draw                p_b = 1 − e^{−λ_b·h}, scaled by the SD-TIP-3 cap taper  [1 draw]
                              on success: queue branch; angle draw 45°–75°             [1 draw]
6. node / leaf draws          leaf_placer.advance(tip, segment)                        [0..6 draws]
```

Documented draw counts matter: `RngStream.normal_std()` consumes **two** uniforms (Box–Muller), so
SD-LEAF-5's `s_var` and SD-LEAF-7's value jitter each advance the stream by 2. Changing that
implementation changes every plant. It is pinned here.

### AR-SIM-7 — `PlantData` is append-only structure-of-arrays

```gdscript
class_name PlantData extends RefCounted
# segments
var seg_a: PackedVector3Array
var seg_b: PackedVector3Array
var seg_normal: PackedVector3Array      # wall normal at creation (SD-LEAF-4 rule 1)
var seg_tip: PackedInt32Array
var seg_order: PackedInt32Array
var seg_s: PackedFloat32Array           # arc length along its tip at creation
var total_length: float                 # float64 accumulator, summed in append order (AS-4)
# leaves — SoA so the whole growing buffer can go to multimesh_set_buffer in one call
var leaf_xform: PackedFloat32Array      # 12 floats per leaf
var leaf_color: PackedFloat32Array      # 4
var leaf_custom: PackedFloat32Array     # 4  = atlas rect xywh
var leaf_tip: PackedInt32Array
var leaf_s_at_node: PackedFloat32Array  # for s_age
var leaf_area: PackedFloat32Array       # alpha_fill·w·h, for SD-METRIC-3 (no rendering needed)
var leaf_frozen_count: int
```

**No removal operations exist on this class.** INV-2 is enforced by the absence of a delete path,
not by convention. Dormant and dead tips simply stop appending.

### AR-SIM-8 — Tip lifecycle

`TipManager` owns the SD-TIP state machine plus the cap. `refresh_vigour()` in tick step (c) caches
`vigour = f_L · f_C · f_S` per tip once per tick, so SD-TIP-4's "least-vigorous live tip" search at a
branch event is an O(N≤160) scan over cached floats rather than 160 field reads inside the growth
loop.

Retirement filters, in order: exclude FLOATING (SD-TIP-5); exclude tips above `0.8 · H_tower` if
fewer than 3 such exist (SD-TIP-6); require `parent.vigour > retiree.vigour · 1.25` (SD-TIP-4).

---

## AR-RENDER — Stem mesh and leaves

### AR-RENDER-1 — Stem: chunked incremental append

SD-GEO-7 forbids full rebuilds. Three options were considered:

| Option | Verdict |
|---|---|
| `SurfaceTool` rebuild per tick | Rejected — this *is* the forbidden full rebuild. |
| `RenderingServer.mesh_surface_update_vertex_region` into a preallocated buffer with degenerate-filled indices | Correct and fastest, but fiddly. **Held as the profiling escape hatch.** |
| **Chunked append: a bounded hot chunk, sealed into frozen `MeshInstance3D`s** | **Chosen.** Per-tick cost is O(hot chunk), not O(total). Straightforward GDScript. |

`CHUNK_SEGMENTS = 128`. Each segment emits its own short tube (3 rings × 5 verts with Catmull-Rom
subdivision; 1 ring × 5 at M1) using a parallel-transported frame carried on the `Tip`, so
consecutive segments' rings coincide exactly and there is no visible seam despite the duplicated
ring vertices. Rebuild cost at Grow speed: ~1,920 verts/tick × 20 ticks/s ≈ 38 k verts/s — fine.
~125 frozen chunks at full coverage ≈ 125 static draw calls, which is nothing.

### AR-RENDER-2 — Tip taper vs. immutability (a real conflict, resolved)

SD-STEM's `clamp(s_from_tip / 0.15, 0.35, 1)` means a segment's radius keeps changing for 0.15 m
after it is laid — i.e. it mutates already-emitted geometry, which collides with AR-RENDER-1's freeze
model (and, read strictly, with SD-GEO-7). Resolution:

- **Branch-order taper** (`1/(1 + 0.25·o)`) is known at birth. No conflict; bake it into the vertices.
- **Tip taper** is done in the **vertex shader**. Each vertex carries `CUSTOM0 = (s_seg, r_authored)`
  and `CUSTOM1.x = tip_id`; a 256×1 `R32F` texture holds each tip's current length, updated once per
  tick. The shader recovers the ring centre as `VERTEX − r_authored · NORMAL` (true for a tube, where
  the vertex normal *is* the radial direction) and re-expands at the correct radius. Zero CPU cost,
  geometry stays immutable, INV-2 and SD-GEO-7 both hold literally.
- **Catmull-Rom smoothing** needs the following segment, so tube emission **lags by one segment**.
  The trailing 3 cm of each live tip is simply not drawn. Nobody will see 3 cm; it is far cheaper
  than a per-tip cap mesh.

M1 uses a fixed radius and no smoothing (SD-M1), so none of this exists until M4/W-006-full.

### AR-RENDER-3 — Leaves: two preallocated MultiMeshes

Both `MultiMesh`es are allocated **once** at their maximum size (`leaves_static` = `leaf_cap` = 20,000;
`leaves_growing` = 600) with `use_colors` and `use_custom_data` enabled, and drawn via
`visible_instance_count`. Resizing a `MultiMesh` in Godot 4 reallocates and discards existing
instance data, so growth-by-resize is not an option; preallocation costs 20,000 × 20 floats ≈ 1.6 MB
and removes the failure mode entirely.

- `leaves_growing` is rewritten wholesale each tick with a single
  `RenderingServer.multimesh_set_buffer(rid, packed)` call — 600 instances is one buffer upload, far
  cheaper than 600 `set_instance_transform` calls.
- `leaves_static` is appended to incrementally with `multimesh_instance_set_transform/_color/
  _custom_data` as leaves freeze (`s_age == 1`, i.e. more than `leaf_expand_distance = 0.12 m` behind
  the tip).
- **Growing-buffer occupancy check:** 160 tips × (0.12 m / 0.040 m internode) = 480 ≤ 600. It fits,
  but not by much. `LeafRenderer` asserts occupancy and, on overflow, force-freezes the oldest
  growing leaves early rather than dropping them (a dropped leaf is a visible hole; a leaf frozen
  0.01 m early is invisible).

### AR-RENDER-4 — Leaf material

`StandardMaterial3D` cannot select an atlas sub-rect per instance, so SD-LEAF-1 requires a
`ShaderMaterial`.

```glsl
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, alpha_to_coverage;
// vertex:   UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
// fragment: ALBEDO = tex.rgb * COLOR.rgb;  ALPHA = tex.a;  ALPHA_SCISSOR_THRESHOLD = 0.5;
//           NORMAL_MAP / ROUGHNESS sampled with the same rect (the maps share the 2048² layout)
//           BACKLIGHT = vec3(0.30, 0.45, 0.18);              // SD-LEAF-1 transmittance
```

Three implementation traps, called out because each one silently produces a blacklisted artifact:

1. **Alpha-to-coverage requires MSAA** (AR-SCENE-7). Without it the render mode is ignored and leaf
   edges hard-clip.
2. **Mip erosion.** Alpha-scissored foliage thins out at distance as mips average alpha toward zero.
   Enable "Fix Alpha Border" on the atlas import and, if the aerial camera shows thinning, scale
   alpha by a mip-compensation factor. Do not solve it by lowering the scissor threshold — that
   reintroduces the soft edges alpha-to-coverage exists to provide.
3. **Premultiplication.** `LeafSet017_Leaves_RGBA.png` was composited with `-compose CopyOpacity`,
   which produces *straight* alpha. Leave "Premultiply Alpha" **off** in the import settings; with a
   0.5 scissor the surviving texels have α≈1 either way, but the import flag will darken the AA
   fringe if enabled.

Card geometry: M1 is a flat quad (4 verts); full is the SD-LEAF-1 cupped 3×3 patch (9 verts, 8 tris).
Both are pivoted at the petiole `(0.5, 1.0)` from `leaf_atlas.json`, so local +Y runs petiole → blade
tip and the SD-LEAF-4 rotations are all about sensible axes. Aspect comes from `atlas.aspect[id]` via
non-uniform basis scale — the photograph is never stretched (SD-LEAF-5).

---

## AR-PARAM — The parameter resource (INV-6, SD-PARAM)

### AR-PARAM-1 — One resource, injected

`IvyParams : Resource` carries every §30 row and every SD-PARAM row as an `@export`, organized with
`@export_group` per source section (`Spec30`, `Time`, `Field`, `Geometry`, `Tips`, `Leaf`, `Stem`).
`res://src/params/ivy_params_default.tres` is the committed default. `Main` loads it once and injects
it; no other file may `load()` it.

### AR-PARAM-2 — Derived values are computed, never cached

`a = exp(−dt_sim / light_memory)` is recomputed every tick from the current parameter value, which is
exactly what SD-ENV-8 requires ("changing `light_memory` at runtime recomputes `a` on the next tick
only"). The same applies to `gradient_epsilon = 1.5 · field_cell` and
`field_sample_jitter = 0.35 · field_cell` — these are stored as *ratios* in the resource, so
retuning `field_cell` cannot desync them.

### AR-PARAM-3 — Enforcing "no §30 literal at a call site"

A GUT test (`test_params_conformance.gd`) scans `src/sim/`, `src/env/`, and `src/world/` for the
numeric literals of the §30 and SD-PARAM defaults and fails on any hit outside
`src/params/`. Crude, and it will occasionally need an allowlist entry, but SD-PHYS-4 is a rule that
decays silently otherwise, and a decayed INV-6 makes G6 impossible.

### AR-PARAM-4 — `content_hash()`

`IvyParams.content_hash() -> String` serializes every exported property in sorted-name order with a
fixed float format and returns a SHA-256. The acceptance harness records it (SD-METRIC harness
integrity guard); a run whose hash differs from the committed default is marked non-conforming.

### AR-PARAM-5 — Feature flags

Two booleans, both defaulting to the recommended state, both cheap to flip:

| Flag | Default | Purpose |
|---|---|---|
| `diel_gate_enabled` | `true` | **INV-3a, ratified 2026-08-09.** The gate is applied at exactly one call site — `Physiology.growth_rate()` — as a scalar multiplier, which is what makes "magnitude only, never direction" checkable by inspection rather than by argument. The flag is retained not as an escrow but because **AS-3 clause (b) requires running the same seed with the gate disabled** and comparing daily elongation to ±5%. Do not delete it once M2 lands. |
| `dev_build` | `true` in editor | Enables the AR-TOWER-3 assertions, the INV-1 writer guard, blacklist assertions, and the dev overlay. |

`Solar.g_ref` (SD-TIME-8's previous-day mean of `g`) is **not** a runtime rolling average. Because
`SD-TIME-6` fixes the date, `g_ref` is a constant for all of Phase 1; it is computed once at
`Solar._init` by averaging `g` over 24 hourly samples. This also removes the undefined-first-day case
that the rule as written leaves open (AR-AMBIG-7).

---

## AR-RNG — Determinism plumbing (SD-RNG)

| ID | Rule |
|---|---|
| AR-RNG-1 | `RngStream` wraps Godot's `RandomNumberGenerator` (PCG32, portable and seed-stable in 4.4). Seeded from `Hash64.mix(parent_seed, branch_index)` — splitmix64, implemented on 64-bit ints with no float arithmetic anywhere in the mixing path. |
| AR-RNG-2 | Streams advance **only** in `GrowthStep` and `LeafPlacer`, both of which are called only from inside the `while B >= h` loop. **No RNG call exists in any `_process` or `_physics_process` body.** A grep for `randf`/`randi`/`RandomNumberGenerator` outside `src/core/rng_stream.gd` is part of `test_rng.gd`. |
| AR-RNG-3 | `RngStream.draw_count()` is maintained in dev builds. `test_determinism.gd` asserts the per-tip draw count after a fixed run, which catches an accidental reorder of SD-RNG-3 far earlier than a screenshot diff would. |
| AR-RNG-4 | Field jitter goes through `Hash64.jitter_vec3(tip_id, seg, channel)` and touches no stream (SD-RNG-4), so adding a field channel cannot desync growth. |
| AR-RNG-5 | `RunHash.of(plant, tips) -> String` fingerprints `{live_tip_count, total_tip_count, total_length (float64 bits), segment_count, leaf_count, sum of leaf positions}`. Total length is accumulated in append order as a float64 so "identical to the bit" (SD-RNG-5) is a meaningful claim. |

---

## AR-UI — Controls, dev overlay, and UI-script verbs

### AR-UI-1 — Player controls (SD-AGENCY, complete list, nothing more)

`Hud`: four anchor buttons (greyed when `Anchor.available == false`), Pause / Watch / Fast / Grow,
a date-time readout, and the SD-TIME-5 time-lapse indicator shown whenever the render blend `b < 1`.

### AR-UI-2 — Dev overlay (W-013, G6)

`DevOverlay` reflects over `IvyParams`' exported properties to generate its controls, so a new
SD-PARAM row appears in the overlay with no UI work. Edits write the live resource; per SD-EDGE-10
they affect future growth only, which is already guaranteed by AR-SIM-1 and AR-SIM-7 rather than by
overlay logic. Field visualization renders `D_L` and `C` as a per-cell debug `MultiMesh` of small
quads sampled at the shell, toggled with a key.

### AR-UI-3 — `run_ui_script.gd` verb extensions (new work item W-027)

The existing runner has only `WAIT` and `SCREENSHOT`, which cannot verify anything in this project.
The following verbs are an **architectural deliverable**, not tooling polish — without
`ADVANCE_DAYS`, every screenshot check is a wall-clock race and AS-4 cannot be verified from a
script.

| Verb | Effect |
|---|---|
| `CAMERA <sun\|shade\|aerial\|silhouette>` | `CameraRig.select()` |
| `SEED <n\|e\|s\|w>` | Re-seed at that anchor (SD-EDGE-11 semantics: reset plant + crowding, keep and re-warm the light field) |
| `SPEED <pause\|watch\|fast\|grow>` | `SimClock.speed` |
| `ADVANCE_DAYS <float>` | **Deterministic**: `clock.advance_ticks(round(days·24))`, no wall-clock dependence |
| `SET_PARAM <name> <value>` | Live `IvyParams` edit, for W-013 verification |
| `DUMP_METRICS <file.json>` | `CoverageMetric.measure()` + `RunHash` + `IvyParams.content_hash()` |
| `ASSERT <metric> <op> <value>` | Fails the run with a non-zero exit code |

`SCREENSHOT` gains an implicit settle of 3 frames after `ADVANCE_DAYS` so the renderer has synced.

---

## AR-METRIC — Metrics placement

`CoverageMetric` is constructed from `TowerSpec` alone and reads only `PlantData` — it never touches
the environment field (SD-METRIC-4) and never renders. Bucket mapping is analytic: 72 azimuth × 35
height buckets in tower-cylindrical coordinates, with the opening mask derived from
`TowerSpec.door_*` / `window_*` rather than from geometry queries.

**The ratified AS-1 requires three coverage numbers, not one.** `measure()` returns
`{overall_pct, sun_half_pct, shade_half_pct, stem_bucket_pct, sector_stem_length[12],
sector_leaf_count[12], lip_reached}`. The sun half is the 180° centred on the seed anchor's azimuth
(not a hardcoded compass direction — AS-2's shaded-side control run seeds on the opposite face, and a
hardcoded half would silently invert that comparison). The Director's coupling rule — the two half
floors must average to at least the overall floor — is asserted in `test_metric.gd` against whatever
values `DESIGN.md` currently holds, so an inconsistent future revision fails a test rather than
producing an unsatisfiable acceptance run.

**AS-2 samples during the run, not at the end.** `SimRoot` exposes
`metrics_snapshot_days: PackedFloat32Array` (default `[30, 60, 150]`); the harness records a full
measurement at each. This is cheap — one pass over `PlantData` — and it is the only way to test the
ratified day-30 and day-60 latency targets.

**Projected leaf area per bucket** (resolving AR-AMBIG-6): each leaf contributes
`leaf_area[i] · |dot(n_leaf, n_bucket)|` to the single bucket containing its petiole anchor, where
`leaf_area[i] = alpha_fill[atlas_id] · w · h` is precomputed at placement time and stored in
`PlantData`. Leaves straddling a bucket boundary are attributed wholly to one bucket; at 0.17 × 0.10 m
buckets and ~0.075 m leaves this is a small, unbiased, and stable approximation, and it costs one
multiply per leaf instead of a polygon clip.

---

## AR-BUDGET — Quantitative budgets (sanity targets, not requirements)

These are derived from the SD-* parameters and are given so the Programmer can tell "working" from
"subtly wrong" without waiting for M4.

| Quantity | Expected at day 150, defaults | Diagnostic if violated |
|---|---:|---|
| Segments per tick per tip, at noon | `r_max·ĝ·dt / h = 0.12 · 2.1 / 24 / 0.03 = 0.35` | `max_segments_per_tick = 8` should **never** fire under defaults. If it does, `r` is wrong by >20×. |
| Live tips | ≤ 160 (hard cap), typically 96–160 | If tips sit at the cap from day 20, `f_C` or the SD-TIP-3 taper is not working. |
| Total segments | 35,000–45,000 | Above ~55,000 while live tips remain well below the soft cap suggests runaway tip turnover accumulating immutable volume — investigate the homeostat and stall rule, not crowding alone (crowding cannot suppress beyond `C = 1`; see SD-LEAF-8). |
| Total stem length | 1,000–1,400 m | Above ~1,600 m under the same conditions — same diagnostic as segments. |
| Leaves | 15,000–20,000 (cap 20,000) | Hitting `leaf_cap` before day 120 means `leaf_crowd_suppress` is too weak. |
| Leaf area laid down | 55–70 m² against ~43 m² of eligible wall | Above ~75 m² with sun-facing coverage still >95% confirms redundant sunny-side layering (rubric criterion 2) — address with density-gated leaf levers, not volume brakes. |
| Tips ever created | 850–1,050 | Above ~1,200 suggests branching turnover is runaway without a binding constraint. |
| Bake time at load | < 1.5 s | Above 3 s, move to the AR-FIELD-6 disk cache. |
| Field memory | ~3.8 MB (`P(cell,hour)`) + ~1 MB channels | |

**A quantitative risk worth surfacing now (AR-RISK-4).** The wall is 2,520 buckets × 0.017 m² ≈
43 m². The ratified AS-1 (70 / 90 / 50) needs roughly `1,260·0.9 + 1,260·0.5 = 1,764` buckets to hold
≥ 0.0085 m² of leaf each — **≈ 15.0 m² of leaf area, perfectly distributed**. With
`leaf_width_base = 0.075 m`, `alpha_fill ≈ 0.64`, and 12,000 leaves, the plant lays down ≈ 27 m².
That is only ~1.8× the theoretical minimum, and real placement clumps, so the margin is thinner than
it looks — particularly on the shaded half, where AS-1's 50% floor must be met by a side that is
simultaneously growing slower (`f_L ≈ 0.57`), branching ~1.9× less often, and being preferentially
retired by `SD-TIP-4`'s vigour rule, which the Director explicitly flagged.

**Do not pre-tune any of this.** All three remedies are single parameter edits already present in
`IvyParams` (`leaf_width_base` toward 0.09 m, `leaf_crowd_suppress` down, `retire_margin` up), and
W-021 lands the coverage metric at M2 precisely so the choice is made from a measurement. The point
of recording the arithmetic here is that the Programmer should recognise a 12 m² result as "the
shaded floor will fail at M4" three milestones before it does.

**2026-08-09 — the measurement arrived, and it is the reverse problem (W-048, Systems Designer).**
The first reproduced day-150 run at defaults measured **42,795 segments (budget 12,000–20,000),
1,257.9 m stem (budget 360–600 m), 18,488 leaves (budget 7,000–15,000, 92% of the 20,000 cap), and
≈66 m² of leaf area (budget 20–35 m²)** — about 1.5 leaf-layers over every square metre of the 43 m²
eligible wall. AS-1 passes (75.13 / 93.83 / 54.43 against 70 / 90 / 50) but by **volume, not
placement**: the day-150 screenshot is a uniform green mat, the rubric-2 wallpaper failure. Note the
three remedies above were written to address the *opposite* risk (AS-1 missed); two of them
(`leaf_width_base` up, `leaf_crowd_suppress` down) push the wrong way here and are explicitly
rejected. The decision:

- **W-040 (stall rule) lands first.** SD-TIP's GROWING→DORMANT stall transition is unimplemented, so
  trickle tips never retire and keep laying stem and spawning branches — a first-order cause of the
  segment/stem overshoot (the tip census shows 937 tips ever created for a budget that implies
  ~300–450). Tuning crowding around a sim with live zombie tips would bake a compensating
  over-strong `leaf_crowd_k` that overcorrects the moment W-040 lands. Re-measure after W-040 before
  finalising the crowding numbers.
- **Then strengthen the density feedback, not the leaf size.** `leaf_crowd_k` 0.5→0.85 (brakes the
  growth→branch loop, the AR-BUDGET ">25,000 = crowding not suppressing growth" diagnostic);
  `leaf_crowd_suppress` 0.55→0.75 and `leaf_crowd_floor` 0.35→0.20 (stop stacking hidden interior
  layers, density-gated so the sparse shaded half is spared). Held: `leaf_width_base = 0.075`
  (raising it adds area — wrong direction), `retire_margin = 1.25` (the cap is barely engaged —
  census peaks at 123 live, never near the 160 hard cap — so retirement is not the binding
  constraint here, though `retire_margin` remains the DESIGN-designated shaded-floor lever if that
  floor is threatened), `branch_rate` and `f_C`'s 0.8 held in reserve. Target operating point: the
  mid-upper AR-BUDGET envelope (≈16–19k segments, ≈480–570 m, ≈8–11k leaves, ≈30–35 m²), deliberately
  not the 12k floor, to preserve AS-1's thin margins. The budget numbers above are **unchanged** —
  the budget was right; the simulation was wrong.

**2026-08-09, later — both brakes were tried and neither worked; the crowding tuning was reverted
(W-050, Code Reviewer).** W-040 landed and cost only ≈2% of the overshoot: a trickle tip emitting one
0.03 m segment every three days still clears the 0.01 m/day stall threshold, so the tips the rule was
aimed at mostly escape it. The crowding tuning was then applied and cost 4% of segments while
breaking two AS-1 floors — **63.17 / 92.47 / 30.76 against 70 / 90 / 50** — and has been reverted to
0.5 / 0.55 / 0.35. The reason is structural rather than a matter of degree: `C` is hard-clamped to
`[0, 1]` (see SD-LEAF-8), so `leaf_crowd_k` cannot deepen suppression in the saturated sunny mat
where the plant actually lives, and its only real effect is to push the sparse shaded half to full
suppression sooner. **The clause above that reads "brakes the growth→branch loop" is therefore
withdrawn** — `f_C` bottoms out at `e^{−0.8} ≈ 0.45` no matter what `k_leaf` is.

What survives the two attempts is a sharper diagnosis. Stem length per tip is **on budget** at
≈1.2 m; the plant is oversized because it creates **962 tips against the ~300–450 the budget
implies**. Both levers tried act on leaf placement and tip retirement — neither touches tip
*creation* — which is consistent with how little they bought. `branch_rate`, held in reserve above,
is the untried lever and the one the measurement now points at. The 2× overshoot and the W-048
re-decision stay open.

**2026-08-09, W-048 re-decision (Systems Designer, informed by W-050).** `branch_rate` was examined
and **rejected** as the volume brake, for a structural reason that also disposes of the caps and the
stall rule as brakes. **The SD-TIP-3 taper is a homeostat.** In quasi-steady state tips-created/day =
tips-removed/day, and the taper `q` self-adjusts to hold (branch-pressure · `q`) ≈ removal, so the
live population and the turnover — hence the accumulated volume — are pinned by the *removal* rate,
**independent of `branch_rate`**, for as long as `q < 1`. Measured `q ≈ 0.586` at 100–123 live tips,
so there is headroom: lowering `branch_rate` from 1.7 merely lets `q` climb toward 1 and changes
almost nothing until `branch_rate ≈ 1.7 · 0.586 ≈ 1.0`, where `q` saturates at 1 and the population
finally falls below the soft cap. But below that threshold the first tips that fail to replace
themselves are the lowest-`λ_b` tips (`λ_b = branch_rate · f_l^{1.3} · (1 − C)^{1.5}`) — the
shaded/crowded ones — so `branch_rate` is inert until a threshold and then **collapses the shaded
half first**. Lowering the caps has the same endpoint (any uniform volume cut halves the volume-limited
shaded coverage), because the shaded 180° is sparse/unsaturated and sits at 53.99% (+3.99) while
carrying ≈60 m² of leaf area — **2× this table's own 20–35 m² line — merely to clear the 50% floor.**

Two conclusions follow. **(1)** The rubric-2 green mat is a separable *sun-side leaf-density* problem
and is fixed with the density-gated leaf levers (SD-LEAF-8: `leaf_crowd_suppress` 0.55→0.70,
`leaf_crowd_floor` 0.35→0.30, landed 2026-08-09), which spare the shaded half. **(2)** The segment/stem/tip
lines cannot be brought into this envelope without breaching the 50% shaded floor, so **the envelope
and the floor are in genuine conflict at the plant's measured placement efficiency — escalated to the
Director as SD-OPEN-6.** This table is explicitly "sanity targets, not requirements": the binding
constraints are AS-1 (floors), AS-5 (performance — peak 123 live tips, the 160 hard cap never
approached), and the rubric. The earlier "the budget was right; the simulation was wrong" verdict is
now half-overturned: per-tip stem (≈1.2 m) is on budget and live-tip count (100–123) is inside the
"96–160" line above; only tips-*ever-created* (≈962) and total accumulated leaf/stem overshoot. The
20–35 m² / 360–600 m lines were back-derived from AR-RISK-4's assumption that ~27 m² *reasonably
distributed* meets 70/90/50; the real distribution is far more uneven, so those lines are an
architectural number to be re-derived by the Director, not quietly relaxed here.

**2026-08-09 — Director ruling on SD-OPEN-6 (supersedes the escalation above).** The envelope is
re-derived in the table header: 35–45k segments, 1,000–1,400 m stem, 55–70 m² leaf area, 850–1,050
tips ever created — bracketing the measured day-150 pass state (40,952 / 1,202 m / ≈60 m² / 962 tips)
at current placement efficiency with AS-1 at 74.83 / 93.67 / 53.99. The old ">25,000 = crowding not
suppressing" diagnostic is withdrawn (W-050: crowding saturates at `C = 1` and cannot distinguish one
layer from three). Placement-efficiency improvement — meeting the shaded floor with less total volume
— is deferred to M4 via W-015/W-030, not pursued through volume brakes that collapse the shaded half.
The SD-LEAF-8 density-gated levers (0.70 / 0.30) landed 2026-08-09 (W-048 visual half); they address
the sunny-side rubric-2 symptom. Measured day-150: 74.58 / 96.23 / 50.62 — all floors pass.
⚠️ Shaded floor margin is 0.62 points. See `DESIGN.md` ratification log.

---

## AR-TEST — Test strategy

### AR-TEST-1 — GUT unit tests (`res://test/`, all headless)

| File | Covers | Notable cases |
|---|---|---|
| `test_conv.gd` | SD-CONV, W-017 | `GRAVITY == (0,−1,0)`; **solar-noon sun vector** (SD-CONV-2: `x≈0`, `y>0`, `z>0`); tangent basis orthonormal with `cross(u,v)≈n` on a vertical wall; **degenerate basis on a horizontal surface** (SD-CONV-5 / SD-EDGE-2 — the AS-6 path); basis continuity as `n` sweeps through the degenerate cone |
| `test_conv_light.gd` | SD-CONV-9 | Instantiates `SkySun`, sets a sun direction, asserts `dot(light.global_basis.z, S) > 0.999`. Scene-based but headless-safe. |
| `test_solar.gd` | SD-TIME-6, W-008 | Day length ≈ 13.5 h at 51.5° N / DOY 105; sunrise/sunset near due E/W; `sinα < 0` at midnight; elevation monotone before solar noon |
| `test_tower_geometry.gd` | SD-CONV-3, AR-TOWER-3 | All four normal assertions over every triangle; mesh and collision triangle arrays identical; doorway and window present in the collision shape (raycast through the aperture misses) |
| `test_surface_query.gd` | AR-TOWER-4/5/6 | Φ sign inside vs outside; Φ vs raycast distance agreement to 5 mm on 200 sampled rays; `nearest()` at the lip crease; `face_index` → material lookup; `SeedAnchors` yields 4 anchors with the north one deterministically offset off the doorway (SD-AGENCY-2, SD-EDGE-1) |
| `test_params.gd` | INV-6, SD-PARAM | Every §30 and SD-PARAM key present with the specified default; `content_hash()` stable across two loads and changes when a value changes |
| `test_params_conformance.gd` | SD-PHYS-4 | Source scan for §30 literals outside `src/params/` (AR-PARAM-3) |
| `test_rng.gd` | SD-RNG, W-018 | Stream reproducibility from a seed; `derive(i)` independence (adding a sibling does not perturb an existing stream); `jitter_vec3` determinism and `‖j‖ ≤ 0.35·cell`; source scan for stray `randf`/`randi` |
| `test_field.gd` | SD-ENV-3/4/5, AR-FIELD | Trilinear exact on a linear ramp; central-difference gradient recovers a known slope; **uniform field ⇒ exactly zero gradient** (SD-EDGE-12); out-of-shell read returns the baseline (SD-EDGE-15); shell projection maps a point 0.35 m out onto the shell; no public nearest-cell accessor exists |
| `test_physiology.gd` | SD-PHYS, §10–§18, §24–§26 | `f_L(12)=1`, `f_L(3)≈0.625`, `f_C(1)≈0.449`, `f_S(F_max)=0.5`; `w_P/w_R/w_L/w_C` at `H∈{0,1}`; `p_b≈0.0497` at ideal; budget loop emits `floor(B/h)` and is bounded at 8 (SD-PHYS-2) |
| `test_geometry.gd` | SD-GEO | §21 sum against a hand-computed case; SD-GEO-2 fallbacks (`‖U‖<1e−4 ⇒ d=P`; `d<1e−5` skips adhesion); **`F` resets at `d_contact=0.02`, not at `d_A=0.15`** (SD-GEO-1); ground clamp + 5-strike dormancy (SD-GEO-4); post-collision point satisfies `Φ ≥ −0.005` (blacklist item 1) |
| `test_tip_lifecycle.gd` | SD-TIP | Every transition in the table; cap taper `q`; never-retire-FLOATING (SD-TIP-5); top-of-tower protection (SD-TIP-6); `retire_margin` prevents thrash; dormant tips keep geometry (INV-2) |
| `test_time.gd` | SD-TIME, INV-3a | **Speed-invariance (SD-TIME-3): a run held at Watch for 20 days then Grow to day 60 produces an identical `RunHash` to a run held at Grow throughout** — the single most important test in the suite; diel gate mean-preservation `mean(ĝ) ≈ 1.0 ± 0.02` over 24 ticks (SD-TIME-8b); `ĝ≈2.1` at noon, `≈0.11` at night (SD-TIME-8c); **AS-3 clause (b) in miniature — total elongation over one game-day with the gate on is within ±5% of the same seed with `diel_gate_enabled = false`**; gate value never reaches any directional term |
| `test_leaf_placement.gd` | SD-LEAF-2..8 | **Node count depends on metres grown, not tick count** (INV-4); tip suppression zone empty; internode lengthens at low `f_L`; phyllotaxy flatten weight; adjacency rule (no atlas id within 2 nodes, SD-LEAF-6); normal-offset ladder produces 5 distinct shells; width CV ≤ 0.35 over 2,000 leaves (blacklist item 5); `w/h == atlas.aspect` |
| `test_determinism.gd` | AS-4, SD-RNG-5 | Two 30-game-day headless runs → identical tip count, bit-identical total length, identical leaf count, identical `RunHash`, identical per-tip draw counts |
| `test_metric.gd` | SD-METRIC, ratified AS-1 | Bucket mapping round-trips; opening buckets excluded from the denominator; a synthetic saturated mat measures 100%; **sun/shade halves are split about the seed anchor's azimuth, not a compass constant**; the AS-1 coupling rule holds (the two half floors average to ≥ the overall floor); 12-sector asymmetry reports correctly on a synthetic one-sided plant |
| `test_blacklist.gd` | D-5 | Each automatable check fires on a synthetic violation and stays quiet on a clean plant |

### AR-TEST-2 — What must be a `run-ui-script` scenario, not a unit test

Per `.cursor/rules/reviewing.mdc`, anything touching multi-step UI or gameplay flow is verified by
script + screenshots, not by reading a diff.

| Scenario | Script | Checks |
|---|---|---|
| **M1 exit gate** | `m1_growth.txt` | `SPEED grow`, `ADVANCE_DAYS 30`, `SCREENSHOT` — "is it recognizably ivy-shaped?" is a human judgement on an image and cannot be a unit test |
| Four canonical angles | `canonical.txt` | The AS-4 / rubric screenshot set at a fixed game-day |
| AS-6 silhouette break | `as6_silhouette.txt` | `CAMERA silhouette` at day 150 — overhang and sag against the sky |
| AS-2 asymmetry, visually | `canonical.txt` at day 30 / 60 | The sun and shade elevations must *look* different; the number comes from `DUMP_METRICS` |
| Re-seed flow | `reseed.txt` | `SEED n` → `SEED s`: plant and crowding reset, field warm-up re-runs, anchors greyed correctly (SD-EDGE-11) |
| Speed / pause UI | `time_controls.txt` | Time-lapse indicator appears at Fast and Grow, disappears at Watch (SD-TIME-5) |
| Dev overlay live tuning | `dev_tuning.txt` | `SET_PARAM` then `ADVANCE_DAYS` then screenshot — M3's exit condition is literally "a parameter change can be seen on screen without a restart" |
| Blacklist items 3, 4, 7 | `canonical.txt` output | Numeric auto-screens run in the harness; **final judgement stays human** (SD-METRIC D-5) |

---

## AR-SEQ — Build sequence

The Director's instruction is non-negotiable: **M1 is an ugly end-to-end vertical slice, and no
tuning, field-precision work, or leaf polish happens before recognizably ivy-shaped growth is visible
in a screenshot.** The sequence below is ordered so that the Programmer always has something that
runs, and so that the first screenshot arrives as early as physically possible.

### Stage 0 — Foundations (no visible output; ~half a day)

| Step | Work item | Deliverable | Gate |
|---|---|---|---|
| 0.1 | W-026 | `IvyParams` + defaults `.tres` | `test_params.gd` green |
| 0.2 | W-017 | `Conv` — all SD-CONV constants and helpers | `test_conv.gd` green (rows 1, 5, 7) |
| 0.3 | W-018 | `Hash64`, `RngStream`, `SimClock` | `test_rng.gd` green |

Everything downstream depends on these three, and each is small enough to land in one sitting. Doing
them first is what prevents the SD-CONV convention bugs that the Systems Designer flagged as the
highest-risk detail in the whole project.

### Stage 1 — M1 vertical slice

| Step | Work item | Deliverable | Gate |
|---|---|---|---|
| 1.1 | W-025 | `main.tscn` → `Node3D`; `world.tscn` skeleton; project settings (AR-SCENE-7); one camera | Screenshot renders a grey box on ground under a sun |
| 1.2 | W-002 (M1 subset) | `TowerSpec`, `TowerBuilder`, `TowerSdf`, `Tower`, `SurfaceQuery`, brick material, ground | **Screenshot: a brick tower with a doorway and a lip.** `test_tower_geometry.gd` + `test_surface_query.gd` green |
| 1.3 | W-003 (M1 subset) | `CellGrid`, `SparseHashField`, `IvyEnvironment` with constant `D_L = 12` — but **trilinear, jitter, projection, and gradients all real from day one** (SD-ENV-3/4/5 is the R-3 mitigation and retrofitting it later means re-tuning everything) | `test_field.gd` green |
| 1.4 | W-004 | `Physiology`, full (SD-M1 says physiology is complete from M1) | `test_physiology.gd` green |
| 1.5 | W-005 | `Tip`, `PlantData`, `GrowthStep`, `SimRoot` tick loop, one hardcoded south anchor | Console: tip position climbs; `test_geometry.gd` green |
| 1.6 | W-006 (M1 subset) | `StemMeshBuilder`, fixed-radius 5-sided tube, chunked append | **Screenshot: a bare vine climbing the tower.** This is the real "does the simulator work" moment |
| 1.7 | W-007 (M1 subset) | `LeafAtlas`, leaf shader/material, `LeafPlacer` M1 subset (flat quad, leaf `a`, fixed size, ±90° alternation, 0.04 m internode, **normal-offset ladder ON**), `LeafRenderer` | **M1 EXIT: `m1_growth.txt` produces a screenshot of recognizably ivy-shaped growth. Ugly is fine.** |

At M1 the sun is a static `DirectionalLight3D` at a fixed hour and the field is constant — there is
no solar model, no bake, no branching cap, no metric, no UI. That is deliberate.

### Stage 2 — M2, environment live

W-008 (`Solar`, three speeds, render-sun blend) → W-019 (`LightBake`) → W-009 (light field,
`SVF`, `V_hours`, EWMA; regression target SD-ENV-10: south `D_L ≈ 26`, north `≈ 2.5`) → W-010
(crowding) → W-011 (branching, lifecycle, tip cap) → W-021 (coverage metric + 12-day warm-up) →
W-020 (diel gate — INV-3a, with the gate-disabled path kept reachable for AS-3 clause (b)) → W-022
(blacklist assertions).
**Gate: AS-2 and AS-3 pass**, including AS-2's day-30 and day-60 latency targets and AS-3's
mean-preservation clause.

W-019 before W-009 matters — building the light field against live raycasts and then retrofitting the
bake means writing the EWMA loop twice.

### Stage 3 — M3, agency and tuning

W-012 (four derived anchors, greying, re-seed, time controls, time-lapse indicator) → W-013 (dev
overlay + field visualization) → W-027 (remaining UI-script verbs).
**Gate: `dev_tuning.txt` shows a parameter change on screen without a restart.**

### Stage 4 — M4, looks good

W-015 (full SD-LEAF: cupped card, phyllotaxy, orientation stack, size model, atlas tiers, colour,
crowding suppression; full SD-STEM: taper via AR-RENDER-2, Catmull-Rom) → W-014 (acceptance harness).
**Gate: blacklist clean, rubric ≥ 5/6, AS-1/4/5/6 pass.** Rubric scoring is blocked on W-024 (the
Director's reference photograph set), which is not an Architect or Programmer dependency — but W-015
should not be *assessed* before it lands.

---

## AR-AMBIG — Systems Designer rules that are ambiguous or not implementable as written

Each of these is a place where following the contract literally would produce a defect or is
under-specified. None is silently reinterpreted; each has a proposal that the Systems Designer or
Director can reject.

| ID | Rule | Problem | Proposed resolution |
|---|---|---|---|
| AR-AMBIG-1 | **SD-ENV-1 / SD-ENV-6** | "~12,200 allocated cells" describes a single-cell-thick surface shell, but SD-ENV-3's mandatory trilinear interpolation needs at least two, realistically three, layers. As written the two rules are mutually inconsistent. | Allocate `\|Φ\| ≤ 0.09 m` (three layers) → ~40 k cells; hourly bake ≈ 3.8 MB instead of 1.2 MB. Still trivial. **Impact: none behavioural, memory only.** |
| AR-AMBIG-2 | **SD-ENV-3 / SD-EDGE-15** | Trilinear interpolation at the edge of a sparse allocation blends real values against fallbacks, fabricating a strong radial gradient that points back at the wall. A floating tip 0.3 m out (the AS-6 case) would be yanked back, destroying the sag SD-EDGE-3 explicitly wants. | **AR-FIELD-3:** project every sample point onto the shell along `∇̂Φ` before lookup. Makes the world-space field behave as the surface field SD-ENV already describes. |
| AR-AMBIG-3 | **SD-ENV-2 vs INV-10** | SD-ENV-2 stores resolved `A_m` per cell; INV-10 requires per-material lookup. A stored scalar cannot be hot-tuned and duplicates the registry. | Store `material_id` per cell; resolve `A_m` through `MaterialRegistry` at read time. |
| AR-AMBIG-4 | **SD-ENV-6** | 64 SVF rays + 24 visibility rays per cell over ~40 k cells is ~3.5 M GDScript raycasts — several seconds of load stall on every run and every re-seed. | Bake visibility products on a coarse 0.12 m grid (~440 k rays) and trilerp; keep `P(cell,hour)` at full resolution since it needs no rays. Disk cache held in reserve. |
| AR-AMBIG-5 | **SD-AGENCY-2** | "hits a collider tagged `opening`" presupposes sub-colliders, but the tower is one trimesh. | Per-face material ids via `intersect_ray`'s `face_index` (AR-TOWER-6). |
| AR-AMBIG-6 | **SD-METRIC-3** | "projected leaf area attributed to a bucket" is not defined for a 3D card straddling a bucket boundary on a curved wall. | `alpha_fill · w · h · \|dot(n_leaf, n_bucket)\|`, attributed wholly to the petiole's bucket. Cheap, stable, unbiased at these scales. |
| AR-AMBIG-7 | **SD-TIME-8** | `g_ref` = "mean of `g` over the previous simulated game-day" is undefined on day 0 and implies a rolling buffer. | Since SD-TIME-6 fixes the date, `g_ref` is a constant. Compute once at `Solar._init` from 24 hourly samples. |
| AR-AMBIG-8 | **SD-STEM vs SD-GEO-7 / INV-2** | Tip taper (`s_from_tip / 0.15`) mutates the radius of segments already emitted and frozen. | Order taper baked at birth; tip taper in the vertex shader from a per-tip length texture (AR-RENDER-2). Geometry stays immutable. |
| AR-AMBIG-9 | **SD-GEO-6** | "rotated about the local wall normal" is undefined for a FLOATING parent, which has no wall normal — and branching off a floating runner is exactly the AS-6 / SD-EDGE-3 case. | Fall back to `tip.last_contact_normal`; if never contacted, use `Conv.tangent_basis(P).x`. |
| AR-AMBIG-10 | **SD-LEAF-9** | `leaves_growing ≤ 600` is asserted but not reconciled with the cap: 160 tips × (0.12 m / 0.040 m) = 480, and shorter internodes under a future tuning pass would overflow it. | Keep 600, assert occupancy, and on overflow force-freeze the oldest growing leaves early rather than dropping them. |
| AR-AMBIG-11 | **SD-LEAF-1** | Alpha-to-coverage is specified but is a silent no-op without MSAA, which is off by default in Godot. | Project setting `msaa_3d = 2` (AR-SCENE-7), with a note in the leaf material file. |

Two notes where a suspected conflict turned out **not** to exist, recorded so nobody re-litigates
them: SD-CONV-2's formula at `Az = 180°` does give `S = (0, sinα, +cosα)`, so "south = +Z" is
consistent with SD-AGENCY-1. And `max_segments_per_tick = 8` can never fire under default parameters
(peak is 0.35 segments/tick/tip) — it is a pure guardrail, not a hot path, and should not be
optimized.

---

## AR-RISK — Technical risks and mitigations

| ID | Risk | Mitigation |
|---|---|---|
| AR-RISK-1 | **Coordinate conventions (the Systems Designer's own top risk).** A sign error in `S` or a flipped tangent basis produces a plausible-looking plant that fails AS-2 for reasons no screenshot reveals. | `Conv` is the only place a basis or world axis is constructed (SD-CONV-7); `test_conv.gd` lands in Stage 0.2, before any geometry exists; AR-TOWER-3's SDF cross-check catches inverted faces independently of the winding code. |
| AR-RISK-2 | **GDScript throughput.** ~640 segment events/s at Grow speed, each with 8 trilinear reads (64 dictionary lookups) plus a raycast. | Bake reduces the per-tick environment update to a table lookup (SD-ENV-6); SoA `Packed*Array` storage throughout; field reads are the profiling target, and `SparseHashField` is a leaf class that can be rewritten as a GDExtension without touching a single caller. |
| AR-RISK-3 | **Stem mesh append.** A naive rebuild is an instant AS-5 failure at 15,000 segments. | Chunked append bounded at 128 segments/chunk (AR-RENDER-1), with `mesh_surface_update_vertex_region` held in reserve. |
| AR-RISK-4 | **Leaf area may not reach the ratified AS-1 bar, especially the 50% shaded floor** (see AR-BUDGET). The vigour-based tip cap actively works against that floor. **Realised in the reverse, 2026-08-09 (W-048):** the shaded half is volume-limited and needs ≈60 m² of leaf area — 2× the old 20–35 m² budget — merely to reach 53.99%, so the risk is not "too little leaf" but that *reducing* volume to the old budget breaks the floor. **Resolved 2026-08-09 (SD-OPEN-6):** AR-BUDGET re-derived upward; placement-efficiency work deferred to M4 (W-015/W-030); sunny-side rubric-2 symptom addressed by SD-LEAF-8 levers (landed 2026-08-09). AS-1 floors unchanged. | All remedies are `IvyParams` edits. W-021 lands the metric at M2, reporting both halves separately. Volume brakes (`branch_rate`, caps, `leaf_crowd_k`) are rejected — they collapse the shaded half first. The density-gated leaf levers (SD-LEAF-8) spare the shaded half and address rubric-2 on the sunny mat. |
| AR-RISK-5 | **Bake time on re-seed.** SD-EDGE-11 re-seeds keep the light field, so the bake does not re-run — but a `TowerSpec` change does. | Bake is coarse (AR-FIELD-6) and `TowerSpec` changes are a dev-only action. |
| AR-RISK-6 | **`leaves_growing` overflow** under future tuning. | AR-AMBIG-10 force-freeze policy plus an assertion. |
| AR-RISK-7 | **Determinism erosion.** Any `randf()` added later in a `_process` body silently breaks INV-7, AS-4, and SD-TIME-3, and the failure appears as an unreproducible screenshot weeks later. | `test_rng.gd` source scan; `RunHash` in every harness output; per-tip draw-count assertion in `test_determinism.gd`. |
| AR-RISK-8 | **`main.tscn` replacement breaks the existing tooling.** | The path and UID are preserved and `tools/*` load by path, so nothing changes; `tools/ui_scripts/smoke.txt` is the regression check and must stay green through step 1.1. |

---

## AR-NONGOAL — Non-goals of this stage

Beyond the `DESIGN.md` and `SD-NONGOAL` lists, the Programmer should **not** build any of the
following, and should push back to this stage if a task seems to require them:

- A GDExtension, C# module, or any native code. GDScript is sufficient for the AR-BUDGET numbers;
  `SparseHashField` is deliberately isolated so this stays a future option, not a present decision.
- A general-purpose SDF or voxelizer. `TowerSdf` is analytic and specific to `TowerSpec`.
- Baked tower mesh artifacts on disk (AR-TOWER-2), a bake disk cache before it is needed
  (AR-FIELD-6), or `mesh_surface_update_vertex_region` before profiling says so (AR-RENDER-1).
  All three are named escape hatches, not tasks.
- Any abstraction over "buildings" or "species". Phase 1 ships one tower and one plant;
  `TowerSpec` + `MaterialRegistry` are the seams Phase 2 will widen.
- An event bus, a service locator, or autoload singletons (AR-OVER-3).
- Camera controls, camera animation, or any runtime camera transform write (AR-SCENE-3).
- Editor plugins or custom inspector UI. The dev overlay is in-game and reflection-driven.
- Re-tuning any `SD-PARAM` or §30 default. Tuning starts at M2 with a measurement, per the
  Director's sequencing rule.

---

## AR-HANDOFF — Handoff to the Gameplay Programmer

**Produced artifacts:** this section (`AR-*`) of `IMPLEMENTATION.md`; the planned file layout and
per-file responsibilities in `TECHNICAL_INDEX.md`; the implementation-order table and new items
W-025 (3D composition root), W-026 (parameter resource) and W-027 (UI-script verbs) in
`work-items/WORK_ITEMS.md`.

**Start here:** `AR-SEQ` Stage 0.1. Do not start at the tower.

**Primary files to change or create first, and why:**

1. `src/params/ivy_params.gd` + `ivy_params_default.tres` — everything else reads it; creating it
   late guarantees §30 literals leak into call sites (INV-6, SD-PHYS-4).
2. `src/core/conv.gd` — the single highest-risk detail in the project; land it and its test before
   any geometry exists (SD-CONV, W-017).
3. `src/core/hash64.gd`, `rng_stream.gd`, `sim_clock.gd` — determinism must be structural from tick
   zero, not retrofitted (SD-RNG, SD-TIME-1, W-018).
4. `src/main/main.tscn` / `main.gd` + `src/world/world.tscn` + the AR-SCENE-7 project settings —
   the 3D shell everything renders into.
5. `src/world/tower_spec.gd`, `tower_builder.gd`, `tower_sdf.gd`, `surface_query.gd` — the exact
   collision surface the simulator queries thousands of times per second (W-002).

**Tests to add, in the order they become meaningful:** `test_params.gd` → `test_conv.gd` →
`test_rng.gd` → `test_tower_geometry.gd` + `test_surface_query.gd` → `test_field.gd` →
`test_physiology.gd` → `test_geometry.gd` → `test_leaf_placement.gd` → `test_time.gd` →
`test_determinism.gd`. See AR-TEST-1 for contents.

**Where a `run-ui-script` scenario replaces a unit test:** the M1 exit gate, the four canonical
angles, AS-6 silhouette, the re-seed flow, time-control UI, and dev-overlay live tuning. See
AR-TEST-2. Per `.cursor/rules/reviewing.mdc`, these are verified by reading the screenshots, not by
exit code.

**Backward-compatibility expectations:**

- `res://src/main/main.tscn` keeps its path and UID. `tools/take_screenshot.gd`,
  `tools/run_ui_script.gd`, and `project.godot`'s `run/main_scene` must continue to work unmodified,
  and `tools/ui_scripts/smoke.txt` must stay green through the 3D conversion.
- `test/test_gut_smoke.gd` stays as-is.
- The ambientCG `.tres` files under `assets/` are **not** edited; project-specific variants live in
  `src/render/materials/`.
- `leaf_atlas.json` is consumed read-only. `alpha_fill` and `tier` are already present (SD-OPEN-4
  resolved), so W-023 needs no further work.
- `IvyEnvironment.invalidate(aabb)` must exist and be correct from M2 even though nothing calls it in
  Phase 1 — it is the SD-ENV-7 seam that keeps the bake a cache rather than an architecture.
- `f_M` and `W(t)` / `W_sky(t)` exist and are pinned to 1.0. Do not delete them, do not implement
  them (INV-9).

**Explicit non-goals for the implementation stage:** see `AR-NONGOAL`. In particular, no tuning of
any parameter before M2 has produced a measurement, and no leaf-quality work before the M1 screenshot
exists.

**Open items the Programmer inherits, none of which block the start:**

- `SD-OPEN-1` and `SD-OPEN-2` are **closed** (Director, 2026-08-09). Build the diel gate as a shipped
  invariant (INV-3a) at the single `Physiology.growth_rate()` call site, keeping the disabled path
  reachable for AS-3 clause (b). Take acceptance numbers from `DESIGN.md`, never from this document.
- `SD-OPEN-3` is now W-024 and belongs to the Director. It gates M4 rubric *scoring* only, not any
  implementation work.
- `SD-OPEN-4` is satisfied — `alpha_fill` and `tier` are present in `leaf_atlas.json`. W-023 needs no
  code; close it.
- `SD-OPEN-5` (whether `LeafSet029`'s Scattering map warrants a custom leaf shader) stays deferred to
  M4. `AR-RENDER-4` ships the constant `BACKLIGHT` tint, which is the decision point: judge it from
  the ground-level silhouette screenshot, not in advance.
- `AR-AMBIG-1` … `AR-AMBIG-11` are proposals, not rulings. Implement them as written unless the
  Systems Designer or Director says otherwise, and cite the `AR-AMBIG-*` id in a comment at each site
  so a later ruling is cheap to apply.

**If you disagree with a decision here, escalate rather than deviate.** Every `AR-*` rule that
constrains behaviour rather than style traces to an `SD-*` contract or a `DESIGN.md` invariant; a
quiet deviation will surface as a failed acceptance signal weeks later, at the point where the cause
is most expensive to find. That is R-1 in miniature.

