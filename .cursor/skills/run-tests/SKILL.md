---
name: run-tests
description: Runs the GUT unit test suite for the ivy Godot project headlessly and interprets the results. Use when asked to run tests, check if tests pass, verify code changes don't break anything, or diagnose test failures.
---

# Run Tests

## Default (fast) suite

Most pipeline work should use the **fast** suite only. It excludes mesh-SDF gate tests and the 30-day mesh scenario regression in `res://test/slow/` (tracked as ivy-c7e.2).

Always run from the project root with `required_permissions: ["all"]` and `working_directory: /Users/andrewhay/github/ivy`:

```bash
pwd && test "$(pwd)" = "/Users/andrewhay/github/ivy" || exit 1
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://test \
  -gexit 2>&1
```

Set `block_until_ms` to at least **`120000`** (2 minutes). Baseline measured 2026-08-24: **22 scripts, 205 tests, ~56 s GUT time** (~57 s wall).

`-gdir=res://test` does **not** recurse into `test/slow/` unless `-ginclude_subdirs` is set.

## Slow suite (mesh SDF + scenario gates)

Run before closing work that touches `assets/structures/*`, `mesh_sdf.gd`, `surface_query.gd`, `structure_body.gd`, or scenario seeding. Also run before M2.6 mesh-gate sign-off.

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://test/slow \
  -gexit 2>&1
```

Set `block_until_ms` to at least **`1200000`** (20 minutes). Baseline measured 2026-08-24: **2 scripts, 23 tests, ~242 s GUT time** (~245 s wall) in isolation.

## Full suite (fast + slow)

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://test \
  -gdir=res://test/slow \
  -gexit 2>&1
```

Set `block_until_ms` to at least **`1200000`** (20 minutes). Baseline measured 2026-08-23 (pre-split): **24 scripts, 228 tests, ~887 s GUT time**. Re-measure after structural changes; running fast and slow separately is faster than one combined process because of SDF memory pressure.

## Interpreting results

- Exit code `0` + `---- All tests passed! ----` → clean
- Any `FAILED` lines → report each failing test name and the assertion message
- Script parse errors (see below) → GUT installation is broken, fix first

## Known failure: mixed GUT version

If output contains `Parse Error: Identifier "GutErrorTracker" not declared`, the local `addons/gut/` has been partially overwritten by Godot's plugin updater (it's gitignored and not pinned). Fix:

```bash
curl -L -o /tmp/gut-9.4.0.zip \
  "https://api.github.com/repos/bitwes/Gut/zipball/v9.4.0"
cd /tmp && unzip -q gut-9.4.0.zip
rm -rf /Users/andrewhay/github/ivy/addons/gut
cp -R /tmp/bitwes-Gut-*/addons/gut /Users/andrewhay/github/ivy/addons/gut
```

Then re-run the test command. The version in `addons/gut/utils.gd` should read `'9.4.0'`.

## Runtime baseline (2026-08-24, ivy-c7e.2)

Per-script GUT times (isolated `-gselect` runs, Godot 4.7.2):

| Script | GUT time | Tests | Notes |
|---|---:|---:|---|
| `slow/test_scenario_seeding.gd` | 140.2 s | 3 | 30-day mesh sim regression (SG-3) |
| `slow/test_mesh_sdf.gd` | 102.0 s | 20 | Loads 10.5 MB `square_sim.sdf`; SG-2 gate |
| `test_scenario_camera.gd` | 21.0 s | 6 | Mesh scenario cameras |
| `test_determinism.gd` | 13.7 s | 1 | 5-day reproducibility |
| `test_leaf_placement.gd` | 12.8 s | 18 | |
| `test_time.gd` | 6.5 s | 13 | |
| `test_light_bake.gd` | 2.3 s | 11 | |
| All other scripts | <0.6 s each | | |

**Dominant cost:** `test/slow/` accounts for ~80% of total suite time. The old "~5 s" figure in this skill matched the pre-M2.6 suite before mesh-SDF tests landed.

## Project facts

| Item | Value |
|---|---|
| GUT version | 9.4.0 |
| Godot version | 4.4+ |
| Fast test directory | `res://test/` (no subdirs) |
| Slow test directory | `res://test/slow/` |
| `addons/gut/` | gitignored — local install only |
