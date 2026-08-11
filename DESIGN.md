# Ivy — Game Design Document

Last updated: 2026-08-10

---

## Concept

Ivy is a **3D game** about covering buildings in beautiful climbing plants.

You do not draw the vines. You shape the world the plant lives in — where it takes root, where the
sun falls, where the water is — and the plant decides for itself where to go. The pleasure is the
pleasure of gardening: indirect authorship, patience, and a result that is partly yours and partly
the plant's.

Underneath is a real simulator, specified in `ivy_simulator_v0.1.md`, built on the causal chain:

**environment → plant physiology → geometry**

Environmental state is mutable at runtime. Existing stems never regenerate; only future growth
responds. That single property is what separates this from a procedural mesh generator, and it is
the thing every later mechanic will be built on.

---

## Phase 1 vision

> Phase 1 delivers one thing: a small circular brick tower, standing in daylight, that a single ivy
> seed climbs and covers over simulated days — and the result is beautiful enough that we want to
> keep looking at it. The sun moves across the sky, the plant remembers where the light has been,
> and the side of the tower that gets more sun ends up visibly greener than the side that does not.
> The player's only powers are choosing where the seed goes and controlling time. There is no score,
> no objective, and no way to lose. Phase 1 exists to answer two questions and no others: *does the
> simulator work*, and *does it look good*.

Phase 1 is deliberately not gamified. Gamification is a later phase and will be easier to design
once we can see what the simulator actually produces.

---

## Target player experience

What we want someone to feel in the first two minutes:

1. **"Oh, it's actually growing."** Movement is visible without fast-forwarding to absurdity. Tips
   creep, branch, and find the wall.
2. **"It went that way because of the sun."** The player should form this belief on their own, from
   looking, before anyone explains the light model to them. Legibility of causation is the single
   most important experiential property of Phase 1.
3. **"That's pretty."** Ivy that reads as a living mat of overlapping leaves with depth and variety
   — not as a texture, a net, or a decal.
4. **"What if I put it on the other side?"** The player wants to re-run with a different choice.
   That impulse is the seed of the eventual core loop.

What we explicitly do *not* want them to feel: that they are looking at a tech demo with sliders,
that they are supposed to be optimizing something, or that the plant is doing something arbitrary.

---

## Core loop impact

The eventual core loop is:

**read the environment → change it → wait → read the result → change it again**

Phase 1 builds the right-hand half of that loop — *wait → read the result* — plus the smallest
possible left-hand half: choosing a seed anchor and controlling time.

This is the correct order. If growth is not legibly *caused* by the environment, then no amount of
later mechanic design produces a loop, because the player's changes will not appear to matter. So
Phase 1's load-bearing property is not simulation fidelity. It is **visible causation**. A less
accurate simulator whose effects you can read from a screenshot is a better Phase 1 outcome than an
accurate one whose effects you cannot.

Everything about how the player *influences* the environment — water points, awnings, cutting back
neighbouring trees, weather, seasons — is Phase 2 and later. The architecture must leave room for
it; Phase 1 must not build it.

---

## Phase 1 subject: the tower

A **small one-story circular brick tower**. Not a house, not a castle, not a keep.

| Property | Target |
|---|---|
| Height | 3–4 m |
| Radius | 1.5–2.5 m |
| Material | Rough brick (adhesion suitability `A_m = 1.00`) |
| Openings | At least one — a doorway and ideally one window or recess |
| Top | A lip, cornice, or crenellation the ivy can grow over and hang from |
| Setting | Simple ground plane and sky. No terrain, no props, no backdrop. |

**Art direction is photoreal/naturalistic.** The tower geometry is built to the spec above rather
than imported from a low-poly kit — the ivy is the hero asset, and stylized flat-shaded kit pieces
would clash with photographed leaves. Building the geometry ourselves also gives the simulator exact
collision surfaces and known material assignment, which a kit piece would not.

Surfacing uses CC0 PBR materials from ambientCG (`Bricks094` primary, `Bricks102` alternate) — see
`assets/CREDITS.md`. The openings and the top lip are not decoration; they are the test fixtures for
shading variation and for the silhouette-break acceptance signal below.

---

## Player agency in Phase 1

Two levers only:

1. **Seed anchor.** A small set of discrete anchor points around the tower base (N / E / S / W is
   sufficient). The player picks one, or moves the plant to another and re-runs. Discrete anchors,
   not free placement — it makes the north-vs-south comparison immediate and legible, which is
   exactly the belief we are trying to install in the player.
2. **Time.** Pause, play, and at least two speeds: a *watch* speed where the day/night cycle is
   readable, and a *grow* speed that reaches full coverage in a tolerable wall-clock time.

Nothing else. No pruning, no painting, no placing objects, no camera-locked cursor tools.

---

## Day/night

Called out by the project owner as really important, and it is also the engine of the whole light
model, so it is in Phase 1 rather than deferred.

Requirements:

- A continuous sun arc driven by an actual solar-position model (spec §5), not a decorative rotating
  light.
- **The light field is always driven by the instantaneous sun** at simulation-tick resolution. The
  render matches it exactly at watch speed; at faster speeds the rendered sun may blend toward the
  day's mean direction so that it does not strobe, and the UI must say so when it does. The plant's
  inputs are never blended. (Amended 2026-08-09: the original wording claimed render and field are
  always the same sun. Ratifying `SD-TIME-4` makes that untrue at high speed, and this document has
  to be accurate about which of the two is authoritative — the field is.)
- Below the horizon, direct light goes to zero and growth falls to near zero — not to exactly zero,
  which reads as a broken simulation rather than as night. Night is real. See INV-3a.
- Fixed date and latitude in Phase 1. Seasons and latitude control are later.

Weather, clouds, and rain are Phase 2. The spec's weather multipliers `W(t)` and `W_sky(t)` should
exist in the code and be pinned to 1.0.

---

## Design goals

| ID | Goal |
|---|---|
| G1 | A single seed at the tower base reliably covers the tower, unattended, at default parameters. |
| G2 | Causation is legible — a viewer can tell which side gets more sun by looking at the ivy alone. |
| G3 | The result reads as ivy, not as a decal, net, or wireframe: silhouette break, overhang, sag, overlapping leaves with real depth. |
| G4 | The day/night cycle is present, readable, and genuinely drives growth. |
| G5 | Runs are deterministic and repeatable, so visual iteration has a stable baseline to compare against. |
| G6 | Every tuning parameter — spec §30 plus every parameter added by a later stage (`SD-PARAM`) — is live-tunable in a dev build. Iteration is measured in minutes, not recompiles. |

---

## Rules the system must preserve

These are invariants, not preferences. Downstream stages may not trade them away for convenience.

- **INV-1 — One-directional causality.** Environment → physiology → geometry. Physiology writes back
  to the environment only through the crowding field. Geometry never writes back to physiology.
- **INV-2 — Existing stems are immutable.** Changing the environment must never move, delete, or
  regenerate geometry that already exists. Only future growth responds.
- **INV-3 — The plant responds to accumulated light `D_L`, never to the instantaneous sun vector.**
  Light memory `τ_L = 3` game-days.
- **INV-3a — The instantaneous sun may modulate growth magnitude, never growth direction.** Ratified
  2026-08-09 to resolve a real contradiction between this document and spec §24 (see the ratification
  log). A scalar diel gate derived from solar elevation may scale growth *rate*; it may not appear in
  any directional term. The gate must be mean-preserving over a game-day, so that total daily
  elongation — and therefore AS-1's day budget — is unchanged. INV-3's actual protection, which is
  that the plant never chases the sun's current *position*, remains fully intact.
- **INV-4 — Timestep independence.** Growth is per simulated time; branching is per metre grown.
  Changing the tick rate or the frame rate must not change the plant's statistics.
- **INV-5 — Sparse simulation.** Only active tips are simulated. Segment creation is budget-gated
  (`B ≥ h`) and decoupled from the environment update rate.
- **INV-6 — One parameter table.** All spec §30 defaults, and every tuning parameter added by any
  later stage, live in a single authoritative place and are hot-tunable in a dev build. A stage that
  introduces a parameter adds it to that table; it does not keep its own.
- **INV-7 — Determinism.** Same seed plus same environment plus same duration yields the same plant.
- **INV-8 — Real unsupported behaviour.** Vines may leave the surface, bridge, sag, reattach, and die.
  `max_float = 0.40 m` and tips that exceed it die. Do not clamp vines to the wall to avoid the problem.
- **INV-9 — Unimplemented seams must exist.** Moisture is present as `f_M` and hardwired to `1.0`.
  Weather multipliers are present and pinned to `1.0`. Do not delete them and do not implement them.
- **INV-10 — Material-driven adhesion.** Adhesion suitability `A_m` is looked up per surface material,
  not hardcoded at the call site — even though Phase 1 only ships brick.

---

## Success criteria

The owner's bar is "it looks good." That is not directly testable, so we decompose it into three
kinds of signal: automatable structural metrics, a fixed artifact blacklist, and a repeatable human
review with a stable reference set. Phase 1 closes only when all three pass.

Screenshots are always taken from the **four canonical camera angles**, fixed once and never moved:
sun-facing elevation, shade-facing elevation, 45° from above, and ground-level looking up at the
silhouette against the sky.

### Automatable signals

