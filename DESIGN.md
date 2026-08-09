# Ivy — Game Design Document

Last updated: 2026-08-09

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
| AS-1 | **Coverage, and it must be uneven.** From a single sun-facing seed at 150 game-days, default parameters, unattended: **≥70% of the eligible outer wall overall**, **≥90% on the sun-facing 180°**, and **≥50% on the shaded 180°**, with the top lip reached. Measured by the leaf-area bucket metric (`SD-METRIC`). The two halves exist so that a uniform mediocre mat cannot pass — that is the wallpaper failure mode rubric criterion 2 is there to catch, and a single overall number does not catch it. The shaded floor exists so that "asymmetry" cannot degenerate into a bald side, which would fail G1. |
| AS-2 | **Light asymmetry, and it must arrive early.** With the seed at the sun-facing base, sun-facing-vs-shaded total stem length asymmetry reaches **≥20% by game-day 30**, **≥40% by game-day 60**, and remains **≥30% at day 150**. The same run seeded on the shaded side produces **≥20% less total stem length**. The early targets matter more than the late one: the causal belief we are trying to install either forms in the first minute or it does not form. Late compression is expected and acceptable — the sunny side saturates and its crowding penalty bites while the shaded side is still uncrowded, so the cumulative ratio narrows. |
| AS-3 | **Day/night drives growth.** In a debug readout: (a) growth rate at solar midnight is ≤15% of the daily-mean rate and ≤10% of the solar-noon rate, rising through the morning; (b) the diel gate is mean-preserving: it changes *when* growth occurs within a game-day, never the daily total budget AS-1 depends on (INV-3a). Verified in two places, neither comparing two divergent long runs: **(b.1) Unit invariant (primary).** Over the 24 simulation-tick hours of one game-day, the diel gate multiplier ĝ has arithmetic mean 1 to within 1×10⁻⁶, sampled at exactly the 24 tick-hours the simulation applies it on. Exact by construction (ĝ = g / g_ref, with g_ref the mean of g over those same 24 hours). Asserted by `test_time.gd::test_diel_gate_mean_is_unity_over_24_ticks`. **(b.2) Applied near-linear check (backstop).** With branching disabled in both runs (`SET_PARAM branch_rate 0.0`), cumulative stem elongation from game-day 0 through game-day 29 with the diel gate enabled is within **±2%** of an otherwise identical run with `diel_gate_enabled = false`, comparing `TOTAL_STEM_LENGTH` from `DUMP_METRICS` (scripts `qa_as3b_nobranch_on.txt` / `qa_as3b_nobranch_off.txt`). Branching is disabled because it is the exponential amplifier that turns sub-millimetre per-tick timing differences into an 11% cumulative gap by day 29 — a measure of trajectory divergence, not of the gate. The branching-enabled cumulative comparison ratified under W-049 is withdrawn as a test instrument: for any nonlinear growth model it exceeds any fixed tolerance at some horizon N regardless of gate correctness. Single-day deltas remain excluded (W-049). Clause (b) is the budget/mean-preservation guard only; a gate wrongly applied to a directional term is not caught here (daily elongation total unchanged) and is instead caught by (a) and the INV-3a rule that ĝ never enter a directional term; (c) accumulated light `D_L` lags a step change in instantaneous light with the expected ~3-game-day time constant. Clause (b) is the one that protects AS-1 — without it a gate that quietly halves total growth would pass (a) and (c) and fail AS-1 much later, when the cause is expensive to find. |
| AS-4 | **Determinism.** Two runs with identical seed, environment, and duration produce identical tip counts and total stem length, and visually identical canonical screenshots. **Standing rule:** AS-4 must always demand bit-identical outputs. It must never be relaxed to a tolerance — a tolerance would turn it into a Lyapunov divergence meter and inherit the class defect that invalidated the W-049 AS-3(b) instrument. |
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

Owner: Game Director. Tracked as **W-024**. Gates M4 exit only; M4 may not be scored before the set is
committed.

---

## Milestones and sequencing

The sequencing below is a director-level instruction, not a suggestion. It exists to defend against
the project's largest risk.

| Milestone | Content | Exit condition |
|---|---|---|
| **M1 — Ugly end-to-end** | Tower scene, constant-light stub environment, minimal physiology, growth geometry, crude stem mesh, crude leaves. | Recognizably ivy-shaped growth is on the tower and visible in a screenshot. Ugly is fine. |
| **M2 — Environment live** | Solar position, day/night, sparse hash light field, accumulated light, sky-view factor, crowding, branching, tip lifecycle. | AS-2 and AS-3 pass. |
| **M3 — Agency and tuning** | Seed anchors, time controls, debug overlay with all §30 parameters live and field visualization. | A parameter change can be seen on screen without a restart. |
| **M4 — Looks good** | Leaf art and placement quality, stem mesh quality, iteration against the rubric. | Artifact blacklist clean, rubric ≥5/6, AS-1/4/5/6 pass. |

**No parameter tuning, no field-precision work, and no leaf-art polish happens before M1 is on
screen.** The goal of M1 is to discover what is actually hard, as early and as cheaply as possible.

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

---

## Handoff

The Systems Designer stage is complete (`IMPLEMENTATION.md`, sections `SD-*`, 2026-08-08), and the
three items it escalated are ratified above.

**Next stage: Gameplay Architect.**

Inputs to carry forward: this document (authoritative for vision, invariants INV-1–INV-10 and INV-3a,
and the acceptance numbers), `IMPLEMENTATION.md` (authoritative for system contracts where the spec is
silent), and `ivy_simulator_v0.1.md` (authoritative for equations). The Phase 1 work item queue is in
`work-items/WORK_ITEMS.md` (W-002 through W-024).

Authority order when they disagree: `DESIGN.md` invariants override everything, then
`ivy_simulator_v0.1.md` for equations, then `IMPLEMENTATION.md`. `SD-TIME-8` is the one sanctioned
deviation from a spec equation; any further deviation needs Director ratification and a ratification
log entry, not a note in a table.
