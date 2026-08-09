---
name: run-ui-script
description: Runs a plain-text sequence of UI steps against the running ivy game scene, capturing screenshots at chosen points. Use when verifying multi-step UI/gameplay flows or regression-testing interactive behavior.
---

# Run UI Script

Headlessly launches the main scene, executes a `.txt` verb file, and captures PNGs where requested.

## Run command

Run with `required_permissions: ["all"]` and `working_directory: /Users/andrewhay/github/ivy`:

```bash
pwd && test "$(pwd)" = "/Users/andrewhay/github/ivy" || exit 1
/Applications/Godot.app/Contents/MacOS/Godot \
  res://tools/run_ui_script.tscn \
  -- \
  --script=/Users/andrewhay/github/ivy/tools/ui_scripts/smoke.txt
```

`--outdir` is optional and defaults to `res://.tmp/ui_scripts/`, which is gitignored. Do not point it
at `/tmp/` — output belongs inside the project so runs need no extra permissions.

Set `block_until_ms` to at least `30000`; a 30-game-day growth run takes ~13s plus Godot startup.

After the run, read the PNGs from the output directory and check the log for `FAILED` steps.
**Reading the screenshot is the point** — per `.cursor/rules/reviewing.mdc`, a zero exit code is not
evidence that a gameplay or UI flow is correct.

## Instruction file format

Plain `.txt`, one verb per line, `#` comments and blank lines ignored.

## Verb reference

| Verb | Effect |
|---|---|
| `WAIT <ms>` | Wait N real-time milliseconds |
| `SPEED <pause\|watch\|fast\|grow>` | Set the `SimClock` speed |
| `ADVANCE_DAYS <n>` | Advance the simulation by `n` game-days (`n · 24` ticks) directly, independent of wall-clock time. Accepts fractions |
| `TRACE <days>` | Advance one tick at a time, printing a per-tick state checksum (tick, tips, segments, length, tip-0 position/vigour/state). Diff two runs to find the first divergent tick |
| `DUMP` | Print simulation state: day, tick, tip counts by state, segments, leaves, total stem length, and tip-0 detail |
| `DUMP_LIGHT` | Print light-field probes at fixed points on each face |
| `DUMP_METRICS [seed_azimuth_deg]` | Print the AS-1 coverage split (overall / sun-facing / shaded, with the eligible bucket counts), `LIP_REACHED`, and the AS-2 stem asymmetry |
| `SET_PARAM <name> <value>` | Override one `IvyParams` field before the run. Use it for A/B comparisons such as `diel_gate_enabled false` |
| `SCREENSHOT [name.png]` | Capture a PNG into the output directory |

## Determinism: always pause, then advance

At any running speed, `_process` also advances ticks from the real frame delta, so tick totals depend
on wall-clock timing and the run is **not** reproducible (INV-7). Every measurement script must open
with `SPEED pause` and drive time with `ADVANCE_DAYS`, which pins the run to exactly 24 ticks per
game-day. This was defect W-034; the runner sets a `script_driven` flag so `main.gd` will not
auto-start the clock.

A correct run reproduces digit-for-digit. If two runs of the same script disagree at all, something
has reintroduced non-determinism — treat it as a blocker, not noise.

## Screenshots: check the time of day before you believe one

`start_hour` is 6.0 and `day_of_year` is fixed at 105, so **`ADVANCE_DAYS` by a whole number of days
always lands at 06:00**, with the sun a few degrees above the horizon. The plant reads as a uniform
dark mass in that light: no leaf shapes, no exposed wall, no legible sun/shade asymmetry. Two Fixer
cycles drew opposite visual conclusions from that same frame and neither was supportable (W-051).

Advance a further `0.25` days before `SCREENSHOT` to reach local noon, and `0.75` after it if you
need later checkpoints to stay on whole-day tick counts — `m2_metrics.txt` shows the pattern. Metric
dumps are unaffected by the offset; they read the plant and the field, not pixels.

## Existing scripts

| Script | Purpose |
|---|---|
| `smoke.txt` | Canonical smoke test — boot and capture. Run it after any scene or composition-root change |
| `m1_growth.txt` | The M1 exit gate: 30 game-days, dumps at day 0/1/30, screenshot at midday |
| `m1_light.txt` | Light-field probes per face |
| `m1_trace.txt` | Per-tick checksums for determinism bisection |
| `m2_metrics.txt` | The M2 acceptance run: dumps state and metrics at day 0/30/60/150. ~75s |
| `as3b_gate_on.txt` / `as3b_nodiel.txt` | AS-3(b) pair — identical runs with the diel gate on and off, to check the gate is mean-preserving |
| `as3b_day1_gate_on.txt` / `as3b_day1_nodiel.txt` | The same pair over day 0→1 only, where both runs provably share a starting state |
| `as3c_dl_decay.txt` | AS-3(c) — `D_L` step response, to measure the implied `tau_L` |
| `qa_as3b_nobranch_on.txt` / `_off.txt` | The gate pair with `branch_rate = 0`. Branching amplifies any timing difference exponentially, so this near-linear regime is what actually isolates the gate: 0.39% at day 29, against 11% with branching on (W-052) |
| `qa_stall_dormant.txt` | W-040 — midday frames across the band where dormant tips rise from 28 to 128, to confirm no vine pops or vanishes (INV-2) |
| `qa_silhouette_lip.txt` | AS-6 / W-038 — midday frames at lip-reach and saturation |
| `qa_playtest_watch.txt` | Interactive watch-speed session. Wall-clock driven, so **not** for metric determinism |

Write a throwaway `.txt` for a one-off repro rather than describing the steps in prose.

## Files involved

- `tools/run_ui_script.gd` — runner script and verb dispatch
- `tools/run_ui_script.tscn` — scene hosting the runner
- `tools/ui_scripts/*.txt` — instruction files

## Not yet implemented

`CAMERA`, `SEED` and `ASSERT` are specified in work item W-027 but do not exist. Without `ASSERT` no
script can fail a visual gate on its own, so results still need a human or agent to read them. Keep
the verb table above in sync as verbs land.

## Healthy output

```
[ui-script] script=...  outdir=res://.tmp/ui_scripts/  steps=8
[ui-script]   DUMP day=30.0 tick=720 tips=114 live=67 ... segments=2295 leaves=1027 total_len=66.6237528464408
[ui-script]   saved /Users/andrewhay/github/ivy/.tmp/ui_scripts/m1_exit.png size=(1920, 1080)
```