| ID | Signal |
|---|---|
| AS-1 | **Coverage, and it must be uneven.** From a single sun-facing seed at 150 game-days, default parameters, unattended: **≥70% of the eligible outer wall overall**, **≥90% on the sun-facing 180°**, and **≥50% on the shaded 180°**, with the top lip reached. Measured by the leaf-area bucket metric (`SD-METRIC`) on a **placement-count occupancy basis** — fixed leaf-`a` reference area (`SD-METRIC-7j`, AR-METRIC-1) per leaf attributed to its petiole bucket; SD-LEAF-5 `s_light`, variant/tier, and **card orientation excluded** (`SD-OPEN-13` amendment). A bucket is covered when accumulated `ref_area` from leaves placed there reaches ≥50% of bucket area. AS-1 certifies *structural wall occupancy by placement*, not rendered size or presentation tilt. Card-normal projection remains an optional **diagnostic** only. The two halves exist so that a uniform mediocre mat cannot pass — that is the wallpaper failure mode rubric criterion 2 is there to catch, and a single overall number does not catch it. The shaded floor exists so that "asymmetry" cannot degenerate into a bald side, which would fail G1. |
| AS-2 | **Light asymmetry, and it must arrive early.** With the seed at the sun-facing base, sun-facing-vs-shaded total stem length asymmetry reaches **≥20% by game-day 30**, **≥40% by game-day 60**, and remains **≥30% at day 150**. The same run seeded on the shaded side produces **≥20% less total stem length**. The early targets matter more than the late one: the causal belief we are trying to install either forms in the first minute or it does not form. Late compression is expected and acceptable — the sunny side saturates and its crowding penalty bites while the shaded side is still uncrowded, so the cumulative ratio narrows. |
| AS-3 | **Day/night drives growth.** In a debug readout: (a) growth rate at solar midnight is ≤15% of the daily-mean rate and ≤10% of the solar-noon rate, rising through the morning; (b) the diel gate is mean-preserving: it changes *when* growth occurs within a game-day, never the daily total budget AS-1 depends on (INV-3a). Verified in two places, neither comparing two divergent long runs: **(b.1) Unit invariant (primary).** Over the 24 simulation-tick hours of one game-day, the diel gate multiplier ĝ has arithmetic mean 1 to within 1×10⁻⁶, sampled at exactly the 24 tick-hours the simulation applies it on. Exact by construction (ĝ = g / g_ref, with g_ref the mean of g over those same 24 hours). Asserted by `test_time.gd::test_diel_gate_mean_is_unity_over_24_ticks`. **(b.2) Applied near-linear check (backstop).** With branching disabled in both runs (`SET_PARAM branch_rate 0.0`), cumulative stem elongation from game-day 0 through game-day 29 with the diel gate enabled is within **±2%** of an otherwise identical run with `diel_gate_enabled = false`, comparing `TOTAL_STEM_LENGTH` from `DUMP_METRICS` (scripts `qa_as3b_nobranch_on.txt` / `qa_as3b_nobranch_off.txt`). Branching is disabled because it is the exponential amplifier that turns sub-millimetre per-tick timing differences into an 11% cumulative gap by day 29 — a measure of trajectory divergence, not of the gate. The branching-enabled cumulative comparison ratified under W-049 is withdrawn as a test instrument: for any nonlinear growth model it exceeds any fixed tolerance at some horizon N regardless of gate correctness. Single-day deltas remain excluded (W-049). Clause (b) is the budget/mean-preservation guard only; a gate wrongly applied to a directional term is not caught here (daily elongation total unchanged) and is instead caught by (a) and the INV-3a rule that ĝ never enter a directional term; (c) accumulated light `D_L` lags a step change in instantaneous light with the expected ~3-game-day time constant. Clause (b) is the one that protects AS-1 — without it a gate that quietly halves total growth would pass (a) and (c) and fail AS-1 much later, when the cause is expensive to find. |
| AS-4 | **Determinism.** Two consecutive serial runs with identical seed, environment, and duration on the dev machine produce: **(simulation — exact, no tolerance)** identical tip counts, segment count, leaf count, total stem length, and every automatable metric field to **six decimal places** (INV-7 scope); **(canonical screenshots — tolerance)** the four PNGs from `tools/ui_scripts/qa_m25_canonical.txt` satisfy the **LG-3 image-stability half** — ≤**0.05%** of pixels with any RGB channel delta >**1/255**, **and** RGB RMSE ≤**1×10⁻⁴** — pairwise on the same script and `force_draw` capture path. **Standing rule (simulation):** AS-4 must never relax exact-match requirements on any simulation output listed above. Any tolerance on tip counts, segment/leaf counts, stem length, or dumped metrics would turn AS-4 into a Lyapunov divergence meter and inherit the class defect that invalidated the W-049 AS-3(b) instrument — this rule is unchanged and binding. **Standing rule (rasterisation):** bit-exact PNG equality is explicitly not required and must not be demanded; GPU floating-point non-determinism on alpha-cutout edges is not simulation divergence and is bounded only by the LG-3 image-stability tolerances (hardened via W-081 before M4 exit). **M4 adds no separate pixel ceiling** — presentation drift at M4 is additionally guarded by the artifact blacklist and director rubric. |
| AS-5 | **Performance.** ≥60 fps on the dev machine with the tower fully covered at default parameters. A full-coverage run at grow speed completes in ≤3 minutes wall-clock. The live tip cap is documented and never exceeded. |
| AS-6 | **Silhouette break.** At full coverage, tips have grown over the top lip and sag downward, visibly breaking the tower's outline against the sky in the ground-level camera. This is the "not a texture" test. |

The specific numbers in AS-1 and AS-2 are first estimates. They may be revised once M2 provides real
measurements — but they must remain concrete numbers, recorded here, not softened into "enough" or
"noticeably more."

**AS-1's three numbers are arithmetically coupled and must only ever be revised together.** Overall
coverage is the bucket-count-weighted mean of the two halves, so the halves' floors must average to
at least the overall floor. Proposing one number in isolation produces a set that cannot be satisfied
by any plant. (The Systems Designer's original proposal of 70/85/35 had exactly this defect: 85% and
35% average to 60%, so no result could ever reach the 70% overall floor. Corrected to 90/50 on
ratification.) Any future revision must show the arithmetic.

**Known tension to watch:** the tip cap retires the least-vigorous tips first (`SD-TIP-4`), which by
design retires shaded tips before sunny ones and therefore actively suppresses shaded coverage. If
that mechanism drives the shaded half below AS-1's 50% floor, the correct response is to soften the
retirement margin, **not** to quietly lower the floor. The floor is what stops the cap from eating a
whole side of the tower.

### Artifact blacklist

Zero occurrences across the four canonical angles:

- Stems passing through the tower wall or growing inside it.
- Stems floating unsupported beyond `max_float` (0.40 m).
- Axis-aligned or rectilinear banding in growth direction or density that reveals the underlying
  hash-field grid. Ivy on a cylinder must not look like it is following a lattice.
- Z-fighting or coplanar leaf sheets.
- Leaves detached from stems, or leaves at wildly inconsistent scale.
- Ivy growing on the ground plane or floating in mid-air.
- Visible repetition — the same leaf cluster recognizably instanced in a regular pattern.

### Director visual review

A fixed six-criterion rubric, scored on the four canonical screenshots at every iteration
checkpoint. **Phase 1 closes at 5 of 6 or better.** Scoring is against a committed reference set
(below), so that the judgment stays stable across iterations and across people.

1. **Reads as ivy at a glance.** An unprompted viewer says "ivy," not "netting," "seaweed," "wire,"
   or "a texture."
2. **Density varies.** There are thick mats and sparse skirmishers. It is not uniform wallpaper.
3. **It conforms to the building.** Stems visibly follow the curve of the wall and travel around or
   into openings and recesses rather than cutting across them.
4. **Leaves have depth.** Orientations vary, leaves overlap and self-shadow, the mat has thickness.
5. **The growth front reads as a front.** Leading tips are thinner, more exploratory, and more
   irregular than the settled interior.
6. **Nothing reads as a grid, a spline, or a repeat.**

### The reference set

Three photographs of real ivy on brick, committed to `assets/reference/ivy/`. They did not exist when
the rubric was first written, which left it with nothing to score against; specifying them is
therefore part of the rubric, not an errand attached to it.

They are chosen to exercise the rubric rather than to be attractive:

| Slot | Content | Rubric criteria it anchors |
|---|---|---|
| 1 | Mid-range elevation of an established ivy mat on brick, showing a thick interior **and** a sparse leading edge in the same frame. Curved or round masonry preferred, since the subject is a cylinder. | 2 (density varies), 3 (conforms to the building) |
| 2 | Close-range detail of the leaf mat — leaves at varied angles, overlapping in depth, self-shadowing, with visible specular highlight. | 4 (leaves have depth), 6 (no repeat) |
| 3 | Backlit or low-angle shot with ivy breaking a roofline or wall edge against open sky. | 1 (reads as ivy), 5 (growth front), and AS-6 |

**Licensing: Public Domain or CC0 only.** The project's committed assets are strictly CC0 and
reference images are no exception, because committing them to the repository is distribution
regardless of the fact that they never ship in a build. Wikimedia Commons is the expected source; it
carries genuinely public-domain and CC0 material. **Unsplash and Pexels are not acceptable** — their
licenses are permissive but are their own, not CC0. CC-BY and CC-BY-SA are also excluded, so that the
rule stays a single bright line rather than a judgment call at each commit.

Each image is recorded in `assets/CREDITS.md` with source URL, author, license, and retrieval date,
matching the existing convention.

**If no acceptable Public Domain or CC0 image can be found for a slot, the fallback is to replace
that slot with a written descriptive criterion in the rubric — never to relax the license.** Stated
explicitly so that the licensing rule cannot lapse quietly under deadline pressure at M4.

Owner: Game Director. Tracked as **W-024**. Gates **M4 rubric scoring only** — not M2.5. See the
W-024 unblocking plan in `work-items/WORK_ITEMS.md`.

**Unblocking plan (Director, 2026-08-10).** The owner commits three files to
`assets/reference/ivy/` (`slot1_mat_edge.jpg`, `slot2_leaf_detail.jpg`, `slot3_silhouette.jpg`) and
records each in `assets/CREDITS.md`. Wikimedia Commons is the source; search terms and slot
requirements are specified in W-024. M2.5's legibility gate (LG-1/LG-2′) does **not** depend on these
photographs — they exist so M4 rubric scoring has a stable comparative baseline, not so causation
becomes visible.

---

## Milestones and sequencing

The sequencing below is a director-level instruction, not a suggestion. It exists to defend against
the project's largest risk.

| Milestone | Content | Exit condition |
|---|---|---|
| **M1 — Ugly end-to-end** | Tower scene, constant-light stub environment, minimal physiology, growth geometry, crude stem mesh, crude leaves. | Recognizably ivy-shaped growth is on the tower and visible in a screenshot. Ugly is fine. |
| **M2 — Environment live** | Solar position, day/night, sparse hash light field, accumulated light, sky-view factor, crowding, branching, tip lifecycle. | AS-2 and AS-3 pass. **DONE.** |
| **M2.5 — Visible causation** | Environment presentation (sky, tower surfacing, four canonical cameras) plus the minimum leaf rules that make sun/shade asymmetry readable on the plant. | LG-1, LG-2′, LG-3, and LG-4 pass (below). AS-1 and AS-2 re-verified as automatable causation backstops. **DONE.** |
| **M3 — Agency and tuning** | Seed anchors, time controls, dev overlay with all §30 parameters live and field visualization. | A parameter change can be seen on screen without a restart. **Unblocked (M2.5 done).** |
| **M4 — Looks good** | Remaining leaf and stem polish, full SD-LEAF/SD-STEM, iteration against the rubric. | Artifact blacklist clean, rubric ≥5/6 (requires W-024), AS-1/4/5/6 pass. |

