---
name: run-tests
description: Runs the GUT unit test suite for the ivy Godot project headlessly and interprets the results. Use when asked to run tests, check if tests pass, verify code changes don't break anything, or diagnose test failures.
---

<!-- Generated from semantic-memory/assets/gamedev/skills/run-tests/SKILL.md by
     scripts/bootstrap-gamedev.sh. Edit the template there, not this
     copy: local edits are overwritten on the next install. -->

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

Set `block_until_ms` to at least **`240000`** (4 minutes). Baseline measured 2026-10-28 (ivy-zfg): **72 scripts, 606 tests, ~170 s GUT time** (~175 s wall) on Godot 4.7.2 / main after grass + leaf gusts.

`-gdir=res://test` does **not** recurse into `test/slow/` unless `-ginclude_subdirs` is set.

### Running one script (timing / debug)

`-gtest` takes **full `res://` paths** and **adds** scripts; it does **not** filter `-gdir`. Do **not** combine `-gdir=res://test` with `-gtest=name.gd` — that still runs the whole directory.

```bash
# One file only:
/Applications/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://test/test_time.gd -gexit 2>&1

# Filename substring filter (still scans -gdir):
/Applications/Godot.app/Contents/MacOS/Godot --headless --script addons/gut/gut_cmdln.gd \
  -gdir=res://test -gselect=time -gexit 2>&1
```

Per-file wall times (isolated `-gtest=res://…` only): see `.tmp/gut_per_file_times.txt` after a sweep; top fast-suite costs before ivy-zfg moves were `test_time` (~103 s), `test_village_grass_scatter` (~21 s), `test_village_backdrop` (~19 s), `test_determinism` (~17 s).

## Slow suite (mesh SDF + scenario gates)

Run before closing work that touches `assets/structures/*`, `mesh_sdf.gd`, `surface_query.gd`, `structure_body.gd`, scenario seeding, **`main.tscn` building picker / session teardown**, or **SG-8 / interior light bake** on `surface_wall_sim`. Also run before M2.6 mesh-gate sign-off.

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless \
  --script addons/gut/gut_cmdln.gd \
  -gdir=res://test/slow \
  -gexit 2>&1
```

Set `block_until_ms` to at least **`1200000`** (20 minutes). Includes `test_change_building.gd`, `test_sg8_interior_light.gd`, `test_interior_leak.gd` (ivy-zfg), mesh SDF, scenario seeding, wall archetypes, etc. Re-measure after adding slow scripts; the three moved integration scripts alone are ~110 s wall in one process (2026-10-28).

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

## Runtime baseline (2026-10-28, ivy-zfg)

| Suite | GUT time | Tests | Wall (approx.) |
|---|---:|---:|---:|
| Fast `-gdir=res://test` | 170 s | 606 | 175 s |
| Slow `-gdir=res://test/slow` (full dir) | re-measure | — | often 15–20+ min |

Historical fast-suite hotspots (isolated `-gtest=res://…` only, pre–ivy-zfg `test_time` cuts): `slow/test_change_building.gd` (Main + bake), `test_time.gd` (~103 s), `slow/test_sg8_interior_light.gd` / `slow/test_interior_leak.gd` (~32 s each), `test_village_grass_scatter.gd` (~21 s).

**Dominant cost:** anything that boots `main.tscn`, runs multi–game-day GROW sims, or calls `LightBake.bake()` belongs in `test/slow/` or uses a minimal tick horizon (see `test_time.gd` `SHORT_GROW_GAME_DAYS`, `test_m6_free_plant.gd`).

## Project facts

| Item | Value |
|---|---|
| GUT version | 9.4.0 |
| Godot version | 4.4+ |
| Fast test directory | `res://test/` (no subdirs) |
| Slow test directory | `res://test/slow/` |
| `addons/gut/` | gitignored — local install only |