**No parameter tuning, no field-precision work, and no leaf-art polish happens before M1 is on
screen.** The goal of M1 is to discover what is actually hard, as early and as cheaply as possible.

### Why M2.5 precedes M3

M2 closes the simulation question. Phase 1's load-bearing property is **visible causation** (G2), and
that question is still open: the measured day-150 split (96.23% sun / 50.62% shade coverage; stem
length 973.6 m vs 311.4 m) is real but was invisible in every canonical screenshot until the debug
camera arrived, because `CamSun` never showed the shaded half and the presentation layer — flat
white leaves on an untextured tower under a null sky — does not surface what the simulator already
knows.

M3's core offer is choosing where to plant. That choice is meaningless until a viewer can *see* that
one side of the tower differs from the other. Shipping seed anchors and a dev overlay first would
produce a playable thing whose central belief — "it went that way because of the sun" — still cannot
form from looking. That inverts Phase 1's stated build order: the right-hand loop half (*wait → read
the result*) must become readable before the left-hand half (*change it*) earns its keep.

The counter-argument — agency sooner, polish is endless — is real but secondary here. M3's time
controls and field overlay also help iteration, and a thin M3 slice (pause/play/speed only, deferring
W-013's full overlay) could run parallel to M2.5 leaf work without blocking it. **Seed anchors (W-012)
and rubric-scored polish stay gated on M2.5**, because re-seeding is the impulse we are trying to
install and it requires visible asymmetry first.

### M2.5 exit gate — visible causation

M2.5 closes when an unprompted viewer can tell which side gets more sun by looking at the ivy, and
when the environment itself is present enough to read day/night. This gate is deliberately narrower
than M4: no rubric score, no performance budget, no reference photographs.

**Prerequisites (already met at M2, re-verified if M2.5 leaf work changes presentation):**

- **AS-1** — coverage asymmetry (≥70% / ≥90% / ≥50%) on the **placement-count occupancy basis**
  (`SD-OPEN-13` amendment). Restated here as the automatable backstop for *structural* sun/shade
  causation (density and baldness); the canonical run reads **75.17% overall / 96.23% sun-facing /
  51.86% shaded** (count basis; card-normal diagnostic 50.09% shaded).
- **AS-2** — light asymmetry in stem length reaches ≥20% by day 30 and ≥40% by day 60 on the default
  south seed (51.31% at day 150 on the canonical run). Restated here because LG-1 is about *reading*
  asymmetry the metrics already prove.
- **AS-3(a)** — growth rate at solar midnight ≤15% of daily mean. M2.5 adds the requirement that
  day/night is *visible* (sky and sun energy), not only simulated.

**Automatable signals (new — must be able to fail):**

| ID | Signal |
|---|---|
| LG-2′ | **SD-LEAF-6/7 regression guard** (replaces withdrawn LG-2a/LG-2b hemisphere deltas — see SD-OPEN-10). Two layers, both must pass: **(a) Deterministic mechanism assertions** — SD-LEAF-7: instance `Color.g` span **0.18**, monotone in `f_L`, endpoints at `f_L = 0` and `f_L = 1`; reverting tint to `Color.WHITE` → span 0. SD-LEAF-6: healthy-tier fraction tracks **`0.25 + 0.65·f_L`**; fixing the tier → flat fraction. Unit-level, survivorship-immune. **(b) Whole-plant integration backstop** — on the canonical day-150 south-seed run, over eligible sampled leaves area-weighted by rendered `leaf_area` (SD-METRIC-7c), ranked by plumbed experienced light (`f_L`): top-decile vs bottom-decile separation must exceed **≥0.013** mean `Color.g` delta **and** **≥0.05** healthy-tier area-fraction delta (SD-OPEN-14; measured 0.02239 / 0.0895; ~1.7× headroom; **provisional** on one probe). ±60° sector splits are diagnostic only. Both layers collapse to zero if the corresponding rule is removed or unwired. Contract: `IMPLEMENTATION.md` SD-METRIC-7h. |
| LG-3 | **Four canonical cameras exist, are fixed, and give a reproducible visual baseline.** All four transforms authored in `main.tscn`, each pinned to **local noon** (game-hour 12) when captured. `tools/ui_scripts/qa_m25_canonical.txt` captures all four without moving any camera at runtime. **Simulation determinism (exact, INV-7 scope):** two consecutive serial runs of that script on the dev machine with default seed and parameters produce identical segment count, leaf count, total stem length, and every `DUMP_LEAF_COLOUR` / `DUMP_METRICS` field to **six decimal places** — this half is not relaxed. **Image stability (tolerance):** comparing run A to run B, each of the four PNGs (`m25_cam_sun.png`, `m25_cam_shade.png`, `m25_cam_top.png`, `m25_cam_silhouette.png`) must satisfy **both**: (i) at most **0.05%** of pixels differ in any RGB channel by more than **1/255**; **and** (ii) RGB RMSE ≤ **1×10⁻⁴**. Bit-exact PNG equality is explicitly **not** required (shared with AS-4 image-stability half — SD-OPEN-12). Thresholds are **provisional** until W-081 hardening. Closes the W-002 remainder. |
| LG-4 | **Sky and tower surfacing present.** `WorldEnvironment.environment` is non-null (procedural sky live — AR-SCENE-2). Tower wall shows repeating brick detail at ≥1 texel/cm equivalent (AR-TOWER-1 / W-046). Verified by human on the sun-facing elevation screenshot; fails if the wall is still a smooth gradient. |

**Human signal (must be able to fail):**

| ID | Signal |
|---|---|
| LG-1 | **Unprompted causation read.** Show a reviewer the sun-facing and shade-facing canonical elevation pair (day 150, south seed, noon) with **no simulation numbers, no field overlay, no explanation of the light model**. Pass only if the reviewer (a) correctly identifies the sun-facing side, **and** (b) cites at least one **plant-side** visible difference (greener/denser/healthier vs paler/sparser/weaker — not sky colour or brick alone). Fail if sides look the same, if identification is wrong, or if the difference is attributed only to exposed wall area. QA records pass/fail and reviewer quotes in the work item. |

**How the gates divide labour.** Whole-side causation — *"this side of the tower got more sun"* — is
guarded by **AS-1 + AS-2** (automatable, structural) and **LG-1** (human, reads the screenshot).
Per-leaf appearance causation — *"a leaf grown in more light is greener and more often healthy"* — is
guarded by **LG-2′**. LG-1 without LG-2′ repeats the W-053 trap for SD-LEAF-6/7 (subjective-only
regression guard). LG-2′ without LG-1 passes mechanism checks while failing to install the player
belief. All four LG signals are required. The withdrawn hemisphere-delta LG-2a/LG-2b gates asserted a
*whole-side greenness* claim that survivorship makes dishonest at the 180° average; the sun side reads
different because it is **balder**, which is AS-1's job, not a tint delta.

**Explicit non-goals for M2.5** (defer to M4 unless needed to pass LG-1):

- SD-LEAF-1 cup geometry (9-vertex card) — depth/pretty, not causation
- SD-LEAF-5 full size model (`s_order`, `s_age`, `s_var`) — rubric 2 and 5, not G2
- SD-LEAF-4 full jitter/droop stack — anti-repeat and depth
- SD-LEAF-3 phyllotaxy flattening beyond what M1 already ships
- SD-STEM taper and Catmull-Rom smoothing
- `LeavesStatic` MultiMesh split (AR-RENDER-3) — performance path, AS-5
- Placement-efficiency / crowding-gradient steering (W-015 deferred scope)
- Director rubric scoring and W-024 reference photographs
- AS-1, AS-4, AS-5, AS-6 (remain M4 gates)

**Required leaf rules for M2.5** (see W-060): SD-LEAF-6 (atlas health tiers), SD-LEAF-7 (sun/shade
tint), SD-LEAF-5 **`s_light` factor only**, SD-LEAF-4 **rule 5 phototropic cant only**. SD-LEAF-8
already landed at M2.

### M4 exit gate — looks good (unchanged scope, clarified boundary)

M4 begins after M2.5 and M3. It adds polish and the full acceptance suite:

- **Artifact blacklist** — zero occurrences across the four canonical angles
- **Director visual rubric** — ≥5 of 6 criteria on the four canonical screenshots, scored against
  the W-024 reference set (M4 may not be rubric-scored before W-024 lands)
- **AS-1** — coverage floors (≥70% / ≥90% / ≥50%) — already passing by volume; re-verify after M4
  leaf polish
- **AS-4** — exact simulation determinism plus LG-3 image-stability tolerances on canonical screenshots (SD-OPEN-12)
- **AS-5** — ≥60 fps at full coverage; 150-day grow run ≤3 min wall-clock; tip cap never exceeded
- **AS-6** — silhouette break at ground-level camera

AS-2 and AS-3 remain M2 properties; M4 does not re-open them unless a change regresses them. AS-5 is
explicitly **not** an M2.5 requirement — legibility precedes performance optimization.

---

## Non-goals for Phase 1

Explicitly out of scope. Building any of these is scope creep and should be pushed back to the
Game Director.

**Simulation:** moisture and water points (`f_M` pinned to 1.0) · weather, clouds, rain · seasons ·
latitude/longitude control · artificial light sources · runtime geometry changes such as awnings or
destruction · multiple plant species · plant ageing or juvenile/adult leaf morphs.

**Content:** houses, castles, multi-storey buildings, interiors · any second building · flowers,
berries, autumn colour · terrain, backdrops, rolling hills, forests, cliffs · wind or any vine
animation beyond growth itself.

**Game:** objectives, scoring, currency, progression, unlocks, win or fail states · save/load of a
grown plant · tutorial or onboarding · audio · menus beyond what time controls require.

**Interaction:** free-placement seeding · pruning, cutting, or training vines · directly drawing or
painting growth · placing objects in the world · any tool that lets the player author vine position
directly. Agency comes from the environment, always.

**Technical:** platforms other than desktop · LOD, GPU instancing, or multithreading beyond whatever
AS-5 requires · networked or persistent simulation.

---

## Risks to watch

**R-1 — The simulation black hole (highest).** The single largest threat to this project is that it
becomes a beautiful piece of simulation engineering with no game in it and nothing on screen. The
spec is 35 sections of appealing mathematics and every one of them can absorb a week. Mitigations:
the M1 vertical slice before any subsystem is made accurate; the parameter table (INV-6) so that
"getting it right" is a tuning activity rather than a coding activity; and holding to the position
that visible causation beats fidelity.

**R-2 — Leaves are what "looks good," and the spec does not mention them.**
`ivy_simulator_v0.1.md` is entirely about stems. It says nothing about leaf placement, size,
orientation, phyllotaxy, colour variation, or translucency — and those are almost certainly what
determines whether the result is beautiful. A perfect stem simulation with bad leaves fails Phase 1.
Leaf presentation is a first-class Phase 1 deliverable with its own work item, not a garnish applied
at the end.

**R-3 — Grid artifacts from the world-space hash field.** A voxel or sparse-hash field can produce
axis-aligned banding in the light and crowding gradients. On a curved brick tower this reads
immediately as unnatural rectilinear growth. Explicitly on the artifact blacklist; needs deliberate
mitigation (jittered sampling, interpolation, or field resolution relative to segment length).

**R-4 — Curvature and faceting.** A cylindrical wall means adhesion and surface-tangent gradients
operate on continuous curvature, and a vine growing "horizontally" needs near-constant collision
correction. Watch for stair-stepping or faceting at 3 cm segments on a ~2 m radius.

**R-5 — Timescale collision between day/night and growth.** At 0.12 m/game-day, a lead tip needs
~30 game-days to reach the top. A day/night cycle slow enough to enjoy makes coverage take half an
hour; a cycle fast enough for coverage makes the sun strobe and collapses the 3-day light memory to
seconds. These two desires are in direct conflict and it is not a minor tuning matter. See D-1.

**R-6 — Tip-count explosion.** At `λ₀ = 1.7/m`, branching compounds. Full coverage of the tower could
mean hundreds of live tips and thousands of segments. A cap is needed, and the behaviour at the cap
is a design decision, not an engineering detail — it determines what a mature plant looks like.

---

## Open decisions for the Systems Designer

All five were resolved by the Systems Designer on 2026-08-08. Resolutions live in `IMPLEMENTATION.md`;
this table is the index.

| ID | Decision | Status |
|---|---|---|
| D-1 | How the day/night cycle and growth timescale coexist (see R-5). Both a watch speed and a grow speed must exist. Whichever way, INV-3 and INV-4 must survive it. | Resolved — `SD-TIME`. Fixed 1-game-hour simulation tick at every speed; speed changes only how many ticks run per real second; the rendered sun blends to daily-average at high speed while the light field never blends. |
| D-2 | How wall coverage percentage is actually measured, for AS-1. It must be automatable and stable across runs. | Resolved — `SD-METRIC`. Leaf-area occupancy over 2,520 fixed buckets in tower-cylindrical coordinates, independent of the simulation's own hash field. Correctly rejects measuring from the crowding field, which the plant writes to and tuning could game. |
| D-3 | The live tip cap value, and the behaviour at the cap (see R-6). | Resolved — `SD-TIP`. Soft 96 / hard 160, tapered branch probability between them, vigour-based retirement at the hard cap, with floating tips and the top-of-tower tips protected. |
| D-4 | Whether the four seed anchors are authored or derived from geometry at runtime. | Resolved — `SD-AGENCY`. Derived by raycast at load and cached, so they cannot desync from a re-modelled or re-scaled tower. |
| D-5 | Which artifact-blacklist items are automatable versus screenshot-only. | Resolved — `SD-METRIC`. Four automatable, two auto-screened with human confirmation, one (visible repetition) human-only with preventative guards instead. |

---

## Ratification log

Decisions taken by the Game Director on escalated items. Recorded here because `DESIGN.md` is the
authoritative home for vision, invariants, and acceptance numbers.

**2026-08-09 — SD-OPEN-1, the diel growth gate: ratified.** The contradiction was real and the
Designer was right to escalate rather than pick a side. Spec §24 drives growth from *accumulated*
light, which barely moves overnight at `τ_L = 3` days, so as specified the plant grows at nearly full
rate all night and AS-3 could not pass. Ratified as **INV-3a**, for three reasons: growth that
visibly pulses with the sun teaches the player that sun causes growth within the first minute, which
is the load-bearing property of Phase 1; the gate is mean-preserving, so nothing downstream needs
recalibrating; and it touches magnitude only, so what INV-3 actually protects against — the plant
swinging toward the sun's current position — cannot occur. AS-3 reworded to test what is now
observable, including an explicit mean-preservation clause.

*Recorded trade:* in many real plants stem elongation peaks at night, not at noon, so a noon-peaked
gate is botanically backwards. Accepted knowingly under the standing ruling that a readable effect
beats an accurate one, and recorded here rather than left to be rediscovered as a bug. This is the
second such trade after `SD-LEAF-5`'s sun/shade leaf sizing; two is fine, but a growing list of them
is a signal that the simulation is drifting from its own premise, and it should be reviewed at the
end of Phase 1.

**2026-08-09 — SD-OPEN-2, AS-1′ and AS-2′: ratified with a corrected AS-1.** The Designer's diagnosis
was right — a single overall coverage number can be satisfied by uniform mediocre coverage, which is
the exact failure mode rubric criterion 2 exists to catch, so splitting it is a genuine improvement.
The proposed floors of 70% overall / 85% sun / 35% shaded are however inconsistent as a test: 85 and
35 average to 60, so a plant could clear both half floors and still fail the 70% overall floor, and
the three checks would contradict each other rather than reinforce. (A plant at 90/50 would have
passed all three, so the set was not unsatisfiable — it was simply not self-consistent, which is
worse in an acceptance suite because it fails unpredictably.) Corrected to **70 / 90 / 50**, where
the half floors average exactly to the overall floor, keeping the committed 70% headline unmoved
since no measurement yet exists that would justify moving it. Added the rule that the three numbers are coupled and may only be
revised together, and flagged the tension with the tip cap's vigour-based retirement. AS-2′'s
legibility-latency targets ratified as proposed, with a day-150 figure relaxed to ≥30% because
crowding saturation on the sunny side is expected to compress the cumulative ratio late — requiring
≥40% at day 150 would have set a trap.

**2026-08-09 — SD-OPEN-3, reference photographs: specified.** The rubric had nothing to score
against. Three-slot set defined above, chosen to exercise specific rubric criteria rather than to look
good, restricted to Public Domain or CC0 from Wikimedia Commons, with an explicit no-license-relaxation
fallback. Director-owned, tracked as W-024, gates M4 exit only.

**2026-08-09 — SD-OPEN-6, AR-BUDGET vs the 50% shaded floor: split ruling.** The Systems Designer's
escalation was correct — the original 20–35 m² / 360–600 m / 12–20k-segment lines were back-derived
from the assumption that ~27 m² *reasonably distributed* meets 70/90/50, and the measured plant is far
more uneven: the shaded 180° is sparse and volume-limited, needs ≈60 m² of leaf area merely to reach
53.99%, and every uniform volume brake (`branch_rate`, caps, stall rule, `leaf_crowd_k`) cuts that
half first because the SD-TIP-3 taper is a homeostat. **AS-1's 70/90/50 floors are unchanged** — the
budget was wrong for this distribution, not the plant for the budget.

Two concerns, two timelines:

1. **Volume envelope (architectural sanity) — re-derived now (option a).** The binding constraints
   are AS-1 (floors), AS-5 (performance), and the rubric — not the old envelope. New sanity targets
   live in `IMPLEMENTATION.md` § AR-BUDGET, bracketing the measured day-150 pass state (40,952
   segments / 1,202 m / ≈60 m² leaf area / 962 tips ever created). The old ">25,000 segments = crowding
   not suppressing growth" diagnostic is withdrawn — crowding is hard-clamped to [0, 1] and cannot
   deepen suppression where the plant is already saturated (W-050). Red flags now target runaway
   turnover and redundant sunny-side layering, not segment count alone.

2. **Placement efficiency (rubric criterion 2) — deferred to M4 (option b, tracked).** Meeting the
   shaded floor with less total volume requires better placement, not more brakes — crowding-gradient
   steering, leaf-quality work, and related M4 iteration under **W-015** and **W-030**. That is the
   correct long-term fix for the wallpaper symptom; it is not an M2 task.

**M2 gate:** AS-1 passing by volume does **not** block M2 — AS-1 is an M4 signal. The envelope
conflict no longer blocks M2 after this re-derivation. **The green mat does block M2 close:** the
pending density-gated leaf levers (`leaf_crowd_suppress` 0.55→0.70, `leaf_crowd_floor` 0.35→0.30,
SD-LEAF-8) must land via the Gameplay Fixer and be verified before M2 is declared done — not because
rubric-2 is an M2 metric, but because leaf-density feedback is part of "environment live" and the
uniform wallpaper state means that feedback is not yet doing its job on the sunny mat. Full rubric-2
scoring remains M4.

**Lowering AS-1's floors was not considered** — the analysis does not argue for it and the floors
exist precisely to catch the failure mode we are seeing.

**2026-08-09 — W-049, AS-3(b) instrument: ratified (superseded by SD-OPEN-7 below).** The Systems
Designer's evidence is accepted. The diel gate is mean-preserving: cumulative stem length differs by
0.028% at day 1, 0.052% at day 3, and 2.84% at day 29 between gated and ungated runs from an
identical starting state. The single-day day 29→30 delta of 9.05% fails only because the two runs are
different plants by then and discrete per-metre events make any one day's delta noisy (−9.98% to
+6.75% over consecutive days). AS-3(b) was reworded to test branched cumulative elongation; that
instrument failed again immediately (W-052) — see SD-OPEN-7.

**2026-08-09 — SD-OPEN-7 / W-052, AS-3(b) instrument (second restatement): ratified.** W-049 removed
discretisation noise but not the deeper confound: gated and gate-disabled runs are the same plant only
at tick 0, and branching amplifies any timing difference exponentially. The ratified branched
cumulative comparison therefore measured Lyapunov divergence, not the gate — evidenced by the day-29
gap (0.39% with `branch_rate = 0` vs 11% with branching enabled), and by the gap reversing sign
(gated ahead at W-049, gated behind after unrelated leaf-crowding changes), which a mean-preserving
multiplier cannot do. **AS-3(b) reworded** per `IMPLEMENTATION.md` § SD-TIME-8f: primary unit
invariant `mean(ĝ) = 1` over 24 tick-hours to 1×10⁻⁶; near-linear applied backstop at ±2% with
branching disabled at game-day 29. W-049 branched comparison withdrawn. Do not tune the gate to
satisfy either superseded instrument.

*Division of labour accepted:* AS-3(b) guards the daily growth budget only. A gate applied to a
directional term instead of magnitude (an INV-3a violation) is not caught by AS-3(b) and cannot be —
with magnitude un-gated the daily elongation total is unchanged. It is caught by AS-3(a) (night growth
rate would not fall to ≤15% of daily mean / ≤10% of noon) and by the INV-3a rule that ĝ never enter a
directional term. The aspirational "gate value never reaches any directional term" unit assertion listed
in `IMPLEMENTATION.md`'s test surface is **not implemented** — tracked as **W-053**, adequate for M2
via AS-3(a) plus code review of the single call site, but must land before M3 tuning work.

*Unit-test tolerance:* `test_diel_gate_mean_is_unity_over_24_ticks` must tighten from ±0.02 to
1×10⁻⁶ — **Gameplay Fixer, W-053**. The current ±0.02 would pass a gate 1.9% off
mean-preservation, which is precisely the silent budget drift AS-3(b) exists to catch.

*Acceptance-signal audit accepted:* AS-4 is immune only while it demands bit-identity (guardrail
written into AS-4 above); AS-5 is immune (single-run thresholds); AS-2's sun-seed-vs-shade-seed clause
is a low-severity watch near the 20% inequality margin — no action now. **General lesson recorded:**
any criterion requiring two runs differing in some input to stay within a tight tolerance is measuring
Lyapunov divergence as much as the property under test, and is unsatisfiable at large horizon for any
nonlinear growth model.

*Risk to watch:* a budget leak that manifests only at multi-tip saturation is unmeasurable by any clean
two-run comparison and is backstopped by AS-1 itself — acceptable trade for M2.

**M2 gate: DONE.** AS-2 passes all three checkpoints; AS-3(a)/(b)/(c) pass under ratified
instruments (QA evidence: (a) midnight/noon 5.52%, midnight/mean 11.40%; (b) unit mean = 1, near-linear
backstop 0.39% at day 29; (c) `tau_L_implied = 3.0000`); determinism reproduces digit-for-digit;
stall rule and AS-6 silhouette verified. Leaves reading as fine speckling rather than overlapping
foliage is **M4 placement/art work** (W-015, W-030, W-046) — agree with QA milestone attribution; not
an M2 blocker. Shaded AS-1 margin (+0.62 pts above the 50% floor) remains an M4 tension to watch.

**2026-08-10 — SD-OPEN-8, M2.5 sequencing and legibility gate: ratified.** M2 closes the simulation
question; Phase 1's legibility question remains open because the presentation layer does not surface
what the simulator already proves. **M2.5 — Visible causation** inserted between M2 and M3; M3 seed
anchors blocked until LG-1/LG-2 pass. Rationale: visible causation is the load-bearing property
(G2); choosing a seed anchor is meaningless until sun/shade asymmetry is readable on the plant.
Counter-argument (agency sooner) accepted for time controls only — W-012 and rubric-scored polish
stay gated. M2.5 exit: LG-1 (human unprompted causation read), LG-2′ (SD-LEAF-6/7 regression
guard — see SD-OPEN-10), LG-3 (four canonical cameras), LG-4 (sky + brick UV); AS-1 and AS-2
re-verified as automatable causation backstops. Required leaf rules: SD-LEAF-6, SD-LEAF-7, SD-LEAF-5 `s_light` only, SD-LEAF-4
phototropic cant only. Deferred to M4: SD-LEAF-1 cup, SD-LEAF-5 full model, SD-LEAF-4 jitter/droop,
SD-STEM polish, AR-RENDER-3 static/growing split. **Disagreement with owner framing recorded:**
SD-LEAF-6 is not merely "variety/pretty" — `IMPLEMENTATION.md` specifies it as the primary
causation signal (healthy tier probability scales with `f_L`). SD-LEAF-5's `s_light` is secondary
(±10%; "dominant legibility signal is density and count, not size"). W-024 gates M4 rubric only, not
M2.5; unblocking plan in W-024 row. Tracked: W-059 (sky), W-060 (legibility leaf minimum), W-061
(LG-2 metric + canonical script).

**2026-08-10 — SD-OPEN-9 / W-063, LG-2 threshold miscalibration: ratified.** The Systems Designer's
arithmetic is accepted in full. On a day-150 south-seed run the shaded *hemisphere* reaches
`D_L ≈ 4.3 → f_L ≈ 0.736`, not the ≈0.57 that earlier SD-LEAF prose assumed (that figure is correct
for the *north wall* / deep-shade point in SD-ENV-10, `D_L ≈ 2.5`, but not for the south-seed
shaded half). With SD-LEAF-7 `Color.g = 0.86 + 0.18·f_L`, the honest sun−shade tint separation is
**≈0.041–0.047**, below the SD-OPEN-8 figure of ≥0.06 — a gate a correct build *fails*, the inverse of
the W-053/W-058 could-not-fail trap. **≥0.06 withdrawn.** LG-2 split into two required automatable
checks:

- **LG-2a (SD-LEAF-7 tint):** area-weighted mean instance `Color.g`, sun-facing 180° minus shaded
  180° **≥0.03** provisional; one-time calibration locks to `0.6 ×` measured Δg, floor 0.02. If
  measured Δg < 0.035, widen tint gain within the two-species bound — do not lower the threshold toward
  noise.
- **LG-2b (SD-LEAF-6 tier):** sun−shade healthy-tier area-fraction delta **≥0.08** provisional;
  one-time calibration locks to `0.6 ×` measured Δ, floor 0.05. Modelled Δ ≈0.15 (≈1.9× margin).

**Widening the tint rejected.** Clearing 0.06 honestly would need a green spread ≈0.4 against the
current 0.18 — the plant would read as two species, violating the SD-LEAF-7 constraint and G2
("one plant in two light conditions"). The fix is the gate number, not the model.

**On calibration vs circularity:** adjusting acceptance thresholds to match measured honest physics
is not the W-048 trap (retuning simulation parameters to satisfy an arbitrary bar). The gate remains
meaningful because removing SD-LEAF-7 or SD-LEAF-6 drives both metrics to zero, and the 0.6× rule
preserves headroom below the measured signal. Calibration converts model-derived provisional numbers
into empirical anchors; it does not make the check tautological.

**Stale `f_L` audit:** no other ratified acceptance number in this document depended on the wrong
hemisphere assumption. SD-ENV-10 north-wall `f_L ≈ 0.57` stands. SD-LEAF-2 internode and SD-LEAF-5
`s_light` examples citing `f_L = 0.57` are deep-shade illustrations, not south-seed hemisphere means
— corrected in `IMPLEMENTATION.md` SD-LEAF-f_L; no parameter default changes required. W-063
closed; W-061 unblocked.

**2026-08-11 — SD-OPEN-10, LG-2 hemisphere-delta withdrawal and LG-2′: ratified.** The Systems
Designer's survivorship diagnosis is accepted in full. Canonical day-150.25 south-seed run measured
`LG-2a Δg = 0.00834` (threshold 0.03) and `LG-2b Δ = 0.0423` (threshold 0.08), both FAIL — not
because SD-LEAF-6/7 are wrong but because the metric averaged over the leaves that *survived*, and
survivorship concentrates shade-hemisphere leaf area in the lit cells (`f̄_L ≈ 0.95`, not the surface
0.736 SD-OPEN-9 assumed). Tint inversion reproduces the measured Δg to five figures (predicted
0.00835). Recalibration cannot rescue: `0.6 ×` measured lands under both floors. **LG-2a ≥ 0.03 and
LG-2b ≥ 0.08 withdrawn.** The honest per-leaf claim — *a leaf grown in more light is greener and more
often healthy* — stands; the dishonest whole-side claim — *the sun hemisphere looks greener* — does
not, because the shade side reads different primarily because it is **balder** (AS-1: 96.15% vs
50.27%; AS-2: 51.31% stem asymmetry; LG-1 reads this comfortably).

**Ratified replacements:**

- **LG-2′** — two-layer SD-LEAF-6/7 regression guard (SD-METRIC-7h): (a) deterministic mechanism
  assertions at unit level (tint span 0.18 monotone; tier fraction `0.25 + 0.65·f_L`; both collapse
  to zero on rule removal); (b) whole-plant top-vs-bottom-decile-by-light integration backstop,
  threshold **pending one serial measurement (W-073)** — do not guess.
- **Causation backstop naming** — whole-side causation: **AS-1 + AS-2** (automatable, structural) +
  **LG-1** (human). Per-leaf appearance: **LG-2′**. Tint widening stays rejected (two-species /
  G2). No leaf parameter changes.
- **AS-1 metric basis** — `CoverageMetric` divides SD-LEAF-5 `s_light` out of leaf area
  (`SD-METRIC-7j`); floor values (70/90/50) unchanged. Pre-W-060 shaded read 50.62% on the
  placement-only basis; after decoupling the structural margin returns to **≈+0.6 pt above the 50%
  floor** — remains an **M4 tension to watch**, separate from the presentation coupling that briefly
  cut margin to +0.27 pt.
- **M2.5 exit** — still LG-1 through LG-4 with LG-2 replaced by LG-2′; AS-1 and AS-2 re-verified.

**Rejected alternatives (Systems Designer reasoning accepted):** ±60° sector narrowing (does not
remove survivorship dilution; reintroduces a banned second angular convention); full retirement of
automatable SD-LEAF-6/7 guard (LG-1-only trap); surface-area weighting in the colour metric (folds
coverage into tint, breaking remove-the-rule → zero semantics).

**Process guardrail (ratified):** any new acceptance threshold derived analytically from a model must
be **measured once on a throwaway serial probe run before ratification**, not locked from arithmetic
alone. AS-3(b) (W-049) and LG-2 (SD-OPEN-9/10) both failed this way. Overhead is one serial run per
candidate threshold — cheap against a second withdrawal.

*Risk to watch:* LG-2′ decile threshold (W-077) must be set with the same probe discipline; a guessed
number would repeat the error.

*Acceptance signals for QA:* LG-2′ layer (a) passes in unit suite; layer (b) passes after W-077
threshold locked; AS-1 on placement-only basis ≥ 50% shaded with ≈+0.6 pt structural margin; LG-1
reviewer identifies sun side and cites plant-side density/sparsity difference; canonical shade
elevation shows unmistakable north-wall baldness vs south-wall mat.

**Inputs used:** SD-METRIC-7g–7j and SD-OPEN-10 in `IMPLEMENTATION.md`; canonical day-150.25 serial
measurements; SD-OPEN-9 ratification (2026-08-10); shade-facing canonical screenshot review.

**Artifacts produced:** LG-2′ ratified; LG-2a/LG-2b withdrawn; AS-1 metric-basis ruling;
SD-OPEN-10 ratification log entry; M2.5 milestone row updated.

---

**2026-08-11 — LG-1: PASSED (owner sign-off).** Judged on the matched day-150 canonical pair,
`CamSun` and `CamShade` at local noon on the south-seed run, with no numbers, no field overlay and
no explanation of the light model, per the LG-1 protocol. The pair is a true mirror after W-072 —
same height, same distance, yawed 180° — so the only difference presented to the eye is the plant.
Verdict: the sun-facing side is identifiable unprompted.

This matters more than a checkbox, because LG-1 is now carrying weight it was not originally
expected to carry. The plan had two automatable colour gates (LG-2a/LG-2b) standing alongside it;
both were withdrawn the same day for measuring a survivorship-diluted signal. LG-1 plus the
structural AS-1/AS-2 pair is therefore the *whole* of the causation evidence, with LG-2′ demoted to
a per-rule regression guard rather than a causation measurement. The gate passing on the first
honest look is the strongest single piece of evidence that Phase 1's premise — growth legibly
caused by the environment — holds.

**Consequences.** M3 seed anchors (W-012) unblock: choosing where to plant is only a meaningful
decision once a player can see that one side of the tower is better than another, which was the
stated reason for the block. LG-1's pass also depends on `s_light` and the phototropic cant
remaining in the render path, so both are now protected by a shipped human gate and must not be
reverted to satisfy a metric — a live concern, since reverting the cant was proposed as a remedy
for the AS-1 shortfall the same day and would have traded confirmed visual quality for an
acceptance number.

**Owner note, deferred not dismissed (W-080).** The weathered tier reads as reddish speckle
scattered fairly evenly, closer to autumn or disease than to weathering. It did not impede the
causation read, so it does not gate M2.5, and it is deferred to the M4 visual pass. Recorded here
because the plausible causes are design-level rather than art-level: `P(healthy) = 0.25 + 0.65·f_L`
leaves even fully sunlit growth 10% weathered and gives the distribution no spatial or temporal
structure, whereas real weathering concentrates in old, shaded and stressed tissue. The deferred
`s_age` / `s_order` terms are the natural home for that, since leaf age is precisely the missing
signal.

**2026-08-11 — SD-OPEN-11, LG-3 byte-identical withdrawal and restatement: ratified.** W-073
evidence accepted in full. Two serial canonical runs produced identical simulation state (43,870
segments / 18,390 leaves / 1288.816543 m; every dumped metric equal to six decimal places) and
three of four captures byte-identical, but `m25_cam_silhouette.png` differed on **600 of
2,073,600 pixels (0.029%)**, max per-channel delta **1/255**, RMSE **4.2×10⁻⁶** — 1-LSB shading
noise on leaf alpha-cutout edges against bright sky, not a simulation determinism failure. INV-7
covers the plant reproducing itself; portable bit-exact GPU rasterisation is not a property the
engine guarantees and was never what LG-3's stated purpose — a stable canonical visual baseline for
comparing runs — actually required.

**Ratified restatement:** LG-3 splits into two conjunctive halves (see milestone table row):

1. **Simulation determinism (exact)** — segment/leaf/length counts and full metric dump match to six
   decimal places across two consecutive serial runs. Same standard as INV-7; unchanged from what
   already passed in W-073.
2. **Image stability (tolerance)** — per-PNG pairwise comparison on the four canonical captures:
   ≤**0.05%** of pixels with any RGB channel delta >**1/255**, **and** RGB RMSE ≤**1×10⁻⁴**.
   Shared with AS-4 image-stability half (SD-OPEN-12); bit-exact PNG equality is not required.

**Threshold honesty (one sample):** the only probe is the single W-073 pair on one dev-machine GPU.
That is **not** enough to claim permanent calibration across drivers or machines. It **is** enough
to set a **provisional** ceiling with deliberate headroom above the observed noise floor — not at
the measured 0.029%, which would be a tolerance chosen only because today's run happened to pass
it. Observed 0.029% → ceiling **0.05%** (~1.7× headroom, ~1,038 pixels at 1920×1080). Observed
max delta 1/255 → retain **1/255** as the per-pixel ceiling (anything larger is real shading
change, not FP noise). Observed RMSE 4.2×10⁻⁶ → ceiling **1×10⁻⁴** (~24× headroom). **Confirmation
required before hardening:** three additional serial run pairs on the dev machine (tracked as
**W-081**); if any PNG exceeds **50%** of a provisional ceiling on any metric, escalate to Director
before M2.5 exit. Cross-machine portability is explicitly out of scope.

**What the tolerance must not permit (gate still has teeth):**

- **Camera transform drift** (W-069 class) — reframes the entire tower; tens of thousands to
  hundreds of thousands of pixels shift, far above 0.05%.
- **Viewport resolution or MSAA change** — essentially all pixels differ.
- **Renderer / material / sky / tower-surfacing regression** — global or regional colour shifts
  blow RMSE past 1×10⁻⁴ even when per-pixel deltas stay at 1 LSB.
- **Missing or misplaced geometry** — a single canonical-scale leaf against sky is ~100–500 solid
  pixels with channel deltas ≫ 1/255; two–three such errors approach the 0.05% cap with large
  deltas and fail the RMSE bound.
- **Simulation-affecting presentation bugs** that the dump would catch are already covered by the
  exact half; the image half catches presentation-only failures the dump cannot see.

**Image comparison retained:** the metric dump does not observe camera aim, framing, resolution,
lighting presentation, or material wiring. LG-3's unique value is guarding the four canonical views
as a fixed comparative baseline — exactly what M4 rubric scoring and the artifact blacklist will
need. Drop the image half and LG-3 collapses to INV-7 plus a camera-existence check W-002 already
proved.

**Capture path (`caffeinate` / `force_draw`):** subsumed, not a separate blocker. W-071's
`RenderingServer.force_draw()` path is the authoritative capture mechanism — it removes OS
presentation as a variable and is what LG-3 verification must use. W-070 `caffeinate` remains
recommended so long day-150 runs do not lose the process to display sleep, but it is not part of
the gate definition. The earlier byte-identical pass under `frame_post_draw` + `caffeinate` (W-069)
neither validates nor invalidates the restated gate; an intermittent bit-exact requirement was the
defect, not the capture path change.

**Rejected alternatives:** (a) keep byte-identical and re-run until pass — teaches flakiness,
conflates GPU noise with regressions; (b) drop the image half entirely — loses camera/renderer
regression detection LG-3 exists to provide; (c) set tolerance at measured 0.029% — indistinguishable
from cherry-picking the one number that was measured.

*Risk to watch:* provisional ceilings could still be too loose for a subtle presentation regression
that moves many edge pixels by exactly 1 LSB — unlikely for structural changes, possible for a
global dithering or MSAA change. W-081 confirmation is the backstop.

*Acceptance signals for QA:* two consecutive serial runs of `qa_m25_canonical.txt` via
`force_draw` capture; simulation half exact (counts + dump to 6 dp); all four PNGs within
0.05% / 1/255 / 1×10⁻⁴; W-081 three-pair confirmation logged before treating thresholds as
non-provisional.

**Inputs used:** W-073 measurement; W-069/W-071 capture-path history; SD-OPEN-10 process
guardrail; INV-7 and AS-4 boundary.

**Artifacts produced:** LG-3 row restated in this document; SD-OPEN-11 ratification log entry.

**Next handoff: Systems Designer** — document the dual-run comparison contract in
`IMPLEMENTATION.md` (simulation exact-match rules, per-PNG tolerance algorithm, output layout for
run A vs run B). **Gameplay Programmer** — implement comparison tooling per that contract (W-082).

**2026-08-11 — SD-OPEN-12, AS-4 split and standing-rule sharpening: ratified.** Owner escalation
accepted: leaving AS-4's screenshot clause bit-identical after SD-OPEN-11 would guarantee a third
withdrawal-after-implementation-contact — this time with the failure already measured (W-073:
`m25_cam_silhouette.png`, 600 pixels / 0.029% / 1/255 / RMSE 4.2×10⁻⁶, simulation identical to
six decimal places). The Lyapunov-divergence rationale for the anti-tolerance standing rule is
**correct for simulation outputs and must stay binding there**; it does **not** transfer to GPU
rasterisation, where the simulation state is already bit-identical, noise does not amplify with run
length, and the origin is entirely outside the iterated system (driver, shader compiler, tile
scheduling, FMA choices).

**Ratified restatement:** AS-4 splits into the same two halves as LG-3 (see acceptance-signals
table row):

1. **Simulation determinism (exact)** — tip/segment/leaf counts, total stem length, and full metric
   dump to six decimal places. No tolerance. Standing rule preserved and sharpened to name exactly
   which outputs it covers.
2. **Image stability (tolerance)** — four canonical PNGs under the **LG-3 image-stability half**,
   same numbers, same instrument, same capture path. AS-4 does **not** define a separate or tighter
   pixel ceiling.

**Why AS-4 does not need bit-identical screenshots that LG-3 also lacks:** at M4, presentation
quality is guarded by the **artifact blacklist** and **director rubric** (human, reference-photograph
scored). AS-4's unique M4 role is re-verifying that polish did not break **simulation** reproducibility
or the **pairwise-stable visual baseline** LG-3 established — not demanding a property the GPU cannot
provide. A tolerance on pixels cannot mask simulation divergence because the simulation half already
asserts exact equality; the two halves are conjunctive.

**Numbers decision:** AS-4 **reuses LG-3's tolerances by reference**, not a separate table. One
instrument, one ceiling, hardened once via W-081. M4 adds blacklist + rubric for qualitative drift;
tighter pixel bounds without a fresh measurement would repeat the guardrail violation SD-OPEN-10
exists to prevent. **M4 exit requires W-081 complete** (thresholds no longer provisional) **and** a
fresh serial pair on the M4 build (W-083) reporting the same metrics — if any PNG exceeds 50% of the
hardened ceiling, escalate before AS-4 pass.

**Platform-impossibility audit (2026-08-11, post SD-OPEN-11):**

| Item | Verdict |
|---|---|
| **INV-7** | **Clean.** Simulation plant only; digit-for-digit at day 150. |
| **G5** (stable iteration baseline) | **Clean.** Satisfied by exact simulation + tolerant image stability, not bit-exact PNGs. |
| **AS-1** | **Clean** for this class. Single-run floors; W-078 is metric-basis, not platform. Floors untouched. |
| **AS-2** | **Clean.** Single-run checkpoints + cross-seed inequality; Lyapunov-adjacent clause already scoped and ratified under SD-OPEN-7. |
| **AS-3** | **Clean.** Unit invariant primary; branching-disabled backstop only; branching-enabled cumulative withdrawn (W-049 class). |
| **AS-5** | **Clean.** Single-run performance floors (fps, wall-clock); inherent run-to-run variance is expected and not claimed reproducible. |
| **AS-6** | **Clean.** Human "visibly breaking" judgment; no pixel reproducibility asserted. |
| **LG-2′** | **Clean** for this class. Survivorship class audited SD-OPEN-10; decile threshold pending W-077 measurement. |
| **LG-3 / LG-4** | **Clean** post SD-OPEN-11/12. |
| **Artifact blacklist** | **Clean.** Human zero-occurrence inspection, not byte identity. |
| **Director rubric** | **Clean.** Human ≥5/6 scoring against reference photographs. |
| **AS-4** | **Fixed** by this entry. Was the only remaining ratified bit-identical screenshot requirement. |
| **SD-TIME-3** (`IMPLEMENTATION.md`) | **Clean.** Byte-identical tip count and stem length after speed change — simulation outputs only. |

**Rejected alternatives:** (a) keep AS-4 bit-identical and discover failure at M4; (b) drop AS-4's
screenshot clause entirely — loses re-verification after M4 polish that blacklist/rubric do not
automate (camera drift, resolution change, renderer regression with identical metrics); (c) set a
tighter AS-4-only pixel ceiling without measurement.

*Risk to watch:* M4 leaf polish adds alpha-cutout edge area; noise fraction may rise on the
silhouette camera. W-083 re-probe on the M4 build is the backstop — not a separate tolerance table.

*Acceptance signals for QA:* AS-4 pass = simulation half exact + four PNGs within hardened LG-3
tolerances on a fresh M4 serial pair (W-083); W-081 logged before M4 exit.

**Inputs used:** SD-OPEN-11 / W-073; owner Lyapunov-boundary argument; SD-OPEN-10 process
guardrail.

**Artifacts produced:** AS-4 row restated; LG-3 row cross-reference corrected; M4 exit bullet
updated; SD-OPEN-12 ratification log entry.

**Next handoff: Systems Designer** — extend `IMPLEMENTATION.md` dual-run comparison contract to
name AS-4 explicitly; document that LG-3 and AS-4 share one image-stability instrument and that
W-081 hardens thresholds for both. **Gameplay Programmer** — W-082/W-083 tooling covers LG-3 and
AS-4 without duplicate comparators.

**2026-08-11 — SD-OPEN-13, AS-1 instrument: shaded margin and projection normal (W-078 + W-079):
ratified.** Two entangled instrument questions resolved in one pass so the reasoning stays
consistent. **→ Projection-normal ruling superseded by SD-OPEN-13 amendment (placement-count basis)
below; W-078 shaded-margin ruling stands.**

**W-078 — does AS-1 pass, and is a 0.09-point margin acceptable?**

On the shipped fixed leaf-`a` reference footprint with card-normal (`n_leaf`) projection, shaded
coverage is **50.09%** against the **50%** floor — technically a pass. **A 0.09-point margin is not
acceptable as a durable ratified gate.** It is seven times narrower than the +0.62 pt M2 figure that
was already flagged as an M4 tension, smaller than the effect of almost any unrelated change, and
within measurement noise of the reference-leaf choice alone (leaf `a`'s `alpha_fill/aspect` = 0.60301
vs six-variant mean 0.57256 — worth ≈the whole margin). The original M2 finding stands regardless of
arithmetic: the plant was clearing 50% partly on cosmetic leaf-size inflation; the "structural margin"
never existed at 0.62 pt once the metric is honest.

**Ruling:** AS-1 **passes for M2.5 re-verification** on the current instrument (50.09% ≥ 50%). The
**70 / 90 / 50 floors are unchanged** — no co-revision, no mechanism softening for M2.5. LG-1 already
passed; visible coverage is not in question. The knife-edge margin is an **instrument defect**, not a
simulation defect, and is resolved by W-079 below — not by lowering floors or retuning
`leaf_photo_cant` (LG-1 pin).

**W-079 — which normal does SD-METRIC-3 use for AS-1?**

Diagnostic on the canonical run (card-normal vs wall-normal projection, same plant, same
`ref_area`):

| Basis | Shaded | Sun-facing |
|---|---|---|
| `n_leaf` (canted card normal) | 50.09% | 96.15% |
| `n_wall` (petiole wall normal) | **51.86%** | 96.23% |
| Cost of cant | **−1.77 pt** | −0.08 pt |

The Architect's deferral prediction (`l_dir → 0` in shade → cant depresses sun only) is **wrong**.
Shaded buckets sit at the occupancy threshold; marginal tilts tip them out. East/west flanks in the
shaded 180° carry real light gradients and real cant. The cant enters through the stored card normal;
the code is correct — this is a design ruling on what coverage *means*.

**What AS-1 measures:** *structural wall occupancy by leaf placement* — whether the shaded
hemisphere holds enough ivy to avoid the bald-side failure mode (G1, LG-1, AS-1 shaded floor). It
does **not** measure effective perpendicular occlusion after a presentation orientation choice.

**Ruling:** SD-METRIC-3 projection for AS-1 uses **`n_wall` at the petiole anchor** (segment wall
normal), **not** the phototropic card normal `n_leaf`. Same decoupling principle as W-076: presentation
terms (`s_light`, variant/tier, **`leaf_photo_cant` tilt**) must not move a structural gate.
Phototropic cant remains in the render path unchanged (LG-1 pin). Jitter and droop stay in the render
only; AS-1 asks "is leaf material placed here?" not "how edge-on is this card?"

Card-normal coverage remains a **reported diagnostic** (`n_wall`-vs-`n_leaf` split) so cant coupling
stays visible; it does not gate.

**Restated canonical AS-1 figures (post W-079):** overall **75.17%**, sun-facing **96.23%**, shaded
**51.86%** — **+1.86 pt** above the 50% floor, restorable M4 watch margin. (This entry originally
recorded 74.28 / 96.15 / 51.86, which mixed bases: the overall and sun-facing figures were the
card-normal ones. Corrected against the measured run after the amendment below landed; the shaded
figure and therefore the ruling are unaffected.)

**Programmer spec (W-079, do not retune `leaf_photo_cant`):** In `CoverageMetric.measure()`, compute
`|dot(n, n_bucket)|` using the stored **segment/petiole wall normal** (`n_wall`), not the leaf
transform's face normal. Keep the parallel card-normal accumulator as diagnostic output only.

**Rejected alternatives:** (a) accept 0.09 pt and treat AS-1 as passing at M4 — gate flips on
unrelated work; (b) lower shaded floor or co-revise 70/90/50 — plant is not bald, LG-1 confirms;
(c) keep `n_leaf` because projected area is "physically real" — physically real but presentation-driven
for cant, same category error as `s_light` in the metric; (d) switch reference leaf to six-variant mean
— would land under 50% and metric-game the ratified basis.

*Risk to watch:* if wall-normal AS-1 passes but a future build regresses LG-1 (shade side reads bald
despite metric pass), the projection contract was wrong — escalate.

*Falsification:* canonical shaded drops below 50% on wall-normal basis after a change that does not
remove leaves from the shaded hemisphere; or LG-1 fail on re-test after W-079 lands.

**2026-08-11 — SD-OPEN-13 amendment, placement-count basis (W-079 correction): ratified.**
Supersedes the projection-normal wording in SD-OPEN-13 above; M2.5 close (SD-OPEN-15) stands.

**Factual correction accepted.** Code inspection of `coverage.gd` shows the "wall normal" proposed in
SD-OPEN-13 is `Vector3(ox, 0, oz).normalized()` — the radial direction of **the leaf's own
position**. The azimuth bin is computed from that same position; the bucket normal is the bin-centre
radial. The angle between them cannot exceed half a bin (**2.5°**); `|dot| ≥ cos(2.5°) ≈ 0.999`.
The projection term is arithmetically a no-op (scale 0.999–1.0). The real choice was not "which
normal to project with" but **whether to project at all**.

**Confirmed ruling: (a) Pure placement count.** Orientation is irrelevant to AS-1. SD-METRIC-3's
`|dot(n_leaf, n_bucket)|` projection clause is **withdrawn from the AS-1 contract** — not left inert
in ratified prose. Per-leaf weight is **`ref_area` only**, attributed to the petiole bucket. A bucket
is covered when `Σ ref_area ≥ 50%` of bucket area — equivalent to enough leaves *placed* there.
Presentation orientation (`leaf_photo_cant`, jitter, droop) stays in the render path only (LG-1 pin).

**Why (a) and not (b) or (c):**

- **(b) Card-normal projection** — AS-1 stays at **50.09%** shaded; Decision 1's 0.09 pt margin
  problem returns in full; cant remains a presentation term binding a structural gate. Rejected.
- **(c) Fixed geometric normal** — on a cylindrical tower, bin-centre radial and petiole radial differ
  by ≤2.5°; no meaningful orientation signal beyond what (a) already provides. Adds complexity without
  changing the gate's meaning. Rejected.

**(a) is what SD-OPEN-13's principle always pointed at** — "structural wall occupancy by placement" —
but the entry incorrectly described it as a normal choice. Stated knowingly now.

**Third basis change — stated out loud.** AS-1's 70 / 90 / 50 floors were ratified against
orientation-weighted figures. Every historical quoted value in this document — 50.62%, 50.27%, 47.34%,
50.09% — used card-normal projection to some degree. **51.86% is the first count-based number the
project has.** The floors are now compared against a basis they were not calibrated on. This does not
invalidate (a): the canonical count-basis measurement is **75.17 / 96.23 / 51.86** — all three floors
pass, shaded at **+1.86 pt** (better margin than any orientation-weighted figure today). The floors
remain **unchanged** (coupling rule); they are conservative on the new basis. **M4 AS-1 re-verification
uses count basis exclusively**; do not compare future numbers to pre-amendment orientation-weighted
history without labelling the basis.

**SD-METRIC-3 restated (AS-1 portion only):** A bucket is **covered** when accumulated
**`ref_area`** from leaves whose petiole maps to that bucket reaches **≥50% of bucket area**
(0.0085 m²). `ref_area = alpha_fill("a") · leaf_width_base² / aspect("a")`. **No orientation
projection.** AR-AMBIG-6 petiole attribution unchanged. Card-normal weighting
(`ref_area · |dot(n_leaf, n_bucket)|`) may be reported as a **diagnostic** (`*_pct_nleaf` or
equivalent) showing what the withdrawn basis would have read; it does not gate.

**Test replacement (W-079, `test_metric.gd`):**

- **Withdraw** `test_edge_on_leaf_does_not_cover_bucket` — it guards behaviour explicitly removed.
- **Replace with** `test_orientation_does_not_affect_bucket_coverage`: one leaf at a fixed petiole
  position on the south wall, measured twice with face-on vs edge-on card normals; assert
  `overall_pct`, `sun_half_pct`, and `shade_half_pct` are **identical** (SD-OPEN-13 amendment).
- **Retain** `test_face_on_leaves_cover_bucket` — still valid; edge-on leaves must pass it too once
  orientation is irrelevant.

**Programmer spec (W-079 revised, do not retune `leaf_photo_cant`):**

1. `CoverageMetric.measure()`: per-leaf weight = `_ref_area` only; remove `|dot(n_leaf, n_bucket)|`
   from the primary accumulator.
2. Remove the `n_wall` diagnostic accumulator (redundant with count basis — it differed only because
   it approximated count while main used card-normal).
3. Optional: retain card-normal accumulator as diagnostic output (`overall_pct_nleaf`, etc.) for
   regression visibility (canonical: 50.09% shaded vs 51.86% count).
4. Update class header and SD-METRIC-3 cross-references — projection clause must not remain as ratified
   dead spec.
5. Implement test replacement above.

**Rejected:** leaving projection in SD-METRIC-3 prose while code ignores it — same defect class as
today's dead guardrails and unfalsifiable tests.

*Risk to watch:* count basis ignores edge-on leaves that visually occlude less wall; LG-1 is the backstop
that placement density matches visible baldness. If count passes and LG-1 fails, revisit.

*Falsification:* two plants with identical petiole positions but different leaf orientations report
different AS-1; or canonical count-basis shaded drops below 50% without leaf removal from shaded
hemisphere.

**2026-08-11 — SD-OPEN-14, LG-2′ layer (b) decile thresholds (W-077): ratified.** One serial probe
on the canonical day-150.25 south-seed run (bit-identical 43,870 / 18,390 / 1288.816543 m),
area-weighted by rendered `leaf_area` per SD-METRIC-7c, ranked by plumbed `f_L` (cross-check residual
**5.8×10⁻⁷** vs 1×10⁻⁴ bar — ranking key independent of tint under test):

| Scope | n | Δ mean `Color.g` | Δ healthy fraction |
|---|---|---|---|
| **Global top vs bottom decile** | 16,697 | **0.02239** | **0.0895** |
| ±60° sun sector (diagnostic) | 9,168 | 0.00244 | 0.0039 |
| ±60° anti-sun sector (diagnostic) | 1,552 | 0.04793 | 0.1997 |

**Same discipline as LG-3 (SD-OPEN-11):** one sample, thresholds set with **deliberate headroom**
below the observation — not calibrated to barely pass. LG-3 placed tolerances *above* measured GPU
noise (~1.7×); LG-2′ places floors *below* measured separation at the same ratio (~1.7×). Sector
numbers are **diagnostic only** — the sun sector would fail almost any bar by construction (light
saturates; no gradient left to detect); the gate uses **global decile-by-light only**.

**Ratified LG-2′ layer (b) floors (provisional, one probe):**

- Top-decile vs bottom-decile mean instance **`Color.g` separation ≥ 0.013** (measured 0.02239;
  ~1.7× headroom).
- Top-decile vs bottom-decile **healthy-tier area-fraction separation ≥ 0.05** (measured 0.0895;
  ~1.8× headroom).

These replace the withdrawn hemisphere-delta floors (0.03 / 0.08) and the SD-OPEN-9 `0.6×` candidates
(0.01343 / 0.0537) — the `0.6×` rule's 0.02 floor for Δg would leave only 1.12× headroom, repeating
the knife-edge pattern W-078 rejects. **Confirmation before hardening:** re-probe on a second canonical
serial run before M4 treats these as non-provisional (same spirit as W-081 for LG-3).

*Risk to watch:* decile separation narrows if tier probability or tint gain changes — layer (a) unit
assertions catch rule removal; layer (b) catches wiring failure.

*Falsification:* second probe global Δg < 0.013 or Δhealthy < 0.05 with SD-LEAF-6/7 still wired →
threshold miscalibrated or plant regressed.

**2026-08-11 — SD-OPEN-15, M2.5 milestone close: ratified.**

**Verdict: M2.5 closes.**

| Gate | Status |
|---|---|
| **LG-1** | PASSED — owner unprompted causation read (2026-08-11) |
| **LG-2′ (a)** | PASSED — unit mechanism assertions (189/189 suite) |
| **LG-2′ (b)** | PASSED — measured 0.02239 / 0.0895 vs floors 0.013 / 0.05 (SD-OPEN-14) |
| **LG-3** | PASSED — simulation exact; image stability provisional (SD-OPEN-11) |
| **LG-4** | PASSED — day/night distinct; brick coursing visible |
| **AS-1 / AS-2** | Re-verified — AS-2 51.31%; AS-1 75.17 / 96.23 / 51.86% (placement-count basis) |
| **Code review** | PASS — no blocking findings (`a01fdb3`, `0124d98`; 189/189) |

**What M2.5 proved:** Visible causation installs from looking — an unprompted viewer identifies the
sun-facing side and cites plant-side differences (LG-1). The environment reads as day and night (LG-4).
Four fixed canonical cameras give a reproducible baseline with exact simulation determinism and bounded
GPU image noise (LG-3). Per-leaf appearance rules (SD-LEAF-6/7 tint and tier) are wired, guarded at unit
and integration level (LG-2′), and decoupled from survivorship-poisoned hemisphere averages
(SD-OPEN-10). Structural sun/shade asymmetry remains proven by AS-1 + AS-2 with an honest metric
instrument (SD-OPEN-13).

**What M2.5 cost:** Three acceptance-signal withdrawals or restatements (LG-2a/LG-2b, LG-3
byte-identity, AS-4 bit-identical screenshots) — all the same defect class: requirements resting on
properties the platform or survivorship math do not guarantee. One human gate (LG-1) now carries
whole-side causation evidence weight formerly shared with automatable colour deltas. AS-1 metric basis
required two decoupling passes (W-076 presentation size, W-079 presentation cant). Provisional
tolerances/thresholds (LG-3 image stability, LG-2′ decile floors) await confirmation probes (W-081,
second decile re-probe) before M4 hardening.

**M3 unblocked:** seed anchors (W-012) and dev tuning overlay proceed; first M3 item is the dev tuning
overlay per milestone table.

**Remaining implementation (does not block M2.5 close):** W-079 (placement-count basis in
`CoverageMetric` per SD-OPEN-13 amendment), W-082 (LG-3 dual-run comparison tooling), W-081 (LG-3
tolerance confirmation).

**Corrected stale claim:** SD-OPEN-10's "≈+0.6 pt structural margin after decoupling" assumed
≈50.62% shaded on fixed footprint; measured fixed leaf-`a` + card-normal is 50.09%. Placement-count
basis (SD-OPEN-13 amendment) gives **51.86% shaded (+1.86 pt)** — the durable margin W-078 required.
The SD-OPEN-13 "wall-normal projection" description was incorrect; the operative change is dropping
projection entirely.

---

## Handoff

**Next stage: Gameplay Programmer** — W-079 (placement-count basis per SD-OPEN-13 amendment:
`ref_area` only, drop projection, test replacement); W-082 (LG-3/AS-4 dual-run comparison tooling).
**Systems Designer** — restate SD-METRIC-3 AS-1 portion (projection withdrawn); document
SD-OPEN-13 amendment and SD-OPEN-14 thresholds in `IMPLEMENTATION.md`. **QA** — W-081 three-pair
LG-3 confirmation; LG-2′ decile re-probe before M4 hardening.

**Inputs to carry forward:** this document (authoritative for vision, invariants INV-1–INV-10 and
INV-3a, and the acceptance numbers), `IMPLEMENTATION.md` (authoritative for system contracts where
the spec is silent), and `ivy_simulator_v0.1.md` (authoritative for equations). The Phase 1 work item
queue is in `work-items/WORK_ITEMS.md`.

Authority order when they disagree: `DESIGN.md` invariants override everything, then
`ivy_simulator_v0.1.md` for equations, then `IMPLEMENTATION.md`. `SD-TIME-8` is the one sanctioned
deviation from a spec equation; any further deviation needs Director ratification and a ratification
log entry, not a note in a table.
